import 'package:flutter_test/flutter_test.dart';
import 'package:floating_clock/models/time_source.dart';

void main() {
  group('TimeSource persistence compatibility', () {
    test('restores legacy NTP records without a type field', () {
      final source = TimeSource.fromJson({'host': 'pool.ntp.org', 'alias': 'Pool'});
      expect(source.type, TimeSourceType.ntp);
      expect(source.host, 'pool.ntp.org');
      expect(source.alias, 'Pool');
    });

    test('round-trips HTTP headers without changing the stored schema', () {
      final source = TimeSource.http('https://example.test/time',
          alias: 'Test', headers: const {'X-Test': 'value'});
      final restored = TimeSource.fromJson(source.toJson());
      expect(restored.type, TimeSourceType.http);
      expect(restored.host, source.host);
      expect(restored.alias, 'Test');
      expect(restored.headers, {'X-Test': 'value'});
    });
  });
}
