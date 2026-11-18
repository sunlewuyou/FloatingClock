enum TimeSourceType { system, ntp, http }

class TimeSource {
  final String host;
  String alias;
  int offsetMillis;
  DateTime? lastSync;
  final TimeSourceType type;
  final bool isSystem;
  final Map<String, String>? headers;

  TimeSource._(
    this.host, {
    this.alias = '',
    this.offsetMillis = 0,
    this.lastSync,
    this.type = TimeSourceType.ntp,
    this.isSystem = false,
    this.headers,
  });

  factory TimeSource.system() => TimeSource._(
        '',
        alias: 'System',
        offsetMillis: 0,
        isSystem: true,
        type: TimeSourceType.system,
      );

  factory TimeSource.ntp(String host, {String alias = ''}) => TimeSource._(
        host,
        alias: alias,
        offsetMillis: 0,
        lastSync: null,
        isSystem: false,
        type: TimeSourceType.ntp,
      );

  factory TimeSource.http(
    String url, {
    String alias = '',
    Map<String, String>? headers,
  }) =>
      TimeSource._(
        url,
        alias: alias,
        offsetMillis: 0,
        lastSync: null,
        isSystem: false,
        type: TimeSourceType.http,
        headers: headers == null ? null : Map.unmodifiable(headers),
      );

  Map<String, dynamic> toJson() => {
        'host': host,
        'alias': alias,
        'type': type.name,
        if (headers != null) 'headers': headers,
      };

  static TimeSource fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString();
    final rawHost = json['host'];
    final rawAlias = json['alias'];
    final host = rawHost is String ? rawHost : '';
    final alias = rawAlias is String ? rawAlias : '';

    if (rawType == 'http' || rawType == 'TimeSourceType.http') {
      final rawHeaders = json['headers'];
      final headers = <String, String>{};
      if (rawHeaders is Map) {
        rawHeaders.forEach((key, value) {
          if (key != null && value != null) {
            headers[key.toString()] = value.toString();
          }
        });
      }
      return TimeSource.http(
        host,
        alias: alias,
        headers: headers.isEmpty ? null : headers,
      );
    }

    // Historical lock-in: older releases stored enum.toString() values.
    // Unknown or missing types safely retain the previous NTP default.
    return TimeSource.ntp(host, alias: alias);
  }
}
