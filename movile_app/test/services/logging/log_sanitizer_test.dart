import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/logging/log_sanitizer.dart';

void main() {
  group('LogSanitizer', () {
    test('redacts access_token query param in URLs', () {
      const input = 'https://api.mapbox.com/geocode?access_token=pk.abc123&q=x';
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

    test('sanitizeContext recurses into nested maps', () {
      final out = LogSanitizer.sanitizeContext({
        'response': {
          'access_token': 'pk.nested-secret',
          'nested': {'password': 'hunter2'},
        },
      });
      final response = out!['response'] as Map<String, dynamic>;
      expect(response['access_token'], '***REDACTED***');
      final nested = response['nested'] as Map<String, dynamic>;
      expect(nested['password'], '***REDACTED***');
    });

    test('sanitizeContext recurses into lists of maps', () {
      final out = LogSanitizer.sanitizeContext({
        'items': [
          {'token': 'abc'},
          {'safe': 1},
        ],
      });
      final items = out!['items'] as List<dynamic>;
      expect((items[0] as Map)['token'], '***REDACTED***');
      expect((items[1] as Map)['safe'], 1);
    });

    test('sanitizeContext sanitizes string values inside nested lists', () {
      final out = LogSanitizer.sanitizeContext({
        'urls': ['https://api.test?access_token=secret&foo=1'],
      });
      final urls = out!['urls'] as List<dynamic>;
      expect(urls[0], contains('access_token=***REDACTED***'));
      expect(urls[0], contains('foo=1'));
    });

    test('sanitizeContext redacts additional sensitive keys', () {
      final out = LogSanitizer.sanitizeContext({
        'secret': 's',
        'jwt': 'j',
        'cookie': 'c',
        'set-cookie': 'sc',
        'session': 'sess',
        'email': 'user@example.com',
      });
      expect(out!['secret'], '***REDACTED***');
      expect(out['jwt'], '***REDACTED***');
      expect(out['cookie'], '***REDACTED***');
      expect(out['set-cookie'], '***REDACTED***');
      expect(out['session'], '***REDACTED***');
      expect(out['email'], '***REDACTED***');
    });
  });
}
