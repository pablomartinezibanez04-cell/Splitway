import 'dart:async';

import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../config/app_config.dart';
import '../../data/repositories/local_draft_repository.dart';
import '../../data/repositories/speed_repository.dart';
import '../../services/auth/auth_service.dart';
import '../../services/garage/garage_service.dart';
import '../../services/garage/vehicle.dart';
import '../../services/profile/profile_service.dart';
import '../../services/settings/app_settings_controller.dart';
import '../../services/speed/speed_metric.dart';
import '../../services/speed/speed_session.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/splitway_map.dart';
import '../garage/vehicle_detail_screen.dart';
import '../home/home_shell.dart';
import 'history_filters.dart';
import 'history_filters_sheet.dart';

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

enum _HistoryFilter { all, speed }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.repository,
    required this.settingsController,
    this.config = const AppConfig(),
    this.authService,
    this.profileService,
    this.garageService,
    this.speedRepository,
    this.initialTab,
  });

  final LocalDraftRepository repository;
  final AppSettingsController settingsController;
  final AppConfig config;
  final AuthService? authService;
  final ProfileService? profileService;
  final GarageService? garageService;
  final SpeedRepository? speedRepository;

  /// When set to `'speed'`, the screen opens directly on the Velocidad tab.
  /// Defaults to the combined "all" view.
  final String? initialTab;

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
  _HistoryFilter _filter = _HistoryFilter.all;
  List<SpeedSession> _speedSessions = const [];
  bool _speedLoading = false;

  StreamSubscription<void>? _changesSub;
  Timer? _reloadDebouncer;

  // --- Search / filter state ---
  final TextEditingController _searchCtrl = TextEditingController();
  HistoryFilters _filters = const HistoryFilters();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialTab == 'speed') {
      _filter = _HistoryFilter.speed;
    }
    _changesSub = widget.repository.changes.listen((_) {
      _reloadDebouncer?.cancel();
      _reloadDebouncer = Timer(const Duration(milliseconds: 300), _reload);
    });
    widget.authService?.addListener(_onAuthChanged);
    _load();
    if (_filter == _HistoryFilter.speed) {
      _loadSpeed();
    }
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    _reloadDebouncer?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    widget.authService?.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    _reload();
  }

  // --- Search helpers ---

  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _filters = _filters.copyWith(query: value);
      });
    });
    // Force rebuild so the suffix clear icon updates synchronously.
    setState(() {});
  }

  void _clearAllFilters() {
    _searchCtrl.clear();
    setState(() => _filters = const HistoryFilters());
  }

  /// Drops vehicle ids from the filter that no longer exist in the garage.
  /// Uses addPostFrameCallback to avoid calling setState during build.
  void _pruneStaleVehicleIds() {
    final svc = widget.garageService;
    if (svc == null) return;
    if (_filters.vehicleIds.isEmpty) return;
    final known = svc.vehicles.map((v) => v.id).toSet();
    final pruned =
        _filters.vehicleIds.where((id) => id == null || known.contains(id)).toSet();
    if (pruned.length != _filters.vehicleIds.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _filters = _filters.copyWith(vehicleIds: pruned));
      });
    }
  }

  // --- Filter mapping helpers ---

  HistoryEntryFields _toFilterFields(AppLocalizations l, _HistoryEntry e) {
    return switch (e) {
      _SessionEntry(:final session) => HistoryEntryFields(
          kind: HistoryEntryKind.session,
          displayName: _routes[session.routeTemplateId]?.name ??
              l.historyDeletedRoute,
          vehicleId: session.vehicleId,
          date: session.startedAt,
          maxSpeedMps: session.maxSpeedMps,
          totalDistanceMeters: session.totalDistanceMeters,
        ),
      _FreeRideEntry(:final ride) => HistoryEntryFields(
          kind: HistoryEntryKind.freeRide,
          displayName: ride.name ?? l.historyFreeRideLabel,
          vehicleId: ride.vehicleId,
          date: ride.startedAt,
          maxSpeedMps: ride.maxSpeedMps,
          totalDistanceMeters: ride.totalDistanceMeters,
        ),
    };
  }

  SpeedSessionFields _toSpeedFilterFields(SpeedSession s) {
    return SpeedSessionFields(
      displayName: s.name,
      vehicleId: s.vehicleId,
      date: s.startedAt,
      topSpeedKmh: s.results[SpeedMetric.topSpeed],
    );
  }

  // --- Active filter chips row ---

  /// Returns a label for the date-range chip, checking for preset ranges first.
  String _dateRangeChipLabel(AppLocalizations l, DateTimeRange range) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Helper: compare at day granularity.
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    // Last 7 days preset.
    final last7Start = today.subtract(const Duration(days: 7));
    if (sameDay(range.start, last7Start) && sameDay(range.end, today)) {
      return l.historyDateLast7Days;
    }

    // Last 30 days preset.
    final last30Start = today.subtract(const Duration(days: 30));
    if (sameDay(range.start, last30Start) && sameDay(range.end, today)) {
      return l.historyDateLast30Days;
    }

    // This year preset.
    final yearStart = DateTime(now.year, 1, 1);
    if (sameDay(range.start, yearStart) && sameDay(range.end, today)) {
      return l.historyDateThisYear;
    }

    // Custom range — use abbreviated month format.
    final fmt = DateFormat.MMMd(l.localeName);
    return '${fmt.format(range.start)} – ${fmt.format(range.end)}';
  }

  /// Builds the horizontally scrollable row of active filter chips.
  Widget _buildActiveFilterChips(AppLocalizations l) {
    if (_filters.activeCount == 0) return const SizedBox.shrink();

    final unit = widget.settingsController.unitSystem;
    final chips = <Widget>[];

    // Kind chip (only when exactly one kind is selected).
    if (_filters.kinds.length == 1) {
      final kind = _filters.kinds.first;
      final label = kind == HistoryEntryKind.session
          ? l.historyFilterKindSession
          : l.historyFilterKindFreeRide;
      chips.add(InputChip(
        label: Text(label),
        onDeleted: () =>
            setState(() => _filters = _filters.copyWith(kinds: const {})),
      ));
    }

    // Vehicle chip.
    if (_filters.vehicleIds.isNotEmpty) {
      if (_filters.vehicleIds.length == 1) {
        final id = _filters.vehicleIds.first;
        final String label;
        if (id == null) {
          label = l.historyNoVehicle;
        } else {
          final vehicle = widget.garageService?.vehicles
              .where((v) => v.id == id)
              .firstOrNull;
          label = vehicle?.name ?? '';
        }
        if (label.isNotEmpty) {
          chips.add(InputChip(
            label: Text(label),
            onDeleted: () => setState(
                () => _filters = _filters.copyWith(vehicleIds: const {})),
          ));
        }
      } else {
        chips.add(InputChip(
          label: Text(l.historyFilterVehicleChipMany(_filters.vehicleIds.length)),
          onDeleted: () => setState(
              () => _filters = _filters.copyWith(vehicleIds: const {})),
        ));
      }
    }

    // Date range chip.
    final dateRange = _filters.dateRange;
    if (dateRange != null) {
      chips.add(InputChip(
        label: Text(_dateRangeChipLabel(l, dateRange)),
        onDeleted: () =>
            setState(() => _filters = _filters.copyWith(dateRange: null)),
      ));
    }

    // Min max speed chip.
    final minSpeedMps = _filters.minMaxSpeedMps;
    if (minSpeedMps != null) {
      final speedDisplay = unit == UnitSystem.imperial
          ? minSpeedMps * 2.23694
          : minSpeedMps * 3.6;
      final speedStr = speedDisplay.toStringAsFixed(1);
      final speedWithUnit = unit == UnitSystem.imperial
          ? '$speedStr mph'
          : '$speedStr km/h';
      chips.add(InputChip(
        label: Text(l.historyFilterMinSpeedChip(speedWithUnit)),
        onDeleted: () => setState(
            () => _filters = _filters.copyWith(minMaxSpeedMps: null)),
      ));
    }

    // Min distance chip.
    final minDistM = _filters.minDistanceMeters;
    if (minDistM != null) {
      final distDisplay = unit == UnitSystem.imperial
          ? minDistM / 1609.344
          : minDistM / 1000.0;
      final distStr = distDisplay.toStringAsFixed(1);
      final distWithUnit =
          unit == UnitSystem.imperial ? '$distStr mi' : '$distStr km';
      chips.add(InputChip(
        label: Text(l.historyFilterMinDistanceChip(distWithUnit)),
        onDeleted: () => setState(
            () => _filters = _filters.copyWith(minDistanceMeters: null)),
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < chips.length; i++) {
      children.add(chips[i]);
      if (i < chips.length - 1) children.add(const SizedBox(width: 8));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: children),
      ),
    );
  }

  // --- Filtered empty state widget ---

  Widget _filteredEmptyState(AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 56),
          const SizedBox(height: 12),
          Text(
            l.historyFilteredEmptyTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.clear),
            label: Text(l.historyFilteredEmptyAction),
            onPressed: _clearAllFilters,
          ),
        ],
      ),
    );
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
    _pruneStaleVehicleIds();
    return ListenableBuilder(
      listenable: widget.settingsController,
      builder: (context, _) => Scaffold(
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
        body: Column(
          children: [
            // Search row — always visible on both tabs.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onQueryChanged,
                      decoration: InputDecoration(
                        hintText: l.historySearchHint,
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: MaterialLocalizations.of(context)
                                    .deleteButtonTooltip,
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _onQueryChanged('');
                                },
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  // Filter button with optional badge showing active filter count.
                  _FilterButton(
                    tooltip: l.historyFiltersOpen,
                    activeCount: _filters.activeCount,
                    onPressed: () async {
                      final result = await showHistoryFiltersSheet(
                        context: context,
                        initial: _filters,
                        vehicles:
                            widget.garageService?.vehicles ?? const [],
                        isSpeedTab: _filter == _HistoryFilter.speed,
                        unitSystem:
                            widget.settingsController.unitSystem,
                      );
                      if (result != null) {
                        setState(() => _filters = result);
                      }
                    },
                  ),
                ],
              ),
            ),
            _buildActiveFilterChips(l),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SegmentedButton<_HistoryFilter>(
                segments: [
                  ButtonSegment(
                    value: _HistoryFilter.all,
                    label: Text(l.historyTitle),
                  ),
                  ButtonSegment(
                    value: _HistoryFilter.speed,
                    label: Text(l.speedHistoryTab),
                    icon: const Icon(Icons.speed_outlined),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (s) {
                  setState(() => _filter = s.first);
                  if (_filter == _HistoryFilter.speed) _loadSpeed();
                },
              ),
            ),
            Expanded(
              child: _filter == _HistoryFilter.speed
                  ? _buildSpeedList(l)
                  : _buildMainList(l),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainList(AppLocalizations l) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_entries.isEmpty) {
      return EmptyState(
        icon: Icons.history_toggle_off,
        title: l.historyNoEntriesTitle,
        message: l.historyNoEntriesMessage,
      );
    }

    // Apply filters.
    final filtered = _filters.isEmpty
        ? _entries
        : _entries
            .where((e) =>
                matchesHistoryFilters(_filters, _toFilterFields(l, e)))
            .toList();

    if (filtered.isEmpty) {
      return _filteredEmptyState(l);
    }

    // Hide the load-more sentinel when any filter is active to avoid loading
    // pages that will be entirely filtered out.
    final showSentinel = _hasMore && _filters.isEmpty;

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: filtered.length + (showSentinel ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, index) {
        if (index >= filtered.length) {
          // Load-more sentinel: trigger next page when visible.
          _load();
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final entry = filtered[index];
        return switch (entry) {
          _SessionEntry(:final session) => _SessionTile(
              session: session,
              route: _routes[session.routeTemplateId],
              repository: widget.repository,
              config: widget.config,
              garageService: widget.garageService,
              settingsController: widget.settingsController,
            ),
          _FreeRideEntry(:final ride) => _FreeRideTile(
              ride: ride,
              repository: widget.repository,
              config: widget.config,
              garageService: widget.garageService,
              settingsController: widget.settingsController,
            ),
        };
      },
    );
  }

  Future<void> _loadSpeed() async {
    if (widget.speedRepository == null) return;
    final userId = widget.authService?.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _speedSessions = const []);
      return;
    }
    if (mounted) setState(() => _speedLoading = true);
    final list = await widget.speedRepository!.listForUser(userId);
    if (!mounted) return;
    setState(() {
      _speedSessions = list;
      _speedLoading = false;
    });
  }

  Widget _buildSpeedList(AppLocalizations l) {
    if (_speedLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_speedSessions.isEmpty && _filters.isEmpty) {
      return Center(child: Text(l.speedHistoryEmpty));
    }

    // Apply filters.
    final filtered = _filters.isEmpty
        ? _speedSessions
        : _speedSessions
            .where((s) =>
                matchesSpeedFilters(_filters, _toSpeedFilterFields(s)))
            .toList();

    if (filtered.isEmpty) {
      return _filteredEmptyState(l);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final s = filtered[i];
        final top = s.results[SpeedMetric.topSpeed];
        final dateLabel =
            DateFormat.yMd(l.localeName).add_Hm().format(s.startedAt);
        final subtitle = top == null
            ? dateLabel
            : '$dateLabel  ·  ${top.round()} km/h';
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.speed_outlined)),
          title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle),
          trailing: IconButton(
            tooltip: l.speedHistoryDeleteTooltip,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDeleteSpeed(s),
          ),
          onTap: () => context.push('/history/speed/${s.id}'),
        );
      },
    );
  }

  Future<void> _confirmDeleteSpeed(SpeedSession s) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.speedHistoryDeleteTitle),
        content: Text(l.speedHistoryDeleteConfirm(s.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (widget.speedRepository == null) return;
    await widget.speedRepository!.softDelete(s.id);
    if (!mounted) return;
    await _loadSpeed();
  }
}

// ---------------------------------------------------------------------------
// Filter icon button with an active-count badge.
// ---------------------------------------------------------------------------

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.tooltip,
    required this.activeCount,
    required this.onPressed,
  });

  final String tooltip;
  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: tooltip,
          icon: const Icon(Icons.tune),
          onPressed: onPressed,
        ),
        if (activeCount > 0)
          Positioned(
            top: 4,
            right: 4,
            child: IgnorePointer(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: colorScheme.error,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$activeCount',
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onError,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helper functions for unit-aware formatting (used by inner widgets).
// [ctrl] may be null when opened from contexts that don't carry settings
// (e.g. RouteDetailScreen → SessionDetailScreen). In that case metric/dot
// defaults are used.
// ---------------------------------------------------------------------------

String _speedLabel(
    AppLocalizations l, double mps, AppSettingsController? ctrl) {
  final unit = ctrl?.unitSystem ?? UnitSystem.metric;
  final v = Formatters.speedMps(mps, unit: unit);
  return unit == UnitSystem.imperial ? l.unitMph(v) : l.unitKmh(v);
}

String _distanceLabel(
    AppLocalizations l, double meters, AppSettingsController? ctrl) {
  final unit = ctrl?.unitSystem ?? UnitSystem.metric;
  final (value, isLarge) = Formatters.distanceMeters(meters, unit: unit);
  final formatted = value.toStringAsFixed(value >= 10 ? 1 : 2);
  if (unit == UnitSystem.imperial) {
    return isLarge ? l.unitMiles(formatted) : l.unitFeet(formatted);
  }
  return isLarge ? l.unitKilometers(formatted) : l.unitMeters(formatted);
}

String _elevationLabel(
    AppLocalizations l, double meters, AppSettingsController? ctrl) {
  final unit = ctrl?.unitSystem ?? UnitSystem.metric;
  if (unit == UnitSystem.imperial) {
    final feet = meters * 3.28084;
    return l.elevationRangeValueFeet(feet.toStringAsFixed(0));
  }
  return l.elevationRangeValue(meters.toStringAsFixed(0));
}

// ---------------------------------------------------------------------------

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.route,
    required this.repository,
    required this.config,
    required this.settingsController,
    this.garageService,
  });

  final SessionRun session;
  final RouteTemplate? route;
  final LocalDraftRepository repository;
  final AppConfig config;
  final AppSettingsController settingsController;
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
        ? l.historyBestLapSuffix(Formatters.duration(
            best.duration,
            dotSeparator: settingsController.timeFormatDot,
          ))
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
                    settingsController: settingsController,
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
    required this.settingsController,
    this.garageService,
  });

  final FreeRideRun ride;
  final LocalDraftRepository repository;
  final AppConfig config;
  final AppSettingsController settingsController;
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
    final distStr = _distanceLabel(l, ride.totalDistanceMeters, settingsController);
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
                settingsController: settingsController,
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
    this.settingsController,
    this.config = const AppConfig(),
  });

  final String rideId;
  final LocalDraftRepository repository;
  final AppSettingsController? settingsController;
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
                    _FreeRideSummaryRow(
                      ride: _ride!,
                      settingsController: widget.settingsController,
                    ),
                  ],
                ),
    );
  }
}

class _FreeRideSummaryRow extends StatelessWidget {
  const _FreeRideSummaryRow({
    required this.ride,
    this.settingsController,
  });

  final FreeRideRun ride;
  final AppSettingsController? settingsController;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final distStr = _distanceLabel(l, ride.totalDistanceMeters, settingsController);
    final entries = [
      (l.historyDistanceLabel, distStr),
      (l.historyMaxSpeedLabel, _speedLabel(l, ride.maxSpeedMps, settingsController)),
      (l.historyAvgSpeedLabel, _speedLabel(l, ride.avgSpeedMps, settingsController)),
    ];
    final elevation = ride.elevationRangeMeters;
    return Column(
      children: [
        Row(
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
        ),
        if (elevation != null) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(l.elevationRangeLabel,
                      style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(width: 8),
                  Text(
                    _elevationLabel(l, elevation, settingsController),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.sessionId,
    required this.repository,
    this.settingsController,
    this.config = const AppConfig(),
  });

  final String sessionId;
  final LocalDraftRepository repository;
  final AppSettingsController? settingsController;
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
                    _SummaryRow(
                      session: _session!,
                      settingsController: widget.settingsController,
                    ),
                    const SizedBox(height: 16),
                    Text(l.historyLapsLabel,
                        style: Theme.of(context).textTheme.titleMedium),
                    for (final lap in _session!.laps)
                      ListTile(
                        leading: CircleAvatar(child: Text('${lap.lapNumber}')),
                        title: Text(Formatters.duration(
                          lap.duration,
                          dotSeparator: widget.settingsController?.timeFormatDot ?? true,
                        )),
                        subtitle: Text(() {
                            final dist = _distanceLabel(
                              l,
                              lap.distanceMeters,
                              widget.settingsController,
                            );
                            final speed = _speedLabel(
                              l,
                              lap.avgSpeedMps,
                              widget.settingsController,
                            );
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
                            _speedLabel(
                              l,
                              sec.avgSpeedMps,
                              widget.settingsController,
                            ),
                          ),
                        ),
                        trailing: Text(Formatters.duration(
                          sec.duration,
                          dotSeparator: widget.settingsController?.timeFormatDot ?? true,
                        )),
                      ),
                  ],
                ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.session,
    this.settingsController,
  });

  final SessionRun session;
  final AppSettingsController? settingsController;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final distStr = _distanceLabel(l, session.totalDistanceMeters, settingsController);
    final entries = [
      (l.historyDistanceLabel, distStr),
      (l.historyMaxSpeedLabel, _speedLabel(l, session.maxSpeedMps, settingsController)),
      (l.historyAvgSpeedLabel, _speedLabel(l, session.avgSpeedMps, settingsController)),
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
