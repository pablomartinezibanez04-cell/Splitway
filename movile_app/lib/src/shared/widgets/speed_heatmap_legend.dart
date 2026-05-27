import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../services/settings/app_settings_controller.dart';
import '../formatters.dart';
import '../speed_palette.dart';

/// Horizontal color-bar legend overlaid on the bottom of the map when the
/// speed heatmap mode is active. Always labels in km/h or mph, never m/s.
class SpeedHeatmapLegend extends StatelessWidget {
  const SpeedHeatmapLegend({
    super.key,
    required this.maxMps,
    required this.unit,
  });

  /// Maximum speed represented at the right end of the bar, in m/s.
  /// Caller should pass a `niceMaxMps(...)` value.
  final double maxMps;
  final UnitSystem unit;

  String _label(AppLocalizations l, double mps) {
    final v = Formatters.speedMps(mps, unit: unit);
    return unit == UnitSystem.imperial ? l.unitMph(v) : l.unitKmh(v);
  }

  static const _labelStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    shadows: [
      Shadow(offset: Offset(0, 0), blurRadius: 3, color: Colors.black),
      Shadow(offset: Offset(0, 0), blurRadius: 6, color: Colors.black),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    final colors = kSpeedPaletteStops.map((s) => s.$2).toList();
    final stops = kSpeedPaletteStops.map((s) => s.$1).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_label(l, 0), style: _labelStyle),
              Text(_label(l, maxMps / 2), style: _labelStyle),
              Text(_label(l, maxMps), style: _labelStyle),
            ],
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 6,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: colors,
                  stops: stops,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
