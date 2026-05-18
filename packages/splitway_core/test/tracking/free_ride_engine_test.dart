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
        timestamp: baseTime.add(const Duration(seconds: 10)),
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
        timestamp: baseTime.add(const Duration(seconds: 30)),
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
  });
}
