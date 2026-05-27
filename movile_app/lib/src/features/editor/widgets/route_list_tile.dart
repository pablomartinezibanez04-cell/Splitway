import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../../services/settings/app_settings_controller.dart';
import '../../../shared/formatters.dart';

class RouteListTile extends StatelessWidget {
  const RouteListTile({
    super.key,
    required this.route,
    required this.sessionCount,
    this.bestLap,
    required this.onTap,
    this.settingsController,
  });

  final RouteTemplate route;
  final int sessionCount;
  final Duration? bestLap;
  final VoidCallback onTap;
  final AppSettingsController? settingsController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final diffColor = switch (route.difficulty) {
      RouteDifficulty.easy => Colors.green,
      RouteDifficulty.medium => Colors.orange,
      RouteDifficulty.hard => Colors.red,
    };

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: diffColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(l),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (bestLap != null) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.emoji_events_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.duration(bestLap!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(AppLocalizations l) {
    final parts = <String>[];
    parts.add(_distanceLabel(l, route.totalDistanceMeters, settingsController));
    if (route.locationLabel != null) {
      parts.add(route.locationLabel!);
    }
    parts.add(route.isClosed ? l.editorClosedLoop : l.editorOpenRoute);
    return parts.join(' · ');
  }
}

String _distanceLabel(
    AppLocalizations l, double meters, AppSettingsController? ctrl) {
  final unit = ctrl?.unitSystem ?? UnitSystem.metric;
  final (value, isLarge) = Formatters.distanceMeters(meters, unit: unit);
  final formatted = value.toStringAsFixed(value >= 10 ? 1 : 2);
  if (unit == UnitSystem.imperial) {
    return isLarge ? l.unitMiles(formatted) : l.unitFeet(formatted);
  }
  return isLarge ? l.unitKilometers(formatted) : l.unitMeters(formatted);
}

String _elevationLabel(
    AppLocalizations l, double meters, AppSettingsController? ctrl) {
  final unit = ctrl?.unitSystem ?? UnitSystem.metric;
  if (unit == UnitSystem.imperial) {
    final feet = meters * 3.28084;
    return '↕ ${l.elevationRangeValueFeet(feet.toStringAsFixed(0))}';
  }
  return '↕ ${l.elevationRangeValue(meters.toStringAsFixed(0))}';
}
