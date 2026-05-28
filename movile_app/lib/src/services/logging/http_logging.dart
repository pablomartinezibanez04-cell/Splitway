import 'package:http/http.dart' as http;

import 'app_logger.dart';
import 'log_level.dart';
import 'network_error.dart';

/// Wraps a Supabase call. Logs and rethrows on failure with the operation
/// name and elapsed milliseconds. No-op on success.
///
/// Transport failures (DNS, socket, retryable auth) are logged at WARNING
/// instead of ERROR — those mean "device is offline", not "code is broken".
Future<T> logSupabase<T>(String op, Future<T> Function() body) async {
  final sw = Stopwatch()..start();
  try {
    return await body();
  } catch (e, st) {
    final logger = AppLogger.maybeInstance;
    if (logger != null) {
      final level = isTransportError(e) ? LogLevel.warning : LogLevel.error;
      await logger.log(
        level,
        'supabase',
        '$op failed',
        error: e,
        stackTrace: st,
        context: {
          'op': op,
          'durationMs': sw.elapsedMilliseconds,
        },
      );
    }
    rethrow;
  }
}

/// Wraps an HTTP call. Logs at WARNING for status >= 400, at ERROR on throw
/// (downgraded to WARNING for transport failures like DNS/socket errors).
/// Returns the response unchanged.
Future<http.Response> logHttp(
  String tag,
  Uri url,
  Future<http.Response> Function() send,
) async {
  final sw = Stopwatch()..start();
  try {
    final response = await send();
    if (response.statusCode >= 400) {
      final logger = AppLogger.maybeInstance;
      if (logger != null) {
        await logger.log(
          LogLevel.warning,
          tag,
          'HTTP ${response.statusCode} ${url.path}',
          context: {
            'url': url.toString(),
            'statusCode': response.statusCode,
            'durationMs': sw.elapsedMilliseconds,
          },
        );
      }
    }
    return response;
  } catch (e, st) {
    final logger = AppLogger.maybeInstance;
    if (logger != null) {
      final level = isTransportError(e) ? LogLevel.warning : LogLevel.error;
      await logger.log(
        level,
        tag,
        'HTTP request threw on ${url.path}',
        error: e,
        stackTrace: st,
        context: {
          'url': url.toString(),
          'durationMs': sw.elapsedMilliseconds,
        },
      );
    }
    rethrow;
  }
}
