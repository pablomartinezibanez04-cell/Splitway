import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../config/app_config.dart';
import '../../data/repositories/local_draft_repository.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/splitway_map.dart';
import '../history/history_screen.dart';
import 'route_editor_controller.dart';
import 'widgets/bento_grid.dart';
import 'widgets/difficulty_selector.dart';

class RouteDetailScreen extends StatefulWidget {
  const RouteDetailScreen({
    super.key,
    required this.route,
    required this.controller,
    required this.config,
  });

  final RouteTemplate route;
  final RouteEditorController controller;
  final AppConfig config;

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  bool _showSectors = false;

  RouteTemplate get _route =>
      widget.controller.routes.firstWhere(
        (r) => r.id == widget.route.id,
        orElse: () => widget.route,
      );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    widget.controller.select(widget.route);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  Future<void> _confirmDelete() async {
    final l = AppLocalizations.of(context);
    final route = _route;
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
    if (ok == true && mounted) {
      await widget.controller.deleteRoute(route.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final sessions = widget.controller.sessionsForSelected;
    final bestLap = _findBestLap(sessions);
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(route.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Map
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: SplitwayMap(
                useMapbox: widget.config.hasMapbox,
                route: route,
                showSectors: _showSectors,
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
                TextButton.icon(
                  onPressed: () => setState(() => _showSectors = !_showSectors),
                  icon: Icon(
                    _showSectors ? Icons.flag : Icons.flag_outlined,
                  ),
                  label: Text(
                    _showSectors ? l.editorHideSectors : l.editorShowSectors,
                  ),
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
                  onTap: route.sectors.isNotEmpty
                      ? () => setState(() => _showSectors = !_showSectors)
                      : null,
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
                  onTap: _confirmDelete,
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ],
      ),
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
        routeName: _route.name,
        sessions: widget.controller.sessionsForSelected,
        repository: widget.controller.repository,
        config: widget.config,
      ),
    ));
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final route = _route;
    final result = await showModalBottomSheet<_EditRouteResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EditRouteSheet(
        name: route.name,
        description: route.description,
        difficulty: route.difficulty,
      ),
    );
    if (result == null) return;
    await widget.controller.updateRouteMetadata(
      routeId: route.id,
      name: result.name,
      description: result.description,
      difficulty: result.difficulty,
    );
  }
}

// ---------------------------------------------------------------------------
// Supporting private widgets
// ---------------------------------------------------------------------------

class _RouteSessionsScreen extends StatelessWidget {
  const _RouteSessionsScreen({
    required this.routeName,
    required this.sessions,
    required this.repository,
    required this.config,
  });

  final String routeName;
  final List<SessionRun> sessions;
  final LocalDraftRepository repository;
  final AppConfig config;

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
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SessionDetailScreen(
                        sessionId: s.id,
                        repository: repository,
                        config: config,
                      ),
                    )),
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

class _EditRouteSheet extends StatefulWidget {
  const _EditRouteSheet({
    required this.name,
    required this.difficulty,
    this.description,
  });

  final String name;
  final String? description;
  final RouteDifficulty difficulty;

  @override
  State<_EditRouteSheet> createState() => _EditRouteSheetState();
}

class _EditRouteSheetState extends State<_EditRouteSheet> {
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
    final l = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
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
                child: Icon(Icons.edit_road_rounded, color: cs.onPrimaryContainer, size: 24),
              ),
              const SizedBox(width: 14),
              Text(
                l.editorEditRouteDialogTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: l.editorNameLabel,
              prefixIcon: const Icon(Icons.label_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            autofocus: true,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            decoration: InputDecoration(
              labelText: l.editorDescriptionLabel,
              prefixIcon: const Icon(Icons.notes_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              alignLabelWithHint: true,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          Text(
            l.editorDifficultyLabel,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          DifficultySelector(
            value: _difficulty,
            onChanged: (d) => setState(() => _difficulty = d),
          ),
          const SizedBox(height: 28),
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
                  onPressed: () {
                    final name = _nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(
                      context,
                      _EditRouteResult(
                        name: name,
                        difficulty: _difficulty,
                        description: _descCtrl.text.trim().isEmpty
                            ? null
                            : _descCtrl.text.trim(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: Text(l.commonSave),
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
