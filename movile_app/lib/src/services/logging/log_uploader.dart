import 'dart:async';

import 'log_entry.dart';
import 'sinks/local_sink.dart';

typedef LogBatchUploader = Future<void> Function(List<LogEntry> batch);

/// Drains unsynced rows from a [LocalSink] and pushes them through [upload]
/// in batches. Independent of any concrete remote backend.
class LogUploader {
  LogUploader({
    required LocalSink sink,
    required LogBatchUploader upload,
    int batchSize = 50,
    Duration debounce = const Duration(seconds: 5),
    bool Function()? enabled,
  })  : _sink = sink,
        _upload = upload,
        _batchSize = batchSize,
        _debounce = debounce,
        _enabled = enabled ?? (() => true);

  final LocalSink _sink;
  final LogBatchUploader _upload;
  final int _batchSize;
  final Duration _debounce;
  final bool Function() _enabled;

  Timer? _timer;
  bool _running = false;

  /// Schedules a drain after the debounce window. Multiple calls during the
  /// window collapse into a single run.
  void scheduleDrain() {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      _timer = null;
      drain();
    });
  }

  /// Uploads pending rows immediately. Safe to await; concurrent calls return
  /// fast (only one drain runs at a time).
  Future<void> drain() async {
    if (_running) return;
    if (!_enabled()) return;
    _running = true;
    try {
      while (true) {
        final batch = await _sink.pendingSync(limit: _batchSize);
        if (batch.isEmpty) break;
        try {
          await _upload(batch);
          await _sink.markSynced(batch.map((e) => e.id).toList());
        } catch (_) {
          await _sink.incrementAttempts(batch.map((e) => e.id).toList());
          // Stop draining on first error so we don't hammer Supabase.
          break;
        }
      }
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}
