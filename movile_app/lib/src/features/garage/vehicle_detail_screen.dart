import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/garage/garage_service.dart';
import '../../services/garage/vehicle.dart';
import '../../shared/image_utils.dart';
import 'widgets/vehicle_form_sheet.dart';

class VehicleDetailScreen extends StatefulWidget {
  const VehicleDetailScreen({
    super.key,
    required this.vehicle,
    required this.garageService,
  });

  final Vehicle vehicle;
  final GarageService garageService;

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  late Vehicle _vehicle;

  @override
  void initState() {
    super.initState();
    _vehicle = widget.vehicle;
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (image == null) return;

    final bytes = await image.readAsBytes();
    final compressed = await compressToWebp(bytes);
    if (compressed == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).garageErrorUnexpected)),
      );
      return;
    }

    final success = await widget.garageService.uploadPhoto(
      _vehicle.id,
      compressed,
      'webp',
    );
    if (!mounted) return;

    final l = AppLocalizations.of(context);
    if (success) {
      final updated = widget.garageService.vehicles
          .where((v) => v.id == _vehicle.id)
          .firstOrNull;
      if (updated != null) {
        setState(() => _vehicle = updated);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.garagePhotoUpdated)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.garageErrorUnexpected)),
      );
    }
  }

  Future<void> _editVehicle() async {
    final result = await showModalBottomSheet<VehicleFormResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => VehicleFormSheet(vehicle: _vehicle),
    );
    if (result == null) return;
    if (!mounted) return;

    final updated = _vehicle.copyWith(
      name: result.name,
      type: result.type,
      model: result.model,
      year: result.year,
      horsepower: result.horsepower,
      torqueNm: result.torqueNm,
      weightKg: result.weightKg,
      drivetrain: result.drivetrain,
      notes: result.notes,
    );

    final success = await widget.garageService.updateVehicle(updated);
    if (!mounted) return;

    final l = AppLocalizations.of(context);
    if (success) {
      setState(() => _vehicle = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.garageVehicleSavedSnack)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.garageErrorUnexpected)),
      );
    }
  }

  Future<void> _deleteVehicle() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.garageDeleteVehicleTitle),
        content: Text(l.garageDeleteVehicleConfirm(_vehicle.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonBack),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final success = await widget.garageService.deleteVehicle(_vehicle.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? l.garageVehicleDeletedSnack : l.garageErrorUnexpected,
        ),
      ),
    );
    if (success) Navigator.pop(context);
  }

  String _drivetrainLabel(AppLocalizations l, Drivetrain dt) => switch (dt) {
        Drivetrain.front => l.drivetrainFront,
        Drivetrain.rear => l.drivetrainRear,
        Drivetrain.allWheel => l.drivetrainAllWheel,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final v = _vehicle;

    final hasSpecs = v.model != null ||
        v.year != null ||
        v.horsepower != null ||
        v.torqueNm != null ||
        v.weightKg != null ||
        v.drivetrain != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(v.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: _editVehicle,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: _deleteVehicle,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Photo section
          GestureDetector(
            onTap: _pickPhoto,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  image: v.photoUrl != null
                      ? DecorationImage(
                          image: NetworkImage(v.photoUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: v.photoUrl != null
                    ? Stack(
                        children: [
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  cs.surface.withValues(alpha: 0.8),
                              child: const Icon(Icons.edit, size: 18),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            size: 48,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.garageChangePhoto,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
              ),
            ),
          ),

          // Specs section
          if (hasSpecs) ...[
            const SizedBox(height: 24),
            Text(
              l.vehicleDetailSpecs,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (v.model != null)
                  _SpecChip(
                    icon: Icons.directions_car_outlined,
                    label: v.model!,
                  ),
                if (v.year != null)
                  _SpecChip(
                    icon: Icons.calendar_today,
                    label: v.year!.toString(),
                  ),
                if (v.horsepower != null)
                  _SpecChip(
                    icon: Icons.speed,
                    label: l.vehicleDetailHorsepower(v.horsepower!),
                  ),
                if (v.torqueNm != null)
                  _SpecChip(
                    icon: Icons.rotate_right,
                    label: l.vehicleDetailTorque(v.torqueNm!),
                  ),
                if (v.weightKg != null)
                  _SpecChip(
                    icon: Icons.fitness_center,
                    label: l.vehicleDetailWeight(v.weightKg!),
                  ),
                if (v.drivetrain != null)
                  _SpecChip(
                    icon: Icons.settings,
                    label: _drivetrainLabel(l, v.drivetrain!),
                  ),
              ],
            ),
          ],

          // Notes section
          if (v.notes != null && v.notes!.isNotEmpty) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  v.notes!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SpecChip extends StatelessWidget {
  const _SpecChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      backgroundColor: cs.surfaceContainerLow,
      visualDensity: VisualDensity.compact,
    );
  }
}
