import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/src/data/local/speed_session_dao.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/speed_repository.dart';
import 'package:splitway_mobile/src/services/speed/speed_metric.dart';
import 'package:splitway_mobile/src/services/speed/speed_session.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SplitwayLocalDatabase db;
  late SpeedRepository repo;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    repo = SpeedRepository(
      localDao: SpeedSessionDao(db.raw),
      supabase: null,
    );
  });

  tearDown(() async => db.close());

  test('save persists locally and listForUser returns it', () async {
    final now = DateTime.now();
    final session = SpeedSession(
      id: 'a',
      userId: 'u',
      vehicleId: null,
      name: 'n',
      selectedMetrics: {SpeedMetric.topSpeed},
      results: {SpeedMetric.topSpeed: 90.0},
      countdownSeconds: 3,
      isPartial: false,
      startedAt: now,
      finishedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    await repo.save(session);
    final list = await repo.listForUser('u');
    expect(list.single.name, 'n');
  });
}
