import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:splitway_mobile/src/services/logging/network_error.dart';

void main() {
  group('isTransportError', () {
    test('SocketException is transport', () {
      expect(isTransportError(const SocketException('boom')), isTrue);
    });

    test('HandshakeException is transport', () {
      expect(isTransportError(const HandshakeException('tls bad')), isTrue);
    });

    test('TimeoutException is transport', () {
      expect(isTransportError(TimeoutException('slow')), isTrue);
    });

    test('http.ClientException is transport', () {
      expect(isTransportError(http.ClientException('client')), isTrue);
    });

    test('DNS failure message is transport (string match)', () {
      final err = Exception(
        "Failed host lookup: 'jylteevzapwnovfkxwzc.supabase.co'",
      );
      expect(isTransportError(err), isTrue);
    });

    test('AuthRetryableFetchException message is transport (string match)', () {
      final err = Exception(
        'AuthRetryableFetchException(message: ClientException with '
        'SocketException, uri=https://x/auth/v1/token, statusCode: null)',
      );
      expect(isTransportError(err), isTrue);
    });

    test('plain bug exception is NOT transport', () {
      expect(isTransportError(StateError('null check failed')), isFalse);
      expect(isTransportError(Exception('rpc error: invalid arg')), isFalse);
    });

    test('FormatException is NOT transport', () {
      expect(isTransportError(const FormatException('bad json')), isFalse);
    });
  });
}
