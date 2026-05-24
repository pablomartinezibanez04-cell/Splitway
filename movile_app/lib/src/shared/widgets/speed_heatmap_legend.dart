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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final colors = kSpeedPaletteStops.map((s) => s.$2).toList();
    final stops = kSpeedPaletteStops.map((s) => s.$1).toList();

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      color: theme.colorScheme.surface.withValues(alpha: 0.9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 10,
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
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_label(l, 0), style: theme.textTheme.labelSmall),
                Text(_label(l, maxMps / 2), style: theme.textTheme.labelSmall),
                Text(_label(l, maxMps), style: theme.textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
