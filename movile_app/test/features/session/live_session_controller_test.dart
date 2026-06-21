import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/features/session/live_session_controller.dart';
import 'package:splitway_mobile/src/services/sensors/device_heading_service.dart';

/// No-op heading service — avoids platform-channel calls in unit tests.
class _StubHeadingService extends DeviceHeadingService {
  @override
  void start() {}
  @override
  void stop() {}
  @override
  void dispose() {}
  @override
  Stream<double> get headingStream => const Stream.empty();
  @override
  double? get currentHeadingDeg => null;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SplitwayLocalDatabase db;
  late LocalDraftRepository repo;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    repo = LocalDraftRepository(db)..userId = 'user-1';
  });

  tearDown(() async => db.close());

  RouteTemplate route() => RouteTemplate(
        id: 'r1',
        name: 'R1',
        path: const [],
        startFinishGate: GateDefinition(
          left: GeoPoint(latitude: 0, longitude: 0),
          right: GeoPoint(latitude: 0, longitude: 0),
        ),
        sectors: const [],
        difficulty: RouteDifficulty.medium,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  TelemetryPoint tp(double lat, double lon, DateTime t) => TelemetryPoint(
        timestamp: t,
        location: GeoPoint(latitude: lat, longitude: lon),
        speedMps: 12,
      );

  RouteTemplate openRoute() => RouteTemplate(
        id: 'r-open',
        name: 'Open',
        path: const [
          GeoPoint(latitude: 40.0, longitude: -3.0),
          GeoPoint(latitude: 40.00018, longitude: -3.0),
          GeoPoint(latitude: 40.00036, longitude: -3.0),
        ],
        startFinishGate: GateDefinition(
          left: GeoPoint(latitude: 40.0, longitude: -3.0001),
          right: GeoPoint(latitude: 40.0, longitude: -2.9999),
        ),
        sectors: const [],
        difficulty: RouteDifficulty.easy,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  Future<void> seedPriorSession() async {
    await repo.saveRouteTemplate(route());
    await repo.saveSessionRun(SessionRun(
      id: 'prev',
      routeTemplateId: 'r1',
      startedAt: DateTime.utc(2026, 1, 1),
      endedAt: DateTime.utc(2026, 1, 1, 0, 2),
      status: SessionStatus.completed,
      points: const [],
      laps: [
        LapSummary(
          lapNumber: 1,
          duration: const Duration(seconds: 90),
          startedAt: DateTime.utc(2026, 1, 1),
          endedAt: DateTime.utc(2026, 1, 1, 0, 1, 30),
          distanceMeters: 1000,
          avgSpeedMps: 11,
        ),
      ],
      sectorSummaries: [
        SectorSummary(
          sectorId: 'sec-1',
          lapNumber: 1,
          duration: const Duration(seconds: 30),
          startedAt: DateTime.utc(2026, 1, 1),
          endedAt: DateTime.utc(2026, 1, 1, 0, 0, 30),
          distanceMeters: 300,
          avgSpeedMps: 10,
        ),
      ],
      totalDistanceMeters: 1000,
      maxSpeedMps: 12,
      avgSpeedMps: 11,
    ));
  }

  test('includeHistorical=true loads sector records and best lap', () async {
    await seedPriorSession();
    final ctrl = LiveSessionController(repo, headingService: _StubHeadingService());
    await ctrl.load();
    ctrl.selectRoute(route());
    await ctrl.startSession(includeHistorical: true);

    expect(ctrl.historicalSectorRecords['sec-1'], const Duration(seconds: 30));
    expect(ctrl.historicalBestLap, const Duration(seconds: 90));
    ctrl.dispose();
  });

  test('includeHistorical=false leaves history empty', () async {
    await seedPriorSession();
    final ctrl = LiveSessionController(repo, headingService: _StubHeadingService());
    await ctrl.load();
    ctrl.selectRoute(route());
    await ctrl.startSession(includeHistorical: false);

    expect(ctrl.historicalSectorRecords, isEmpty);
    expect(ctrl.historicalBestLap, isNull);
    ctrl.dispose();
  });

  test('open route auto-finishes the session when the end is reached',
      () async {
    await repo.saveRouteTemplate(openRoute());
    final ctrl =
        LiveSessionController(repo, headingService: _StubHeadingService());
    await ctrl.load();
    ctrl.selectRoute(openRoute());
    await ctrl.startSession(includeHistorical: false);

    expect(ctrl.stage, LiveSessionStage.running);

    final base = DateTime(2026, 5, 9, 10);
    final t = ctrl.tracker!;
    // South of the gate → cross gate (lap begins, ~34 m from end) → reach the
    // last path point (40.00036). The crossing point stays outside the 20 m
    // finish-proximity so the run does not finish prematurely.
    t.ingestSimulatedPoint(tp(39.9999, -3.0, base));
    t.ingestSimulatedPoint(tp(40.00005, -3.0, base.add(const Duration(seconds: 1))));
    t.ingestSimulatedPoint(tp(40.00036, -3.0, base.add(const Duration(seconds: 2))));

    // Let the engine event propagate to the tracker, then to the session
    // controller, then let the async finishSession() complete (it awaits the
    // repo save).
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(ctrl.stage, LiveSessionStage.finished);
    expect(ctrl.result, isNotNull);
    expect(ctrl.result!.id, t.sessionId);

    // The finished run was persisted for the route. (saveSessionRun upserts by
    // id, so this asserts the run exists, not that the save ran exactly once.)
    final saved = await repo.getSessionsByRoute('r-open');
    expect(saved.length, 1);
    expect(saved.single.id, t.sessionId);

    ctrl.dispose();
  });

  test('referenceDuration uses previous best total when competing', () async {
    // Route with a normal time, plus a prior completed run of 100 s.
    final r = route().copyWith(expectedDuration: const Duration(seconds: 200));
    await repo.saveRouteTemplate(r);
    await repo.saveSessionRun(SessionRun(
      id: 'prev-open',
      routeTemplateId: 'r1',
      startedAt: DateTime.utc(2026, 1, 1, 0, 0, 0),
      endedAt: DateTime.utc(2026, 1, 1, 0, 1, 40), // 100 s
      status: SessionStatus.completed,
      points: const [],
      laps: const [],
      sectorSummaries: const [],
      totalDistanceMeters: 500,
      maxSpeedMps: 12,
      avgSpeedMps: 10,
    ));
    final ctrl = LiveSessionController(repo, headingService: _StubHeadingService());
    await ctrl.load();
    ctrl.selectRoute(r);
    await ctrl.startSession(includeHistorical: true);

    expect(ctrl.referenceDuration, const Duration(seconds: 100));
    ctrl.dispose();
  });

  test('referenceDuration falls back to route normal time', () async {
    // Competing chosen but no prior runs → use expectedDuration.
    final r = route().copyWith(expectedDuration: const Duration(seconds: 200));
    await repo.saveRouteTemplate(r);
    final ctrl = LiveSessionController(repo, headingService: _StubHeadingService());
    await ctrl.load();
    ctrl.selectRoute(r);
    await ctrl.startSession(includeHistorical: true);

    expect(ctrl.referenceDuration, const Duration(seconds: 200));

    // Not competing → also the normal time, even if a prior run exists.
    await ctrl.startSession(includeHistorical: false);
    expect(ctrl.referenceDuration, const Duration(seconds: 200));
    ctrl.dispose();
  });
}
