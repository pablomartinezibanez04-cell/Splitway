import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/logging/log_sanitizer.dart';

void main() {
  group('LogSanitizer', () {
    test('redacts access_token query param in URLs', () {
      const input =
          'https://api.mapbox.com/geocode?access_token=pk.abc123&q=x';
      final out = LogSanitizer.sanitizeText(input);
      expect(out, isNot(contains('pk.abc123')));
      expect(out, contains('access_token=***REDACTED***'));
    });

    test('redacts apikey and Bearer tokens', () {
      const input = 'Authorization: Bearer eyJabc.def\napikey=supersecret';
      final out = LogSanitizer.sanitizeText(input);
      expect(out, isNot(contains('eyJabc.def')));
      expect(out, isNot(contains('supersecret')));
      expect(out, contains('***REDACTED***'));
    });

    test('returns text unchanged when no secrets present', () {
      const input = 'rpc upsert_session_with_telemetry failed';
      expect(LogSanitizer.sanitizeText(input), input);
    });

    test('sanitizeContext redacts blacklisted keys', () {
      final input = {
        'url': 'https://x.test',
        'password': 'hunter2',
        'token': 'abc',
        'apikey': 'k',
        'authorization': 'Bearer x',
        'refresh_token': 'r',
        'access_token': 'a',
        'safe': 1,
      };
      final out = LogSanitizer.sanitizeContext(input);
      expect(out!['password'], '***REDACTED***');
      expect(out['token'], '***REDACTED***');
      expect(out['apikey'], '***REDACTED***');
      expect(out['authorization'], '***REDACTED***');
      expect(out['refresh_token'], '***REDACTED***');
      expect(out['access_token'], '***REDACTED***');
      expect(out['safe'], 1);
      expect(out['url'], 'https://x.test');
    });

    test('sanitizeContext also sanitizes string values for tokens in URLs', () {
      final out = LogSanitizer.sanitizeContext({
        'url': 'https://api.test?access_token=secret&foo=1',
      });
      expect(out!['url'], contains('access_token=***REDACTED***'));
      expect(out['url'], contains('foo=1'));
    });

    test('sanitizeContext returns null when input is null', () {
      expect(LogSanitizer.sanitizeContext(null), isNull);
    });
  });
}
