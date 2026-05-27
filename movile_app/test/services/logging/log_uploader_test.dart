import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/services/logging/log_entry.dart';
import 'package:splitway_mobile/src/services/logging/log_level.dart';
import 'package:splitway_mobile/src/services/logging/log_uploader.dart';
import 'package:splitway_mobile/src/services/logging/sinks/local_sink.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SplitwayLocalDatabase db;
  late LocalSink sink;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    sink = LocalSink(db);
  });

  tearDown(() async {
    await db.close();
  });

  LogEntry sample(String id) => LogEntry(
        id: id,
        timestamp: DateTime.utc(2026, 5, 27, 12),
        level: LogLevel.error,
        tag: 'supabase',
        message: id,
        appVersion: '0.4.0+1',
        platform: 'test',
        deviceModel: 'test',
      );

  test('drain uploads pending rows in batches and marks them synced', () async {
    for (var i = 0; i < 3; i++) {
      await sink.write(sample('id$i'));
    }
    final calls = <int>[];
    final uploader = LogUploader(
      sink: sink,
      upload: (batch) async => calls.add(batch.length),
      batchSize: 2,
    );

    await uploader.drain();

    expect(calls, [2, 1]);
    expect(await sink.countPending(), 0);
  });

  test('drain increments attempts when upload throws', () async {
    await sink.write(sample('id0'));
    final uploader = LogUploader(
      sink: sink,
      upload: (_) async => throw Exception('boom'),
      batchSize: 10,
    );

    await uploader.drain();

    expect(await sink.countPending(), 1);
    final rows = await db.raw.query('app_logs');
    expect(rows.first['sync_attempts'], 1);
    expect(rows.first['synced'], 0);
  });

  test('drain is a no-op when upload is disabled', () async {
    await sink.write(sample('id0'));
    var called = false;
    final uploader = LogUploader(
      sink: sink,
      upload: (_) async => called = true,
      batchSize: 10,
      enabled: () => false,
    );

    await uploader.drain();

    expect(called, isFalse);
    expect(await sink.countPending(), 1);
  });

  test('scheduleDrain debounces concurrent triggers', () async {
    await sink.write(sample('id0'));
    var calls = 0;
    final uploader = LogUploader(
      sink: sink,
      upload: (_) async => calls++,
      batchSize: 10,
      debounce: const Duration(milliseconds: 10),
    );

    uploader.scheduleDrain();
    uploader.scheduleDrain();
    uploader.scheduleDrain();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(calls, 1);
  });
}
