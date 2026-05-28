import 'dart:convert';

import 'log_level.dart';

/// Immutable log record. Persisted both locally (with `synced`/`sync_attempts`
/// added by `LocalSink`) and remotely (without those columns).
class LogEntry {
  const LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    required this.appVersion,
    required this.platform,
    required this.deviceModel,
    this.error,
    this.stackTrace,
    this.context,
    this.userId,
  });

  final String id;
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? error;
  final String? stackTrace;
  final Map<String, dynamic>? context;
  final String appVersion;
  final String platform;
  final String deviceModel;
  final String? userId;

  /// Returns a map suitable for SQLite or Supabase. `context` is JSON-encoded
  /// to a string column.
  Map<String, dynamic> toMap() => {
        'id': id,
        'timestamp': timestamp.toUtc().millisecondsSinceEpoch,
        'level': level.name,
        'tag': tag,
        'message': message,
        'error': error,
        'stack_trace': stackTrace,
        'context_json': context == null ? null : jsonEncode(context),
        'app_version': appVersion,
        'platform': platform,
        'device_model': deviceModel,
        'user_id': userId,
      };

  /// Map for Supabase REST payload (timestamp as ISO-8601, context as JSON
  /// object rather than string).
  Map<String, dynamic> toRemoteJson() => {
        'id': id,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'level': level.name,
        'tag': tag,
        'message': message,
        'error': error,
        'stack_trace': stackTrace,
        'context': context,
        'app_version': appVersion,
        'platform': platform,
        'device_model': deviceModel,
        'user_id': userId,
      };

  factory LogEntry.fromMap(Map<String, dynamic> m) {
    final ctx = m['context_json'];
    Map<String, dynamic>? parsedContext;
    if (ctx is String && ctx.isNotEmpty) {
      parsedContext = Map<String, dynamic>.from(
        jsonDecode(ctx) as Map<dynamic, dynamic>,
      );
    } else if (ctx is Map) {
      parsedContext = Map<String, dynamic>.from(ctx);
    }

    return LogEntry(
      id: m['id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        m['timestamp'] as int,
        isUtc: true,
      ),
      level: LogLevel.fromName(m['level'] as String),
      tag: m['tag'] as String,
      message: m['message'] as String,
      error: m['error'] as String?,
      stackTrace: m['stack_trace'] as String?,
      context: parsedContext,
      appVersion: m['app_version'] as String,
      platform: m['platform'] as String,
      deviceModel: m['device_model'] as String,
      userId: m['user_id'] as String?,
    );
  }
}
