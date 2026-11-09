import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// One validated NTP measurement.
class NtpSample {
  const NtpSample({required this.offsetMillis, required this.delayMillis});

  final int offsetMillis;
  final int delayMillis;
}

/// NTP client with address-family-aware sockets and monotonic receive timing.
class NtpService {
  const NtpService();

  static const int _ntpEpochOffset = 2208988800;
  static const int _eraSeconds = 0x100000000;

  Future<int?> queryOffset(
    String host, {
    int port = 123,
    Duration timeout = const Duration(seconds: 2),
    int attempts = 5,
  }) async {
    if (host.trim().isEmpty || port < 1 || port > 65535 || attempts < 1) {
      return null;
    }
    final samples = <NtpSample>[];
    for (var i = 0; i < attempts; i++) {
      final sample = await queryOnce(host, port: port, timeout: timeout);
      if (sample != null && sample.delayMillis >= 0) {
        samples.add(sample);
        if (sample.delayMillis < 100) break;
      }
      if (i + 1 < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
    if (samples.isEmpty) return null;
    samples.sort((a, b) => a.delayMillis.compareTo(b.delayMillis));
    final best = samples.take(samples.length >= 3 ? 3 : samples.length)
        .map((s) => s.offsetMillis).toList()..sort();
    return best[best.length ~/ 2];
  }

  Future<NtpSample?> queryOnce(
    String host, {
    int port = 123,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (host.trim().isEmpty || port < 1 || port > 65535 || timeout <= Duration.zero) {
      return null;
    }
    List<InternetAddress> addresses;
    try {
      addresses = await InternetAddress.lookup(host).timeout(timeout);
    } catch (_) {
      return null;
    }
    for (final address in addresses) {
      final sample = await _queryAddress(address, port, timeout);
      if (sample != null) return sample;
    }
    return null;
  }

  Future<NtpSample?> _queryAddress(
    InternetAddress address,
    int port,
    Duration timeout,
  ) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    try {
      final bindAddress = address.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4;
      socket = await RawDatagramSocket.bind(bindAddress, 0).timeout(timeout);
      final packet = Uint8List(48)..[0] = 0x23; // LI=0, VN=4, client mode.
      final data = ByteData.view(packet.buffer);
      final wallStartUs = DateTime.now().microsecondsSinceEpoch;
      final monotonic = Stopwatch()..start();
      final t1Seconds = wallStartUs ~/ 1000000 + _ntpEpochOffset;
      final t1Fraction = ((wallStartUs % 1000000) * 0x100000000) ~/ 1000000;
      data.setUint32(40, t1Seconds & 0xffffffff, Endian.big);
      data.setUint32(44, t1Fraction & 0xffffffff, Endian.big);

      final completer = Completer<NtpSample?>();
      socket.send(packet, address, port);
      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        final datagram = socket?.receive();
        if (datagram == null || datagram.data.length < 48) return;
        if (datagram.address.address != address.address || datagram.port != port) return;
        final bytes = datagram.data;
        final response = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
        final mode = bytes[0] & 0x7;
        final version = (bytes[0] >> 3) & 0x7;
        final leap = (bytes[0] >> 6) & 0x3;
        final stratum = response.getUint8(1);
        if (mode != 4 || version < 3 || leap == 3 || stratum == 0 || stratum > 15) return;

        final originateSeconds = response.getUint32(24, Endian.big);
        final originateFraction = response.getUint32(28, Endian.big);
        if (originateSeconds != (t1Seconds & 0xffffffff) ||
            originateFraction != (t1Fraction & 0xffffffff)) return;

        final t4Us = wallStartUs + monotonic.elapsedMicroseconds;
        final t1Ms = wallStartUs ~/ 1000;
        final t2Ms = ntpTimestampToUnixMillis(
          response.getUint32(32, Endian.big),
          response.getUint32(36, Endian.big),
          t4Us ~/ 1000000,
        );
        final t3Ms = ntpTimestampToUnixMillis(
          response.getUint32(40, Endian.big),
          response.getUint32(44, Endian.big),
          t4Us ~/ 1000000,
        );
        final t4Ms = t4Us ~/ 1000;
        final offset = ((t2Ms - t1Ms) + (t3Ms - t4Ms)) ~/ 2;
        final delay = ((t4Ms - t1Ms) - (t3Ms - t2Ms));
        if (delay >= -2 && delay <= timeout.inMilliseconds * 2) {
          completer.complete(NtpSample(offsetMillis: offset, delayMillis: delay));
        }
      });
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      await subscription?.cancel();
      socket?.close();
    }
  }

  /// Unfold the 32-bit NTP seconds field into the era nearest the local clock.
  static int ntpTimestampToUnixMillis(int seconds32, int fraction32, int nearUnixSeconds) {
    final nearNtpSeconds = nearUnixSeconds + _ntpEpochOffset;
    final era = ((nearNtpSeconds - seconds32) / _eraSeconds).round();
    final fullNtpSeconds = seconds32 + era * _eraSeconds;
    final unixSeconds = fullNtpSeconds - _ntpEpochOffset;
    final fractionMillis = (fraction32 * 1000) ~/ 0x100000000;
    return unixSeconds * 1000 + fractionMillis;
  }
}
