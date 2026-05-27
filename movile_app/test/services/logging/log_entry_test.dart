import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/logging/log_entry.dart';
import 'package:splitway_mobile/src/services/logging/log_level.dart';

void main() {
  group('LogEntry', () {
    final ts = DateTime.utc(2026, 5, 27, 12, 30, 15);

    test('toMap/fromMap round-trip preserves all fields', () {
      final entry = LogEntry(
        id: 'abc-123',
        timestamp: ts,
        level: LogLevel.error,
        tag: 'supabase',
        message: 'rpc failed',
        error: 'PostgrestException(...)',
        stackTrace: '#0 main',
        context: {'op': 'upsertSession', 'durationMs': 142},
        appVersion: '0.4.0+1',
        platform: 'android 14',
        deviceModel: 'Pixel 7',
        userId: 'user-1',
      );

      final round = LogEntry.fromMap(entry.toMap());

      expect(round.id, entry.id);
      expect(round.timestamp, entry.timestamp);
      expect(round.level, entry.level);
      expect(round.tag, entry.tag);
      expect(round.message, entry.message);
      expect(round.error, entry.error);
      expect(round.stackTrace, entry.stackTrace);
      expect(round.context, entry.context);
      expect(round.appVersion, entry.appVersion);
      expect(round.platform, entry.platform);
      expect(round.deviceModel, entry.deviceModel);
      expect(round.userId, entry.userId);
    });

    test('toMap stores timestamp as UTC milliseconds', () {
      final entry = _minimal(ts);
      expect(entry.toMap()['timestamp'], ts.millisecondsSinceEpoch);
    });

    test('fromMap handles null optional fields', () {
      final map = _minimal(ts).toMap();
      final round = LogEntry.fromMap(map);
      expect(round.error, isNull);
      expect(round.stackTrace, isNull);
      expect(round.context, isNull);
      expect(round.userId, isNull);
    });
  });
}

LogEntry _minimal(DateTime ts) => LogEntry(
      id: 'id',
      timestamp: ts,
      level: LogLevel.info,
      tag: 'app',
      message: 'm',
      appVersion: '0.0.0',
      platform: 'test',
      deviceModel: 'test',
    );
