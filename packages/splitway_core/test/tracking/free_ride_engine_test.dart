import 'package:splitway_core/splitway_core.dart';
import 'package:test/test.dart';

void main() {
  group('FreeRideEngine', () {
    late FreeRideEngine engine;
    final baseTime = DateTime(2026, 1, 1, 10, 0);

    setUp(() {
      engine = FreeRideEngine(
        sessionId: 'test-fr',
        clock: () => baseTime.add(const Duration(minutes: 5)),
      );
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('snapshot is idle before start', () {
      expect(engine.snapshot.status, FreeRideTrackingStatus.idle);
      expect(engine.snapshot.pointCount, 0);
    });

    test('snapshot transitions to recording after start', () {
      engine.start();
      expect(engine.snapshot.status, FreeRideTrackingStatus.recording);
    });

    test('ignores points before start', () {
      engine.ingest(TelemetryPoint(
        timestamp: baseTime,
        location: const GeoPoint(latitude: 40.0, longitude: -3.0),
      ));
      expect(engine.snapshot.pointCount, 0);
    });

    test('accumulates distance between ingested points', () {
      engine.start();
      final p1 = TelemetryPoint(
        timestamp: baseTime,
        location: const GeoPoint(latitude: 40.0, longitude: -3.0),
        speedMps: 5.0,
      );
      final p2 = TelemetryPoint(
        timestamp: baseTime.add(const Duration(seconds: 2)),
        location: const GeoPoint(latitude: 40.001, longitude: -3.0),
        speedMps: 10.0,
      );
      engine.ingest(p1);
      engine.ingest(p2);

      expect(engine.snapshot.pointCount, 2);
      expect(engine.snapshot.totalDistanceMeters, greaterThan(100));
      expect(engine.snapshot.maxSpeedMps, 10.0);
      expect(engine.snapshot.currentSpeedMps, 10.0);
    });

    test('finish returns a FreeRideRun with computed stats', () {
      engine.start();
      engine.ingest(TelemetryPoint(
        timestamp: baseTime,
        location: const GeoPoint(latitude: 40.0, longitude: -3.0),
        speedMps: 5.0,
      ));
      engine.ingest(TelemetryPoint(
        timestamp: baseTime.add(const Duration(seconds: 2)),
        location: const GeoPoint(latitude: 40.001, longitude: -3.0),
        speedMps: 12.0,
      ));

      final result = engine.finish();

      expect(result.id, 'test-fr');
      expect(result.status, FreeRideStatus.completed);
      expect(result.points, hasLength(2));
      expect(result.totalDistanceMeters, greaterThan(100));
      expect(result.maxSpeedMps, 12.0);
      expect(result.avgSpeedMps, greaterThan(0));
      expect(result.endedAt, isNotNull);
    });

    test('finish is idempotent', () {
      engine.start();
      engine.ingest(TelemetryPoint(
        timestamp: baseTime,
        location: const GeoPoint(latitude: 40.0, longitude: -3.0),
      ));
      final first = engine.finish();
      final second = engine.finish();
      expect(first.id, second.id);
      expect(first.points.length, second.points.length);
    });

    test('ignores points after finish', () {
      engine.start();
      engine.ingest(TelemetryPoint(
        timestamp: baseTime,
        location: const GeoPoint(latitude: 40.0, longitude: -3.0),
      ));
      engine.finish();
      engine.ingest(TelemetryPoint(
        timestamp: baseTime.add(const Duration(seconds: 60)),
        location: const GeoPoint(latitude: 41.0, longitude: -3.0),
      ));
      expect(engine.snapshot.pointCount, 1);
    });

    group('gap detection', () {
      test('gap skips distance and speed updates', () {
        engine.start();
        engine.ingest(TelemetryPoint(
          timestamp: baseTime,
          location: const GeoPoint(latitude: 40.0, longitude: -3.0),
          speedMps: 5.0,
        ));
        engine.ingest(TelemetryPoint(
          timestamp: baseTime.add(const Duration(seconds: 1)),
          location: const GeoPoint(latitude: 40.0001, longitude: -3.0),
          speedMps: 8.0,
        ));

        final preGapDistance = engine.snapshot.totalDistanceMeters;
        final preGapMax = engine.snapshot.maxSpeedMps;
        final preGapCurrent = engine.snapshot.currentSpeedMps;

        // 10-second gap — exceeds the 5 s threshold
        engine.ingest(TelemetryPoint(
          timestamp: baseTime.add(const Duration(seconds: 11)),
          location: const GeoPoint(latitude: 40.01, longitude: -3.0),
          speedMps: 99.0,
        ));

        expect(engine.snapshot.totalDistanceMeters, preGapDistance);
        expect(engine.snapshot.maxSpeedMps, preGapMax);
        expect(engine.snapshot.currentSpeedMps, preGapCurrent);
      });

      test('recovery window skips metrics for subsequent points', () {
        engine.start();
        engine.ingest(TelemetryPoint(
          timestamp: baseTime,
          location: const GeoPoint(latitude: 40.0, longitude: -3.0),
          speedMps: 5.0,
        ));
        engine.ingest(TelemetryPoint(
          timestamp: baseTime.add(const Duration(seconds: 1)),
          location: const GeoPoint(latitude: 40.0001, longitude: -3.0),
          speedMps: 5.0,
        ));

        final preGapDistance = engine.snapshot.totalDistanceMeters;

        // Trigger gap at t=11s
        engine.ingest(TelemetryPoint(
          timestamp: baseTime.add(const Duration(seconds: 11)),
          location: const GeoPoint(latitude: 40.01, longitude: -3.0),
          speedMps: 50.0,
        ));

        // Point within the 3 s recovery window (t=13s, recovery ends at t=14s)
        engine.ingest(TelemetryPoint(
          timestamp: baseTime.add(const Duration(seconds: 13)),
          location: const GeoPoint(latitude: 40.011, longitude: -3.0),
          speedMps: 40.0,
        ));

        expect(engine.snapshot.totalDistanceMeters, preGapDistance);
        expect(engine.snapshot.maxSpeedMps, 5.0);
      });

      test('normal tracking resumes after recovery window', () {
        engine.start();
        engine.ingest(TelemetryPoint(
          timestamp: baseTime,
          location: const GeoPoint(latitude: 40.0, longitude: -3.0),
          speedMps: 5.0,
        ));
        engine.ingest(TelemetryPoint(
          timestamp: baseTime.add(const Duration(seconds: 1)),
          location: const GeoPoint(latitude: 40.0001, longitude: -3.0),
          speedMps: 5.0,
        ));

        // Trigger gap at t=11s — recovery until t=14s
        engine.ingest(TelemetryPoint(
          timestamp: baseTime.add(const Duration(seconds: 11)),
          location: const GeoPoint(latitude: 40.01, longitude: -3.0),
          speedMps: 50.0,
        ));
        // Still recovering at t=13s
        engine.ingest(TelemetryPoint(
          timestamp: baseTime.add(const Duration(seconds: 13)),
          location: const GeoPoint(latitude: 40.0101, longitude: -3.0),
          speedMps: 40.0,
        ));

        final preResumeDistance = engine.snapshot.totalDistanceMeters;

        // Past recovery at t=15s — normal tracking resumes
        engine.ingest(TelemetryPoint(
          timestamp: baseTime.add(const Duration(seconds: 15)),
          location: const GeoPoint(latitude: 40.0102, longitude: -3.0),
          speedMps: 12.0,
        ));

        expect(engine.snapshot.totalDistanceMeters, greaterThan(preResumeDistance));
        expect(engine.snapshot.currentSpeedMps, 12.0);
        expect(engine.snapshot.maxSpeedMps, 12.0);
      });
    });
  });
}
