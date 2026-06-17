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
}
