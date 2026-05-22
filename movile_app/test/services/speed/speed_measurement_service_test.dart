import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/speed/speed_measurement_service.dart';
import 'package:splitway_mobile/src/services/speed/speed_metric.dart';
import 'package:splitway_mobile/src/services/speed/speed_sample.dart';

void main() {
  group('SpeedMeasurementService (skeleton)', () {
    test('starts with all targets null and updates topSpeed', () {
      final svc = SpeedMeasurementService.forTesting(
        targets: {SpeedMetric.topSpeed},
      );
      svc.start();
      expect(svc.results.value[SpeedMetric.topSpeed], null);
      svc.debugInjectSample(const SpeedSample(
        tSinceStart: Duration(milliseconds: 100),
        speedKmh: 50,
        distanceM: 1.5,
        accelMs2: 4,
      ));
      svc.debugInjectSample(const SpeedSample(
        tSinceStart: Duration(milliseconds: 200),
        speedKmh: 80,
        distanceM: 3.7,
        accelMs2: 4,
      ));
      svc.stop();
      expect(svc.results.value[SpeedMetric.topSpeed], 80.0);
    });
  });

  group('SpeedMeasurementService milestones', () {
    test('zeroTo100 resolved by linear interpolation', () {
      final svc = SpeedMeasurementService.forTesting(
        targets: {SpeedMetric.zeroTo100},
      );
      svc.start();
      svc.debugInjectSample(const SpeedSample(
        tSinceStart: Duration(milliseconds: 4000),
        speedKmh: 90,
        distanceM: 30,
        accelMs2: 8,
      ));
      svc.debugInjectSample(const SpeedSample(
        tSinceStart: Duration(milliseconds: 4500),
        speedKmh: 110,
        distanceM: 50,
        accelMs2: 8,
      ));
      svc.stop();
      // 100 km/h crossed: 4000 + (100-90)/(110-90) * 500 = 4250 ms
      expect(svc.results.value[SpeedMetric.zeroTo100], closeTo(4.25, 1e-6));
    });

    test('sixtyFoot resolved by distance crossing', () {
      final svc = SpeedMeasurementService.forTesting(
        targets: {SpeedMetric.sixtyFoot},
      );
      svc.start();
      svc.debugInjectSample(const SpeedSample(
        tSinceStart: Duration(milliseconds: 1500),
        speedKmh: 40,
        distanceM: 10,
        accelMs2: 5,
      ));
      svc.debugInjectSample(const SpeedSample(
        tSinceStart: Duration(milliseconds: 2500),
        speedKmh: 60,
        distanceM: 30,
        accelMs2: 5,
      ));
      svc.stop();
      // 18.29 m crossed: 1500 + (18.29-10)/(30-10) * 1000 = 1914.5 ms
      expect(svc.results.value[SpeedMetric.sixtyFoot], closeTo(1.9145, 1e-3));
    });

    test('quarterMile resolved by distance crossing', () {
      final svc = SpeedMeasurementService.forTesting(
        targets: {SpeedMetric.quarterMile},
      );
      svc.start();
      svc.debugInjectSample(const SpeedSample(
        tSinceStart: Duration(milliseconds: 10000),
        speedKmh: 180,
        distanceM: 380,
        accelMs2: 4,
      ));
      svc.debugInjectSample(const SpeedSample(
        tSinceStart: Duration(milliseconds: 11000),
        speedKmh: 200,
        distanceM: 430,
        accelMs2: 4,
      ));
      svc.stop();
      // 402.336 crossed: 10000 + (402.336-380)/(430-380) * 1000 = 10446.7 ms
      expect(svc.results.value[SpeedMetric.quarterMile], closeTo(10.4467, 1e-3));
    });

    test('reactionTime resolved when sustained speed exceeds threshold', () {
      final svc = SpeedMeasurementService.forTesting(
        targets: {SpeedMetric.reactionTime},
      );
      svc.start();
      svc.debugInjectSample(const SpeedSample(
        tSinceStart: Duration(milliseconds: 100),
        speedKmh: 0.2,
        distanceM: 0.01,
        accelMs2: 0,
      ));
      svc.debugInjectSample(const SpeedSample(
        tSinceStart: Duration(milliseconds: 250),
        speedKmh: 1,
        distanceM: 0.05,
        accelMs2: 4,
      ));
      svc.debugInjectSample(const SpeedSample(
        tSinceStart: Duration(milliseconds: 420),
        speedKmh: 4,
        distanceM: 0.3,
        accelMs2: 4,
      ));
      svc.stop();
      expect(
        svc.results.value[SpeedMetric.reactionTime],
        closeTo(0.25, 1e-3),
      );
    });
  });

  group('SpeedMeasurementService false start', () {
    test('emits FalseStartDetected when speed sustained over threshold', () async {
      final svc = SpeedMeasurementService.forTesting(
        targets: {SpeedMetric.zeroTo100},
      );
      final events = <FalseStartDetected>[];
      final sub = svc.falseStartStream.listen(events.add);
      svc.arm();
      svc.debugInjectSample(const SpeedSample(
        tSinceStart: Duration(milliseconds: 50),
        speedKmh: 2,
        distanceM: 0.1,
        accelMs2: 2,
      ));
      svc.debugInjectSample(const SpeedSample(
        tSinceStart: Duration(milliseconds: 220),
        speedKmh: 3,
        distanceM: 0.3,
        accelMs2: 2,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      await sub.cancel();
    });

    test('does not trigger on brief sub-threshold jitter', () async {
      final svc = SpeedMeasurementService.forTesting(
        targets: {SpeedMetric.zeroTo100},
      );
      final events = <FalseStartDetected>[];
      final sub = svc.falseStartStream.listen(events.add);
      svc.arm();
      svc.debugInjectSample(const SpeedSample(
        tSinceStart: Duration(milliseconds: 50),
        speedKmh: 0.4,
        distanceM: 0.0,
        accelMs2: 0.2,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      await sub.cancel();
    });
  });
}
