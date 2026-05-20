import 'dart:async';

import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../config/app_config.dart';
import '../../data/repositories/local_draft_repository.dart';
import '../../services/auth/auth_service.dart';
import '../../services/garage/garage_service.dart';
import '../../services/garage/vehicle.dart';
import '../../services/profile/profile_service.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/splitway_map.dart';
import '../garage/vehicle_detail_screen.dart';
import '../home/home_shell.dart';

sealed class _HistoryEntry implements Comparable<_HistoryEntry> {
  DateTime get date;

  @override
  int compareTo(_HistoryEntry other) => other.date.compareTo(date);
}

class _SessionEntry extends _HistoryEntry {
  _SessionEntry(this.session);
  final SessionRun session;

  @override
  DateTime get date => session.startedAt;
}

class _FreeRideEntry extends _HistoryEntry {
  _FreeRideEntry(this.ride);
  final FreeRideRun ride;

  @override
  DateTime get date => ride.startedAt;
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.repository,
    this.config = const AppConfig(),
    this.authService,
    this.profileService,
    this.garageService,
  });

  final LocalDraftRepository repository;
  final AppConfig config;
  final AuthService? authService;
  final ProfileService? profileService;
  final GarageService? garageService;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _pageSize = 30;

  bool _loading = true;
  List<_HistoryEntry> _entries = const [];
  Map<String, RouteTemplate> _routes = const {};
  bool _hasMore = true;
  int _sessionOffset = 0;
  int _freeRideOffset = 0;

  StreamSubscription<void>? _changesSub;
  Timer? _reloadDebouncer;

  @override
  void initState() {
    super.initState();
    _changesSub = widget.repository.changes.listen((_) {
      _reloadDebouncer?.cancel();
      _reloadDebouncer = Timer(const Duration(milliseconds: 300), _reload);
    });
    widget.authService?.addListener(_onAuthChanged);
    _load();
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    _reloadDebouncer?.cancel();
    widget.authService?.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    _reload();
  }

  /// Full reload: resets pagination and re-fetches the first page.
  void _reload() {
    _sessionOffset = 0;
    _freeRideOffset = 0;
    _hasMore = true;
    _entries = const [];
    _load();
  }

  /// Loads the next page of entries (both sessions and free rides).
  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = _entries.isEmpty);

    final sessions = await widget.repository.getAllSessions(
      limit: _pageSize,
      offset: _sessionOffset,
    );
    final freeRides = await widget.repository.getAllFreeRides(
      limit: _pageSize,
      offset: _freeRideOffset,
    );
    final routeList = await widget.repository.getAllRoutes();
    if (!mounted) return;

    final newEntries = <_HistoryEntry>[
      ...sessions.map(_SessionEntry.new),
      ...freeRides.map(_FreeRideEntry.new),
    ]..sort();

    setState(() {
      if (_sessionOffset == 0 && _freeRideOffset == 0) {
        _entries = newEntries;
      } else {
        _entries = [..._entries, ...newEntries];
      }
      _routes = {for (final r in routeList) r.id: r};
      _sessionOffset += sessions.length;
      _freeRideOffset += freeRides.length;
      _hasMore = sessions.length == _pageSize || freeRides.length == _pageSize;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: buildDrawerLeading(
          context,
          widget.authService,
          widget.profileService,
        ),
        title: Text(l.historyTitle),
        actions: [
          IconButton(
            tooltip: l.commonRefresh,
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? EmptyState(
                  icon: Icons.history_toggle_off,
                  title: l.historyNoEntriesTitle,
                  message: l.historyNoEntriesMessage,
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _entries.length + (_hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, index) {
                    if (index >= _entries.length) {
                      // Load-more sentinel: trigger next page when visible.
                      _load();
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final entry = _entries[index];
                    return switch (entry) {
                      _SessionEntry(:final session) => _SessionTile(
                          session: session,
                          route: _routes[session.routeTemplateId],
                          repository: widget.repository,
                          config: widget.config,
                          garageService: widget.garageService,
                        ),
                      _FreeRideEntry(:final ride) => _FreeRideTile(
                          ride: ride,
                          repository: widget.repository,
                          config: widget.config,
                          garageService: widget.garageService,
                        ),
                    };
                  },
                ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.route,
    required this.repository,
    required this.config,
    this.garageService,
  });

  final SessionRun session;
  final RouteTemplate? route;
  final LocalDraftRepository repository;
  final AppConfig config;
  final GarageService? garageService;

  Vehicle? get _vehicle {
    final vid = session.vehicleId;
    if (vid == null || garageService == null) return null;
    return garageService!.vehicles
        .where((v) => v.id == vid)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final best = session.bestLap;
    final bestLapSuffix = best != null
        ? l.historyBestLapSuffix(Formatters.duration(best.duration))
        : '';
    final vehicle = _vehicle;
    return Card(
      child: ListTile(
        title: Text(route?.name ?? l.historyDeletedRoute),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.historySessionSubtitle(
                Formatters.dateTime(session.startedAt),
                session.laps.length,
                bestLapSuffix,
              ),
            ),
            if (vehicle != null)
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => VehicleDetailScreen(
                    vehicle: vehicle,
                    garageService: garageService!,
                  ),
                )),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_car,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        vehicle.name,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: route == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SessionDetailScreen(
                    sessionId: session.id,
                    repository: repository,
                    config: config,
                  ),
                )),
      ),
    );
  }
}

class _FreeRideTile extends StatelessWidget {
  const _FreeRideTile({
    required this.ride,
    required this.repository,
    required this.config,
    this.garageService,
  });

  final FreeRideRun ride;
  final LocalDraftRepository repository;
  final AppConfig config;
  final GarageService? garageService;

  Vehicle? get _vehicle {
    final vid = ride.vehicleId;
    if (vid == null || garageService == null) return null;
    return garageService!.vehicles
        .where((v) => v.id == vid)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (dv, isKm) = Formatters.distanceMeters(ride.totalDistanceMeters);
    final distStr = isKm
        ? l.unitKilometers(dv.toStringAsFixed(2))
        : l.unitMeters(dv.toStringAsFixed(0));
    final vehicle = _vehicle;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.explore, color: Colors.teal),
        title: Text(ride.name ?? l.historyFreeRideLabel),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.historyFreeRideSubtitle(
                Formatters.dateTime(ride.startedAt),
                distStr,
              ),
            ),
            if (vehicle != null)
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => VehicleDetailScreen(
                    vehicle: vehicle,
                    garageService: garageService!,
                  ),
                )),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_car,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        vehicle.name,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FreeRideDetailScreen(
                rideId: ride.id,
                repository: repository,
                config: config,
              ),
            )),
      ),
    );
  }
}

class FreeRideDetailScreen extends StatefulWidget {
  const FreeRideDetailScreen({
    super.key,
    required this.rideId,
    required this.repository,
    this.config = const AppConfig(),
  });

  final String rideId;
  final LocalDraftRepository repository;
  final AppConfig config;

  @override
  State<FreeRideDetailScreen> createState() => _FreeRideDetailScreenState();
}

class _FreeRideDetailScreenState extends State<FreeRideDetailScreen> {
  FreeRideRun? _ride;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ride = await widget.repository.getFreeRideRun(widget.rideId);
    if (!mounted) return;
    setState(() {
      _ride = ride;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_ride?.name ?? l.historyFreeRideTitle),
        actions: [
          if (_ride != null)
            IconButton(
              tooltip: l.historyRenameFreeRideTitle,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final rideId = _ride?.id;
                final currentName = _ride?.name;
                if (rideId == null) return;
                final nameCtrl =
                    TextEditingController(text: currentName ?? '');
                final newName = await showDialog<String>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    title: Text(l.historyRenameFreeRideTitle),
                    content: TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: l.historyRenameFreeRideLabel,
                      ),
                      autofocus: true,
                      onSubmitted: (v) => Navigator.pop(dialogCtx, v),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: Text(l.commonCancel),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(dialogCtx, nameCtrl.text),
                        child: Text(l.commonSave),
                      ),
                    ],
                  ),
                );
                if (newName == null || newName.trim().isEmpty) return;
                await widget.repository.updateFreeRideMetadata(
                  rideId,
                  name: newName.trim(),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.historyRenamedSnack)),
                );
                _load();
              },
            ),
          if (_ride != null)
            IconButton(
              tooltip: l.historyDeleteFreeRideTitle,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final rideId = _ride?.id;
                if (rideId == null) return;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    title: Text(l.historyDeleteFreeRideTitle),
                    content: Text(l.historyIrreversibleWarning),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: Text(l.commonCancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        child: Text(l.commonDelete),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                await widget.repository.deleteFreeRide(rideId);
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ride == null
              ? EmptyState(
                  icon: Icons.error_outline,
                  title: l.historySessionNotFound,
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_ride!.points.isNotEmpty)
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: SplitwayMap(
                            useMapbox: widget.config.hasMapbox,
                            telemetry: _ride!.points,
                            interactive: false,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      Formatters.dateTime(_ride!.startedAt),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    _FreeRideSummaryRow(ride: _ride!),
                  ],
                ),
    );
  }
}

class _FreeRideSummaryRow extends StatelessWidget {
  const _FreeRideSummaryRow({required this.ride});

  final FreeRideRun ride;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (dv, isKm) = Formatters.distanceMeters(ride.totalDistanceMeters);
    final distStr = isKm
        ? l.unitKilometers(dv.toStringAsFixed(2))
        : l.unitMeters(dv.toStringAsFixed(0));
    final entries = [
      (l.historyDistanceLabel, distStr),
      (l.historyMaxSpeedLabel, l.unitKmh(Formatters.speedMps(ride.maxSpeedMps))),
      (l.historyAvgSpeedLabel, l.unitKmh(Formatters.speedMps(ride.avgSpeedMps))),
    ];
    return Row(
      children: [
        for (final e in entries)
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Text(e.$1,
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Text(e.$2,
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.sessionId,
    required this.repository,
    this.config = const AppConfig(),
  });

  final String sessionId;
  final LocalDraftRepository repository;
  final AppConfig config;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  SessionRun? _session;
  RouteTemplate? _route;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await widget.repository.getSessionRun(widget.sessionId);
    final route = session == null
        ? null
        : await widget.repository.getRouteTemplate(session.routeTemplateId);
    if (!mounted) return;
    setState(() {
      _session = session;
      _route = route;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_route?.name ?? l.historySessionTitle),
        actions: [
          if (_route != null)
            IconButton(
              tooltip: l.historyRenameRouteTitle,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final routeId = _route?.id;
                final currentName = _route?.name;
                if (routeId == null) return;
                final nameCtrl =
                    TextEditingController(text: currentName ?? '');
                final newName = await showDialog<String>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    title: Text(l.historyRenameRouteTitle),
                    content: TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: l.historyRenameRouteLabel,
                      ),
                      autofocus: true,
                      onSubmitted: (v) => Navigator.pop(dialogCtx, v),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: Text(l.commonCancel),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(dialogCtx, nameCtrl.text),
                        child: Text(l.commonSave),
                      ),
                    ],
                  ),
                );
                if (newName == null || newName.trim().isEmpty) return;
                await widget.repository.updateRouteTemplateName(
                  routeId,
                  newName.trim(),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.historyRenamedSnack)),
                );
                _load();
              },
            ),
          if (_session != null)
            IconButton(
              tooltip: l.historyDeleteSessionTitle,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final sessionId = _session?.id;
                if (sessionId == null) return;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    title: Text(l.historyDeleteSessionTitle),
                    content: Text(l.historyIrreversibleWarning),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: Text(l.commonCancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        child: Text(l.commonDelete),
                      ),
                    ],
                  ),
                );
                if (ok != true) return;
                await widget.repository.deleteSession(sessionId);
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _session == null || _route == null
              ? EmptyState(
                  icon: Icons.error_outline,
                  title: l.historySessionNotFound,
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: SplitwayMap(
                          useMapbox: widget.config.hasMapbox,
                          route: _route!,
                          telemetry: _session!.points,
                          interactive: false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      Formatters.dateTime(_session!.startedAt),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    _SummaryRow(session: _session!),
                    const SizedBox(height: 16),
                    Text(l.historyLapsLabel,
                        style: Theme.of(context).textTheme.titleMedium),
                    for (final lap in _session!.laps)
                      ListTile(
                        leading: CircleAvatar(child: Text('${lap.lapNumber}')),
                        title: Text(Formatters.duration(lap.duration)),
                        subtitle: Text(() {
                            final (dv, isKm) = Formatters.distanceMeters(lap.distanceMeters);
                            final dist = isKm
                                ? l.unitKilometers(dv.toStringAsFixed(2))
                                : l.unitMeters(dv.toStringAsFixed(0));
                            final speed = l.unitKmh(Formatters.speedMps(lap.avgSpeedMps));
                            return '$dist · $speed';
                          }()),
                        trailing: lap.completed
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : const Icon(Icons.timer_off, color: Colors.orange),
                      ),
                    const SizedBox(height: 16),
                    Text(l.historySectorsLabel,
                        style: Theme.of(context).textTheme.titleMedium),
                    for (final sec in _session!.sectorSummaries)
                      ListTile(
                        leading: const Icon(Icons.flag_outlined),
                        title: Text(_route!.sectors
                            .firstWhere(
                              (s) => s.id == sec.sectorId,
                              orElse: () => SectorDefinition(
                                id: sec.sectorId,
                                order: 0,
                                label: sec.sectorId,
                                gate: _route!.startFinishGate,
                              ),
                            )
                            .label),
                        subtitle: Text(
                          l.historySectorSubtitle(
                            sec.lapNumber,
                            l.unitKmh(Formatters.speedMps(sec.avgSpeedMps)),
                          ),
                        ),
                        trailing: Text(Formatters.duration(sec.duration)),
                      ),
                  ],
                ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.session});

  final SessionRun session;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (dv, isKm) = Formatters.distanceMeters(session.totalDistanceMeters);
    final distStr = isKm
        ? l.unitKilometers(dv.toStringAsFixed(2))
        : l.unitMeters(dv.toStringAsFixed(0));
    final entries = [
      (l.historyDistanceLabel, distStr),
      (l.historyMaxSpeedLabel, l.unitKmh(Formatters.speedMps(session.maxSpeedMps))),
      (l.historyAvgSpeedLabel, l.unitKmh(Formatters.speedMps(session.avgSpeedMps))),
    ];
    return Row(
      children: [
        for (final e in entries)
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Text(e.$1,
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Text(e.$2,
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
