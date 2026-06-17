import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SplitwayLocalDatabase db;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
  });

  tearDown(() async => db.close());

  RouteTemplate makeRoute({
    required String id,
    bool isOfficial = false,
    DateTime? updatedAt,
  }) {
    return RouteTemplate(
      id: id,
      name: 'Route $id',
      path: const [],
      startFinishGate: GateDefinition(
        left: GeoPoint(latitude: 0, longitude: 0),
        right: GeoPoint(latitude: 0, longitude: 0),
      ),
      sectors: const [],
      difficulty: RouteDifficulty.medium,
      createdAt: DateTime.utc(2026, 1, 1),
      isOfficial: isOfficial,
      updatedAt: updatedAt,
    );
  }

  test('saveRouteTemplate persists isOfficial and updatedAt', () async {
    final repo = LocalDraftRepository(db);
    repo.userId = 'user-1';
    final ts = DateTime.utc(2026, 5, 1);
    final route = makeRoute(id: 'r1', isOfficial: false, updatedAt: ts);
    await repo.saveRouteTemplate(route);
    final loaded = await repo.getRouteTemplate('r1');
    expect(loaded!.isOfficial, isFalse);
    expect(loaded.updatedAt?.millisecondsSinceEpoch, ts.millisecondsSinceEpoch);
  });

  test('saveRouteTemplate allows owner_id NULL only for official routes',
      () async {
    final repo = LocalDraftRepository(db);
    // No userId set → simulates anonymous / cold-start writes
    final official = makeRoute(id: 'official-1', isOfficial: true);
    await repo.saveRouteTemplate(official);
    expect(await repo.getRouteTemplate('official-1'), isNotNull);

    // Non-official write with no userId must be rejected by the assert
    final userRoute = makeRoute(id: 'user-1', isOfficial: false);
    expect(
      () => repo.saveRouteTemplate(userRoute),
      throwsA(isA<AssertionError>()),
    );
  });

  test('clearUserData keeps all is_official=1 routes', () async {
    final repo = LocalDraftRepository(db);
    await repo.saveRouteTemplate(
        makeRoute(id: 'off-1', isOfficial: true));
    await repo.saveRouteTemplate(
        makeRoute(id: 'off-2', isOfficial: true));
    repo.userId = 'user-1';
    await repo.saveRouteTemplate(
        makeRoute(id: 'user-route', isOfficial: false));

    await repo.clearUserData();

    repo.userId = null;
    final remaining = await repo.getAllRoutes();
    final ids = remaining.map((r) => r.id).toSet();
    expect(ids, {'off-1', 'off-2'});
  });

  test(
      'purgeOwnerlessSessions removes NULL-owner sessions/free-rides and '
      'cascades telemetry, keeping owned rows', () async {
    // A route to satisfy the session_runs.route_id foreign key.
    await db.raw.insert('route_templates', {
      'id': 'r1',
      'name': 'Route r1',
      'path_json': '[]',
      'start_finish_gate_json':
          '{"left":{"latitude":0,"longitude":0},"right":{"latitude":0,"longitude":0}}',
      'difficulty': 'medium',
      'created_at': 0,
      'is_official': 1,
      'owner_id': null,
    });

    Map<String, Object?> session(String id, String? owner) => {
          'id': id,
          'route_id': 'r1',
          'started_at': 0,
          'status': 'completed',
          'lap_summaries_json': '[]',
          'sector_summaries_json': '[]',
          'total_distance_m': 0.0,
          'max_speed_mps': 0.0,
          'avg_speed_mps': 0.0,
          'owner_id': owner,
        };
    await db.raw.insert('session_runs', session('s-null', null));
    await db.raw.insert('session_runs', session('s-owned', 'user-1'));
    await db.raw.insert('telemetry_points', {
      'session_id': 's-null',
      'ts': 0,
      'lat': 0.0,
      'lng': 0.0,
    });

    Map<String, Object?> ride(String id, String? owner) => {
          'id': id,
          'started_at': 0,
          'status': 'completed',
          'total_distance_m': 0.0,
          'max_speed_mps': 0.0,
          'avg_speed_mps': 0.0,
          'owner_id': owner,
        };
    await db.raw.insert('free_rides', ride('fr-null', null));
    await db.raw.insert('free_rides', ride('fr-owned', 'user-1'));

    final repo = LocalDraftRepository(db);
    await repo.purgeOwnerlessSessions();

    final sessionIds = (await db.raw.query('session_runs'))
        .map((r) => r['id'])
        .toSet();
    final rideIds =
        (await db.raw.query('free_rides')).map((r) => r['id']).toSet();
    final telemetry = await db.raw.query('telemetry_points',
        where: 'session_id = ?', whereArgs: ['s-null']);

    expect(sessionIds, {'s-owned'});
    expect(rideIds, {'fr-owned'});
    expect(telemetry, isEmpty);
  });

  test(
      'purgeOrphanedSessions removes sessions whose route is missing and '
      'cascades telemetry, keeping linked sessions', () async {
    await db.raw.insert('route_templates', {
      'id': 'r-keep',
      'name': 'Route r-keep',
      'path_json': '[]',
      'start_finish_gate_json':
          '{"left":{"latitude":0,"longitude":0},"right":{"latitude":0,"longitude":0}}',
      'difficulty': 'medium',
      'created_at': 0,
      'is_official': 0,
      'owner_id': 'user-1',
    });

    Map<String, Object?> session(String id, String routeId) => {
          'id': id,
          'route_id': routeId,
          'started_at': 0,
          'status': 'completed',
          'lap_summaries_json': '[]',
          'sector_summaries_json': '[]',
          'total_distance_m': 0.0,
          'max_speed_mps': 0.0,
          'avg_speed_mps': 0.0,
          'owner_id': 'user-1',
        };

    await db.raw.insert('session_runs', session('s-keep', 'r-keep'));
    // Orphan: route_id points to a route that doesn't exist. Insert with the
    // FK disabled to reproduce the legacy bad-data state.
    await db.raw.execute('PRAGMA foreign_keys = OFF');
    await db.raw.insert('session_runs', session('s-orphan', 'ghost-route'));
    await db.raw.execute('PRAGMA foreign_keys = ON');
    await db.raw.insert('telemetry_points', {
      'session_id': 's-orphan',
      'ts': 0,
      'lat': 0.0,
      'lng': 0.0,
    });

    final repo = LocalDraftRepository(db);
    await repo.purgeOrphanedSessions();

    final sessionIds =
        (await db.raw.query('session_runs')).map((r) => r['id']).toSet();
    final orphanTelemetry = await db.raw.query('telemetry_points',
        where: 'session_id = ?', whereArgs: ['s-orphan']);

    expect(sessionIds, {'s-keep'});
    expect(orphanTelemetry, isEmpty);
  });

  test('purgeLegacyPublicRoutes removes orphan NULL-owner non-official routes',
      () async {
    // Insert a legacy orphan directly (bypassing the guardrail).
    await db.raw.insert('route_templates', {
      'id': 'legacy-orphan',
      'name': 'Old Demo',
      'description': null,
      'path_json': '[]',
      'start_finish_gate_json':
          '{"left":{"latitude":0,"longitude":0},"right":{"latitude":0,"longitude":0}}',
      'difficulty': 'medium',
      'created_at': 0,
      'location_label': null,
      'owner_id': null,
      'thumbnail_url': null,
      'elevation_range_m': null,
      'is_official': 0,
      'updated_at': null,
    });
    final repo = LocalDraftRepository(db);
    await repo.saveRouteTemplate(
        makeRoute(id: 'official-keep', isOfficial: true));

    await repo.purgeLegacyPublicRoutes();

    final remaining = await repo.getAllRoutes();
    final ids = remaining.map((r) => r.id).toSet();
    expect(ids, {'official-keep'});
  });

  SessionRun makeSession({required String id, String? name}) => SessionRun(
        id: id,
        routeTemplateId: 'r1',
        startedAt: DateTime.utc(2026, 1, 1),
        status: SessionStatus.completed,
        points: const [],
        laps: const [],
        sectorSummaries: const [],
        totalDistanceMeters: 0,
        maxSpeedMps: 0,
        avgSpeedMps: 0,
        name: name,
      );

  test('saveSessionRun round-trips the optional name', () async {
    final repo = LocalDraftRepository(db);
    repo.userId = 'user-1';
    await repo.saveRouteTemplate(makeRoute(id: 'r1'));

    await repo.saveSessionRun(makeSession(id: 's1', name: 'Hot lap'));
    expect((await repo.getSessionRun('s1'))!.name, 'Hot lap');

    await repo.saveSessionRun(makeSession(id: 's2', name: null));
    expect((await repo.getSessionRun('s2'))!.name, isNull);
  });
}
