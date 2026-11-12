import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/time_source.dart';

/// Performs network time queries without depending on Flutter widgets.
///
/// All network operations have bounded timeouts and release their sockets or
/// HTTP clients on every exit path. A failed query returns null, matching the
/// application's previous behavior.
class TimeSyncService {
  const TimeSyncService();

  static const int _ntpEpochOffset = 2208988800;
  static const int _ntpEraSeconds = 0x100000000;

  Future<int?> queryNtpOffset(
    String host, {
    int port = 123,
    Duration timeout = const Duration(seconds: 2),
    int attempts = 5,
  }) async {
    final normalizedHost = host.trim();
    if (normalizedHost.isEmpty || port < 1 || port > 65535 ||
        timeout <= Duration.zero || attempts < 1 || attempts > 10) {
      return null;
    }

    final samples = <_NtpSample>[];
    for (var attempt = 0; attempt < attempts; attempt++) {
      final sample = await _queryNtpOnce(
        normalizedHost,
        port: port,
        timeout: timeout,
      );
      if (sample != null && sample.delay >= 0) {
        samples.add(sample);
        // A low-delay response is generally the least affected by network
        // queueing. Keep the existing early-exit behavior.
        if (sample.delay < 100) break;
      }
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }

    if (samples.isEmpty) return null;
    samples.sort((a, b) => a.delay.compareTo(b.delay));
    final bestCount = samples.length >= 3 ? 3 : samples.length;
    final offsets = samples.take(bestCount).map((s) => s.offset).toList()
      ..sort();
    return offsets[offsets.length ~/ 2];
  }

  Future<_NtpSample?> _queryNtpOnce(
    String host, {
    required int port,
    required Duration timeout,
  }) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? timeoutTimer;
    final completer = Completer<_NtpSample?>();

    void finish(_NtpSample? value) {
      if (!completer.isCompleted) completer.complete(value);
      timeoutTimer?.cancel();
      socket?.close();
    }

    try {
      final addresses =
          await InternetAddress.lookup(host).timeout(timeout);
      if (addresses.isEmpty) return null;

      // Prefer IPv4 but preserve IPv6-only network support. Bind to the same
      // address family as the selected destination.
      final address = addresses.firstWhere(
        (item) => item.type == InternetAddressType.IPv4,
        orElse: () => addresses.first,
      );
      final bindAddress = address.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4;
      final udpSocket =
          await RawDatagramSocket.bind(bindAddress, 0).timeout(timeout);
      socket = udpSocket;

      final request = Uint8List(48);
      request[0] = 0x23; // LI=0, VN=4, Mode=3 (client).
      final sentAtMicros = DateTime.now().microsecondsSinceEpoch;
      final sentNtpSeconds =
          sentAtMicros ~/ Duration.microsecondsPerSecond + _ntpEpochOffset;
      final sentFraction =
          ((sentAtMicros % Duration.microsecondsPerSecond) *
                  _ntpEraSeconds) ~/
              Duration.microsecondsPerSecond;
      final requestData = ByteData.sublistView(request);
      requestData.setUint32(40, sentNtpSeconds & 0xffffffff, Endian.big);
      requestData.setUint32(44, sentFraction & 0xffffffff, Endian.big);

      udpSocket.send(request, address, port);
      timeoutTimer = Timer(timeout, () => finish(null));

      subscription = udpSocket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) return;
        final datagram = udpSocket.receive();
        if (datagram == null || datagram.data.length < 48) return;
        final packet = datagram.data;
        final data = ByteData.sublistView(packet);

        final leap = (packet[0] >> 6) & 0x3;
        final mode = packet[0] & 0x7;
        final stratum = data.getUint8(1);
        if (leap == 3 || mode != 4 || stratum == 0 || stratum > 15) return;

        final originateSeconds = data.getUint32(24, Endian.big);
        final originateFraction = data.getUint32(28, Endian.big);
        if (originateSeconds != (sentNtpSeconds & 0xffffffff) ||
            originateFraction != (sentFraction & 0xffffffff)) {
          return;
        }

        final receiveSeconds = data.getUint32(32, Endian.big);
        final receiveFraction = data.getUint32(36, Endian.big);
        final transmitSeconds = data.getUint32(40, Endian.big);
        final transmitFraction = data.getUint32(44, Endian.big);
        if ((receiveSeconds == 0 && receiveFraction == 0) ||
            (transmitSeconds == 0 && transmitFraction == 0)) {
          return;
        }

        final receivedAtMillis = DateTime.now().millisecondsSinceEpoch;
        final t1 = sentAtMicros ~/ 1000;
        final t2 = _ntpTimestampToUnixMillis(
          receiveSeconds,
          receiveFraction,
          referenceUnixMillis: receivedAtMillis,
        );
        final t3 = _ntpTimestampToUnixMillis(
          transmitSeconds,
          transmitFraction,
          referenceUnixMillis: receivedAtMillis,
        );
        final t4 = receivedAtMillis;
        final offset = ((t2 - t1) + (t3 - t4)) ~/ 2;
        final delay = (t4 - t1) - (t3 - t2);
        if (delay < -5) return;
        finish(_NtpSample(offset: offset, delay: delay < 0 ? 0 : delay));
      }, onError: (_) => finish(null), onDone: () => finish(null));

      return await completer.future;
    } on Object {
      return null;
    } finally {
      timeoutTimer?.cancel();
      await subscription?.cancel();
      socket?.close();
    }
  }

  static int _ntpTimestampToUnixMillis(
    int seconds,
    int fraction, {
    required int referenceUnixMillis,
  }) {
    final referenceNtpSeconds =
        referenceUnixMillis ~/ 1000 + _ntpEpochOffset;
    final era =
        ((referenceNtpSeconds - seconds) / _ntpEraSeconds).round();
    final fullNtpSeconds = seconds + era * _ntpEraSeconds;
    final unixSeconds = fullNtpSeconds - _ntpEpochOffset;
    final fractionMillis = (fraction * 1000) ~/ _ntpEraSeconds;
    return unixSeconds * 1000 + fractionMillis;
  }

  /// Queries an HTTP endpoint whose JSON response contains an epoch-ms value
  /// in `data`. The existing endpoint contract is intentionally unchanged.
  Future<int?> queryHttpOffset(
    TimeSource source, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (source.type != TimeSourceType.http || timeout <= Duration.zero) {
      return null;
    }

    final uri = Uri.tryParse(source.host);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      source.headers?.forEach((key, value) {
        request.headers.set(key, value);
      });
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) return null;

      // Enforce a response-size limit while streaming, rather than after
      // joining an arbitrarily large response into memory.
      final bodyBuilder = BytesBuilder(copy: false);
      var receivedBytes = 0;
      await for (final chunk in response.timeout(timeout)) {
        receivedBytes += chunk.length;
        if (receivedBytes > 64 * 1024) return null;
        bodyBuilder.add(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bodyBuilder.takeBytes()));
      if (decoded is! Map || !decoded.containsKey('data')) return null;

      final rawTimestamp = decoded['data'];
      final serverMillis = rawTimestamp is num
          ? rawTimestamp.toInt()
          : int.tryParse(rawTimestamp?.toString() ?? '');
      if (serverMillis == null || serverMillis <= 0) return null;
      return serverMillis - DateTime.now().millisecondsSinceEpoch;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

class _NtpSample {
  const _NtpSample({required this.offset, required this.delay});

  final int offset;
  final int delay;
}
