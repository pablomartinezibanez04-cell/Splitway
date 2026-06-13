import 'package:splitway_core/splitway_core.dart';
import 'package:test/test.dart';

RouteTemplate _buildTestRoute() {
  final start = const GateDefinition(
    left: GeoPoint(latitude: 0, longitude: -0.001),
    right: GeoPoint(latitude: 0, longitude: 0.001),
  );
  final s1 = SectorDefinition(
    id: 'sec-1',
    order: 0,
    label: 'Sector 1',
    gate: const GateDefinition(
      left: GeoPoint(latitude: 0.001, longitude: 0.0005),
      right: GeoPoint(latitude: 0.001, longitude: 0.0015),
    ),
  );
  final s2 = SectorDefinition(
    id: 'sec-2',
    order: 1,
    label: 'Sector 2',
    gate: const GateDefinition(
      left: GeoPoint(latitude: 0.0005, longitude: 0.002),
      right: GeoPoint(latitude: 0.0015, longitude: 0.002),
    ),
  );
  return RouteTemplate(
    id: 'route-test',
    name: 'Test loop',
    path: const [
      GeoPoint(latitude: 0, longitude: 0),
      GeoPoint(latitude: 0.001, longitude: 0.001),
      GeoPoint(latitude: 0.001, longitude: 0.002),
      GeoPoint(latitude: 0, longitude: 0),
    ],
    startFinishGate: start,
    sectors: [s1, s2],
    difficulty: RouteDifficulty.easy,
    createdAt: DateTime.parse('2026-04-29T10:00:00Z'),
  );
}

TelemetryPoint _p(double lat, double lng, DateTime t, {double speed = 10}) {
  return TelemetryPoint(
    timestamp: t,
    location: GeoPoint(latitude: lat, longitude: lng),
    speedMps: speed,
  );
}

void main() {
  test('engine emits started, sectorCrossed, lapClosed in order', () async {
    final route = _buildTestRoute();
    final base = DateTime.parse('2026-04-29T10:00:00Z');
    final engine =
        TrackingEngine(route: route, sessionId: 'sess-1', clock: () => base);
    final received = <TrackingEvent>[];
    engine.events.listen(received.add);

    engine.start();
    // Approach the start gate.
    engine.ingest(_p(-0.0005, 0, base));
    // Cross start gate (mid-gate at lng~0.0004).
    engine.ingest(_p(0.0005, 0.0008, base.add(const Duration(seconds: 1))));
    // Cross sector 1 gate (mid-gate at lng=0.0008).
    engine.ingest(_p(0.0015, 0.0008, base.add(const Duration(seconds: 4))));
    // Cross sector 2 gate.
    engine.ingest(_p(0.001, 0.0025, base.add(const Duration(seconds: 7))));
    // Cross start gate again to close lap 1.
    engine.ingest(_p(-0.0005, 0, base.add(const Duration(seconds: 10))));

    await Future<void>.delayed(Duration.zero);

    expect(received, isNotEmpty);
    expect(received.first, isA<TrackingStarted>());
    final sectorEvents = received.whereType<SectorCrossed>().toList();
    expect(sectorEvents.length, 2);
    expect(sectorEvents[0].sectorId, 'sec-1');
    expect(sectorEvents[1].sectorId, 'sec-2');
    final lapEvents = received.whereType<LapClosed>().toList();
    expect(lapEvents.length, 1);
    expect(lapEvents.first.lap.lapNumber, 1);
    expect(lapEvents.first.lap.duration, const Duration(seconds: 9));
    await engine.dispose();
  });

  test('sectorSummaries getter exposes crossings as they accumulate',
      () async {
    final route = _buildTestRoute();
    final base = DateTime.parse('2026-04-29T10:00:00Z');
    final engine =
        TrackingEngine(route: route, sessionId: 'sess-sec', clock: () => base);

    expect(engine.sectorSummaries, isEmpty);

    engine.start();
    engine.ingest(_p(-0.0005, 0, base));
    engine.ingest(_p(0.0005, 0.0008, base.add(const Duration(seconds: 1))));
    engine.ingest(_p(0.0015, 0.0008, base.add(const Duration(seconds: 4))));
    engine.ingest(_p(0.001, 0.0025, base.add(const Duration(seconds: 7))));

    final summaries = engine.sectorSummaries;
    expect(summaries.length, 2);
    expect(summaries[0].sectorId, 'sec-1');
    expect(summaries[0].lapNumber, 1);
    expect(summaries[1].sectorId, 'sec-2');

    await engine.dispose();
  });

  test('engine ignores points before start() is called', () {
    final route = _buildTestRoute();
    final base = DateTime.parse('2026-04-29T10:00:00Z');
    final engine =
        TrackingEngine(route: route, sessionId: 'sess-2', clock: () => base);

    engine.ingest(_p(0.0005, 0, base));
    expect(engine.snapshot.status, TrackingStatus.idle);
    expect(engine.snapshot.totalDistanceMeters, 0);
  });

  test('finish() returns a SessionRun with the recorded laps', () async {
    final route = _buildTestRoute();
    final base = DateTime.parse('2026-04-29T10:00:00Z');
    final engine =
        TrackingEngine(route: route, sessionId: 'sess-3', clock: () => base);

    engine.start();
    engine.ingest(_p(-0.0005, 0, base));
    engine.ingest(_p(0.0005, 0.0008, base.add(const Duration(seconds: 1))));
    engine.ingest(_p(0.0015, 0.0008, base.add(const Duration(seconds: 4))));
    engine.ingest(_p(0.001, 0.0025, base.add(const Duration(seconds: 7))));
    engine.ingest(_p(-0.0005, 0, base.add(const Duration(seconds: 10))));

    final session = engine.finish();
    expect(session.id, 'sess-3');
    expect(session.routeTemplateId, route.id);
    expect(session.status, SessionStatus.completed);
    expect(session.laps.length, greaterThanOrEqualTo(1));
    expect(session.laps.first.completed, isTrue);
    expect(session.sectorSummaries.length, 2);
    expect(session.totalDistanceMeters, greaterThan(0));
    await engine.dispose();
  });

  test('finish() with an open lap marks it as incomplete', () async {
    final route = _buildTestRoute();
    final base = DateTime.parse('2026-04-29T10:00:00Z');
    final engine =
        TrackingEngine(route: route, sessionId: 'sess-4', clock: () => base);

    engine.start();
    engine.ingest(_p(-0.0005, 0, base));
    engine.ingest(_p(0.0005, 0.0008, base.add(const Duration(seconds: 1))));
    engine.ingest(_p(0.0015, 0.0008, base.add(const Duration(seconds: 4))));

    final session = engine.finish();
    expect(session.laps.length, 1);
    expect(session.laps.first.completed, isFalse);
    await engine.dispose();
  });

  test('gate cooldown: two crossings 500 ms apart count as one', () async {
    // Minimal closed route: start gate at (0,0), path loops back.
    final gate = GateDefinition(
      left: GeoPoint(latitude: 0.0, longitude: -0.0001),
      right: GeoPoint(latitude: 0.0, longitude: 0.0001),
    );
    final route = RouteTemplate(
      id: 'r1', name: 'test',
      path: const [
        GeoPoint(latitude: 0.0,    longitude: 0.0),
        GeoPoint(latitude: 0.0005, longitude: 0.0),
        GeoPoint(latitude: 0.001,  longitude: 0.0),
        GeoPoint(latitude: 0.0,    longitude: 0.0),
      ],
      startFinishGate: gate,
      sectors: const [],
      difficulty: RouteDifficulty.easy,
      createdAt: DateTime(2026),
    );

    final now = DateTime(2026, 1, 1, 12, 0, 0);
    var tick = now;
    final engine = TrackingEngine(
      route: route,
      sessionId: 's1',
      clock: () => tick,
    )..start();

    final events = <TrackingEvent>[];
    engine.events.listen(events.add);

    // Approach from south (before gate).
    final pBefore = GeoPoint(latitude: -0.0002, longitude: 0.0);
    // Point past gate (north, inside circuit).
    final pInside = GeoPoint(latitude: 0.0002, longitude: 0.0);

    // First crossing — should open lap 1.
    tick = now;
    engine.ingest(TelemetryPoint(timestamp: tick, location: pBefore, speedMps: 10));
    tick = now.add(const Duration(milliseconds: 100));
    engine.ingest(TelemetryPoint(timestamp: tick, location: pInside, speedMps: 10));

    // Second crossing 500 ms later — should be ignored (cooldown = 3 s).
    tick = now.add(const Duration(milliseconds: 600));
    engine.ingest(TelemetryPoint(timestamp: tick, location: pBefore, speedMps: 10));
    tick = now.add(const Duration(milliseconds: 700));
    engine.ingest(TelemetryPoint(timestamp: tick, location: pInside, speedMps: 10));

    await Future<void>.delayed(Duration.zero);  // flush async stream

    // Only one TrackingStarted (lap opened once, not twice).
    expect(events.whereType<TrackingStarted>().length, 1);
    // Both back-crossings were within the 3-second cooldown window,
    // so no lap should have been closed.
    expect(events.whereType<LapClosed>().length, 0);
    await engine.dispose();
  });

  group('gap detection', () {
    test('gap skips distance accumulation but updates speed', () async {
      final route = _buildTestRoute();
      final base = DateTime.parse('2026-04-29T10:00:00Z');
      final engine =
          TrackingEngine(route: route, sessionId: 'gap-1', clock: () => base);

      engine.start();
      engine.ingest(_p(-0.0005, 0, base));
      engine.ingest(_p(-0.0004, 0, base.add(const Duration(seconds: 1))));

      final preGapSnapshot = engine.snapshot;

      // 10-second gap — exceeds the 5 s threshold
      engine.ingest(_p(0.01, 0, base.add(const Duration(seconds: 11)),
          speed: 99));

      // Distance must not jump across the gap (anti-teleport guard).
      expect(engine.snapshot.totalDistanceMeters,
          preGapSnapshot.totalDistanceMeters);
      // But speed is per-sample — the latest reading is shown immediately.
      expect(engine.snapshot.lastSpeedMps, 99);
      await engine.dispose();
    });

    test('recovery window skips metrics for subsequent points', () async {
      final route = _buildTestRoute();
      final base = DateTime.parse('2026-04-29T10:00:00Z');
      final engine =
          TrackingEngine(route: route, sessionId: 'gap-2', clock: () => base);

      engine.start();
      engine.ingest(_p(-0.0005, 0, base));
      engine.ingest(_p(-0.0004, 0, base.add(const Duration(seconds: 1))));

      final preGapDistance = engine.snapshot.totalDistanceMeters;

      // Trigger gap at t=11s — recovery until t=14s
      engine.ingest(_p(0.01, 0, base.add(const Duration(seconds: 11)),
          speed: 50));
      // Still recovering at t=13s
      engine.ingest(_p(0.011, 0, base.add(const Duration(seconds: 13)),
          speed: 40));

      expect(engine.snapshot.totalDistanceMeters, preGapDistance);
      await engine.dispose();
    });

    test('normal tracking resumes after recovery window', () async {
      final route = _buildTestRoute();
      final base = DateTime.parse('2026-04-29T10:00:00Z');
      final engine =
          TrackingEngine(route: route, sessionId: 'gap-3', clock: () => base);

      engine.start();
      engine.ingest(_p(-0.0005, 0, base));
      engine.ingest(_p(-0.0004, 0, base.add(const Duration(seconds: 1))));

      // Trigger gap at t=11s — recovery until t=14s
      engine.ingest(_p(0.01, 0, base.add(const Duration(seconds: 11)),
          speed: 50));
      // Still recovering at t=13s
      engine.ingest(_p(0.0101, 0, base.add(const Duration(seconds: 13)),
          speed: 40));

      final preResumeDistance = engine.snapshot.totalDistanceMeters;

      // Past recovery at t=15s
      engine.ingest(_p(0.0102, 0, base.add(const Duration(seconds: 15)),
          speed: 12));

      expect(engine.snapshot.totalDistanceMeters,
          greaterThan(preResumeDistance));
      expect(engine.snapshot.lastSpeedMps, 12);
      await engine.dispose();
    });
  });

  group('open route', () {
    /// Builds a point-to-point (open) route:
    ///   start gate at latitude=0, sector at lat=0.001, finish at lat=0.002.
    ///   Path goes from (0,0) → (0.001,0.001) → (0.002,0).
    ///   First ≠ last → isClosed == false.
    RouteTemplate _buildOpenRoute() {
      final start = const GateDefinition(
        left: GeoPoint(latitude: 0, longitude: -0.001),
        right: GeoPoint(latitude: 0, longitude: 0.001),
      );
      final s1 = SectorDefinition(
        id: 'sec-1',
        order: 0,
        label: 'Sector 1',
        gate: const GateDefinition(
          left: GeoPoint(latitude: 0.001, longitude: 0.0005),
          right: GeoPoint(latitude: 0.001, longitude: 0.0015),
        ),
      );
      return RouteTemplate(
        id: 'route-open',
        name: 'Test open',
        path: const [
          GeoPoint(latitude: 0, longitude: 0),
          GeoPoint(latitude: 0.001, longitude: 0.001),
          GeoPoint(latitude: 0.002, longitude: 0),
        ],
        startFinishGate: start,
        sectors: [s1],
        difficulty: RouteDifficulty.easy,
        createdAt: DateTime.parse('2026-04-29T10:00:00Z'),
      );
    }

    test('route is recognised as open', () {
      final route = _buildOpenRoute();
      expect(route.isClosed, isFalse);
    });

    test('start gate begins tracking, sector is recorded, proximity finishes',
        () async {
      final route = _buildOpenRoute();
      final base = DateTime.parse('2026-04-29T10:00:00Z');
      final engine = TrackingEngine(
          route: route, sessionId: 'open-1', clock: () => base);
      final received = <TrackingEvent>[];
      engine.events.listen(received.add);

      engine.start();
      // Approach the start gate.
      engine.ingest(_p(-0.0005, 0, base));
      // Cross start gate.
      engine.ingest(_p(0.0005, 0.0008, base.add(const Duration(seconds: 1))));
      // Cross sector 1 gate.
      engine.ingest(_p(0.0015, 0.0008, base.add(const Duration(seconds: 4))));
      // Arrive within 20 m of the last path point (0.002, 0).
      // GeoPoint(0.002, 0.00005) is ~5 m away from (0.002, 0).
      engine.ingest(_p(0.002, 0.00005, base.add(const Duration(seconds: 7))));

      await Future<void>.delayed(Duration.zero);

      expect(received.first, isA<TrackingStarted>());
      expect(received.whereType<SectorCrossed>().length, 1);
      expect(received.whereType<SectorCrossed>().first.sectorId, 'sec-1');
      // No laps — open route.
      expect(received.whereType<LapClosed>().length, 0);
      // Auto-finished via proximity.
      expect(received.whereType<TrackingFinished>().length, 1);
      expect(engine.snapshot.status, TrackingStatus.finished);

      await engine.dispose();
    });

    test('re-crossing start/finish gate during run is ignored', () async {
      final route = _buildOpenRoute();
      final base = DateTime.parse('2026-04-29T10:00:00Z');
      final engine = TrackingEngine(
          route: route, sessionId: 'open-2', clock: () => base);
      final received = <TrackingEvent>[];
      engine.events.listen(received.add);

      engine.start();
      engine.ingest(_p(-0.0005, 0, base));
      // Cross start gate → TrackingStarted.
      engine.ingest(_p(0.0005, 0.0008, base.add(const Duration(seconds: 1))));
      // Move away and back across start gate (after cooldown).
      engine.ingest(_p(-0.0005, 0, base.add(const Duration(seconds: 5))));
      engine.ingest(_p(0.0005, 0.0008, base.add(const Duration(seconds: 6))));

      await Future<void>.delayed(Duration.zero);

      // Only one TrackingStarted, no LapClosed.
      expect(received.whereType<TrackingStarted>().length, 1);
      expect(received.whereType<LapClosed>().length, 0);
      // Still in progress — haven't reached the finish.
      expect(engine.snapshot.status, TrackingStatus.inLap);

      await engine.dispose();
    });

    test('finish() before reaching end produces no laps', () async {
      final route = _buildOpenRoute();
      final base = DateTime.parse('2026-04-29T10:00:00Z');
      final engine = TrackingEngine(
          route: route, sessionId: 'open-3', clock: () => base);

      engine.start();
      engine.ingest(_p(-0.0005, 0, base));
      engine.ingest(_p(0.0005, 0.0008, base.add(const Duration(seconds: 1))));
      engine.ingest(_p(0.0015, 0.0008, base.add(const Duration(seconds: 4))));

      final session = engine.finish();
      expect(session.laps, isEmpty);
      expect(session.sectorSummaries.length, 1);
      expect(session.totalDistanceMeters, greaterThan(0));

      await engine.dispose();
    });

    test('finish() after auto-finish returns correct session', () async {
      final route = _buildOpenRoute();
      final base = DateTime.parse('2026-04-29T10:00:00Z');
      final engine = TrackingEngine(
          route: route, sessionId: 'open-4', clock: () => base);

      engine.start();
      engine.ingest(_p(-0.0005, 0, base));
      engine.ingest(_p(0.0005, 0.0008, base.add(const Duration(seconds: 1))));
      engine.ingest(_p(0.0015, 0.0008, base.add(const Duration(seconds: 4))));
      // Reach finish.
      engine.ingest(_p(0.002, 0.00005, base.add(const Duration(seconds: 7))));

      final session = engine.finish();
      expect(session.laps, isEmpty);
      expect(session.sectorSummaries.length, 1);
      expect(session.status, SessionStatus.completed);
      expect(session.endedAt, isNotNull);

      await engine.dispose();
    });
  });

  test('finish() right after lap close does not save phantom lap', () async {
    final route = _buildTestRoute();
    final base = DateTime.parse('2026-04-29T10:00:00Z');
    final engine =
        TrackingEngine(route: route, sessionId: 'sess-phantom', clock: () => base);

    engine.start();
    engine.ingest(_p(-0.0005, 0, base));
    engine.ingest(_p(0.0005, 0.0008, base.add(const Duration(seconds: 1))));
    engine.ingest(_p(0.0015, 0.0008, base.add(const Duration(seconds: 4))));
    engine.ingest(_p(0.001, 0.0025, base.add(const Duration(seconds: 7))));
    // Cross start gate again to close lap 1 — engine opens lap 2 internally.
    engine.ingest(_p(-0.0005, 0, base.add(const Duration(seconds: 10))));
    // Finish immediately — lap 2 has ~0 m distance.
    final session = engine.finish();

    expect(session.laps.length, 1);
    expect(session.laps.first.completed, isTrue);
    expect(session.laps.first.lapNumber, 1);
    await engine.dispose();
  });

  test('gate cooldown: crossing after 3+ s is accepted and closes lap', () async {
    final gate = GateDefinition(
      left: GeoPoint(latitude: 0.0, longitude: -0.0001),
      right: GeoPoint(latitude: 0.0, longitude: 0.0001),
    );
    final route = RouteTemplate(
      id: 'r1',
      name: 'test',
      path: const [
        GeoPoint(latitude: 0.0, longitude: 0.0),
        GeoPoint(latitude: 0.0005, longitude: 0.0),
        GeoPoint(latitude: 0.001, longitude: 0.0),
        GeoPoint(latitude: 0.0, longitude: 0.0),
      ],
      startFinishGate: gate,
      sectors: const [],
      difficulty: RouteDifficulty.easy,
      createdAt: DateTime(2026),
    );

    final now = DateTime(2026, 1, 1, 12, 0, 0);
    var tick = now;
    final engine = TrackingEngine(
      route: route,
      sessionId: 's1',
      clock: () => tick,
    )..start();

    final events = <TrackingEvent>[];
    engine.events.listen(events.add);

    final pBefore = GeoPoint(latitude: -0.0002, longitude: 0.0);
    final pInside = GeoPoint(latitude: 0.0002, longitude: 0.0);

    // First crossing — opens lap 1.
    tick = now;
    engine.ingest(TelemetryPoint(timestamp: tick, location: pBefore, speedMps: 10));
    tick = now.add(const Duration(milliseconds: 100));
    engine.ingest(TelemetryPoint(timestamp: tick, location: pInside, speedMps: 10));

    // Second crossing 3.5 s later — past the cooldown, should close lap 1.
    tick = now.add(const Duration(milliseconds: 3500));
    engine.ingest(TelemetryPoint(timestamp: tick, location: pBefore, speedMps: 10));
    tick = now.add(const Duration(milliseconds: 3600));
    engine.ingest(TelemetryPoint(timestamp: tick, location: pInside, speedMps: 10));

    await Future<void>.delayed(Duration.zero); // flush async stream

    expect(events.whereType<TrackingStarted>().length, 1);
    expect(events.whereType<LapClosed>().length, 1);
    await engine.dispose();
  });
}
