import 'package:splitway_core/splitway_core.dart';
import 'package:test/test.dart';

void main() {
  group('SessionRun.hasStarted', () {
    SessionRun base({
      List<TelemetryPoint> points = const [],
      List<LapSummary> laps = const [],
    }) =>
        SessionRun(
          id: 's-1',
          routeTemplateId: 'r-1',
          startedAt: DateTime.utc(2026, 1, 1),
          endedAt: DateTime.utc(2026, 1, 1),
          status: SessionStatus.completed,
          points: points,
          laps: laps,
          sectorSummaries: const [],
          totalDistanceMeters: 0,
          maxSpeedMps: 0,
          avgSpeedMps: 0,
        );

    test('is false when the run never crossed the start line', () {
      expect(base().hasStarted, isFalse);
    });

    test('is true when telemetry points were recorded', () {
      final run = base(points: [
        TelemetryPoint(
          timestamp: DateTime.utc(2026, 1, 1),
          location: const GeoPoint(latitude: 40.0, longitude: -3.0),
          speedMps: 10,
        ),
      ]);
      expect(run.hasStarted, isTrue);
    });

    test('is true when a lap was recorded', () {
      final run = base(laps: [
        LapSummary(
          lapNumber: 1,
          duration: const Duration(seconds: 60),
          startedAt: DateTime.utc(2026, 1, 1),
          endedAt: DateTime.utc(2026, 1, 1, 0, 1),
          distanceMeters: 500,
          avgSpeedMps: 8,
        ),
      ]);
      expect(run.hasStarted, isTrue);
    });
  });
}
