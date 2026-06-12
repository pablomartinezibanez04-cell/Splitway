import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/logging/app_logger.dart';
import 'package:splitway_mobile/src/services/logging/device_metadata.dart';
import 'package:splitway_mobile/src/services/logging/log_entry.dart';
import 'package:splitway_mobile/src/services/logging/log_level.dart';
import 'package:splitway_mobile/src/services/logging/sinks/log_sink.dart';

class _RecordingSink implements LogSink {
  final List<LogEntry> entries = [];
  @override
  Future<void> write(LogEntry entry) async => entries.add(entry);
}

void main() {
  late _RecordingSink sink;
  late AppLogger logger;

  setUp(() {
    sink = _RecordingSink();
    logger = AppLogger.test(
      sinks: [sink],
      metadata: const DeviceMetadata(
        appVersion: '0.4.0+1',
        platform: 'test',
        deviceModel: 'test',
      ),
      minLevel: () => LogLevel.warning,
      userId: () => 'user-1',
    );
  });

  test('drops entries below minLevel', () async {
    await logger.info('app', 'noise');
    expect(sink.entries, isEmpty);
  });

  test('emits entries at or above minLevel', () async {
    await logger.warning('app', 'careful');
    expect(sink.entries, hasLength(1));
    expect(sink.entries.first.level, LogLevel.warning);
  });

  test('attaches metadata and user id', () async {
    await logger.error('supabase', 'rpc failed');
    final e = sink.entries.first;
    expect(e.appVersion, '0.4.0+1');
    expect(e.platform, 'test');
    expect(e.deviceModel, 'test');
    expect(e.userId, 'user-1');
  });

  test('sanitizes message, error, stack and context', () async {
    await logger.error(
      'mapbox',
      'GET https://api.mapbox.com?access_token=pk.secret',
      error: Exception('Bearer eyJabc'),
      stackTrace: StackTrace.fromString('apikey=secret\n'),
      context: {
        'url': 'https://api.test?access_token=pk.x',
        'token': 'sensitive',
      },
    );
    final e = sink.entries.first;
    expect(e.message, isNot(contains('pk.secret')));
    expect(e.error, isNot(contains('eyJabc')));
    expect(e.stackTrace, isNot(contains('secret')));
    expect(e.context!['url'], contains('***REDACTED***'));
    expect(e.context!['token'], '***REDACTED***');
  });

  test('rate-limits identical (level,tag) above the threshold', () async {
    for (var i = 0; i < 15; i++) {
      await logger.error('flutter', 'boom $i');
    }
    expect(sink.entries.length, lessThanOrEqualTo(10));
  });

  test('truncates oversized message, error and stack to caps', () async {
    final longMsg = 'm' * (AppLogger.maxMessageLength + 500);
    final longErr = 'e' * (AppLogger.maxErrorLength + 500);
    final longStack = 's' * (AppLogger.maxStackLength + 500);

    await logger.error(
      'app',
      longMsg,
      error: longErr,
      stackTrace: StackTrace.fromString(longStack),
    );

    final e = sink.entries.first;
    expect(e.message.length, lessThanOrEqualTo(AppLogger.maxMessageLength));
    expect(e.error!.length, lessThanOrEqualTo(AppLogger.maxErrorLength));
    expect(e.stackTrace!.length, lessThanOrEqualTo(AppLogger.maxStackLength));
    // The tail is replaced by a marker so it's obvious it was cut.
    expect(e.message, endsWith('…[truncated]'));
  });
}
