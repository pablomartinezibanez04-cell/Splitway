import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/services/logging/log_entry.dart';
import 'package:splitway_mobile/src/services/logging/log_level.dart';
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

  LogEntry sample(String id, {DateTime? ts, LogLevel level = LogLevel.error}) =>
      LogEntry(
        id: id,
        timestamp: ts ?? DateTime.utc(2026, 5, 27, 12),
        level: level,
        tag: 'supabase',
        message: 'm $id',
        appVersion: '0.4.0+1',
        platform: 'test',
        deviceModel: 'test',
      );

  test('write inserts the entry as unsynced with 0 attempts', () async {
    await sink.write(sample('a'));
    final rows = await db.raw.query('app_logs');
    expect(rows, hasLength(1));
    expect(rows.first['synced'], 0);
    expect(rows.first['sync_attempts'], 0);
    expect(rows.first['id'], 'a');
  });

  test('write ignores duplicate id (idempotent)', () async {
    await sink.write(sample('a'));
    await sink.write(sample('a'));
    final rows = await db.raw.query('app_logs');
    expect(rows, hasLength(1));
  });

  test('pendingSync returns unsynced rows oldest-first', () async {
    await sink.write(sample('old', ts: DateTime.utc(2026, 5, 27, 10)));
    await sink.write(sample('new', ts: DateTime.utc(2026, 5, 27, 14)));
    final pending = await sink.pendingSync(limit: 50);
    expect(pending.map((e) => e.id), ['old', 'new']);
  });

  test('markSynced flips the synced flag', () async {
    await sink.write(sample('a'));
    await sink.markSynced(['a']);
    final pending = await sink.pendingSync(limit: 50);
    expect(pending, isEmpty);
  });

  test('incrementAttempts bumps the counter', () async {
    await sink.write(sample('a'));
    await sink.incrementAttempts(['a']);
    await sink.incrementAttempts(['a']);
    final rows = await db.raw.query('app_logs', where: 'id = ?', whereArgs: ['a']);
    expect(rows.first['sync_attempts'], 2);
  });

  test('purgeOlderThan deletes only synced rows past the threshold', () async {
    final old = DateTime.utc(2026, 5, 20);
    final recent = DateTime.utc(2026, 5, 27);
    await sink.write(sample('old-synced', ts: old));
    await sink.write(sample('old-unsynced', ts: old));
    await sink.write(sample('recent', ts: recent));
    await sink.markSynced(['old-synced']);
    await sink.purgeOlderThan(DateTime.utc(2026, 5, 25));
    final ids = (await db.raw.query('app_logs'))
        .map((r) => r['id'] as String)
        .toList()
      ..sort();
    expect(ids, ['old-unsynced', 'recent']);
  });

  test('purgeOlderThan also drops dead rows (>=5 attempts)', () async {
    final old = DateTime.utc(2026, 5, 20);
    await sink.write(sample('dead', ts: old));
    for (var i = 0; i < 5; i++) {
      await sink.incrementAttempts(['dead']);
    }
    await sink.purgeOlderThan(DateTime.utc(2026, 5, 25));
    final rows = await db.raw.query('app_logs');
    expect(rows, isEmpty);
  });

  test('trimToMaxCount keeps only the newest N rows', () async {
    for (var i = 0; i < 10; i++) {
      await sink.write(
        sample('id$i', ts: DateTime.utc(2026, 5, 27, 12, i)),
      );
    }
    await sink.trimToMaxCount(3);
    final ids = (await db.raw
            .query('app_logs', orderBy: 'timestamp DESC'))
        .map((r) => r['id'] as String)
        .toList();
    expect(ids, ['id9', 'id8', 'id7']);
  });

  test('list applies level and tag filters', () async {
    await sink.write(sample('a', level: LogLevel.error));
    await sink.write(sample('b', level: LogLevel.info));
    final errors = await sink.list(level: LogLevel.warning, limit: 100);
    expect(errors.map((e) => e.id), ['a']);
  });
}
