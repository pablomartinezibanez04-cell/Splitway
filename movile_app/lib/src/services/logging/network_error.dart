import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Returns `true` if [error] looks like a transient network/transport failure
/// (DNS, connection reset, TLS handshake, timeout, retryable auth refresh)
/// rather than an application-level bug.
///
/// These shouldn't be logged at ERROR severity: when the device is offline,
/// every background timer (Supabase's auth token refresh, sync polling, etc.)
/// keeps throwing the same exception. Logging them all as errors floods the
/// diagnostics screen with noise the user/developer can't act on. They are
/// recorded as warnings under a dedicated `network` tag so they're easy to
/// filter out — but still visible if we ever need them.
bool isTransportError(Object error) {
  if (error is SocketException) return true;
  if (error is HandshakeException) return true;
  if (error is TimeoutException) return true;
  if (error is http.ClientException) return true;

  // Many SDKs (notably supabase_flutter) wrap socket errors in their own
  // exception types — fall back to string inspection so we still catch them.
  final msg = error.toString();
  return msg.contains('SocketException') ||
      msg.contains('Failed host lookup') ||
      msg.contains('Network is unreachable') ||
      msg.contains('Connection closed') ||
      msg.contains('Connection reset') ||
      msg.contains('Connection refused') ||
      // supabase_flutter's AuthRetryableFetchException — retried automatically
      msg.contains('AuthRetryableFetchException');
}
