import 'package:flutter_test/flutter_test.dart';
import 'package:floating_clock/models/time_precision.dart';

void main() {
  group('TimePrecision persistence', () {
    test('stores and restores centisecond precision', () {
      expect(TimePrecision.centisecond.storageValue, 'centisecond');
      expect(precisionFromStorage('centisecond'), TimePrecision.centisecond);
    });

    test('stores and restores decisecond precision', () {
      expect(TimePrecision.decisecond.storageValue, 'decisecond');
      expect(precisionFromStorage('decisecond'), TimePrecision.decisecond);
    });

    test('defaults unknown values to centisecond precision', () {
      expect(precisionFromStorage(null), TimePrecision.centisecond);
      expect(precisionFromStorage('invalid'), TimePrecision.centisecond);
    });
  });
}
