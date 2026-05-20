import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../../services/settings/app_settings_controller.dart';
import '../../../shared/formatters.dart';

class RouteGridTile extends StatelessWidget {
  const RouteGridTile({
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
    final diffLabel = switch (route.difficulty) {
      RouteDifficulty.easy => l.editorDifficultyEasy,
      RouteDifficulty.medium => l.editorDifficultyMedium,
      RouteDifficulty.hard => l.editorDifficultyHard,
    };

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    route.isClosed ? Icons.loop : Icons.linear_scale,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      route.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _distanceLabel(l, route.totalDistanceMeters, settingsController),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (route.elevationRangeMeters != null) ...[
                const SizedBox(height: 2),
                Text(
                  '↕ ${_elevationLabel(l, route.elevationRangeMeters!, settingsController)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              if (route.locationLabel != null)
                Text(
                  route.locationLabel!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (route.thumbnailUrl != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        route.thumbnailUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stack) {
                          return Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.map_outlined,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                )
              else
                const Spacer(),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: diffColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      diffLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: diffColor.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (sessionCount > 0)
                    Text(
                      l.routesSessionsCount(sessionCount),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
    return l.elevationRangeValueFeet(feet.toStringAsFixed(0));
  }
  return l.elevationRangeValue(meters.toStringAsFixed(0));
}
