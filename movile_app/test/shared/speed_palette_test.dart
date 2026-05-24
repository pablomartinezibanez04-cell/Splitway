import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';
import 'package:splitway_mobile/src/shared/speed_palette.dart';

void main() {
  group('speedColor', () {
    test('returns the first stop for t<=0', () {
      expect(speedColor(0).value, kSpeedPaletteStops.first.$2.value);
      expect(speedColor(-1).value, kSpeedPaletteStops.first.$2.value);
    });

    test('returns the last stop for t>=1', () {
      expect(speedColor(1).value, kSpeedPaletteStops.last.$2.value);
      expect(speedColor(5).value, kSpeedPaletteStops.last.$2.value);
    });

    test('returns the middle stop for t=0.5', () {
      // 0.5 is exactly the green stop.
      expect(speedColor(0.5).value, kSpeedPaletteStops[2].$2.value);
    });

    test('interpolates between stops', () {
      // 0.125 is halfway between blue (0.0) and cyan (0.25).
      final c = speedColor(0.125);
      final blue = kSpeedPaletteStops[0].$2;
      final cyan = kSpeedPaletteStops[1].$2;
      expect(c.red, ((blue.red + cyan.red) / 2).round());
      expect(c.green, ((blue.green + cyan.green) / 2).round());
      expect(c.blue, ((blue.blue + cyan.blue) / 2).round());
    });
  });

  group('niceMaxMps', () {
    double mpsToKmh(double mps) => mps * 3.6;
    double mpsToMph(double mps) => mps * 2.23694;

    test('rounds up to next 10 km/h below 120', () {
      // 47 km/h → 50 km/h. 47 km/h = 13.0556 m/s.
      expect(mpsToKmh(niceMaxMps(47 / 3.6, UnitSystem.metric)),
          closeTo(50, 1e-9));
      expect(mpsToKmh(niceMaxMps(87 / 3.6, UnitSystem.metric)),
          closeTo(90, 1e-9));
    });

    test('keeps exact multiples of 10 km/h unchanged', () {
      expect(mpsToKmh(niceMaxMps(120 / 3.6, UnitSystem.metric)),
          closeTo(120, 1e-9));
    });

    test('rounds up to next 20 km/h above 120', () {
      expect(mpsToKmh(niceMaxMps(121 / 3.6, UnitSystem.metric)),
          closeTo(140, 1e-9));
      expect(mpsToKmh(niceMaxMps(153 / 3.6, UnitSystem.metric)),
          closeTo(160, 1e-9));
    });

    test('rounds in mph for imperial unit', () {
      expect(mpsToMph(niceMaxMps(87 / 2.23694, UnitSystem.imperial)),
          closeTo(90, 1e-9));
      expect(mpsToMph(niceMaxMps(95 / 2.23694, UnitSystem.imperial)),
          closeTo(100, 1e-9));
    });

    test('falls back to 1 km/h for zero/negative input', () {
      expect(mpsToKmh(niceMaxMps(0, UnitSystem.metric)), closeTo(1, 1e-9));
      expect(mpsToKmh(niceMaxMps(-5, UnitSystem.metric)), closeTo(1, 1e-9));
    });
  });

  group('buildSpeedHeatmapStops', () {
    TelemetryPoint tp(double lat, double lng, double? mps) => TelemetryPoint(
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          location: GeoPoint(latitude: lat, longitude: lng),
          speedMps: mps,
        );

    test('returns empty when fewer than two points', () {
      expect(
        buildSpeedHeatmapStops(
          telemetry: [tp(0, 0, 5)],
          maxMps: 10,
        ),
        isEmpty,
      );
    });

    test('returns empty when no points have speed', () {
      expect(
        buildSpeedHeatmapStops(
          telemetry: [tp(0, 0, null), tp(0, 0.001, null)],
          maxMps: 10,
        ),
        isEmpty,
      );
    });

    test('first stop at 0.0 and last at 1.0', () {
      final stops = buildSpeedHeatmapStops(
        telemetry: [
          tp(40.0, -3.0, 5),
          tp(40.001, -3.0, 7),
          tp(40.002, -3.0, 9),
        ],
        maxMps: 10,
      );
      expect(stops.first.progress, 0.0);
      expect(stops.last.progress, 1.0);
    });

    test('progress is strictly increasing', () {
      final tel = <TelemetryPoint>[];
      for (var i = 0; i < 50; i++) {
        tel.add(tp(40.0 + i * 0.0005, -3.0, 5 + i * 0.1));
      }
      final stops = buildSpeedHeatmapStops(telemetry: tel, maxMps: 20);
      for (var i = 1; i < stops.length; i++) {
        expect(stops[i].progress, greaterThan(stops[i - 1].progress));
      }
    });

    test('caps output at maxStops while preserving endpoints', () {
      final tel = <TelemetryPoint>[];
      for (var i = 0; i < 2000; i++) {
        tel.add(tp(40.0 + i * 0.00001, -3.0, 5));
      }
      final stops =
          buildSpeedHeatmapStops(telemetry: tel, maxMps: 20, maxStops: 100);
      expect(stops.length, lessThanOrEqualTo(100));
      expect(stops.first.progress, 0.0);
      expect(stops.last.progress, 1.0);
    });
  });
}
