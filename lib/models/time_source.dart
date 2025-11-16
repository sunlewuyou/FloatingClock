enum TimeSourceType { system, ntp, http }

class TimeSource {
  final String host;
  String alias;
  int offsetMillis;
  DateTime? lastSync;
  final TimeSourceType type;
  final bool isSystem;
  final Map<String, String>? headers;

  TimeSource._(this.host,
      {this.alias = '',
      this.offsetMillis = 0,
      this.lastSync,
      this.type = TimeSourceType.ntp,
      this.isSystem = false,
      this.headers});

  factory TimeSource.system() => TimeSource._('',
      alias: 'System',
      offsetMillis: 0,
      isSystem: true,
      type: TimeSourceType.system);
  factory TimeSource.ntp(String host, {String alias = ''}) => TimeSource._(host,
      alias: alias,
      offsetMillis: 0,
      lastSync: null,
      isSystem: false,
      type: TimeSourceType.ntp);
  factory TimeSource.http(String url,
          {String alias = '', Map<String, String>? headers}) =>
      TimeSource._(url,
          alias: alias,
          offsetMillis: 0,
          lastSync: null,
          isSystem: false,
          type: TimeSourceType.http,
          headers: headers);

  Map<String, dynamic> toJson() => {
        'host': host,
        'alias': alias,
        'type': type.toString(),
        'headers': headers
      };

  static TimeSource fromJson(Map<String, dynamic> m) {
    final t = m['type'] ?? 'ntp';
    if (t == 'TimeSourceType.http' || t == 'http') {
      final rawHeaders = m['headers'] ?? {};
      final headers = <String, String>{};
      if (rawHeaders is Map) {
        rawHeaders.forEach((k, v) {
          headers[k.toString()] = v.toString();
        });
      }
      return TimeSource.http(m['host'] ?? '',
          alias: m['alias'] ?? '', headers: headers);
    }
    return TimeSource.ntp(m['host'] ?? '', alias: m['alias'] ?? '');
  }
}
