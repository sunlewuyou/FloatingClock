import 'package:flutter_test/flutter_test.dart';
import 'package:floating_clock/models/time_source.dart';

void main() {
  group('TimeSource serialization', () {
    test('round-trips an NTP source', () {
      final source = TimeSource.ntp('ntp.example.com', alias: 'Example');

      final restored = TimeSource.fromJson(source.toJson());

      expect(restored.type, TimeSourceType.ntp);
      expect(restored.host, 'ntp.example.com');
      expect(restored.alias, 'Example');
      expect(restored.headers, isNull);
    });

    test('round-trips an HTTP source and its headers', () {
      final source = TimeSource.http(
        'https://time.example.com/now',
        alias: 'HTTP time',
        headers: const {'User-Agent': 'FloatingClock Test'},
      );

      final restored = TimeSource.fromJson(source.toJson());

      expect(restored.type, TimeSourceType.http);
      expect(restored.host, 'https://time.example.com/now');
      expect(restored.alias, 'HTTP time');
      expect(restored.headers, {'User-Agent': 'FloatingClock Test'});
    });

    test('reads legacy enum string values', () {
      final restored = TimeSource.fromJson({
        'host': 'legacy.example.com',
        'alias': 'Legacy',
        'type': 'TimeSourceType.http',
        'headers': {'X-Test': 'legacy'},
      });

      expect(restored.type, TimeSourceType.http);
      expect(restored.headers, {'X-Test': 'legacy'});
    });

    test('handles malformed persisted values safely', () {
      final restored = TimeSource.fromJson({
        'host': 123,
        'alias': false,
        'type': 'unknown',
        'headers': ['not', 'a', 'map'],
      });

      expect(restored.type, TimeSourceType.ntp);
      expect(restored.host, isEmpty);
      expect(restored.alias, isEmpty);
    });
  });
}
