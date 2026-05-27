/// Severity levels for log entries. Ordered from least to most severe so they
/// can be compared numerically (`level.index >= minLevel.index`).
enum LogLevel {
  debug,
  info,
  warning,
  error;

  /// Parses a stored string back to a [LogLevel], defaulting to [error] if
  /// the value is unknown (so we never lose a noisy entry to a typo).
  static LogLevel fromName(String name) {
    for (final level in LogLevel.values) {
      if (level.name == name) return level;
    }
    return LogLevel.error;
  }

  /// Short single-letter code, used in `ConsoleSink` for compact output.
  String get shortCode => switch (this) {
        LogLevel.debug => 'D',
        LogLevel.info => 'I',
        LogLevel.warning => 'W',
        LogLevel.error => 'E',
      };
}
