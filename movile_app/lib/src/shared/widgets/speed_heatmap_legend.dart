import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../services/settings/app_settings_controller.dart';
import '../formatters.dart';
import '../speed_palette.dart';

/// Vertical color-bar legend shown next to the map when the speed heatmap
/// mode is active. Always labels in km/h or mph (never m/s).
class SpeedHeatmapLegend extends StatelessWidget {
  const SpeedHeatmapLegend({
    super.key,
    required this.maxMps,
    required this.unit,
  });

  /// Maximum speed represented at the top of the bar, in m/s.
  /// Caller should pass a `niceMaxMps(...)` value.
  final double maxMps;
  final UnitSystem unit;

  String _label(AppLocalizations l, double mps) {
    final v = Formatters.speedMps(mps, unit: unit);
    return unit == UnitSystem.imperial ? l.unitMph(v) : l.unitKmh(v);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Build the gradient stops from the palette, top = max, bottom = 0.
    final colors = kSpeedPaletteStops.reversed.map((s) => s.$2).toList();
    final stops = kSpeedPaletteStops.reversed.map((s) => 1.0 - s.$1).toList();

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      color: theme.colorScheme.surface.withValues(alpha: 0.9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: colors,
                    stops: stops,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_label(l, maxMps),
                    style: theme.textTheme.labelSmall),
                Text(_label(l, maxMps / 2),
                    style: theme.textTheme.labelSmall),
                Text(_label(l, 0),
                    style: theme.textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
