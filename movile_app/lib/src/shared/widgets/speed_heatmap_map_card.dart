import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';

import '../../config/app_config.dart';
import '../../services/settings/app_settings_controller.dart';
import '../speed_palette.dart';
import 'speed_heatmap_legend.dart';
import 'speed_heatmap_toggle_button.dart';
import 'splitway_map.dart';

/// Renders the read-only history map for a finished session/free-ride and,
/// when the user toggles it on, overlays a speed heatmap legend on the
/// right and asks [SplitwayMap] to draw the telemetry as a gradient line.
class SpeedHeatmapMapCard extends StatefulWidget {
  const SpeedHeatmapMapCard({
    super.key,
    required this.config,
    required this.telemetry,
    this.route,
    this.unitSystem = UnitSystem.metric,
    this.aspectRatio = 4 / 3,
  });

  final AppConfig config;
  final List<TelemetryPoint> telemetry;
  final RouteTemplate? route;
  final UnitSystem unitSystem;
  final double aspectRatio;

  @override
  State<SpeedHeatmapMapCard> createState() => _SpeedHeatmapMapCardState();
}

class _SpeedHeatmapMapCardState extends State<SpeedHeatmapMapCard> {
  bool _heatmap = false;

  bool get _canHeatmap {
    if (widget.telemetry.length < 2) return false;
    var withSpeed = 0;
    for (final p in widget.telemetry) {
      if (p.speedMps != null) {
        withSpeed += 1;
        if (withSpeed >= 2) return true;
      }
    }
    return false;
  }

  double get _niceMaxMps {
    var raw = 0.0;
    for (final p in widget.telemetry) {
      final s = p.speedMps;
      if (s != null && s > raw) raw = s;
    }
    return niceMaxMps(raw, widget.unitSystem);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          children: [
            SplitwayMap(
              useMapbox: widget.config.hasMapbox,
              route: widget.route,
              telemetry: widget.telemetry,
              interactive: false,
              showSpeedHeatmap: _heatmap,
              speedHeatmapUnit: widget.unitSystem,
            ),
            if (_canHeatmap)
              Positioned(
                top: 8,
                left: 8,
                child: SpeedHeatmapToggleButton(
                  active: _heatmap,
                  onPressed: () => setState(() => _heatmap = !_heatmap),
                ),
              ),
            if (_heatmap && _canHeatmap)
              Positioned(
                top: 56,
                right: 12,
                bottom: 16,
                child: SpeedHeatmapLegend(
                  maxMps: _niceMaxMps,
                  unit: widget.unitSystem,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
