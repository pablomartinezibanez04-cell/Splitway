import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/src/data/local/speed_session_dao.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/services/speed/speed_metric.dart';
import 'package:splitway_mobile/src/services/speed/speed_session.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SplitwayLocalDatabase db;
  late SpeedSessionDao dao;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    dao = SpeedSessionDao(db.raw);
  });

  tearDown(() async => db.close());

  test('insert and listForUser', () async {
    final now = DateTime.now();
    final session = SpeedSession(
      id: 's1',
      userId: 'u1',
      vehicleId: 'v1',
      name: 'Run 1',
      selectedMetrics: {SpeedMetric.zeroTo100, SpeedMetric.topSpeed},
      results: {SpeedMetric.zeroTo100: 5.4, SpeedMetric.topSpeed: 180.0},
      countdownSeconds: 3,
      isPartial: false,
      startedAt: now,
      finishedAt: now.add(const Duration(seconds: 20)),
      createdAt: now,
      updatedAt: now,
    );

    await dao.upsert(session);
    final all = await dao.listForUser('u1');
    expect(all, hasLength(1));
    expect(all.first.id, 's1');
    expect(all.first.results[SpeedMetric.zeroTo100], 5.4);
  });

  test('soft delete excludes from listForUser', () async {
    final now = DateTime.now();
    final session = SpeedSession(
      id: 's2',
      userId: 'u1',
      vehicleId: null,
      name: 'x',
      selectedMetrics: {SpeedMetric.topSpeed},
      results: {SpeedMetric.topSpeed: 100.0},
      countdownSeconds: 3,
      isPartial: false,
      startedAt: now,
      finishedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    await dao.upsert(session);
    await dao.softDelete('s2');
    final all = await dao.listForUser('u1');
    expect(all, isEmpty);
  });
}
