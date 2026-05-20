import 'package:intl/intl.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

class Formatters {
  Formatters._();

  /// Formats [d] as `MM:SS.mmm`. Pass `dotSeparator: false` for comma.
  static String duration(Duration d, {bool dotSeparator = true}) {
    final ms = d.inMilliseconds;
    if (ms < 0) return '--:--.---';
    final totalSeconds = d.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final millis = ms % 1000;
    final sep = dotSeparator ? '.' : ',';
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}$sep'
        '${millis.toString().padLeft(3, '0')}';
  }

  /// Speed in m/s → formatted numeric string in km/h (metric) or mph (imperial).
  /// Caller wraps the result with the appropriate unit label.
  static String speedMps(double mps, {UnitSystem unit = UnitSystem.metric}) {
    final kmh = mps * 3.6;
    if (unit == UnitSystem.imperial) {
      return (kmh * 0.621371).toStringAsFixed(1);
    }
    return kmh.toStringAsFixed(1);
  }

  /// Distance in metres → `(value, isLargeUnit)`.
  ///
  /// Metric: metres / kilometres. Imperial: feet / miles.
  /// `isLargeUnit` is true for km or miles, false for m or feet.
  static (double value, bool isLargeUnit) distanceMeters(
    double meters, {
    UnitSystem unit = UnitSystem.metric,
  }) {
    if (unit == UnitSystem.imperial) {
      final feet = meters * 3.28084;
      if (feet >= 5280) return (feet / 5280, true); // miles
      return (feet, false); // feet
    }
    if (meters >= 1000) return (meters / 1000, true); // km
    return (meters, false); // m
  }

  /// Uses `Intl.defaultLocale` set by `LocaleController`.
  static String dateTime(DateTime dt) {
    return DateFormat('dd MMM yyyy · HH:mm').format(dt);
  }
}
