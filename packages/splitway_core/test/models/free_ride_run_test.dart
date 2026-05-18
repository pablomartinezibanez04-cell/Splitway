import 'package:splitway_core/splitway_core.dart';
import 'package:test/test.dart';

void main() {
  group('FreeRideRun', () {
    test('totalDuration returns difference between start and end', () {
      final run = FreeRideRun(
        id: 'fr-1',
        startedAt: DateTime(2026, 1, 1, 10, 0),
        endedAt: DateTime(2026, 1, 1, 10, 30),
        status: FreeRideStatus.completed,
        points: const [],
        totalDistanceMeters: 5000,
        maxSpeedMps: 15.0,
        avgSpeedMps: 10.0,
      );
      expect(run.totalDuration, const Duration(minutes: 30));
    });

    test('totalDuration is null when endedAt is null', () {
      final run = FreeRideRun(
        id: 'fr-2',
        startedAt: DateTime(2026, 1, 1, 10, 0),
        status: FreeRideStatus.recording,
        points: const [],
        totalDistanceMeters: 0,
        maxSpeedMps: 0,
        avgSpeedMps: 0,
      );
      expect(run.totalDuration, isNull);
    });

    test('copyWith overrides specified fields', () {
      final run = FreeRideRun(
        id: 'fr-3',
        startedAt: DateTime(2026, 1, 1),
        status: FreeRideStatus.recording,
        points: const [],
        totalDistanceMeters: 0,
        maxSpeedMps: 0,
        avgSpeedMps: 0,
      );
      final updated = run.copyWith(
        name: 'Morning jog',
        status: FreeRideStatus.completed,
        totalDistanceMeters: 3000,
      );
      expect(updated.name, 'Morning jog');
      expect(updated.status, FreeRideStatus.completed);
      expect(updated.totalDistanceMeters, 3000);
      expect(updated.id, 'fr-3');
    });

    test('path returns locations from telemetry points', () {
      final points = [
        TelemetryPoint(
          timestamp: DateTime(2026, 1, 1, 10, 0),
          location: const GeoPoint(latitude: 40.0, longitude: -3.0),
          speedMps: 5.0,
        ),
        TelemetryPoint(
          timestamp: DateTime(2026, 1, 1, 10, 1),
          location: const GeoPoint(latitude: 40.001, longitude: -3.001),
          speedMps: 5.0,
        ),
      ];
      final run = FreeRideRun(
        id: 'fr-4',
        startedAt: DateTime(2026, 1, 1, 10, 0),
        status: FreeRideStatus.completed,
        points: points,
        totalDistanceMeters: 150,
        maxSpeedMps: 5.0,
        avgSpeedMps: 5.0,
      );
      expect(run.path, hasLength(2));
      expect(run.path.first.latitude, 40.0);
    });
  });
}
