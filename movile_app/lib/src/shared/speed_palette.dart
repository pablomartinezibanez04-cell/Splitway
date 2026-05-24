import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';

import '../services/settings/app_settings_controller.dart';

/// 5-stop rainbow palette used for the speed heatmap.
/// Ordered from slow (blue) to fast (red).
const List<(double, Color)> kSpeedPaletteStops = [
  (0.0, Color(0xFF1565C0)), // blue
  (0.25, Color(0xFF00BCD4)), // cyan
  (0.5, Color(0xFF43A047)), // green
  (0.75, Color(0xFFFDD835)), // yellow
  (1.0, Color(0xFFE53935)), // red
];

/// Maps a normalized value [t] in [0..1] to a color along the speed palette.
/// Values outside the range are clamped.
Color speedColor(double t) {
  if (t.isNaN) return kSpeedPaletteStops.first.$2;
  if (t <= 0) return kSpeedPaletteStops.first.$2;
  if (t >= 1) return kSpeedPaletteStops.last.$2;
  for (var i = 0; i < kSpeedPaletteStops.length - 1; i++) {
    final (p0, c0) = kSpeedPaletteStops[i];
    final (p1, c1) = kSpeedPaletteStops[i + 1];
    if (t >= p0 && t <= p1) {
      final f = (t - p0) / (p1 - p0);
      return Color.lerp(c0, c1, f)!;
    }
  }
  return kSpeedPaletteStops.last.$2;
}

/// Rounds [rawMaxMps] up to a "nice" value in the user's display unit
/// (km/h or mph) and returns the rounded value back in m/s.
///
/// The display step is 10 (km/h or mph) for values ≤120, 20 above. A value
/// of zero or below is treated as 1 km/h (or 1 mph) to keep the legend usable.
double niceMaxMps(double rawMaxMps, UnitSystem unit) {
  final factor = unit == UnitSystem.imperial ? 2.23694 : 3.6;
  final displayValue = rawMaxMps * factor;
  if (displayValue <= 0 || displayValue.isNaN) {
    return 1.0 / factor;
  }
  // Absorb floating-point drift so that values that are an exact step
  // (e.g. exactly 120 km/h round-tripped through m/s) don't jump up.
  final adjusted = displayValue - 1e-6;
  final step = adjusted <= 10 ? 2.0 : adjusted <= 30 ? 5.0 : adjusted <= 120 ? 10.0 : 20.0;
  final rounded = (adjusted / step).ceil() * step;
  return rounded / factor;
}

/// A single (line-progress, normalized speed) sample used to build the
/// Mapbox `lineGradientExpression` stops.
class SpeedHeatmapStop {
  const SpeedHeatmapStop(this.progress, this.color);
  final double progress;
  final Color color;
}

/// Builds the ordered list of gradient stops along a telemetry polyline.
///
/// Skips points with null `speedMps`. When the resulting count exceeds
/// [maxStops], the list is decimated uniformly while preserving the first
/// and last samples. Normalizes speeds against [maxMps] (clamped to [0..1]).
///
/// Returns an empty list if fewer than two usable points remain.
List<SpeedHeatmapStop> buildSpeedHeatmapStops({
  required List<TelemetryPoint> telemetry,
  required double maxMps,
  int maxStops = 500,
}) {
  if (telemetry.length < 2 || maxMps <= 0) return const [];

  // Cumulative distance along the full telemetry path.
  final cumulative = List<double>.filled(telemetry.length, 0);
  for (var i = 1; i < telemetry.length; i++) {
    cumulative[i] = cumulative[i - 1] +
        telemetry[i - 1].location.distanceTo(telemetry[i].location);
  }
  final total = cumulative.last;
  if (total <= 0) return const [];

  // Collect indices of points with usable speed data.
  final usable = <int>[];
  for (var i = 0; i < telemetry.length; i++) {
    if (telemetry[i].speedMps != null) usable.add(i);
  }
  if (usable.length < 2) return const [];

  // Decimate uniformly while keeping first and last indices.
  List<int> indices;
  if (usable.length <= maxStops) {
    indices = usable;
  } else {
    indices = <int>[];
    for (var k = 0; k < maxStops; k++) {
      final pick = (k * (usable.length - 1) / (maxStops - 1)).round();
      indices.add(usable[pick]);
    }
  }

  final stops = <SpeedHeatmapStop>[];
  for (var k = 0; k < indices.length; k++) {
    final i = indices[k];
    double progress;
    if (k == 0) {
      progress = 0.0;
    } else if (k == indices.length - 1) {
      progress = 1.0;
    } else {
      progress = (cumulative[i] / total).clamp(0.0, 1.0);
    }
    // Mapbox's interpolate expression requires strictly increasing inputs.
    if (stops.isNotEmpty && progress <= stops.last.progress) {
      progress = stops.last.progress + 1e-9;
    }
    final t = (telemetry[i].speedMps! / maxMps).clamp(0.0, 1.0);
    stops.add(SpeedHeatmapStop(progress, speedColor(t)));
  }
  return stops;
}
