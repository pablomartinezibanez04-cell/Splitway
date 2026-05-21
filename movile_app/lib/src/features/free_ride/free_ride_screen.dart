// movile_app/lib/src/features/free_ride/free_ride_screen.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../config/app_config.dart';
import '../../routing/app_router.dart';
import '../../services/auth/auth_service.dart';
import '../../services/garage/garage_service.dart';
import '../../services/profile/profile_service.dart';
import '../../services/settings/app_settings_controller.dart';
import '../../services/tracking/location_service.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/splitway_map.dart';
import '../../shared/widgets/vehicle_picker_tile.dart';
import '../home/home_shell.dart';
import 'free_ride_controller.dart';

class FreeRideScreen extends StatefulWidget {
  const FreeRideScreen({
    super.key,
    required this.controller,
    required this.config,
    required this.settingsController,
    this.authService,
    this.profileService,
    this.garageService,
  });

  final FreeRideController controller;
  final AppConfig config;
  final AppSettingsController settingsController;
  final AuthService? authService;
  final ProfileService? profileService;
  final GarageService? garageService;

  @override
  State<FreeRideScreen> createState() => _FreeRideScreenState();
}

class _FreeRideScreenState extends State<FreeRideScreen> {
  final FlyToNotifier _flyToNotifier = FlyToNotifier();
  bool _followUser = true;
  int _lastPointCount = 0;
  GeoPoint? _initialCenter;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    widget.settingsController.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.controller.selectedVehicleId == null) {
        final defaultId = widget.settingsController.defaultVehicleId;
        if (defaultId != null) {
          widget.controller.selectVehicle(defaultId);
        }
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    widget.settingsController.removeListener(_onSettingsChanged);
    WakelockPlus.disable().catchError((_) {});
    _flyToNotifier.dispose();
    super.dispose();
  }

  void _onChange() {
    _updateWakelock();
    final ctrl = widget.controller;
    if (ctrl.stage == FreeRideStage.recording && _followUser) {
      final points = ctrl.ingested;
      if (points.length > _lastPointCount && points.isNotEmpty) {
        _flyToNotifier.flyTo(points.last.location);
      }
      _lastPointCount = points.length;
    }
    setState(() {});
  }

  void _onSettingsChanged() {
    _updateWakelock();
    setState(() {});
  }

  void _updateWakelock() {
    final shouldKeep = widget.settingsController.keepScreenAwake &&
        widget.controller.stage == FreeRideStage.recording;
    WakelockPlus.toggle(enable: shouldKeep).catchError((_) {});
  }

  Future<GeoPoint?> _getCurrentLocation() async {
    try {
      final servicesOn = await Geolocator.isLocationServiceEnabled();
      if (!servicesOn) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      return GeoPoint(
          latitude: position.latitude, longitude: position.longitude);
    } catch (_) {
      return null;
    }
  }

  void _centerOnUser() {
    final ctrl = widget.controller;
    _followUser = true;
    if (ctrl.ingested.isNotEmpty) {
      _flyToNotifier.flyTo(ctrl.ingested.last.location);
    }
  }

  String _speedLabel(AppLocalizations l, double mps) {
    final v = Formatters.speedMps(mps, unit: widget.settingsController.unitSystem);
    return widget.settingsController.unitSystem == UnitSystem.imperial
        ? l.unitMph(v)
        : l.unitKmh(v);
  }

  String _distanceLabel(AppLocalizations l, double meters) {
    final (value, isLarge) = Formatters.distanceMeters(
      meters,
      unit: widget.settingsController.unitSystem,
    );
    final formatted = value.toStringAsFixed(value >= 10 ? 1 : 2);
    if (widget.settingsController.unitSystem == UnitSystem.imperial) {
      return isLarge ? l.unitMiles(formatted) : l.unitFeet(formatted);
    }
    return isLarge ? l.unitKilometers(formatted) : l.unitMeters(formatted);
  }

  String _elevationLabel(AppLocalizations l, double meters) {
    if (widget.settingsController.unitSystem == UnitSystem.imperial) {
      final feet = meters * 3.28084;
      return l.elevationRangeValueFeet(feet.toStringAsFixed(0));
    }
    return l.elevationRangeValue(meters.toStringAsFixed(0));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ctrl = widget.controller;
    return ListenableBuilder(
      listenable: widget.settingsController,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: buildDrawerLeading(
            context,
            widget.authService,
            widget.profileService,
          ),
          title: Text(l.freeRideTitle),
        ),
        body: switch (ctrl.stage) {
          FreeRideStage.idle => _buildIdle(context, ctrl),
          FreeRideStage.recording => _buildRecording(context, ctrl),
          FreeRideStage.finished => _buildFinished(context, ctrl),
        },
      ),
    );
  }

  Widget _buildIdle(BuildContext context, FreeRideController ctrl) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EmptyState(
            icon: Icons.explore_outlined,
            title: l.freeRideIdleTitle,
            message: l.freeRideIdleMessage,
          ),
          if (ctrl.permissionStatus != null &&
              ctrl.permissionStatus != LocationPermissionStatus.granted) ...[
            const SizedBox(height: 16),
            _PermissionBanner(status: ctrl.permissionStatus!),
          ],
          if (widget.garageService != null &&
              widget.garageService!.vehicles.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(l.vehiclePickerLabel,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            VehiclePickerTile(
              selectedVehicleId: ctrl.selectedVehicleId,
              vehicles: widget.garageService!.vehicles,
              onSelected: ctrl.selectVehicle,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              final allowed = await requireAuth(
                context,
                widget.authService,
                message: AppLocalizations.of(context).loginBannerDefault,
              );
              if (!allowed || !mounted) return;
              _initialCenter = await _getCurrentLocation();
              _followUser = true;
              _lastPointCount = 0;
              await ctrl.startRecording(
                distanceFilterMeters: widget.settingsController.gpsSamplingDistanceFilter,
              );
            },
            icon: const Icon(Icons.play_arrow),
            label: Text(l.freeRideStartButton),
          ),
        ],
      ),
    );
  }

  Widget _buildRecording(BuildContext context, FreeRideController ctrl) {
    final l = AppLocalizations.of(context);
    final snap = ctrl.snapshot;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  SplitwayMap(
                    useMapbox: widget.config.hasMapbox,
                    telemetry: ctrl.ingested,
                    userLocation: ctrl.ingested.isNotEmpty
                        ? ctrl.ingested.last.location
                        : null,
                    initialCenter: _initialCenter,
                    flyToNotifier: _flyToNotifier,
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'free_ride_center',
                      onPressed: _centerOnUser,
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: l.freeRideElapsedLabel,
                  value: Formatters.duration(
                    snap.elapsed,
                    dotSeparator: widget.settingsController.timeFormatDot,
                  ),
                ),
              ),
              Expanded(
                child: _MetricCard(
                  label: l.freeRideDistanceLabel,
                  value: _distanceLabel(l, snap.totalDistanceMeters),
                ),
              ),
              Expanded(
                child: _MetricCard(
                  label: l.freeRideSpeedLabel,
                  value: _speedLabel(l, snap.currentSpeedMps),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _GpsStatusTile(pointCount: snap.pointCount),
          if (ctrl.backgroundActive) ...[
            const SizedBox(height: 4),
            Chip(
              avatar: const Icon(Icons.gps_fixed, color: Colors.green, size: 18),
              label: Text(l.backgroundActiveChip),
              backgroundColor: Colors.green.withValues(alpha: 0.12),
              side: BorderSide(color: Colors.green.withValues(alpha: 0.4)),
            ),
          ],
          if (!ctrl.backgroundActive &&
              ctrl.stage == FreeRideStage.recording) ...[
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l.backgroundDeniedBanner,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  TextButton(
                    onPressed: () => Geolocator.openAppSettings(),
                    child: Text(l.backgroundOpenSettings),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              final savedText = l.freeRideSavedSnackBar;
              final messenger = ScaffoldMessenger.of(context);
              await ctrl.finishRecording();
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(content: Text(savedText)),
              );
            },
            icon: const Icon(Icons.stop),
            label: Text(l.freeRideFinishButton),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinished(BuildContext context, FreeRideController ctrl) {
    final l = AppLocalizations.of(context);
    final result = ctrl.result!;
    final distStr = _distanceLabel(l, result.totalDistanceMeters);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.freeRideCompleteTitle,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Card(
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: SplitwayMap(
              useMapbox: widget.config.hasMapbox,
              telemetry: result.points,
              interactive: false,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatCard(l.freeRideDistanceLabel, distStr),
            ),
            Expanded(
              child: _StatCard(
                l.freeRideMaxSpeedLabel,
                _speedLabel(l, result.maxSpeedMps),
              ),
            ),
            Expanded(
              child: _StatCard(
                l.freeRideAvgSpeedLabel,
                _speedLabel(l, result.avgSpeedMps),
              ),
            ),
          ],
        ),
        if (result.elevationRangeMeters != null) ...[
          const SizedBox(height: 8),
          _StatCard(
            l.elevationRangeLabel,
            _elevationLabel(l, result.elevationRangeMeters!),
          ),
        ],
        if (result.totalDuration != null) ...[
          const SizedBox(height: 8),
          _StatCard(
            l.freeRideElapsedLabel,
            Formatters.duration(
              result.totalDuration!,
              dotSeparator: widget.settingsController.timeFormatDot,
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => _showSaveAsRouteDialog(context, ctrl),
          icon: const Icon(Icons.save_alt),
          label: Text(l.freeRideSaveAsRouteButton),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: ctrl.resetForNewRide,
          icon: const Icon(Icons.refresh),
          label: Text(l.freeRideNewRideButton),
        ),
      ],
    );
  }

  Future<void> _showSaveAsRouteDialog(
    BuildContext context,
    FreeRideController ctrl,
  ) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var difficulty = RouteDifficulty.medium;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final cs = Theme.of(ctx).colorScheme;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.save_rounded,
                          color: cs.onPrimaryContainer, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        l.freeRideSaveRouteDialogTitle,
                        style: Theme.of(ctx)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: l.freeRideNameLabel,
                    prefixIcon: const Icon(Icons.label_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    labelText: l.freeRideDescriptionLabel,
                    prefixIcon: const Icon(Icons.notes_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
                Text(
                  l.freeRideDifficultyLabel,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _FreeRideDifficultySelector(
                  value: difficulty,
                  onChanged: (d) => setDialogState(() => difficulty = d),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
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
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(l.commonSave),
                        style: FilledButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
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
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;

    final route = await ctrl.saveAsRoute(
      name: name,
      description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
      difficulty: difficulty,
    );

    if (!mounted || route == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text(l.freeRideRouteSavedSnack(route.name))),
    );
    ctrl.resetForNewRide();
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _GpsStatusTile extends StatelessWidget {
  const _GpsStatusTile({required this.pointCount});

  final int pointCount;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.gps_fixed, color: Colors.green),
            const SizedBox(width: 8),
            Text(
              l.freeRidePointsLabel(pointCount),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.status});

  final LocationPermissionStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (color, icon, text) = switch (status) {
      LocationPermissionStatus.granted => (
          Colors.green,
          Icons.check_circle_outline,
          l.sessionPermissionGranted,
        ),
      LocationPermissionStatus.denied => (
          Colors.orange,
          Icons.warning_amber_rounded,
          l.sessionPermissionDenied,
        ),
      LocationPermissionStatus.permanentlyDenied => (
          Colors.red,
          Icons.block,
          l.sessionPermissionPermanentlyDenied,
        ),
      LocationPermissionStatus.servicesDisabled => (
          Colors.red,
          Icons.location_off,
          l.sessionServicesDisabled,
        ),
    };
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _FreeRideDifficultySelector extends StatelessWidget {
  const _FreeRideDifficultySelector({
    required this.value,
    required this.onChanged,
  });

  final RouteDifficulty value;
  final ValueChanged<RouteDifficulty> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        _buildOption(
          context: context,
          difficulty: RouteDifficulty.easy,
          label: l.editorDifficultyEasy,
          icon: Icons.park_rounded,
          color: Colors.green,
        ),
        const SizedBox(width: 10),
        _buildOption(
          context: context,
          difficulty: RouteDifficulty.medium,
          label: l.editorDifficultyMedium,
          icon: Icons.terrain_rounded,
          color: Colors.orange,
        ),
        const SizedBox(width: 10),
        _buildOption(
          context: context,
          difficulty: RouteDifficulty.hard,
          label: l.editorDifficultyHard,
          icon: Icons.whatshot_rounded,
          color: Colors.red,
        ),
      ],
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required RouteDifficulty difficulty,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final selected = value == difficulty;
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(difficulty),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.12)
                : cs.surfaceContainerHighest.withValues(alpha: 0.4),
            border: Border.all(
              color: selected ? color : cs.outline.withValues(alpha: 0.2),
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected ? color : cs.onSurfaceVariant, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? color : cs.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
