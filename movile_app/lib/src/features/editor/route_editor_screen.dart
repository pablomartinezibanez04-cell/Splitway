import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../config/app_config.dart';
import '../../routing/app_router.dart';
import '../../services/auth/auth_service.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/splitway_map.dart';
import '../home/home_shell.dart';
import 'route_editor_controller.dart';
import 'widgets/bento_grid.dart';

class RouteEditorScreen extends StatefulWidget {
  const RouteEditorScreen({
    super.key,
    required this.controller,
    required this.config,
    this.authService,
  });

  final RouteEditorController controller;
  final AppConfig config;
  final AuthService? authService;

  @override
  State<RouteEditorScreen> createState() => _RouteEditorScreenState();
}

class _RouteEditorScreenState extends State<RouteEditorScreen> {
  bool _showSectors = false;
  String? _lastSelectedId;
  GeoPoint? _userLocation;

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

  void _onChange() {
    final newId = widget.controller.selected?.id;
    if (newId != _lastSelectedId) {
      _showSectors = false;
      _lastSelectedId = newId;
    }
    setState(() {});
  }

  Future<void> _onCreateRoute() async {
    // Auth guard: require login before creating a new route.
    final allowed = await requireAuth(
      context,
      widget.authService,
      message: AppLocalizations.of(context).loginBannerDefault,
    );
    if (!allowed || !mounted) return;

    final result = await showDialog<_NewRouteResult>(
      context: context,
      builder: (_) => const _NewRouteDialog(),
    );
    if (result == null) return;

    // Try to get the user's current location for the initial map center.
    _userLocation = await _getCurrentLocation();

    widget.controller.startDrawing(
      name: result.name,
      description: result.description,
      difficulty: result.difficulty,
    );
  }

  /// Returns the user's current GPS position, or null if unavailable.
  /// Uses a 5-second timeout to avoid blocking the UI.
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
      return GeoPoint(latitude: position.latitude, longitude: position.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _confirmDelete(RouteTemplate route) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.editorDeleteRouteTitle),
        content: Text(l.editorDeleteRouteConfirm(route.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.controller.deleteRoute(route.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ctrl = widget.controller;
    if (ctrl.drawing) {
      return _DrawingView(
        controller: ctrl,
        config: widget.config,
        initialCenter: _userLocation,
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: buildDrawerLeading(context, widget.authService),
        title: Text(l.editorTitle),
        actions: [
          IconButton(
            tooltip: l.editorNewRouteTooltip,
            onPressed: _onCreateRoute,
            icon: const Icon(Icons.add_location_alt_outlined),
          ),
        ],
      ),
      body: ctrl.loading
          ? const Center(child: CircularProgressIndicator())
          : ctrl.routes.isEmpty
              ? EmptyState(
                  icon: Icons.route_outlined,
                  title: l.editorNoRoutesTitle,
                  message: l.editorNoRoutesMessage,
                  action: FilledButton.icon(
                    onPressed: _onCreateRoute,
                    icon: const Icon(Icons.add),
                    label: Text(l.editorNewRouteButton),
                  ),
                )
              : Column(
                  children: [
                    SizedBox(
                      height: 56,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: ctrl.routes.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, index) {
                          final route = ctrl.routes[index];
                          final selected = route.id == ctrl.selected?.id;
                          return ChoiceChip(
                            selected: selected,
                            label: Text(route.name),
                            onSelected: (_) => ctrl.select(route),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    if (ctrl.selected != null)
                      Expanded(
                        child: _RouteDetail(
                          route: ctrl.selected!,
                          config: widget.config,
                          controller: ctrl,
                          onDelete: () => _confirmDelete(ctrl.selected!),
                          showSectors: _showSectors,
                          onToggleSectors: () => setState(() => _showSectors = !_showSectors),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _RouteDetail extends StatelessWidget {
  const _RouteDetail({
    required this.route,
    required this.config,
    required this.controller,
    required this.onDelete,
    required this.showSectors,
    required this.onToggleSectors,
  });

  final RouteTemplate route;
  final AppConfig config;
  final RouteEditorController controller;
  final VoidCallback onDelete;
  final bool showSectors;
  final VoidCallback onToggleSectors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = controller.sessionsForSelected;
    final bestLap = _findBestLap(sessions);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Map
        Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: SplitwayMap(
              useMapbox: config.hasMapbox,
              route: route,
              showSectors: showSectors,
              interactive: false,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Route name + difficulty + sectors toggle
        Row(
          children: [
            Expanded(
              child: Text(route.name, style: theme.textTheme.headlineSmall),
            ),
            _DifficultyChip(difficulty: route.difficulty),
            if (route.sectors.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: onToggleSectors,
                icon: Icon(
                  showSectors ? Icons.flag : Icons.flag_outlined,
                ),
                tooltip: showSectors ? 'Ocultar sectores' : 'Ver sectores',
              ),
            ],
          ],
        ),
        if (route.description != null && route.description!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(route.description!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 16),

        // Bento grid — 2 columns
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: _halfWidth(context),
              child: BentoTile(
                icon: Icons.straighten,
                label: 'Distancia',
                value: _formatDistance(route.totalDistanceMeters),
              ),
            ),
            SizedBox(
              width: _halfWidth(context),
              child: BentoTile(
                icon: Icons.flag_outlined,
                label: 'Sectores',
                value: '${route.sectors.length}',
                onTap: route.sectors.isNotEmpty ? onToggleSectors : null,
              ),
            ),
            SizedBox(
              width: _halfWidth(context),
              child: BentoTile(
                icon: route.isClosed ? Icons.loop : Icons.linear_scale,
                label: 'Circuito',
                value: route.isClosed ? 'Cerrado' : 'Abierto',
              ),
            ),
            SizedBox(
              width: _halfWidth(context),
              child: BentoTile(
                icon: Icons.location_on_outlined,
                label: 'Localización',
                value: route.locationLabel ?? '—',
              ),
            ),
            SizedBox(
              width: _halfWidth(context),
              child: BentoTile(
                icon: Icons.calendar_today_outlined,
                label: 'Creación',
                value: Formatters.dateTime(route.createdAt),
              ),
            ),
            SizedBox(
              width: _halfWidth(context),
              child: BentoTile(
                icon: Icons.bolt_outlined,
                label: 'Dificultad',
                value: _difficultyLabel(route.difficulty),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: BentoTileWide(
                icon: Icons.emoji_events_outlined,
                label: 'Sesiones',
                value: _sessionsValue(sessions),
                trailingLabel: sessions.isNotEmpty ? 'Mejor' : null,
                trailingText: sessions.isNotEmpty ? _bestLapText(bestLap) : null,
                onTap: sessions.isNotEmpty
                    ? () => _navigateToSessions(context)
                    : null,
              ),
            ),
            SizedBox(
              width: _halfWidth(context),
              child: BentoActionTile(
                icon: Icons.edit_outlined,
                label: 'Editar',
                onTap: () => _showEditDialog(context),
              ),
            ),
            SizedBox(
              width: _halfWidth(context),
              child: BentoActionTile(
                icon: Icons.delete_outline,
                label: 'Eliminar',
                onTap: onDelete,
                backgroundColor: theme.colorScheme.errorContainer,
                foregroundColor: theme.colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ],
    );
  }

  double _halfWidth(BuildContext context) {
    final available = MediaQuery.of(context).size.width - 32 - 8;
    return available / 2;
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  String _difficultyLabel(RouteDifficulty d) => switch (d) {
        RouteDifficulty.easy => 'Fácil',
        RouteDifficulty.medium => 'Media',
        RouteDifficulty.hard => 'Difícil',
      };

  String _sessionsValue(List<SessionRun> sessions) {
    if (sessions.isEmpty) return 'Sin sesiones';
    return '${sessions.length} sesión${sessions.length > 1 ? "es" : ""}';
  }

  String _bestLapText(LapSummary? bestLap) {
    if (bestLap == null) return '—';
    return Formatters.duration(bestLap.duration);
  }

  LapSummary? _findBestLap(List<SessionRun> sessions) {
    LapSummary? best;
    for (final s in sessions) {
      final lap = s.bestLap;
      if (lap != null && (best == null || lap.duration < best.duration)) {
        best = lap;
      }
    }
    return best;
  }

  void _navigateToSessions(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _RouteSessionsScreen(
        routeName: route.name,
        sessions: controller.sessionsForSelected,
      ),
    ));
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final result = await showDialog<_EditRouteResult>(
      context: context,
      builder: (_) => _EditRouteDialog(
        name: route.name,
        description: route.description,
        difficulty: route.difficulty,
      ),
    );
    if (result == null) return;
    await controller.updateRouteMetadata(
      routeId: route.id,
      name: result.name,
      description: result.description,
      difficulty: result.difficulty,
    );
  }
}

class _RouteSessionsScreen extends StatelessWidget {
  const _RouteSessionsScreen({
    required this.routeName,
    required this.sessions,
  });

  final String routeName;
  final List<SessionRun> sessions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sesiones: $routeName')),
      body: sessions.isEmpty
          ? const Center(child: Text('No hay sesiones'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sessions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final s = sessions[i];
                final best = s.bestLap;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(Formatters.dateTime(s.startedAt)),
                    subtitle: Text(
                      '${s.laps.length} vueltas'
                      '${best != null ? " · Mejor: ${Formatters.duration(best.duration)}" : ""}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                );
              },
            ),
    );
  }
}

class _EditRouteResult {
  _EditRouteResult({
    required this.name,
    required this.difficulty,
    this.description,
  });

  final String name;
  final String? description;
  final RouteDifficulty difficulty;
}

class _EditRouteDialog extends StatefulWidget {
  const _EditRouteDialog({
    required this.name,
    required this.difficulty,
    this.description,
  });

  final String name;
  final String? description;
  final RouteDifficulty difficulty;

  @override
  State<_EditRouteDialog> createState() => _EditRouteDialogState();
}

class _EditRouteDialogState extends State<_EditRouteDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late RouteDifficulty _difficulty;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.name);
    _descCtrl = TextEditingController(text: widget.description ?? '');
    _difficulty = widget.difficulty;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar ruta'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Dificultad',
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            const SizedBox(height: 8),
            SegmentedButton<RouteDifficulty>(
              segments: const [
                ButtonSegment(value: RouteDifficulty.easy, label: Text('Fácil')),
                ButtonSegment(value: RouteDifficulty.medium, label: Text('Media')),
                ButtonSegment(value: RouteDifficulty.hard, label: Text('Difícil')),
              ],
              selected: {_difficulty},
              onSelectionChanged: (s) => setState(() => _difficulty = s.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _EditRouteResult(
                name: name,
                difficulty: _difficulty,
                description:
                    _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _DrawingView extends StatefulWidget {
  const _DrawingView({
    required this.controller,
    required this.config,
    this.initialCenter,
  });

  final RouteEditorController controller;
  final AppConfig config;
  final GeoPoint? initialCenter;

  @override
  State<_DrawingView> createState() => _DrawingViewState();
}

class _DrawingViewState extends State<_DrawingView> {
  final ValueNotifier<GeoPoint?> _flyToNotifier = ValueNotifier(null);

  @override
  void dispose() {
    _flyToNotifier.dispose();
    super.dispose();
  }

  Future<void> _centerOnUser() async {
    try {
      final servicesOn = await Geolocator.isLocationServiceEnabled();
      if (!servicesOn) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      _flyToNotifier.value = GeoPoint(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      // Silently ignore — GPS unavailable.
    }
  }

  String _modeLabel(AppLocalizations l, DrawInputMode mode) => switch (mode) {
        DrawInputMode.appendPath => l.editorModeAppendPath,
        DrawInputMode.sectorPoint => l.editorModeSectorGate,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.editorDrawingTitle(controller.draftName)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l.editorCancelTooltip,
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(l.editorCancelDrawingTitle),
                content: Text(l.editorCancelDrawingWarning),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(l.commonBack),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(l.commonDiscard),
                  ),
                ],
              ),
            );
            if (ok == true) controller.cancelDrawing();
          },
        ),
        actions: [
          if (controller.snapping)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: controller.draftCanSave
                  ? () async {
                      final saved = await controller.saveDraft();
                      if (!context.mounted) return;
                      if (saved != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l.editorRouteSavedSnack(saved.name)),
                          ),
                        );
                      }
                    }
                  : null,
              child: Text(l.commonSave),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                SplitwayMap(
                  useMapbox: widget.config.hasMapbox,
                  initialCenter: widget.initialCenter,
                  flyToNotifier: _flyToNotifier,
                  draftPath: controller.draftPath,
                  draftWaypoints: controller.rawWaypoints,
                  draftSectorPoints: controller.draftSectorPoints,
                  onTap: controller.handleMapTap,
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'center_on_user',
                    onPressed: _centerOnUser,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          if (!widget.config.hasMapbox)
            _InfoBanner(
              color: theme.colorScheme.tertiaryContainer,
              icon: Icons.map_outlined,
              message: l.editorNoMapboxToken,
            )
          else if (controller.snapFailed)
            _InfoBanner(
              color: theme.colorScheme.errorContainer,
              icon: Icons.wifi_off_outlined,
              iconColor: theme.colorScheme.onErrorContainer,
              message: l.editorSnapFailedMessage,
              textColor: theme.colorScheme.onErrorContainer,
            ),
          Container(
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_modeLabel(l, controller.inputMode),
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(l.editorSegmentPath),
                      selected: controller.inputMode == DrawInputMode.appendPath,
                      onSelected: (_) =>
                          controller.setInputMode(DrawInputMode.appendPath),
                    ),
                    ChoiceChip(
                      label: Text(l.editorSegmentAddSector),
                      selected: controller.inputMode == DrawInputMode.sectorPoint,
                      onSelected: (_) =>
                          controller.setInputMode(DrawInputMode.sectorPoint),
                    ),
                    OutlinedButton.icon(
                      onPressed: controller.draftPath.isEmpty
                          ? null
                          : controller.undoLastAction,
                      icon: const Icon(Icons.undo, size: 18),
                      label: Text(l.editorUndoPoint),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _DraftStatus(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftStatus extends StatelessWidget {
  const _DraftStatus({required this.controller});

  final RouteEditorController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        _StatusChip(
          icon: Icons.timeline,
          label: l.editorPathPoints(controller.draftWaypointCount),
          ok: controller.draftWaypointCount >= 2,
        ),
        const SizedBox(width: 8),
        _StatusChip(
          icon: Icons.flag_outlined,
          label: l.editorSectorsCount(controller.draftSectorPoints.length),
          ok: true,
          neutral: true,
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.ok,
    this.neutral = false,
  });

  final IconData icon;
  final String label;
  final bool ok;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final color = neutral
        ? Colors.blueGrey
        : (ok ? Colors.green : Colors.orange);
    return Chip(
      avatar: Icon(icon, size: 16, color: color.shade800),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip({required this.difficulty});

  final RouteDifficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (label, color) = switch (difficulty) {
      RouteDifficulty.easy => (l.editorDifficultyEasy, Colors.green),
      RouteDifficulty.medium => (l.editorDifficultyMedium, Colors.orange),
      RouteDifficulty.hard => (l.editorDifficultyHard, Colors.red),
    };
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
      labelStyle: TextStyle(color: color.shade900),
    );
  }
}

/// A full-width informational/warning banner shown below the map.
class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.color,
    required this.icon,
    required this.message,
    this.iconColor,
    this.textColor,
  });

  final Color color;
  final IconData icon;
  final String message;
  final Color? iconColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor =
        iconColor ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final effectiveTextColor =
        textColor ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: effectiveIconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: effectiveTextColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewRouteResult {
  _NewRouteResult({
    required this.name,
    required this.difficulty,
    this.description,
  });

  final String name;
  final String? description;
  final RouteDifficulty difficulty;
}

class _NewRouteDialog extends StatefulWidget {
  const _NewRouteDialog();

  @override
  State<_NewRouteDialog> createState() => _NewRouteDialogState();
}

class _NewRouteDialogState extends State<_NewRouteDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  RouteDifficulty _difficulty = RouteDifficulty.medium;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.editorNewRouteDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: l.editorNameLabel,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: l.editorDescriptionLabel,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(l.editorDifficultyLabel,
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            const SizedBox(height: 8),
            SegmentedButton<RouteDifficulty>(
              segments: [
                ButtonSegment(
                    value: RouteDifficulty.easy, label: Text(l.editorDifficultyEasy)),
                ButtonSegment(
                    value: RouteDifficulty.medium, label: Text(l.editorDifficultyMedium)),
                ButtonSegment(
                    value: RouteDifficulty.hard, label: Text(l.editorDifficultyHard)),
              ],
              selected: {_difficulty},
              onSelectionChanged: (s) => setState(() => _difficulty = s.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _NewRouteResult(
                name: name,
                difficulty: _difficulty,
                description:
                    _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
              ),
            );
          },
          child: Text(l.editorStartDrawingButton),
        ),
      ],
    );
  }
}
