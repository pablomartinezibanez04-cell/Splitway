import 'package:flutter/material.dart';

import 'package:splitway_mobile/l10n/app_localizations.dart';
import '../../services/garage/vehicle.dart';
import '../../shared/widgets/vehicle_picker_tile.dart';
import 'live_session_controller.dart';

/// Configuration gathered from [SessionConfigSheet] before a session starts.
class SessionConfig {
  const SessionConfig({
    required this.vehicleId,
    required this.name,
    required this.source,
    required this.includeHistorical,
  });

  final String? vehicleId;
  final String? name;
  final TrackingSource source;
  final bool includeHistorical;
}

/// Modal sheet shown after the user taps "Start recording". Collects the
/// vehicle, an optional name, the telemetry source (admins only) and whether
/// to compete against the user's historical best on the route. Calls [onStart]
/// with the resulting [SessionConfig]; it does not start the session itself.
class SessionConfigSheet extends StatefulWidget {
  const SessionConfigSheet({
    super.key,
    required this.vehicles,
    required this.initialVehicleId,
    required this.isAdmin,
    required this.initialSource,
    required this.onStart,
  });

  final List<Vehicle> vehicles;
  final String? initialVehicleId;
  final bool isAdmin;
  final TrackingSource initialSource;
  final ValueChanged<SessionConfig> onStart;

  @override
  State<SessionConfigSheet> createState() => _SessionConfigSheetState();
}

class _SessionConfigSheetState extends State<SessionConfigSheet> {
  late String? _vehicleId = widget.initialVehicleId;
  late TrackingSource _source = widget.initialSource;
  final TextEditingController _nameController = TextEditingController();
  bool _includeHistorical = true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(l.sessionConfigTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              if (widget.vehicles.isNotEmpty) ...[
                Text(l.vehiclePickerLabel, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                VehiclePickerTile(
                  selectedVehicleId: _vehicleId,
                  vehicles: widget.vehicles,
                  onSelected: (id) => setState(() => _vehicleId = id),
                ),
                const SizedBox(height: 16),
              ],
              Text(l.sessionConfigNameLabel, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: l.sessionConfigNameHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.isAdmin) ...[
                Text(l.sessionTelemetrySource,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<TrackingSource>(
                  segments: [
                    ButtonSegment(
                      value: TrackingSource.simulated,
                      label: Text(l.sessionSourceSimulated),
                      icon: const Icon(Icons.science_outlined),
                    ),
                    ButtonSegment(
                      value: TrackingSource.realGps,
                      label: Text(l.sessionSourceRealGps),
                      icon: const Icon(Icons.gps_fixed),
                    ),
                  ],
                  selected: {_source},
                  onSelectionChanged: (s) =>
                      setState(() => _source = s.first),
                ),
                const SizedBox(height: 16),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeHistorical,
                onChanged: (v) => setState(() => _includeHistorical = v),
                title: Text(l.sessionConfigIncludeHistoricalTitle),
                subtitle: Text(l.sessionConfigIncludeHistoricalSubtitle),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => widget.onStart(SessionConfig(
                  vehicleId: _vehicleId,
                  name: _nameController.text,
                  source: _source,
                  includeHistorical: _includeHistorical,
                )),
                icon: const Icon(Icons.play_arrow),
                label: Text(l.sessionConfigStartButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
