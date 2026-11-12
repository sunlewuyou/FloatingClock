import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/time_precision.dart';
import '../models/time_source.dart';

/// Owns the on-device persistence format for clock sources and display settings.
///
/// The unified source key is authoritative when it contains valid data. The
/// legacy NTP-only key remains written for compatibility with older releases
/// and is used as a fallback when the unified value is absent or unreadable.
class TimeSourceRepository {
  static const String sourcesKey = 'time_sources_json';
  static const String legacyNtpSourcesKey = 'ntp_servers_json';
  static const String hiddenPresetsKey = 'hidden_presets_json';
  static const String precisionKey = 'time_precision';
  static const String fractionColorKey = 'fraction_color';

  Future<TimeSourceSettings> load({
    required Set<String> validFractionColorKeys,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final savedColor = prefs.getString(fractionColorKey);
    final color = savedColor != null &&
            validFractionColorKeys.contains(savedColor)
        ? savedColor
        : null;

    final precision = precisionFromStorage(prefs.getString(precisionKey));
    final sources = _loadSources(prefs);
    final hiddenPresets = _decodeStringSet(prefs.getString(hiddenPresetsKey));

    return TimeSourceSettings(
      sources: sources,
      precision: precision,
      fractionColorKey: color,
      hiddenPresets: hiddenPresets,
    );
  }

  List<TimeSource> _loadSources(SharedPreferences prefs) {
    final unifiedRaw = prefs.getString(sourcesKey);
    if (unifiedRaw != null && unifiedRaw.isNotEmpty) {
      final unified = _decodeUnifiedSources(unifiedRaw);
      if (unified != null) return unified;
    }

    final legacyRaw = prefs.getString(legacyNtpSourcesKey);
    if (legacyRaw == null || legacyRaw.isEmpty) return <TimeSource>[];
    return _decodeLegacyNtpSources(legacyRaw);
  }

  List<TimeSource>? _decodeUnifiedSources(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;

      final result = <TimeSource>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final map = Map<String, dynamic>.from(item);
          final source = TimeSource.fromJson(map);
          if (source.host.trim().isEmpty) continue;
          result.add(source);
        } catch (_) {
          // Ignore a malformed row without discarding valid neighboring rows.
        }
      }
      // A genuinely empty list means the user removed all custom sources.
      // A non-empty list with no usable rows is treated as corrupt so the
      // legacy NTP key can recover any still-available user configuration.
      if (decoded.isNotEmpty && result.isEmpty) return null;
      return result;
    } catch (_) {
      return null;
    }
  }

  List<TimeSource> _decodeLegacyNtpSources(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <TimeSource>[];

      final result = <TimeSource>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final rawHost = item['host'];
        final rawAlias = item['alias'];
        if (rawHost is! String || rawHost.trim().isEmpty) continue;
        result.add(TimeSource.ntp(
          rawHost,
          alias: rawAlias is String ? rawAlias : '',
        ));
      }
      return result;
    } catch (_) {
      return <TimeSource>[];
    }
  }

  Set<String> _decodeStringSet(String? raw) {
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> saveSources(Iterable<TimeSource> sources) async {
    final prefs = await SharedPreferences.getInstance();
    // Materialize once because an arbitrary Iterable may be single-use.
    final persistentSources =
        sources.where((source) => !source.isSystem).toList();
    final allJson = persistentSources.map((source) => source.toJson()).toList();
    final legacyNtpJson = persistentSources
        .where((source) => source.type == TimeSourceType.ntp)
        .map((source) => {
              'host': source.host,
              'alias': source.alias,
            })
        .toList();

    // Keep both keys in sync so downgrading to a legacy release remains safe.
    await prefs.setString(sourcesKey, jsonEncode(allJson));
    await prefs.setString(legacyNtpSourcesKey, jsonEncode(legacyNtpJson));
  }

  Future<void> saveHiddenPresets(Set<String> hosts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(hiddenPresetsKey, jsonEncode(hosts.toList()));
  }

  Future<void> savePrecision(TimePrecision precision) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(precisionKey, precision.storageValue);
  }

  Future<void> saveFractionColor(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(fractionColorKey, key);
  }
}

class TimeSourceSettings {
  const TimeSourceSettings({
    required this.sources,
    required this.precision,
    required this.fractionColorKey,
    required this.hiddenPresets,
  });

  final List<TimeSource> sources;
  final TimePrecision precision;
  final String? fractionColorKey;
  final Set<String> hiddenPresets;
}
