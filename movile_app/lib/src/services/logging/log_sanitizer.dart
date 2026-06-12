/// Redacts secrets from log strings and context maps before persistence.
class LogSanitizer {
  static const String _redacted = '***REDACTED***';

  static const _blacklistKeys = <String>{
    'password',
    'token',
    'apikey',
    'authorization',
    'refresh_token',
    'access_token',
    'secret',
    'jwt',
    'cookie',
    'set-cookie',
    'session',
    'email',
  };

  // Matches `access_token=...`, `apikey=...`, `api_key=...` query/form values.
  static final _queryParamRegex = RegExp(
    r'(access_token|apikey|api_key|token|refresh_token)=([^&\s"\\]+)',
    caseSensitive: false,
  );

  // Matches `Bearer <jwt>` and `Authorization: Bearer ...`.
  static final _bearerRegex = RegExp(
    r'Bearer\s+[A-Za-z0-9._\-]+',
    caseSensitive: false,
  );

  /// Replaces token values in [input] with the redacted placeholder.
  static String sanitizeText(String input) {
    var out = input.replaceAllMapped(
      _queryParamRegex,
      (m) => '${m.group(1)}=$_redacted',
    );
    out = out.replaceAll(_bearerRegex, 'Bearer $_redacted');
    return out;
  }

  /// Returns a new map where blacklisted keys are redacted and string values
  /// are run through [sanitizeText]. Recurses into nested maps and lists so
  /// secrets buried in structured context (e.g. `{'response': {'token': …}}`)
  /// are redacted too.
  static Map<String, dynamic>? sanitizeContext(Map<String, dynamic>? input) {
    if (input == null) return null;
    final out = <String, dynamic>{};
    for (final entry in input.entries) {
      final keyLower = entry.key.toLowerCase();
      if (_blacklistKeys.contains(keyLower)) {
        out[entry.key] = _redacted;
        continue;
      }
      out[entry.key] = _sanitizeValue(entry.value);
    }
    return out;
  }

  /// Recursively sanitizes an arbitrary context value: strings via
  /// [sanitizeText], maps via [sanitizeContext], lists element-by-element,
  /// and any other type passed through unchanged.
  static dynamic _sanitizeValue(dynamic value) {
    if (value is String) {
      return sanitizeText(value);
    }
    if (value is Map<String, dynamic>) {
      return sanitizeContext(value);
    }
    if (value is Map) {
      return sanitizeContext(value.map(
        (k, v) => MapEntry(k.toString(), v),
      ));
    }
    if (value is List) {
      return value.map(_sanitizeValue).toList();
    }
    return value;
  }
}
