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
    // Minimal route: start gate at (0,0), path goes north briefly.
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
    test('gap skips distance and speed updates', () async {
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

      expect(engine.snapshot.totalDistanceMeters,
          preGapSnapshot.totalDistanceMeters);
      expect(engine.snapshot.lastSpeedMps, preGapSnapshot.lastSpeedMps);
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
