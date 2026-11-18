import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:floating_clock/models/time_source.dart';
import 'package:floating_clock/services/time_sync_service.dart';

void main() {
  const service = TimeSyncService();
  HttpServer? server;

  tearDown(() async {
    await server?.close(force: true);
    server = null;
  });

  test('rejects invalid NTP parameters without opening a socket', () async {
    expect(await service.queryNtpOffset('  '), isNull);
    expect(await service.queryNtpOffset('localhost', port: 0), isNull);
    expect(await service.queryNtpOffset('localhost', attempts: 0), isNull);
    expect(await service.queryNtpOffset('localhost', attempts: 11), isNull);
    expect(
      await service.queryNtpOffset('localhost', timeout: Duration.zero),
      isNull,
    );
  });

  test('accepts a valid local NTP response and calculates its offset',
      () async {
    final udpServer = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final subscription = udpServer.listen((event) {
      if (event != RawSocketEvent.read) return;
      final request = udpServer.receive();
      if (request == null || request.data.length < 48) return;

      final response = Uint8List(48);
      response[0] = 0x24; // LI=0, VN=4, Mode=4 (server).
      response[1] = 1; // Stratum 1.
      final responseData = ByteData.sublistView(response);
      response.setRange(24, 32, request.data.sublist(40, 48));

      final serverMicros =
          DateTime.now().microsecondsSinceEpoch + 400000 + 2208988800 * 1000000;
      final seconds = serverMicros ~/ 1000000;
      final fraction =
          ((serverMicros % 1000000) * 0x100000000) ~/ 1000000;
      responseData.setUint32(32, seconds & 0xffffffff, Endian.big);
      responseData.setUint32(36, fraction & 0xffffffff, Endian.big);
      responseData.setUint32(40, seconds & 0xffffffff, Endian.big);
      responseData.setUint32(44, fraction & 0xffffffff, Endian.big);
      udpServer.send(response, request.address, request.port);
    });

    try {
      final offset = await service.queryNtpOffset(
        '127.0.0.1',
        port: udpServer.port,
        timeout: const Duration(milliseconds: 500),
        attempts: 1,
      );
      expect(offset, isNotNull);
      expect(offset!, inInclusiveRange(250, 600));
    } finally {
      await subscription.cancel();
      udpServer.close();
    }
  });

  test('NTP query is bounded by its timeout', () async {
    final silentServer = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    try {
      final stopwatch = Stopwatch()..start();
      final result = await service.queryNtpOffset(
        '127.0.0.1',
        port: silentServer.port,
        timeout: const Duration(milliseconds: 80),
        attempts: 1,
      );
      stopwatch.stop();
      expect(result, isNull);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    } finally {
      silentServer.close();
    }
  });

  test('rejects non-HTTP time source URLs', () async {
    final source = TimeSource.http('file:///tmp/time.json');
    expect(await service.queryHttpOffset(source), isNull);
  });

  test('reads numeric epoch milliseconds from an HTTP JSON endpoint',
      () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'data': DateTime.now().millisecondsSinceEpoch + 900}));
      await request.response.close();
    });

    final source = TimeSource.http('http://127.0.0.1:${server!.port}/time');
    final offset = await service.queryHttpOffset(source);
    expect(offset, isNotNull);
    expect(offset!, inInclusiveRange(500, 1200));
  });

  test('reads string epoch milliseconds and forwards custom headers',
      () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) async {
      expect(request.headers.value('x-clock-test'), 'present');
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'data': (DateTime.now().millisecondsSinceEpoch + 700).toString(),
        }));
      await request.response.close();
    });

    final source = TimeSource.http(
      'http://127.0.0.1:${server!.port}/time',
      headers: const {'X-Clock-Test': 'present'},
    );
    final offset = await service.queryHttpOffset(source);
    expect(offset, isNotNull);
    expect(offset!, inInclusiveRange(400, 1100));
  });

  test('returns null for non-success HTTP status', () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
    });

    final source = TimeSource.http('http://127.0.0.1:${server!.port}/time');
    expect(await service.queryHttpOffset(source), isNull);
  });

  test('rejects oversized HTTP response bodies', () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('x' * (64 * 1024 + 1));
      await request.response.close();
    });

    final source = TimeSource.http('http://127.0.0.1:${server!.port}/time');
    expect(await service.queryHttpOffset(source), isNull);
  });

  test('returns null for malformed or missing timestamp JSON', () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write('{"unexpected":true}');
      await request.response.close();
    });

    final source = TimeSource.http('http://127.0.0.1:${server!.port}/time');
    expect(await service.queryHttpOffset(source), isNull);
  });
}
