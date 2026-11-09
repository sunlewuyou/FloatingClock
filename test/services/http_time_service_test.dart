import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:floating_clock/services/http_time_service.dart';

void main() {
  late HttpServer server;
  late HttpTimeService service;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    service = const HttpTimeService();
    server.listen((request) async {
      switch (request.uri.path) {
        case '/valid':
          request.response.write(jsonEncode({
            'data': DateTime.now().millisecondsSinceEpoch + 1200,
          }));
          break;
        case '/bad-status':
          request.response.statusCode = HttpStatus.serviceUnavailable;
          break;
        case '/bad-json':
          request.response.write('{not-json');
          break;
        case '/large':
          request.response.write(List<String>.filled(70000, 'x').join());
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  String url(String path) => 'http://${server.address.address}:${server.port}$path';

  test('returns a measured server clock offset', () async {
    final offset = await service.queryOffset(url('/valid'));
    expect(offset, isNotNull);
    expect(offset!, inInclusiveRange(0, 2000));
  });

  test('rejects non-200, invalid JSON and oversized response', () async {
    expect(await service.queryOffset(url('/bad-status')), isNull);
    expect(await service.queryOffset(url('/bad-json')), isNull);
    expect(await service.queryOffset(url('/large')), isNull);
  });

  test('rejects unsupported schemes', () async {
    expect(await service.queryOffset('file:///etc/passwd'), isNull);
  });
}
