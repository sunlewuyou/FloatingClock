import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Fetches a JSON endpoint whose `data` field contains Unix epoch milliseconds.
class HttpTimeService {
  const HttpTimeService({this.maxResponseBytes = 64 * 1024});

  final int maxResponseBytes;

  Future<int?> queryOffset(
    String endpoint, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final uri = Uri.tryParse(endpoint);
    if (uri == null || !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        timeout <= Duration.zero) return null;

    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final requestStartedAt = DateTime.now().millisecondsSinceEpoch;
      final elapsed = Stopwatch()..start();
      final request = await client.getUrl(uri).timeout(timeout);
      headers?.forEach((name, value) {
        try {
          request.headers.set(name, value);
        } catch (_) {
          // Ignore malformed optional headers; the request itself remains valid.
        }
      });
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) return null;
      if (response.contentLength > maxResponseBytes) return null;

      final bytes = <int>[];
      Future<void> readBody() async {
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxResponseBytes) {
            throw const FormatException('HTTP time response exceeds size limit');
          }
          bytes.addAll(chunk);
        }
      }
      await readBody().timeout(timeout);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map || !decoded.containsKey('data')) return null;
      final value = decoded['data'];
      final serverMillis = value is num
          ? value.toInt()
          : int.tryParse(value?.toString() ?? '');
      if (serverMillis == null || serverMillis <= 0) return null;
      final midpointMillis = requestStartedAt + elapsed.elapsedMilliseconds ~/ 2;
      return serverMillis - midpointMillis;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
