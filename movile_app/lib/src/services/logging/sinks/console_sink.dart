import 'package:flutter/foundation.dart';

import '../log_entry.dart';
import 'log_sink.dart';

/// Prints log entries to the dev console via `debugPrint`. No-op in release
/// builds to keep the device log clean.
class ConsoleSink implements LogSink {
  const ConsoleSink();

  @override
  Future<void> write(LogEntry entry) async {
    if (kReleaseMode) return;
    final ts = entry.timestamp.toIso8601String();
    final ctx =
        entry.context == null || entry.context!.isEmpty ? '' : ' ${entry.context}';
    debugPrint(
      '[${entry.level.shortCode}] $ts ${entry.tag}: ${entry.message}$ctx',
    );
    if (entry.error != null) debugPrint('  error: ${entry.error}');
    if (entry.stackTrace != null) debugPrint(entry.stackTrace);
  }
}
