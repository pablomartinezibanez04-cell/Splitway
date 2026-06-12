import 'dart:async';

import 'package:uuid/uuid.dart';

import 'device_metadata.dart';
import 'log_entry.dart';
import 'log_level.dart';
import 'log_sanitizer.dart';
import 'log_uploader.dart';
import 'sinks/local_sink.dart';
import 'sinks/log_sink.dart';

/// Central entrypoint for the logging system. Application code calls
/// `AppLogger.instance.error(...)` (or the level-specific shortcuts).
class AppLogger {
  AppLogger._({
    required List<LogSink> sinks,
    required DeviceMetadata metadata,
    required LogLevel Function() minLevel,
    required String? Function() userId,
  })  : _sinks = sinks,
        _metadata = metadata,
        _minLevel = minLevel,
        _userId = userId;

  /// Test-only constructor with explicit dependencies.
  factory AppLogger.test({
    required List<LogSink> sinks,
    required DeviceMetadata metadata,
    required LogLevel Function() minLevel,
    String? Function()? userId,
  }) =>
      AppLogger._(
        sinks: sinks,
        metadata: metadata,
        minLevel: minLevel,
        userId: userId ?? (() => null),
      );

  static AppLogger? _instance;
  static LocalSink? _localSink;
  static LogUploader? _uploader;

  /// The singleton. Throws if [install] has not run yet.
  static AppLogger get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('AppLogger.install() has not been called yet');
    }
    return i;
  }

  /// Returns the singleton if it has been installed, otherwise null. Use this
  /// during early bootstrap before [install] runs.
  static AppLogger? get maybeInstance => _instance;

  /// Local sink handle for the Diagnostics UI. Null until [attachUiHandles].
  static LocalSink? get localSink => _localSink;

  /// Uploader handle for the Diagnostics UI. Null until [attachUiHandles].
  static LogUploader? get uploader => _uploader;

  /// Installs a singleton. Subsequent calls replace the previous instance
  /// (useful for hot restart in development).
  static void install({
    required List<LogSink> sinks,
    required DeviceMetadata metadata,
    required LogLevel Function() minLevel,
    required String? Function() userId,
  }) {
    _instance = AppLogger._(
      sinks: sinks,
      metadata: metadata,
      minLevel: minLevel,
      userId: userId,
    );
  }

  /// Stores references the Diagnostics screen needs to reach.
  static void attachUiHandles({LocalSink? sink, LogUploader? uploader}) {
    _localSink = sink;
    _uploader = uploader;
  }

  final List<LogSink> _sinks;
  final DeviceMetadata _metadata;
  final LogLevel Function() _minLevel;
  final String? Function() _userId;
  final Uuid _uuid = const Uuid();

  // Field caps, kept in sync with the server-side CHECK constraints on the
  // remote `app_logs` table (migration 20260611000004). Truncating client-side
  // means an oversized log is stored (clipped) instead of being rejected by
  // the constraint and eventually dropped after failed upload retries.
  static const int maxMessageLength = 10000;
  static const int maxErrorLength = 10000;
  static const int maxStackLength = 20000;
  static const String _truncationMarker = '…[truncated]';

  static String _truncate(String value, int max) {
    if (value.length <= max) return value;
    return value.substring(0, max - _truncationMarker.length) +
        _truncationMarker;
  }

  // Rate limit: max 10 entries per (level,tag) per second.
  final Map<String, _RateBucket> _buckets = {};

  Future<void> debug(String tag, String message,
          {Object? error,
          StackTrace? stackTrace,
          Map<String, dynamic>? context}) =>
      log(LogLevel.debug, tag, message,
          error: error, stackTrace: stackTrace, context: context);

  Future<void> info(String tag, String message,
          {Object? error,
          StackTrace? stackTrace,
          Map<String, dynamic>? context}) =>
      log(LogLevel.info, tag, message,
          error: error, stackTrace: stackTrace, context: context);

  Future<void> warning(String tag, String message,
          {Object? error,
          StackTrace? stackTrace,
          Map<String, dynamic>? context}) =>
      log(LogLevel.warning, tag, message,
          error: error, stackTrace: stackTrace, context: context);

  Future<void> error(String tag, String message,
          {Object? error,
          StackTrace? stackTrace,
          Map<String, dynamic>? context}) =>
      log(LogLevel.error, tag, message,
          error: error, stackTrace: stackTrace, context: context);

  Future<void> log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) async {
    if (level.index < _minLevel().index) return;
    if (!_allowByRateLimit(level, tag)) return;

    final entry = LogEntry(
      id: _uuid.v4(),
      timestamp: DateTime.now().toUtc(),
      level: level,
      tag: tag,
      message: _truncate(LogSanitizer.sanitizeText(message), maxMessageLength),
      error: error == null
          ? null
          : _truncate(
              LogSanitizer.sanitizeText(error.toString()), maxErrorLength),
      stackTrace: stackTrace == null
          ? null
          : _truncate(
              LogSanitizer.sanitizeText(stackTrace.toString()), maxStackLength),
      context: LogSanitizer.sanitizeContext(context),
      appVersion: _metadata.appVersion,
      platform: _metadata.platform,
      deviceModel: _metadata.deviceModel,
      userId: _userId(),
    );

    for (final sink in _sinks) {
      try {
        await sink.write(entry);
      } catch (_) {
        // sinks must not throw, but be defensive anyway
      }
    }
  }

  bool _allowByRateLimit(LogLevel level, String tag) {
    final key = '${level.name}:$tag';
    final now = DateTime.now();
    final bucket = _buckets.putIfAbsent(key, () => _RateBucket());
    if (now.difference(bucket.windowStart).inSeconds >= 1) {
      bucket.windowStart = now;
      bucket.count = 0;
    }
    bucket.count += 1;
    return bucket.count <= 10;
  }
}

class _RateBucket {
  DateTime windowStart = DateTime.now();
  int count = 0;
}
