import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:floating_clock/models/time_precision.dart';
import 'package:floating_clock/models/time_source.dart';
import 'package:floating_clock/repositories/time_source_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const validColors = <String>{'deep_red', 'teal'};
  late TimeSourceRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = TimeSourceRepository();
  });

  group('load', () {
    test('loads unified NTP and HTTP sources and display settings', () async {
      SharedPreferences.setMockInitialValues({
        TimeSourceRepository.sourcesKey: jsonEncode([
          TimeSource.ntp('ntp.example.com', alias: 'NTP').toJson(),
          TimeSource.http(
            'https://time.example.com',
            alias: 'HTTP',
            headers: const {'X-Test': 'yes'},
          ).toJson(),
        ]),
        TimeSourceRepository.precisionKey: 'decisecond',
        TimeSourceRepository.fractionColorKey: 'teal',
        TimeSourceRepository.hiddenPresetsKey: jsonEncode(['hidden.example']),
      });

      final settings = await repository.load(
        validFractionColorKeys: validColors,
      );

      expect(settings.sources, hasLength(2));
      expect(settings.sources.first.type, TimeSourceType.ntp);
      expect(settings.sources.last.type, TimeSourceType.http);
      expect(settings.sources.last.headers, {'X-Test': 'yes'});
      expect(settings.precision, TimePrecision.decisecond);
      expect(settings.fractionColorKey, 'teal');
      expect(settings.hiddenPresets, {'hidden.example'});
    });

    test('falls back to legacy NTP key when unified JSON is malformed', () async {
      SharedPreferences.setMockInitialValues({
        TimeSourceRepository.sourcesKey: '{broken json',
        TimeSourceRepository.legacyNtpSourcesKey: jsonEncode([
          {'host': 'legacy.example.com', 'alias': 'Legacy'},
        ]),
      });

      final settings = await repository.load(
        validFractionColorKeys: validColors,
      );

      expect(settings.sources, hasLength(1));
      expect(settings.sources.single.host, 'legacy.example.com');
      expect(settings.sources.single.type, TimeSourceType.ntp);
    });

    test('skips malformed unified rows without losing valid rows', () async {
      SharedPreferences.setMockInitialValues({
        TimeSourceRepository.sourcesKey: jsonEncode([
          TimeSource.ntp('valid.example.com').toJson(),
          null,
          {'host': '', 'type': 'ntp'},
          42,
        ]),
      });

      final settings = await repository.load(
        validFractionColorKeys: validColors,
      );

      expect(settings.sources, hasLength(1));
      expect(settings.sources.single.host, 'valid.example.com');
    });

    test('uses legacy data when every unified row is unusable', () async {
      SharedPreferences.setMockInitialValues({
        TimeSourceRepository.sourcesKey: jsonEncode([
          {'host': '', 'type': 'ntp'},
          null,
        ]),
        TimeSourceRepository.legacyNtpSourcesKey: jsonEncode([
          {'host': 'recovered.example.com', 'alias': 'Recovered'},
        ]),
      });

      final settings = await repository.load(
        validFractionColorKeys: validColors,
      );

      expect(settings.sources, hasLength(1));
      expect(settings.sources.single.host, 'recovered.example.com');
    });

    test('respects an intentionally empty unified source list', () async {
      SharedPreferences.setMockInitialValues({
        TimeSourceRepository.sourcesKey: '[]',
        TimeSourceRepository.legacyNtpSourcesKey: jsonEncode([
          {'host': 'old.example.com', 'alias': 'Old'},
        ]),
      });

      final settings = await repository.load(
        validFractionColorKeys: validColors,
      );

      expect(settings.sources, isEmpty);
    });

    test('ignores an unknown saved fraction color', () async {
      SharedPreferences.setMockInitialValues({
        TimeSourceRepository.fractionColorKey: 'not-a-supported-color',
      });

      final settings = await repository.load(
        validFractionColorKeys: validColors,
      );

      expect(settings.fractionColorKey, isNull);
    });

    test('filters malformed hidden preset entries', () async {
      SharedPreferences.setMockInitialValues({
        TimeSourceRepository.hiddenPresetsKey:
            jsonEncode([' valid.example ', 123, null, '']),
      });

      final settings = await repository.load(
        validFractionColorKeys: validColors,
      );

      expect(settings.hiddenPresets, {'valid.example'});
    });
  });

  group('save', () {
    test('writes unified sources and backward-compatible NTP-only data',
        () async {
      await repository.saveSources([
        TimeSource.system(),
        TimeSource.ntp('ntp.example.com', alias: 'NTP'),
        TimeSource.http('https://time.example.com', alias: 'HTTP'),
      ]);

      final prefs = await SharedPreferences.getInstance();
      final unified = jsonDecode(
        prefs.getString(TimeSourceRepository.sourcesKey)!,
      ) as List<dynamic>;
      final legacy = jsonDecode(
        prefs.getString(TimeSourceRepository.legacyNtpSourcesKey)!,
      ) as List<dynamic>;

      expect(unified, hasLength(2));
      expect(unified.map((item) => item['type']), containsAll(['ntp', 'http']));
      expect(legacy, hasLength(1));
      expect(legacy.single['host'], 'ntp.example.com');
    });

    test('persists precision, color, and hidden presets', () async {
      await repository.savePrecision(TimePrecision.decisecond);
      await repository.saveFractionColor('teal');
      await repository.saveHiddenPresets({'a.example', 'b.example'});

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(TimeSourceRepository.precisionKey),
        'decisecond',
      );
      expect(prefs.getString(TimeSourceRepository.fractionColorKey), 'teal');
      expect(
        (jsonDecode(prefs.getString(TimeSourceRepository.hiddenPresetsKey)!)
                as List<dynamic>)
            .toSet(),
        {'a.example', 'b.example'},
      );
    });
  });
}
