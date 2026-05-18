import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../config/app_config.dart';
import '../../routing/app_router.dart';
import '../../services/auth/auth_service.dart';
import '../../services/tracking/live_tracking_controller.dart';
import '../../services/tracking/location_service.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/splitway_map.dart';
import '../home/home_shell.dart';
import 'live_session_controller.dart';

class LiveSessionScreen extends StatefulWidget {
  const LiveSessionScreen({
    super.key,
    required this.controller,
    required this.config,
    this.authService,
  });

  final LiveSessionController controller;
  final AppConfig config;
  final AuthService? authService;

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    widget.authService?.addListener(_onChange);
    widget.controller.load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    widget.authService?.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ctrl = widget.controller;
    return Scaffold(
      appBar: AppBar(
        leading: buildDrawerLeading(context, widget.authService),
        title: Text(l.sessionTitle),
      ),
      body: switch (ctrl.stage) {
        LiveSessionStage.selecting => _buildEmpty(context),
        LiveSessionStage.ready => _buildReady(context, ctrl),
        LiveSessionStage.running => _buildRunning(context, ctrl),
        LiveSessionStage.finished => _buildFinished(context, ctrl),
      },
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
          DropdownButtonFormField<String>(
            initialValue: ctrl.selected?.id,
            items: [
              for (final r in ctrl.routes)
                DropdownMenuItem(value: r.id, child: Text(r.name)),
            ],
            onChanged: (id) {
              if (id == null) return;
              final route = ctrl.routes.firstWhere((r) => r.id == id);
              ctrl.selectRoute(route);
            },
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
                    // ignore: discarded_futures
                    ctrl.startSession();
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

  Widget _buildRunning(BuildContext context, LiveSessionController ctrl) {
    final l = AppLocalizations.of(context);
    final tracker = ctrl.tracker!;
    final snapshot = tracker.snapshot;
    final route = ctrl.selected!;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
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
          ),
          const SizedBox(height: 12),
          _MetricsRow(snapshot: snapshot),
          const SizedBox(height: 8),
          _LastEventTile(snapshot: snapshot),
          const SizedBox(height: 12),
          if (ctrl.source == TrackingSource.simulated) ...[
            // Progress bar (visible only while auto-simulating)
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
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            // Simulation buttons
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
            // Speed selector
            Row(
              children: [
                Text(l.sessionSpeedLabel,
                    style: Theme.of(context).textTheme.labelMedium),
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
          ] else
            _GpsStatusTile(
              tracker: tracker,
              telemetryCount: tracker.ingested.length,
            ),
          const SizedBox(height: 8),
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
        _StatsGrid(session: result),
        const SizedBox(height: 16),
        Text(l.sessionLapsLabel,
            style: Theme.of(context).textTheme.titleMedium),
        for (final lap in result.laps)
          ListTile(
            leading: CircleAvatar(child: Text('${lap.lapNumber}')),
            title: Text(Formatters.duration(lap.duration)),
            subtitle: Text(() {
                  final (dv, isKm) = Formatters.distanceMeters(lap.distanceMeters);
                  final dist = isKm
                      ? l.unitKilometers(dv.toStringAsFixed(2))
                      : l.unitMeters(dv.toStringAsFixed(0));
                  final speed = l.unitKmh(Formatters.speedMps(lap.avgSpeedMps).toStringAsFixed(1));
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
  const _MetricsRow({required this.snapshot});

  final TrackingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            label: l.sessionCurrentLapLabel,
            value: snapshot.currentLap == 0
                ? l.sessionNoLapYet
                : l.sessionLapNumber(snapshot.currentLap),
          ),
        ),
        Expanded(
          child: _MetricCard(
            label: l.sessionLapTimeLabel,
            value: Formatters.duration(snapshot.currentLapElapsed),
          ),
        ),
        Expanded(
          child: _MetricCard(
            label: l.sessionBestLapLabel,
            value: snapshot.bestLap == null
                ? l.sessionNoLapYet
                : Formatters.duration(snapshot.bestLap!),
          ),
        ),
      ],
    );
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

class _LastEventTile extends StatelessWidget {
  const _LastEventTile({required this.snapshot});

  final TrackingSnapshot snapshot;

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
          Text(Formatters.duration(snapshot.lastSectorTime!)),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.session});

  final SessionRun session;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (dv, isKm) = Formatters.distanceMeters(session.totalDistanceMeters);
    final distStr = isKm
        ? l.unitKilometers(dv.toStringAsFixed(2))
        : l.unitMeters(dv.toStringAsFixed(0));
    final children = [
      _Stat(l.sessionDistanceLabel, distStr),
      _Stat(l.sessionMaxSpeedLabel, l.unitKmh(Formatters.speedMps(session.maxSpeedMps).toStringAsFixed(1))),
      _Stat(l.sessionAvgSpeedLabel, l.unitKmh(Formatters.speedMps(session.avgSpeedMps).toStringAsFixed(1))),
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

class _GpsStatusTile extends StatelessWidget {
  const _GpsStatusTile({
    required this.tracker,
    required this.telemetryCount,
  });

  final LiveTrackingController tracker;
  final int telemetryCount;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final last = telemetryCount == 0 ? null : tracker.ingested.last;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.gps_fixed, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.sessionGpsStatus(telemetryCount),
                    style: theme.textTheme.titleSmall,
                  ),
                  if (last != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      l.sessionGpsAccuracy(
                        last.accuracyMeters?.toStringAsFixed(1) ?? '–',
                        last.location.latitude.toStringAsFixed(5),
                        last.location.longitude.toStringAsFixed(5),
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else ...[
                    const SizedBox(height: 2),
                    Text(
                      l.sessionAwaitingFirstFix,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
