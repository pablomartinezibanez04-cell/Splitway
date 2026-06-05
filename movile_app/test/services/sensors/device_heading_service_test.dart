import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/sensors/device_heading_service.dart';

void main() {
  group('angularDifferenceDeg', () {
    test('returns zero when angles match', () {
      expect(angularDifferenceDeg(90, 90), 0);
    });

    test('returns the signed short-arc difference', () {
      expect(angularDifferenceDeg(100, 80), 20);
      expect(angularDifferenceDeg(80, 100), -20);
    });

    test('handles the 359° → 1° wrap-around', () {
      expect(angularDifferenceDeg(1, 359), closeTo(2, 1e-9));
      expect(angularDifferenceDeg(359, 1), closeTo(-2, 1e-9));
    });
  });

  group('fusedBearingDeg', () {
    test('returns the compass heading when GPS course is null', () {
      expect(
        fusedBearingDeg(
          compassDeg: 42,
          gpsCourseDeg: null,
          speedMps: 100,
        ),
        42,
      );
    });

    test('returns the GPS course when compass is null', () {
      expect(
        fusedBearingDeg(
          compassDeg: null,
          gpsCourseDeg: 270,
          speedMps: 0,
        ),
        270,
      );
    });

    test('returns null when both inputs are null', () {
      expect(
        fusedBearingDeg(
          compassDeg: null,
          gpsCourseDeg: null,
          speedMps: 0,
        ),
        isNull,
      );
    });

    test('uses compass at standstill (below minTrustSpeed)', () {
      expect(
        fusedBearingDeg(
          compassDeg: 30,
          gpsCourseDeg: 200,
          speedMps: 0.2,
        ),
        30,
      );
    });

    test('uses GPS course at speed (above fullTrustSpeed)', () {
      expect(
        fusedBearingDeg(
          compassDeg: 30,
          gpsCourseDeg: 200,
          speedMps: 10,
        ),
        200,
      );
    });

    test('blends along the shorter arc in the transition window', () {
      // Midpoint of the [1, 4] m/s range; expect 50/50 blend along the short
      // arc between 350° and 10°, which is 0° (or 360°).
      final blended = fusedBearingDeg(
        compassDeg: 350,
        gpsCourseDeg: 10,
        speedMps: 2.5,
      );
      expect(blended, isNotNull);
      // Result should sit between 350° and 10° via the +20° short arc,
      // i.e. close to 0° / 360°.
      final diffFromZero =
          angularDifferenceDeg(blended!, 0).abs();
      expect(diffFromZero, lessThan(0.001));
    });
  });
}
