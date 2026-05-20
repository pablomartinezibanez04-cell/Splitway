import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import '../../../services/garage/vehicle.dart';
import 'vehicle_helpers.dart';

class VehicleListTile extends StatelessWidget {
  const VehicleListTile({
    super.key,
    required this.vehicle,
    required this.onTap,
  });

  final Vehicle vehicle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

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
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage: vehicle.photoUrl != null
                    ? NetworkImage(vehicle.photoUrl!)
                    : null,
                child: vehicle.photoUrl == null
                    ? Icon(
                        vehicleTypeIcon(vehicle.type),
                        color: theme.colorScheme.onPrimaryContainer,
                        size: 20,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.name,
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
              if (vehicle.horsepower != null) ...[
                const SizedBox(width: 8),
                Text(
                  l.vehicleDetailHorsepower(vehicle.horsepower!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
    parts.add(vehicleTypeLabel(l, vehicle.type));
    if (vehicle.model != null) parts.add(vehicle.model!);
    if (vehicle.year != null) parts.add(vehicle.year.toString());
    return parts.join(' · ');
  }
}
