import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/src/features/history/run_comparison.dart';

void main() {
  RouteTemplate openRoute() => RouteTemplate(
        id: 'r-open',
        name: 'Open',
        path: const [
          GeoPoint(latitude: 40.0, longitude: -3.0),
          GeoPoint(latitude: 40.001, longitude: -3.0),
        ],
        startFinishGate: GateDefinition(
          left: GeoPoint(latitude: 40.0, longitude: -3.0001),
          right: GeoPoint(latitude: 40.0, longitude: -2.9999),
        ),
        sectors: const [],
        difficulty: RouteDifficulty.easy,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  SessionRun notStartedSession() => SessionRun(
        id: 's-empty',
        routeTemplateId: 'r-open',
        startedAt: DateTime.utc(2026, 1, 1, 0, 0, 0),
        endedAt: DateTime.utc(2026, 1, 1, 0, 0, 0),
        status: SessionStatus.completed,
        points: const [],
        laps: const [],
        sectorSummaries: const [],
        totalDistanceMeters: 0,
        maxSpeedMps: 0,
        avgSpeedMps: 0,
      );

  test('representativeRunTime is null for a not-started open-route session', () {
    expect(representativeRunTime(openRoute(), notStartedSession()), isNull);
  });

  test('percent is negative when faster than expected', () {
    final pct = runDeltaPercent(
      expected: const Duration(seconds: 100),
      actual: const Duration(seconds: 80),
    );
    expect(pct, -20.0);
  });

  test('percent is positive when slower than expected', () {
    final pct = runDeltaPercent(
      expected: const Duration(seconds: 100),
      actual: const Duration(seconds: 110),
    );
    expect(pct, 10.0);
  });

  test('percent is null when expected is zero', () {
    expect(
      runDeltaPercent(
          expected: Duration.zero, actual: const Duration(seconds: 1)),
      isNull,
    );
  });
}
