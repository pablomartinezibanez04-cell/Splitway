# Routes List Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current editor browsing mode (horizontal chip selector + inline detail) with a proper "Rutas" screen showing all routes as a scrollable list (default) or grid/mosaic, with tap-to-detail navigation.

**Architecture:** The existing `RouteEditorScreen` browsing mode is replaced by a list/grid view. The `_RouteDetail` widget is extracted into a standalone `RouteDetailScreen` pushed via Navigator. The controller remains largely unchanged — it still manages routes list and drawing state. The bottom nav tab is renamed from "Editor" to "Rutas".

**Tech Stack:** Flutter, ChangeNotifier, GoRouter, existing RouteEditorController, existing BentoGrid widgets, l10n (ARB + gen-l10n).

---

### Task 1: Add localization strings

**Files:**
- Modify: `movile_app/lib/l10n/app_en.arb`
- Modify: `movile_app/lib/l10n/app_es.arb`

- [ ] **Step 1: Add new English strings to app_en.arb**

Add these entries after the `"navHistory"` line:

```json
"navRoutes": "Routes",
```

Add these entries after the last `editor*` block (after `"editorStartDrawingButton"`):

```json
"routesTitle": "My routes",
"routesViewList": "List",
"routesViewGrid": "Grid",
"routesSessionsCount": "{count, plural, =0{No sessions} =1{1 session} other{{count} sessions}}",
"@routesSessionsCount": { "placeholders": { "count": { "type": "int" } } },
"routesBestLap": "Best: {time}",
"@routesBestLap": { "placeholders": { "time": { "type": "String" } } },
"routesDetailTitle": "Route detail",
```

- [ ] **Step 2: Add new Spanish strings to app_es.arb**

Add these entries in the same positions:

```json
"navRoutes": "Rutas",
```

```json
"routesTitle": "Mis rutas",
"routesViewList": "Lista",
"routesViewGrid": "Mosaico",
"routesSessionsCount": "{count, plural, =0{Sin sesiones} =1{1 sesión} other{{count} sesiones}}",
"routesBestLap": "Mejor: {time}",
"routesDetailTitle": "Detalle de ruta",
```

- [ ] **Step 3: Regenerate l10n Dart files**

Run: `cd movile_app && flutter gen-l10n`
Expected: Generates updated `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_es.dart` with the new getters.

- [ ] **Step 4: Verify the new getter exists**

Run: `grep "routesTitle" movile_app/lib/l10n/app_localizations_en.dart`
Expected: Output shows `String get routesTitle => 'My routes';`

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/l10n/
git commit -m "feat(l10n): add EN/ES strings for routes list screen"
```

---

### Task 2: Create RouteListTile widget

**Files:**
- Create: `movile_app/lib/src/features/editor/widgets/route_list_tile.dart`

- [ ] **Step 1: Create the compact list tile widget**

```dart
import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../../shared/formatters.dart';

class RouteListTile extends StatelessWidget {
  const RouteListTile({
    super.key,
    required this.route,
    required this.sessionCount,
    this.bestLap,
    required this.onTap,
  });

  final RouteTemplate route;
  final int sessionCount;
  final Duration? bestLap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final diffColor = switch (route.difficulty) {
      RouteDifficulty.easy => Colors.green,
      RouteDifficulty.medium => Colors.orange,
      RouteDifficulty.hard => Colors.red,
    };

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: diffColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(l),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (bestLap != null) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.emoji_events_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.duration(bestLap!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(AppLocalizations l) {
    final parts = <String>[];
    parts.add(_formatDistance(route.totalDistanceMeters));
    if (route.locationLabel != null) {
      parts.add(route.locationLabel!);
    }
    parts.add(route.isClosed ? l.editorClosedLoop : l.editorOpenRoute);
    return parts.join(' · ');
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `cd movile_app && flutter analyze lib/src/features/editor/widgets/route_list_tile.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/features/editor/widgets/route_list_tile.dart
git commit -m "feat(routes): add RouteListTile compact widget"
```

---

### Task 3: Create RouteGridTile widget

**Files:**
- Create: `movile_app/lib/src/features/editor/widgets/route_grid_tile.dart`

- [ ] **Step 1: Create the compact grid tile widget**

```dart
import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../../shared/formatters.dart';

class RouteGridTile extends StatelessWidget {
  const RouteGridTile({
    super.key,
    required this.route,
    required this.sessionCount,
    this.bestLap,
    required this.onTap,
  });

  final RouteTemplate route;
  final int sessionCount;
  final Duration? bestLap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final diffColor = switch (route.difficulty) {
      RouteDifficulty.easy => Colors.green,
      RouteDifficulty.medium => Colors.orange,
      RouteDifficulty.hard => Colors.red,
    };
    final diffLabel = switch (route.difficulty) {
      RouteDifficulty.easy => l.editorDifficultyEasy,
      RouteDifficulty.medium => l.editorDifficultyMedium,
      RouteDifficulty.hard => l.editorDifficultyHard,
    };

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    route.isClosed ? Icons.loop : Icons.linear_scale,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      route.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _formatDistance(route.totalDistanceMeters),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              if (route.locationLabel != null)
                Text(
                  route.locationLabel!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: diffColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      diffLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: diffColor.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (sessionCount > 0)
                    Text(
                      l.routesSessionsCount(sessionCount),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `cd movile_app && flutter analyze lib/src/features/editor/widgets/route_grid_tile.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/features/editor/widgets/route_grid_tile.dart
git commit -m "feat(routes): add RouteGridTile compact widget"
```

---

### Task 4: Extract RouteDetailScreen

**Files:**
- Create: `movile_app/lib/src/features/editor/route_detail_screen.dart`

This extracts the current `_RouteDetail` widget from `route_editor_screen.dart` into a full standalone screen with its own Scaffold and AppBar.

- [ ] **Step 1: Create the RouteDetailScreen file**

```dart
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

  @override
  void initState() {
    super.initState();
    widget.controller.select(widget.route);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() => setState(() {});

  RouteTemplate get _route {
    return widget.controller.routes.firstWhere(
      (r) => r.id == widget.route.id,
      orElse: () => widget.route,
    );
  }

  Future<void> _confirmDelete() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.editorDeleteRouteTitle),
        content: Text(l.editorDeleteRouteConfirm(_route.name)),
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
      await widget.controller.deleteRoute(_route.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final route = _route;
    final sessions = widget.controller.sessionsForSelected;
    final bestLap = _findBestLap(sessions);

    return Scaffold(
      appBar: AppBar(title: Text(route.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  route.name,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              _DifficultyChip(difficulty: route.difficulty),
              if (route.sectors.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () =>
                      setState(() => _showSectors = !_showSectors),
                  icon: Icon(
                    _showSectors ? Icons.flag : Icons.flag_outlined,
                  ),
                  tooltip: _showSectors
                      ? l.editorHideSectors
                      : l.editorShowSectors,
                ),
              ],
            ],
          ),
          if (route.description != null &&
              route.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(route.description!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
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
                  value: route.isClosed
                      ? l.editorClosedLoop
                      : l.editorOpenRoute,
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
                  trailingText:
                      sessions.isNotEmpty ? _bestLapText(bestLap) : null,
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
      if (lap != null &&
          (best == null || lap.duration < best.duration)) {
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
    final result = await showModalBottomSheet<_EditRouteResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EditRouteSheet(
        name: _route.name,
        description: _route.description,
        difficulty: _route.difficulty,
      ),
    );
    if (result == null) return;
    await widget.controller.updateRouteMetadata(
      routeId: _route.id,
      name: result.name,
      description: result.description,
      difficulty: result.difficulty,
    );
  }
}

// --- Private helper widgets (moved from route_editor_screen.dart) ---

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
                child: Icon(Icons.edit_road_rounded,
                    color: cs.onPrimaryContainer, size: 24),
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
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
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
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
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
          _DifficultySelector(
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

class _DifficultySelector extends StatelessWidget {
  const _DifficultySelector({
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
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `cd movile_app && flutter analyze lib/src/features/editor/route_detail_screen.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/features/editor/route_detail_screen.dart
git commit -m "feat(routes): extract RouteDetailScreen as standalone screen"
```

---

### Task 5: Add session count method to controller

**Files:**
- Modify: `movile_app/lib/src/features/editor/route_editor_controller.dart`

The routes list needs session counts for all routes (not just the selected one). Add a method to fetch counts for display in the list/grid tiles.

- [ ] **Step 1: Add route session counts map to RouteEditorController**

After line 47 (`List<SessionRun> get sessionsForSelected => _sessionsForSelected;`), add:

```dart
  Map<String, int> _routeSessionCounts = const {};
  Map<String, int> get routeSessionCounts => _routeSessionCounts;

  Map<String, Duration?> _routeBestLaps = const {};
  Map<String, Duration?> get routeBestLaps => _routeBestLaps;
```

- [ ] **Step 2: Add a method to load session summaries for all routes**

After the `_loadSessionsForRoute` method (around line 177), add:

```dart
  Future<void> _loadAllRouteSummaries() async {
    final counts = <String, int>{};
    final bests = <String, Duration?>{};
    for (final route in _routes) {
      final sessions = await _repo.getSessionsByRoute(route.id);
      counts[route.id] = sessions.length;
      LapSummary? best;
      for (final s in sessions) {
        final lap = s.bestLap;
        if (lap != null && (best == null || lap.duration < best.duration)) {
          best = lap;
        }
      }
      bests[route.id] = best?.duration;
    }
    _routeSessionCounts = counts;
    _routeBestLaps = bests;
    notifyListeners();
  }
```

- [ ] **Step 3: Call the summary loader at the end of the `load()` method**

In the `load()` method, after `_loading = false; notifyListeners();` (around line 160), add:

```dart
    _loadAllRouteSummaries();
```

(This runs asynchronously — the list will render immediately with zero counts, then update once sessions are fetched.)

- [ ] **Step 4: Verify file compiles**

Run: `cd movile_app && flutter analyze lib/src/features/editor/route_editor_controller.dart`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/editor/route_editor_controller.dart
git commit -m "feat(routes): add session count/best-lap summaries to controller"
```

---

### Task 6: Rewrite RouteEditorScreen browsing mode

**Files:**
- Modify: `movile_app/lib/src/features/editor/route_editor_screen.dart`

Replace the current browsing mode (chip selector + inline `_RouteDetail`) with a list/grid of routes. The drawing mode (`_DrawingView`) stays unchanged.

- [ ] **Step 1: Add import for new files**

At the top of `route_editor_screen.dart`, add after line 18 (`import 'route_editor_controller.dart';`):

```dart
import 'route_detail_screen.dart';
import 'widgets/route_list_tile.dart';
import 'widgets/route_grid_tile.dart';
```

- [ ] **Step 2: Add view mode enum at file top**

After the imports, before `class RouteEditorScreen`, add:

```dart
enum _ViewMode { list, grid }
```

- [ ] **Step 3: Replace `_showSectors` and `_lastSelectedId` state with `_viewMode`**

In `_RouteEditorScreenState`, replace:

```dart
  bool _showSectors = false;
  String? _lastSelectedId;
  GeoPoint? _userLocation;
```

with:

```dart
  _ViewMode _viewMode = _ViewMode.list;
  GeoPoint? _userLocation;
```

- [ ] **Step 4: Simplify `_onChange` handler**

Replace the `_onChange` method:

```dart
  void _onChange() {
    setState(() {});
  }
```

- [ ] **Step 5: Replace the browsing mode `build` body**

Replace the Scaffold returned when `ctrl.drawing` is false (the entire `return Scaffold(...)` block from the `build` method, lines 159-218 approximately) with:

```dart
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: buildDrawerLeading(context, widget.authService),
        title: Text(l.routesTitle),
        actions: [
          IconButton(
            tooltip: _viewMode == _ViewMode.list
                ? l.routesViewGrid
                : l.routesViewList,
            onPressed: () => setState(() {
              _viewMode = _viewMode == _ViewMode.list
                  ? _ViewMode.grid
                  : _ViewMode.list;
            }),
            icon: Icon(
              _viewMode == _ViewMode.list
                  ? Icons.grid_view_rounded
                  : Icons.view_list_rounded,
            ),
          ),
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
              : _viewMode == _ViewMode.list
                  ? _buildListView(ctrl)
                  : _buildGridView(ctrl),
    );
```

- [ ] **Step 6: Add `_buildListView` and `_buildGridView` methods**

Add these methods to `_RouteEditorScreenState`, after the `build` method:

```dart
  Widget _buildListView(RouteEditorController ctrl) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: ctrl.routes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final route = ctrl.routes[index];
        return RouteListTile(
          route: route,
          sessionCount: ctrl.routeSessionCounts[route.id] ?? 0,
          bestLap: ctrl.routeBestLaps[route.id],
          onTap: () => _openRouteDetail(route),
        );
      },
    );
  }

  Widget _buildGridView(RouteEditorController ctrl) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: ctrl.routes.length,
      itemBuilder: (_, index) {
        final route = ctrl.routes[index];
        return RouteGridTile(
          route: route,
          sessionCount: ctrl.routeSessionCounts[route.id] ?? 0,
          bestLap: ctrl.routeBestLaps[route.id],
          onTap: () => _openRouteDetail(route),
        );
      },
    );
  }

  void _openRouteDetail(RouteTemplate route) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RouteDetailScreen(
        route: route,
        controller: widget.controller,
        config: widget.config,
      ),
    ));
  }
```

- [ ] **Step 7: Remove `_RouteDetail`, `_RouteSessionsScreen`, `_EditRouteSheet`, `_EditRouteResult`, `_DifficultyChip`, `_DifficultySelector` classes**

These have been moved to `route_detail_screen.dart`. Remove them from `route_editor_screen.dart` (approximately lines 222-1261 — everything from `class _RouteDetail` through the end of `class _DifficultySelector`, but **keep** `_DrawingView`, `_DraftStatus`, `_StatusChip`, `_InfoBanner`, `_NewRouteSheet`, `_NewRouteResult`).

Specifically, remove these classes/widgets:
- `_RouteDetail` (lines ~222-452)
- `_RouteSessionsScreen` (lines ~454-501)
- `_EditRouteResult` (lines ~504-514)
- `_EditRouteSheet` (lines ~516-680)
- `_DifficultyChip` (lines ~950-970)
- `_DifficultySelector` (lines ~1177-1261)

Keep these in `route_editor_screen.dart`:
- `_DrawingView` (lines ~682-893)
- `_DraftStatus` (lines ~895-920)
- `_StatusChip` (lines ~922-948)
- `_InfoBanner` (lines ~972-1015)
- `_NewRouteResult` (lines ~1017-1027)
- `_NewRouteSheet` (lines ~1029-1175)

Note: `_NewRouteSheet` still uses `_DifficultySelector`. Since `_DifficultySelector` is now in `route_detail_screen.dart` as a private class, you need to make it a shared widget. **Create a new file** for it:

- [ ] **Step 8: Extract `_DifficultySelector` into a shared widget**

Create `movile_app/lib/src/features/editor/widgets/difficulty_selector.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

class DifficultySelector extends StatelessWidget {
  const DifficultySelector({
    super.key,
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
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Then update both `route_editor_screen.dart` (in `_NewRouteSheet`) and `route_detail_screen.dart` (in `_EditRouteSheet`) to import and use the shared `DifficultySelector` instead of private `_DifficultySelector`.

Add to both files:
```dart
import 'widgets/difficulty_selector.dart';
```

Replace `_DifficultySelector(` with `DifficultySelector(` in both files.

- [ ] **Step 9: Verify the modified file compiles**

Run: `cd movile_app && flutter analyze lib/src/features/editor/`
Expected: No issues found.

- [ ] **Step 10: Commit**

```bash
git add movile_app/lib/src/features/editor/
git commit -m "feat(routes): replace chip selector with list/grid routes view"
```

---

### Task 7: Update HomeShell navigation

**Files:**
- Modify: `movile_app/lib/src/features/home/home_shell.dart`

- [ ] **Step 1: Change the first NavigationDestination**

In `home_shell.dart`, replace the first `NavigationDestination` (lines 58-61):

```dart
          NavigationDestination(
            icon: const Icon(Icons.edit_location_alt_outlined),
            selectedIcon: const Icon(Icons.edit_location_alt),
            label: AppLocalizations.of(context).navEditor,
          ),
```

with:

```dart
          NavigationDestination(
            icon: const Icon(Icons.route_outlined),
            selectedIcon: const Icon(Icons.route),
            label: AppLocalizations.of(context).navRoutes,
          ),
```

- [ ] **Step 2: Verify the file compiles**

Run: `cd movile_app && flutter analyze lib/src/features/home/home_shell.dart`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/features/home/home_shell.dart
git commit -m "feat(routes): rename nav tab Editor → Rutas with route icon"
```

---

### Task 8: Update AppRouter path

**Files:**
- Modify: `movile_app/lib/src/routing/app_router.dart`

- [ ] **Step 1: Change the initial location and route path**

In `app_router.dart`, change line 54:

```dart
    initialLocation: '/editor',
```

to:

```dart
    initialLocation: '/routes',
```

And change line 86:

```dart
                path: '/editor',
```

to:

```dart
                path: '/routes',
```

- [ ] **Step 2: Verify the file compiles**

Run: `cd movile_app && flutter analyze lib/src/routing/app_router.dart`
Expected: No issues found.

- [ ] **Step 3: Check for other references to '/editor'**

Run: `grep -r "'/editor'" movile_app/lib/`
Expected: No matches (if there are, update them to `'/routes'`).

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/routing/app_router.dart
git commit -m "feat(routes): rename /editor path to /routes"
```

---

### Task 9: Full analysis and runtime test

**Files:**
- All modified files

- [ ] **Step 1: Run full project analysis**

Run: `cd movile_app && flutter analyze`
Expected: No issues found.

- [ ] **Step 2: Run l10n generation**

Run: `cd movile_app && flutter gen-l10n`
Expected: Generates without errors.

- [ ] **Step 3: Build the app**

Run: `cd movile_app && flutter build apk --debug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 4: Verify no unused imports or dead code**

Run: `cd movile_app && flutter analyze --no-fatal-infos`
Expected: No errors or warnings (infos are acceptable).

- [ ] **Step 5: Commit any final fixes**

```bash
git add -A
git commit -m "fix: resolve analysis issues from routes screen refactor"
```

---

## Summary of File Changes

**Created:**
- `movile_app/lib/src/features/editor/widgets/route_list_tile.dart` — Compact list card for a route
- `movile_app/lib/src/features/editor/widgets/route_grid_tile.dart` — Compact grid card for a route
- `movile_app/lib/src/features/editor/widgets/difficulty_selector.dart` — Shared DifficultySelector widget
- `movile_app/lib/src/features/editor/route_detail_screen.dart` — Full route detail (extracted)

**Modified:**
- `movile_app/lib/l10n/app_en.arb` — New l10n keys
- `movile_app/lib/l10n/app_es.arb` — New l10n keys
- `movile_app/lib/l10n/app_localizations*.dart` — Regenerated
- `movile_app/lib/src/features/editor/route_editor_screen.dart` — Browsing mode → list/grid
- `movile_app/lib/src/features/editor/route_editor_controller.dart` — Session counts/best laps
- `movile_app/lib/src/features/home/home_shell.dart` — Nav tab label + icon
- `movile_app/lib/src/routing/app_router.dart` — Route path `/editor` → `/routes`
