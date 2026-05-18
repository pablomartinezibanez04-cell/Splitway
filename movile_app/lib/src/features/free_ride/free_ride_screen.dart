// movile_app/lib/src/features/free_ride/free_ride_screen.dart
import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../config/app_config.dart';
import '../../routing/app_router.dart';
import '../../services/auth/auth_service.dart';
import '../../services/tracking/location_service.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/splitway_map.dart';
import '../home/home_shell.dart';
import 'free_ride_controller.dart';

class FreeRideScreen extends StatefulWidget {
  const FreeRideScreen({
    super.key,
    required this.controller,
    required this.config,
    this.authService,
  });

  final FreeRideController controller;
  final AppConfig config;
  final AuthService? authService;

  @override
  State<FreeRideScreen> createState() => _FreeRideScreenState();
}

class _FreeRideScreenState extends State<FreeRideScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
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
        title: Text(l.freeRideTitle),
      ),
      body: switch (ctrl.stage) {
        FreeRideStage.idle => _buildIdle(context, ctrl),
        FreeRideStage.recording => _buildRecording(context, ctrl),
        FreeRideStage.finished => _buildFinished(context, ctrl),
      },
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
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              final allowed = await requireAuth(
                context,
                widget.authService,
                message: AppLocalizations.of(context).loginBannerDefault,
              );
              if (!allowed || !mounted) return;
              await ctrl.startRecording();
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
              child: SplitwayMap(
                useMapbox: widget.config.hasMapbox,
                telemetry: ctrl.ingested,
                userLocation: ctrl.ingested.isNotEmpty
                    ? ctrl.ingested.last.location
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: l.freeRideElapsedLabel,
                  value: Formatters.duration(snap.elapsed),
                ),
              ),
              Expanded(
                child: _MetricCard(
                  label: l.freeRideDistanceLabel,
                  value: () {
                    final (dv, isKm) =
                        Formatters.distanceMeters(snap.totalDistanceMeters);
                    return isKm
                        ? l.unitKilometers(dv.toStringAsFixed(2))
                        : l.unitMeters(dv.toStringAsFixed(0));
                  }(),
                ),
              ),
              Expanded(
                child: _MetricCard(
                  label: l.freeRideSpeedLabel,
                  value: l.unitKmh(
                    Formatters.speedMps(snap.currentSpeedMps)
                        .toStringAsFixed(1),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _GpsStatusTile(pointCount: snap.pointCount),
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
    final (dv, isKm) = Formatters.distanceMeters(result.totalDistanceMeters);
    final distStr = isKm
        ? l.unitKilometers(dv.toStringAsFixed(2))
        : l.unitMeters(dv.toStringAsFixed(0));

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
                l.unitKmh(Formatters.speedMps(result.maxSpeedMps)
                    .toStringAsFixed(1)),
              ),
            ),
            Expanded(
              child: _StatCard(
                l.freeRideAvgSpeedLabel,
                l.unitKmh(Formatters.speedMps(result.avgSpeedMps)
                    .toStringAsFixed(1)),
              ),
            ),
          ],
        ),
        if (result.totalDuration != null) ...[
          const SizedBox(height: 8),
          _StatCard(
            l.freeRideElapsedLabel,
            Formatters.duration(result.totalDuration!),
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l.freeRideSaveRouteDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: l.freeRideNameLabel),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration:
                    InputDecoration(labelText: l.freeRideDescriptionLabel),
              ),
              const SizedBox(height: 16),
              Text(l.freeRideDifficultyLabel,
                  style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<RouteDifficulty>(
                segments: [
                  ButtonSegment(
                    value: RouteDifficulty.easy,
                    label: Text(l.editorDifficultyEasy),
                  ),
                  ButtonSegment(
                    value: RouteDifficulty.medium,
                    label: Text(l.editorDifficultyMedium),
                  ),
                  ButtonSegment(
                    value: RouteDifficulty.hard,
                    label: Text(l.editorDifficultyHard),
                  ),
                ],
                selected: {difficulty},
                onSelectionChanged: (s) {
                  setDialogState(() => difficulty = s.first);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonSave),
            ),
          ],
        ),
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
