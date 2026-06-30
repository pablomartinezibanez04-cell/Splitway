import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';

import '../../config/app_config.dart';
import '../../services/settings/app_settings_controller.dart';
import '../speed_palette.dart';
import 'speed_heatmap_legend.dart';
import 'splitway_map.dart';

/// Returns true if [telemetry] has at least two points with non-null speed.
bool hasUsableSpeedTelemetry(List<TelemetryPoint> telemetry) {
  if (telemetry.length < 2) return false;
  var withSpeed = 0;
  for (final p in telemetry) {
    if (p.speedMps != null) {
      withSpeed += 1;
      if (withSpeed >= 2) return true;
    }
  }
  return false;
}

/// Computes the nice-rounded max speed (in m/s) for a telemetry sample,
/// to drive both the gradient normalization and the legend max.
double niceMaxMpsFor(List<TelemetryPoint> telemetry, UnitSystem unit) {
  var raw = 0.0;
  for (final p in telemetry) {
    final s = p.speedMps;
    if (s != null && s > raw) raw = s;
  }
  return niceMaxMps(raw, unit);
}

/// Read-only history map card with an optional speed-heatmap overlay.
/// The toggle button is owned by the parent and passed in via [showHeatmap].
class SpeedHeatmapMapCard extends StatelessWidget {
  const SpeedHeatmapMapCard({
    super.key,
    required this.config,
    required this.telemetry,
    required this.showHeatmap,
    this.route,
    this.showSectors = false,
    this.unitSystem = UnitSystem.metric,
    this.aspectRatio = 4 / 3,
    this.finishMarker,
  });

  final AppConfig config;
  final List<TelemetryPoint> telemetry;
  final bool showHeatmap;
  final RouteTemplate? route;

  /// When true, the route is drawn in per-sector colors with sector boundary
  /// circles (matching the live panel). No effect when [route] has no sectors.
  final bool showSectors;
  final UnitSystem unitSystem;
  final double aspectRatio;

  /// Finish-flag position for route-less traces (e.g. a finished free ride).
  /// Forwarded to [SplitwayMap.finishMarker].
  final GeoPoint? finishMarker;

  @override
  Widget build(BuildContext context) {
    final canHeatmap = hasUsableSpeedTelemetry(telemetry);
    final showLegend = showHeatmap && canHeatmap;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          children: [
            SplitwayMap(
              useMapbox: config.hasMapbox,
              route: route,
              showSectors: showSectors,
              telemetry: telemetry,
              interactive: false,
              showSpeedHeatmap: showHeatmap,
              speedHeatmapUnit: unitSystem,
              finishMarker: finishMarker,
            ),
            if (showLegend)
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: SpeedHeatmapLegend(
                  maxMps: niceMaxMpsFor(telemetry, unitSystem),
                  unit: unitSystem,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
