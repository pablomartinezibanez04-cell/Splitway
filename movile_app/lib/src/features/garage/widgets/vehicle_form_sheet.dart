import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../../services/garage/vehicle.dart';
import 'vehicle_helpers.dart';

class VehicleFormResult {
  VehicleFormResult({
    required this.name,
    required this.type,
    this.model,
    this.year,
    this.horsepower,
    this.torqueNm,
    this.weightKg,
    this.drivetrain,
    this.notes,
  });

  final String name;
  final VehicleType type;
  final String? model;
  final int? year;
  final int? horsepower;
  final int? torqueNm;
  final int? weightKg;
  final Drivetrain? drivetrain;
  final String? notes;
}

class VehicleFormSheet extends StatefulWidget {
  const VehicleFormSheet({super.key, this.vehicle});

  final Vehicle? vehicle;

  @override
  State<VehicleFormSheet> createState() => _VehicleFormSheetState();
}

class _VehicleFormSheetState extends State<VehicleFormSheet> {
  final _nameCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _hpCtrl = TextEditingController();
  final _torqueCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  VehicleType _type = VehicleType.car;
  Drivetrain? _drivetrain;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    if (v != null) {
      _nameCtrl.text = v.name;
      _modelCtrl.text = v.model ?? '';
      _yearCtrl.text = v.year?.toString() ?? '';
      _hpCtrl.text = v.horsepower?.toString() ?? '';
      _torqueCtrl.text = v.torqueNm?.toString() ?? '';
      _weightCtrl.text = v.weightKg?.toString() ?? '';
      _notesCtrl.text = v.notes ?? '';
      _type = v.type;
      _drivetrain = v.drivetrain;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    _hpCtrl.dispose();
    _torqueCtrl.dispose();
    _weightCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.length < 2) return;

    Navigator.pop(
      context,
      VehicleFormResult(
        name: name,
        type: _type,
        model: _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
        year: int.tryParse(_yearCtrl.text.trim()),
        horsepower: int.tryParse(_hpCtrl.text.trim()),
        torqueNm: int.tryParse(_torqueCtrl.text.trim()),
        weightKg: int.tryParse(_weightCtrl.text.trim()),
        drivetrain: _drivetrain,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isEditing = widget.vehicle != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.directions_car_rounded,
                    color: cs.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  isEditing ? l.vehicleFormTitleEdit : l.vehicleFormTitleNew,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // 1. Name
            TextField(
              controller: _nameCtrl,
              autofocus: !isEditing,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l.vehicleFormNameLabel,
                prefixIcon: const Icon(Icons.label_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 2. Type ChoiceChips
            Text(
              l.vehicleFormTypeLabel,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: VehicleType.values.map((type) {
                return ChoiceChip(
                  showCheckmark: false,
                  avatar: Icon(vehicleTypeIcon(type), size: 18),
                  label: Text(vehicleTypeLabel(l, type)),
                  selected: _type == type,
                  onSelected: (_) => setState(() => _type = type),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            // 3. Model
            TextField(
              controller: _modelCtrl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l.vehicleFormModelLabel,
                prefixIcon: const Icon(Icons.directions_car_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 4. Year + Horsepower
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _yearCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l.vehicleFormYearLabel,
                      prefixIcon: const Icon(Icons.calendar_today_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hpCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l.vehicleFormHorsepowerLabel,
                      prefixIcon: const Icon(Icons.speed_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 5. Torque + Weight
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _torqueCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l.vehicleFormTorqueLabel,
                      prefixIcon: const Icon(Icons.rotate_right_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _weightCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l.vehicleFormWeightLabel,
                      prefixIcon: const Icon(Icons.monitor_weight_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // 6. Drivetrain ChoiceChips (toggleable)
            Text(
              l.vehicleFormDrivetrainLabel,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: Drivetrain.values.map((dt) {
                final isSelected = _drivetrain == dt;
                return ChoiceChip(
                  label: Text(_drivetrainLabel(l, dt)),
                  selected: isSelected,
                  onSelected: (_) => setState(() {
                    _drivetrain = isSelected ? null : dt;
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            // 7. Notes
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l.vehicleFormNotesLabel,
                hintText: l.vehicleFormNotesHint,
                prefixIcon: const Icon(Icons.notes_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 28),
            // 8. Cancel / Save buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(l.commonCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(l.vehicleFormSaveButton),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _drivetrainLabel(AppLocalizations l, Drivetrain dt) => switch (dt) {
        Drivetrain.front => l.drivetrainFront,
        Drivetrain.rear => l.drivetrainRear,
        Drivetrain.allWheel => l.drivetrainAllWheel,
      };
}
