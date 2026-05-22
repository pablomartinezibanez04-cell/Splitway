import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../config/app_config.dart';
import '../../routing/app_router.dart';
import '../../services/auth/auth_service.dart';
import '../../services/garage/garage_service.dart';
import '../../services/profile/profile_service.dart';
import '../../services/settings/app_settings_controller.dart';
import '../../shared/widgets/vehicle_picker_tile.dart';
import '../../services/tracking/location_service.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/splitway_map.dart';
import '../home/home_shell.dart';
import 'live_session_controller.dart';

String _speedLabel(
  AppLocalizations l,
  AppSettingsController ctrl,
  double mps,
) {
  final v = Formatters.speedMps(mps, unit: ctrl.unitSystem);
  return ctrl.unitSystem == UnitSystem.imperial ? l.unitMph(v) : l.unitKmh(v);
}

String _distanceLabel(
  AppLocalizations l,
  AppSettingsController ctrl,
  double meters,
) {
  final (value, isLarge) = Formatters.distanceMeters(meters, unit: ctrl.unitSystem);
  final formatted = value.toStringAsFixed(value >= 10 ? 1 : 2);
  if (ctrl.unitSystem == UnitSystem.imperial) {
    return isLarge ? l.unitMiles(formatted) : l.unitFeet(formatted);
  }
  return isLarge ? l.unitKilometers(formatted) : l.unitMeters(formatted);
}

class LiveSessionScreen extends StatefulWidget {
  const LiveSessionScreen({
    super.key,
    required this.controller,
    required this.config,
    required this.settingsController,
    this.authService,
    this.profileService,
    this.garageService,
  });

  final LiveSessionController controller;
  final AppConfig config;
  final AppSettingsController settingsController;
  final AuthService? authService;
  final ProfileService? profileService;
  final GarageService? garageService;

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen>
    with WidgetsBindingObserver {
  int _lastEventCount = 0;
  AudioPlayer? _audioPlayer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onChange);
    widget.authService?.addListener(_onChange);
    widget.settingsController.addListener(_onSettingsChanged);
    widget.controller.load().then((_) {
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
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onChange);
    widget.authService?.removeListener(_onChange);
    widget.settingsController.removeListener(_onSettingsChanged);
    WakelockPlus.disable().catchError((_) {});
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final ctrl = widget.controller;
      if (ctrl.stage == LiveSessionStage.running &&
          ctrl.source == TrackingSource.realGps &&
          !ctrl.backgroundActive) {
        ctrl.upgradeToBackground();
      }
    }
  }

  void _onChange() {
    _updateWakelock();
    _onNewEvents();
    setState(() {});
  }

  void _onSettingsChanged() {
    _updateWakelock();
    setState(() {});
  }

  void _onNewEvents() {
    final tracker = widget.controller.tracker;
    if (tracker == null) return;
    final events = tracker.events;
    if (events.length <= _lastEventCount) return;

    final newEvents = events.sublist(_lastEventCount);
    bool hasCrossing = false;
    for (final evt in newEvents) {
      if (evt is SectorCrossed || evt is LapClosed) {
        hasCrossing = true;
        break;
      }
    }
    _lastEventCount = events.length;

    if (hasCrossing) {
      if (widget.settingsController.hapticFeedback) {
        HapticFeedback.mediumImpact();
      }
      if (widget.settingsController.audioAlerts) {
        _audioPlayer ??= AudioPlayer();
        unawaited(_audioPlayer!.play(AssetSource('sounds/beep.mp3')));
      }
    }
  }

  void _updateWakelock() {
    final shouldKeep = widget.settingsController.keepScreenAwake &&
        widget.controller.stage == LiveSessionStage.running;
    WakelockPlus.toggle(enable: shouldKeep).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ctrl = widget.controller;
    final isRunning = ctrl.stage == LiveSessionStage.running;
    return ListenableBuilder(
      listenable: widget.settingsController,
      builder: (context, _) => Scaffold(
        extendBody: isRunning,
        // During running: no AppBar — the drawer button is inside the map Stack
        // so it is positioned with SafeArea and cannot be obscured by the
        // system status bar.
        appBar: isRunning
            ? null
            : AppBar(
                leading: buildDrawerLeading(
                  context,
                  widget.authService,
                  widget.profileService,
                ),
                title: Text(l.sessionTitle),
              ),
        body: switch (ctrl.stage) {
          LiveSessionStage.selecting => _buildEmpty(context),
          LiveSessionStage.ready => _buildReady(context, ctrl),
          LiveSessionStage.running => _buildRunning(context, ctrl),
          LiveSessionStage.finished => _buildFinished(context, ctrl),
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final l = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.play_circle_outline,
      title: l.sessionNoRoutesTitle,
      message: l.sessionNoRoutesMessage,
    );
  }

  Widget _buildReady(BuildContext context, LiveSessionController ctrl) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.sessionSelectRoute,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _RoutePickerTile(
            selected: ctrl.selected,
            routes: ctrl.routes,
            onSelected: ctrl.selectRoute,
          ),
          const SizedBox(height: 16),
          if (ctrl.selected != null)
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: SplitwayMap(
                  useMapbox: widget.config.hasMapbox,
                  route: ctrl.selected!,
                  interactive: false,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(l.sessionTelemetrySource,
              style: Theme.of(context).textTheme.titleSmall),
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
            selected: {ctrl.source},
            onSelectionChanged: (s) => ctrl.setSource(s.first),
          ),
          if (ctrl.permissionStatus != null) ...[
            const SizedBox(height: 8),
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
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: ctrl.selected == null
                ? null
                : () async {
                    // Auth guard: require login before recording.
                    final allowed = await requireAuth(
                      context,
                      widget.authService,
                      message: AppLocalizations.of(context).loginBannerDefault,
                    );
                    if (!allowed || !mounted) return;

                    var hasBackground = false;
                    if (ctrl.source == TrackingSource.realGps) {
                      final bgPermission =
                          await LocationService.ensureBackgroundPermission();
                      hasBackground =
                          bgPermission == LocationPermissionStatus.granted;

                      if (!hasBackground && mounted) {
                        final action =
                            await _showBackgroundPermissionDialog(context);
                        if (!mounted) return;
                        if (action == null || action == true) return;
                      }
                    }

                    if (!mounted) return;
                    _lastEventCount = 0;
                    // ignore: discarded_futures
                    ctrl.startSession(
                      distanceFilterMeters:
                          widget.settingsController.gpsSamplingDistanceFilter,
                      backgroundActive: hasBackground,
                    );
                  },
            icon: const Icon(Icons.play_arrow),
            label: Text(l.sessionStartButton),
          ),
          const SizedBox(height: 8),
          Text(
            ctrl.source == TrackingSource.simulated
                ? l.sessionSimulatedHint
                : l.sessionRealGpsHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  bool _simExpanded = false;

  Widget _buildRunning(BuildContext context, LiveSessionController ctrl) {
    final l = AppLocalizations.of(context);
    final tracker = ctrl.tracker!;
    final snapshot = tracker.snapshot;
    final route = ctrl.selected!;
    final theme = Theme.of(context);

    final drawerLeading = buildDrawerLeading(
      context,
      widget.authService,
      widget.profileService,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: SplitwayMap(
            useMapbox: widget.config.hasMapbox,
            route: route,
            telemetry: tracker.ingested,
            highlightSectorId: snapshot.lastCrossedSectorId,
            userLocation: tracker.ingested.isNotEmpty
                ? tracker.ingested.last.location
                : null,
          ),
        ),
        if (drawerLeading != null)
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              bottom: false,
              right: false,
              child: drawerLeading,
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!ctrl.backgroundActive &&
                    ctrl.source == TrackingSource.realGps) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(l.backgroundDeniedBanner,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: Colors.white)),
                          ),
                          GestureDetector(
                            onTap: () => Geolocator.openAppSettings(),
                            child: Text(l.backgroundOpenSettings,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                )),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Container(
                  decoration: BoxDecoration(
                    color:
                        theme.colorScheme.surface.withValues(alpha: 0.85),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MetricsRow(
                        snapshot: snapshot,
                        settingsController: widget.settingsController,
                      ),
                      const SizedBox(height: 8),
                      _LastEventTile(
                        snapshot: snapshot,
                        settingsController: widget.settingsController,
                      ),
                      if (ctrl.source == TrackingSource.simulated) ...[
                        const SizedBox(height: 8),
                        _SimulationToggle(
                          expanded: _simExpanded,
                          onToggle: () =>
                              setState(() => _simExpanded = !_simExpanded),
                          ctrl: ctrl,
                        ),
                      ],
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () async {
                          final savedText = l.sessionSavedSnackBar;
                          final messenger = ScaffoldMessenger.of(context);
                          final session = await ctrl.finishSession();
                          if (!mounted || session == null) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text(savedText)),
                          );
                        },
                        icon: const Icon(Icons.stop),
                        label: Text(l.sessionFinishButton),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<bool?> _showBackgroundPermissionDialog(BuildContext context) {
    final l = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.location_on_outlined, size: 32),
        title: Text(l.backgroundDialogTitle),
        content: Text(l.backgroundDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.backgroundDialogSkip),
          ),
          FilledButton(
            onPressed: () {
              Geolocator.openAppSettings();
              Navigator.pop(ctx, true);
            },
            child: Text(l.backgroundDialogOpenSettings),
          ),
        ],
      ),
    );
  }

  Widget _buildFinished(BuildContext context, LiveSessionController ctrl) {
    final l = AppLocalizations.of(context);
    final result = ctrl.result!;
    final route = ctrl.selected!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.sessionCompleteTitle,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(l.sessionRouteLabel(route.name)),
        const SizedBox(height: 16),
        Card(
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: SplitwayMap(
              useMapbox: widget.config.hasMapbox,
              route: route,
              telemetry: result.points,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _StatsGrid(
          session: result,
          settingsController: widget.settingsController,
        ),
        const SizedBox(height: 16),
        Text(l.sessionLapsLabel,
            style: Theme.of(context).textTheme.titleMedium),
        for (final lap in result.laps)
          ListTile(
            leading: CircleAvatar(child: Text('${lap.lapNumber}')),
            title: Text(Formatters.duration(
              lap.duration,
              dotSeparator: widget.settingsController.timeFormatDot,
            )),
            subtitle: Text(() {
                  final dist = _distanceLabel(l, widget.settingsController, lap.distanceMeters);
                  final speed = _speedLabel(l, widget.settingsController, lap.avgSpeedMps);
                  return '$dist · $speed';
                }()),
            trailing: lap.completed
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.timer_off, color: Colors.orange),
          ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: ctrl.resetForNewSession,
          icon: const Icon(Icons.refresh),
          label: Text(l.sessionNewSessionButton),
        ),
      ],
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({
    required this.snapshot,
    required this.settingsController,
  });

  final TrackingSnapshot snapshot;
  final AppSettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _CompactMetric(
            label: l.sessionCurrentLapLabel,
            value: snapshot.currentLap == 0
                ? l.sessionNoLapYet
                : l.sessionLapNumber(snapshot.currentLap),
          ),
        ),
        Expanded(
          child: _CompactMetric(
            label: l.sessionLapTimeLabel,
            value: Formatters.duration(
              snapshot.currentLapElapsed,
              dotSeparator: settingsController.timeFormatDot,
            ),
          ),
        ),
        Expanded(
          child: _CompactMetric(
            label: l.sessionBestLapLabel,
            value: snapshot.bestLap == null
                ? l.sessionNoLapYet
                : Formatters.duration(
                    snapshot.bestLap!,
                    dotSeparator: settingsController.timeFormatDot,
                  ),
          ),
        ),
      ],
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _LastEventTile extends StatelessWidget {
  const _LastEventTile({
    required this.snapshot,
    required this.settingsController,
  });

  final TrackingSnapshot snapshot;
  final AppSettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final last = snapshot.lastCrossedSectorId;
    if (last == null) {
      return Text(
        snapshot.status == TrackingStatus.awaitingStart
            ? l.sessionAwaitingStart
            : l.sessionCrossingSectors,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return Row(
      children: [
        const Icon(Icons.flag_circle_outlined, size: 18),
        const SizedBox(width: 6),
        Text(l.sessionLastSector(last)),
        const Spacer(),
        if (snapshot.lastSectorTime != null)
          Text(Formatters.duration(
            snapshot.lastSectorTime!,
            dotSeparator: settingsController.timeFormatDot,
          )),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.session,
    required this.settingsController,
  });

  final SessionRun session;
  final AppSettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final distStr = _distanceLabel(l, settingsController, session.totalDistanceMeters);
    final children = [
      _Stat(l.sessionDistanceLabel, distStr),
      _Stat(l.sessionMaxSpeedLabel, _speedLabel(l, settingsController, session.maxSpeedMps)),
      _Stat(l.sessionAvgSpeedLabel, _speedLabel(l, settingsController, session.avgSpeedMps)),
      _Stat(l.sessionLapsCountLabel, '${session.laps.length}'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.4,
      children: [
        for (final s in children)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(s.label,
                      style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 4),
                  Text(s.value,
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Stat {
  _Stat(this.label, this.value);
  final String label;
  final String value;
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.status});

  final LocationPermissionStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
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
            child:
                Text(text, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _SimulationToggle extends StatelessWidget {
  const _SimulationToggle({
    required this.expanded,
    required this.onToggle,
    required this.ctrl,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final LiveSessionController ctrl;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.science_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(l.sessionSourceSimulated,
                    style: theme.textTheme.titleSmall),
                const Spacer(),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          if (ctrl.isAutoSimulating && ctrl.simTotal > 0) ...[
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: ctrl.simProgress / ctrl.simTotal,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${ctrl.simProgress} / ${ctrl.simTotal}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ctrl.simulateOnePoint,
                  icon: const Icon(Icons.fast_forward),
                  label: Text(l.sessionSimulatePoint),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ctrl.toggleAutoSimulate,
                  icon: Icon(ctrl.isAutoSimulating
                      ? Icons.pause
                      : Icons.autorenew),
                  label: Text(ctrl.isAutoSimulating
                      ? l.sessionPauseAuto
                      : l.sessionAutoLap),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(l.sessionSpeedLabel,
                  style: theme.textTheme.labelMedium),
              const SizedBox(width: 8),
              Expanded(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1×')),
                    ButtonSegment(value: 5, label: Text('5×')),
                    ButtonSegment(value: 10, label: Text('10×')),
                  ],
                  selected: {ctrl.simSpeedMultiplier},
                  onSelectionChanged: (s) =>
                      ctrl.setSimSpeedMultiplier(s.first),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RoutePickerTile extends StatelessWidget {
  const _RoutePickerTile({
    required this.selected,
    required this.routes,
    required this.onSelected,
  });

  final RouteTemplate? selected;
  final List<RouteTemplate> routes;
  final ValueChanged<RouteTemplate> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Expanded(
              child: Text(
                selected?.name ?? '',
                style: theme.textTheme.bodyLarge,
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
    final picked = await showModalBottomSheet<RouteTemplate>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
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
                l.sessionSelectRoute,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: routes.length,
                itemBuilder: (ctx, i) {
                  final r = routes[i];
                  final isSelected = r.id == selected?.id;
                  return ListTile(
                    title: Text(r.name),
                    subtitle:
                        r.description != null && r.description!.isNotEmpty
                            ? Text(r.description!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)
                            : null,
                    trailing: isSelected
                        ? Icon(Icons.check,
                            color: Theme.of(ctx).colorScheme.primary)
                        : null,
                    selected: isSelected,
                    onTap: () => Navigator.pop(ctx, r),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) onSelected(picked);
  }
}
