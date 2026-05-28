import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:splitway_mobile/src/services/logging/app_logger.dart';
import 'package:splitway_mobile/src/services/logging/device_metadata.dart';
import 'package:splitway_mobile/src/services/logging/http_logging.dart';
import 'package:splitway_mobile/src/services/logging/log_entry.dart';
import 'package:splitway_mobile/src/services/logging/log_level.dart';
import 'package:splitway_mobile/src/services/logging/sinks/log_sink.dart';

class _Recording implements LogSink {
  final List<LogEntry> entries = [];
  @override
  Future<void> write(LogEntry e) async => entries.add(e);
}

void main() {
  late _Recording sink;
  setUp(() {
    sink = _Recording();
    AppLogger.install(
      sinks: [sink],
      metadata: const DeviceMetadata(
        appVersion: 't',
        platform: 't',
        deviceModel: 't',
      ),
      minLevel: () => LogLevel.debug,
      userId: () => null,
    );
  });

  test('logSupabase logs error and rethrows on exception', () async {
    Future<int> body() async => throw Exception('rpc down');
    await expectLater(
      logSupabase('upsertRoute', body),
      throwsA(isA<Exception>()),
    );
    expect(sink.entries, hasLength(1));
    final e = sink.entries.first;
    expect(e.level, LogLevel.error);
    expect(e.tag, 'supabase');
    expect(e.context!['op'], 'upsertRoute');
    expect(e.context!['durationMs'], isA<int>());
  });

  test('logSupabase does not log on success', () async {
    final out = await logSupabase('fetchAll', () async => 42);
    expect(out, 42);
    expect(sink.entries, isEmpty);
  });

  test('logHttp logs warning when status >= 400', () async {
    final response = http.Response('boom', 500);
    final out = await logHttp(
      'mapbox',
      Uri.parse('https://api.mapbox.com/x?access_token=pk.s'),
      () async => response,
    );
    expect(out, response);
    expect(sink.entries, hasLength(1));
    final e = sink.entries.first;
    expect(e.level, LogLevel.warning);
    expect(e.tag, 'mapbox');
    expect(e.context!['statusCode'], 500);
    expect(e.context!['url'], contains('***REDACTED***'));
  });

  test('logHttp logs error and rethrows on exception', () async {
    Future<http.Response> body() async => throw Exception('no network');
    await expectLater(
      logHttp('mapbox', Uri.parse('https://x'), body),
      throwsA(isA<Exception>()),
    );
    expect(sink.entries.first.level, LogLevel.error);
  });

  test('logHttp does not log on 2xx', () async {
    final r = http.Response('ok', 200);
    await logHttp('mapbox', Uri.parse('https://x'), () async => r);
    expect(sink.entries, isEmpty);
  });

  test('logSupabase downgrades transport errors to WARNING', () async {
    Future<int> body() async =>
        throw const SocketException('Failed host lookup');
    await expectLater(
      logSupabase('fetchRouteTimestamps', body),
      throwsA(isA<SocketException>()),
    );
    expect(sink.entries, hasLength(1));
    expect(sink.entries.first.level, LogLevel.warning);
    expect(sink.entries.first.tag, 'supabase');
  });

  test('logHttp downgrades transport errors to WARNING', () async {
    Future<http.Response> body() async =>
        throw http.ClientException('no connection');
    await expectLater(
      logHttp('mapbox', Uri.parse('https://x'), body),
      throwsA(isA<http.ClientException>()),
    );
    expect(sink.entries, hasLength(1));
    expect(sink.entries.first.level, LogLevel.warning);
  });
}
