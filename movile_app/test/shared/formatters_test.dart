import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';
import 'package:splitway_mobile/src/shared/formatters.dart';

void main() {
  group('Formatters.duration', () {
    test('formats with dot separator', () {
      expect(
        Formatters.duration(
          const Duration(minutes: 1, seconds: 23, milliseconds: 456),
        ),
        '01:23.456',
      );
    });

    test('formats with comma separator', () {
      expect(
        Formatters.duration(
          const Duration(minutes: 1, seconds: 23, milliseconds: 456),
          dotSeparator: false,
        ),
        '01:23,456',
      );
    });

    test('handles zero duration', () {
      expect(Formatters.duration(Duration.zero), '00:00.000');
    });

    test('returns placeholder for negative duration', () {
      expect(
        Formatters.duration(const Duration(milliseconds: -1)),
        '--:--.---',
      );
    });
  });

  group('Formatters.speedMps - metric', () {
    test('converts m/s to km/h', () {
      // 10 m/s = 36 km/h
      expect(Formatters.speedMps(10.0), '36.0');
    });
  });

  group('Formatters.speedMps - imperial', () {
    test('converts m/s to mph', () {
      // 10 m/s = 36 km/h = ~22.37 mph
      final result = double.parse(Formatters.speedMps(10.0, unit: UnitSystem.imperial));
      expect(result, closeTo(22.4, 0.1));
    });
  });

  group('Formatters.distanceMeters - metric', () {
    test('returns meters when below 1000', () {
      final (value, isKm) = Formatters.distanceMeters(500);
      expect(isKm, isFalse);
      expect(value, 500);
    });

    test('returns km when at or above 1000', () {
      final (value, isKm) = Formatters.distanceMeters(1500);
      expect(isKm, isTrue);
      expect(value, 1.5);
    });
  });

  group('Formatters.distanceMeters - imperial', () {
    test('returns feet when below 1 mile', () {
      final (value, isMiles) = Formatters.distanceMeters(100, unit: UnitSystem.imperial);
      expect(isMiles, isFalse);
      expect(value, closeTo(328.1, 0.1));
    });

    test('returns miles when at or above 1 mile (1609m)', () {
      final (value, isMiles) = Formatters.distanceMeters(1609.344, unit: UnitSystem.imperial);
      expect(isMiles, isTrue);
      expect(value, closeTo(1.0, 0.01));
    });
  });
}
