import 'package:flutter_test/flutter_test.dart';
import 'package:floating_clock/services/ntp_service.dart';

void main() {
  group('NtpService timestamp conversion', () {
    test('converts the Unix epoch', () {
      expect(NtpService.ntpTimestampToUnixMillis(2208988800, 0, 0), 0);
    });

    test('converts fractional seconds to milliseconds', () {
      expect(
        NtpService.ntpTimestampToUnixMillis(2208988801, 0x80000000, 1),
        1500,
      );
    });

    test('unfolds the NTP era around the supplied reference time', () {
      const eraZeroSeconds = 0xFFFFFFFF;
      const nearUnixSeconds = 2085978497; // Just after the 2036 era rollover.
      final converted = NtpService.ntpTimestampToUnixMillis(
        eraZeroSeconds, 0, nearUnixSeconds,
      );
      expect(converted, 2085978495000);
    });
  });

  group('NtpService input validation', () {
    test('rejects empty host and invalid port without network access', () async {
      const service = NtpService();
      expect(await service.queryOffset(''), isNull);
      expect(await service.queryOnce('localhost', port: 0), isNull);
    });
  });
}
