import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Small circular button overlaid on the map. Toggles between the regular
/// view and the speed-heatmap view.
class SpeedHeatmapToggleButton extends StatelessWidget {
  const SpeedHeatmapToggleButton({
    super.key,
    required this.active,
    required this.onPressed,
  });

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tooltip = active ? l.heatmapToggleOff : l.heatmapToggleOn;
    final iconColor =
        active ? theme.colorScheme.primary : theme.colorScheme.onSurface;
    return Material(
      elevation: 4,
      shape: const CircleBorder(),
      color: theme.colorScheme.surface.withValues(alpha: 0.9),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(Icons.show_chart, size: 22, color: iconColor),
          ),
        ),
      ),
    );
  }
}
