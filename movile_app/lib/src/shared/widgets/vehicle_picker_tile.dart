import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/garage/vehicle.dart';

IconData _vehicleIcon(VehicleType type) => switch (type) {
      VehicleType.car => Icons.directions_car,
      VehicleType.motorcycle => Icons.two_wheeler,
      VehicleType.bicycle => Icons.pedal_bike,
      VehicleType.goKart => Icons.sports_motorsports,
      VehicleType.other => Icons.commute,
    };

class VehiclePickerTile extends StatelessWidget {
  const VehiclePickerTile({
    super.key,
    required this.selectedVehicleId,
    required this.vehicles,
    required this.onSelected,
  });

  final String? selectedVehicleId;
  final List<Vehicle> vehicles;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final selectedVehicle = selectedVehicleId == null
        ? null
        : vehicles.where((v) => v.id == selectedVehicleId).firstOrNull;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showPicker(context),
      child: InputDecorator(
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        child: Row(
          children: [
            Icon(
              selectedVehicleId == null
                  ? Icons.directions_walk
                  : Icons.directions_car,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selectedVehicle?.name ?? l.vehiclePickerOnFoot,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.3,
        maxChildSize: 0.7,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.vehiclePickerSelectVehicle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.directions_walk),
              title: Text(l.vehiclePickerOnFoot),
              trailing: selectedVehicleId == null
                  ? Icon(Icons.check,
                      color: Theme.of(ctx).colorScheme.primary)
                  : null,
              selected: selectedVehicleId == null,
              onTap: () => Navigator.pop(ctx, '__on_foot__'),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: vehicles.length,
                itemBuilder: (ctx, i) {
                  final v = vehicles[i];
                  final isSelected = v.id == selectedVehicleId;
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundImage: v.photoUrl != null
                          ? NetworkImage(v.photoUrl!)
                          : null,
                      child: v.photoUrl == null
                          ? Icon(_vehicleIcon(v.type), size: 16)
                          : null,
                    ),
                    title: Text(v.name),
                    subtitle: v.model != null ? Text(v.model!) : null,
                    trailing: isSelected
                        ? Icon(Icons.check,
                            color: Theme.of(ctx).colorScheme.primary)
                        : null,
                    selected: isSelected,
                    onTap: () => Navigator.pop(ctx, v.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (result == '__on_foot__') {
      onSelected(null);
    } else if (result != null) {
      onSelected(result);
    }
  }
}
