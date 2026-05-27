import '../log_entry.dart';

/// A destination for log entries. Implementations must be safe to call from
/// any isolate and must not throw — they should swallow their own errors
/// (we cannot afford to crash the logger).
abstract class LogSink {
  Future<void> write(LogEntry entry);
}
