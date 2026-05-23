# History Search & Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent text search bar plus a filters bottom sheet to the History screen, applying to both the "Todo" and "Velocidad" tabs.

**Architecture:** Extract a pure, testable filter module (`HistoryFilters` value class + pure functions) into its own file. Keep the UI (search row, filters sheet, active-filter chips) inside the existing `history_screen.dart` since the file already concentrates feature widgets. When any filter is active, swap the paginated repository fetch for a single full fetch (defensive cap of 1000) and filter in memory. The repository is **not** modified.

**Tech Stack:** Flutter / Dart, `flutter_localizations` ARB pipeline, `intl` `DateFormat`, existing `LocalDraftRepository` and `SpeedRepository`.

**Spec:** [docs/superpowers/specs/2026-05-22-history-search-filters-design.md](../specs/2026-05-22-history-search-filters-design.md)

---

## File structure

| Path | Action | Responsibility |
|------|--------|----------------|
| `movile_app/lib/l10n/app_en.arb` | Modify | Add new search/filter strings (template). |
| `movile_app/lib/l10n/app_es.arb` | Modify | Add new search/filter strings (Spanish). |
| `movile_app/lib/l10n/app_localizations*.dart` | Modify (regenerated) | Picked up automatically by `flutter gen-l10n`. |
| `movile_app/lib/src/features/history/history_filters.dart` | **Create** | Pure model + filter functions; sealed `HistoryEntry` hierarchy moved here (was private to `history_screen.dart`). |
| `movile_app/lib/src/features/history/history_screen.dart` | Modify | Search bar widget, filters bottom sheet, active-filter chips, full-load fallback. Drops local sealed hierarchy in favor of the one from `history_filters.dart`. |
| `movile_app/test/features/history/history_filters_test.dart` | **Create** | Unit tests for the pure filter module. |
| `movile_app/test/features/history/history_screen_search_test.dart` | **Create** | Widget tests for the integrated screen. |

---

## Task 1: Add ARB keys (English template + Spanish)

**Files:**
- Modify: `movile_app/lib/l10n/app_en.arb`
- Modify: `movile_app/lib/l10n/app_es.arb`

- [ ] **Step 1: Add keys to `app_en.arb`**

Insert immediately after the existing `historyRenameRouteLabel` entry (search for `"historyRenameRouteLabel"` to locate it):

```json
  "historySearchHint": "Search…",
  "historyFiltersTitle": "Filters",
  "historyFiltersOpen": "Open filters",
  "historyFiltersApply": "Apply",
  "historyFiltersClear": "Clear",
  "historyFilterKindLabel": "Type",
  "historyFilterKindSession": "Session",
  "historyFilterKindFreeRide": "Free ride",
  "historyFilterVehicleLabel": "Vehicle",
  "historyNoVehicle": "No vehicle",
  "historyFilterDateRangeLabel": "Date range",
  "historyDateLast7Days": "Last 7 days",
  "historyDateLast30Days": "Last 30 days",
  "historyDateThisYear": "This year",
  "historyDateCustom": "Custom…",
  "historyFilterMinMaxSpeedLabel": "Min max speed",
  "historyFilterMinDistanceLabel": "Min distance",
  "historyFilterMinSpeedChip": "≥ {value}",
  "@historyFilterMinSpeedChip": { "placeholders": { "value": { "type": "String" } } },
  "historyFilterMinDistanceChip": "≥ {value}",
  "@historyFilterMinDistanceChip": { "placeholders": { "value": { "type": "String" } } },
  "historyFilterVehicleChipMany": "Vehicles ({count})",
  "@historyFilterVehicleChipMany": { "placeholders": { "count": { "type": "int" } } },
  "historyFilteredEmptyTitle": "No matches",
  "historyFilteredEmptyAction": "Clear filters",
```

- [ ] **Step 2: Add keys to `app_es.arb`**

Insert in the same spot in `app_es.arb` (after `historyRenameRouteLabel`):

```json
  "historySearchHint": "Buscar…",
  "historyFiltersTitle": "Filtros",
  "historyFiltersOpen": "Abrir filtros",
  "historyFiltersApply": "Aplicar",
  "historyFiltersClear": "Limpiar",
  "historyFilterKindLabel": "Tipo",
  "historyFilterKindSession": "Sesión",
  "historyFilterKindFreeRide": "Free ride",
  "historyFilterVehicleLabel": "Vehículo",
  "historyNoVehicle": "Sin vehículo",
  "historyFilterDateRangeLabel": "Rango de fechas",
  "historyDateLast7Days": "Últimos 7 días",
  "historyDateLast30Days": "Últimos 30 días",
  "historyDateThisYear": "Este año",
  "historyDateCustom": "Personalizado…",
  "historyFilterMinMaxSpeedLabel": "Velocidad máx. mínima",
  "historyFilterMinDistanceLabel": "Distancia mínima",
  "historyFilterMinSpeedChip": "≥ {value}",
  "@historyFilterMinSpeedChip": { "placeholders": { "value": { "type": "String" } } },
  "historyFilterMinDistanceChip": "≥ {value}",
  "@historyFilterMinDistanceChip": { "placeholders": { "value": { "type": "String" } } },
  "historyFilterVehicleChipMany": "Vehículos ({count})",
  "@historyFilterVehicleChipMany": { "placeholders": { "count": { "type": "int" } } },
  "historyFilteredEmptyTitle": "Sin resultados",
  "historyFilteredEmptyAction": "Limpiar filtros",
```

- [ ] **Step 3: Regenerate the localization Dart files**

Run from the `movile_app` directory:

```bash
flutter gen-l10n
```

Expected: no warnings; `app_localizations.dart`, `app_localizations_en.dart`, and `app_localizations_es.dart` are updated with new getter signatures (`String get historySearchHint`, etc.).

- [ ] **Step 4: Verify the project still compiles**

Run:

```bash
flutter analyze
```

Expected: no new errors.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/l10n
git commit -m "feat(history): add search and filter localization keys"
```

---

## Task 2: Create the pure filter module with unit tests (TDD)

**Files:**
- Create: `movile_app/lib/src/features/history/history_filters.dart`
- Create: `movile_app/test/features/history/history_filters_test.dart`

- [ ] **Step 1: Write failing tests for `HistoryFilters.isEmpty` and `activeCount`**

Create `movile_app/test/features/history/history_filters_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/src/features/history/history_filters.dart';
import 'package:splitway_mobile/src/services/speed/speed_metric.dart';
import 'package:splitway_mobile/src/services/speed/speed_session.dart';

SessionRun _session({
  String id = 's',
  String routeId = 'r',
  String? vehicleId,
  DateTime? startedAt,
  double maxMps = 30,
  double distanceMeters = 5000,
}) =>
    SessionRun(
      id: id,
      routeTemplateId: routeId,
      vehicleId: vehicleId,
      startedAt: startedAt ?? DateTime(2026, 5, 1, 12),
      laps: const [],
      sectorSummaries: const [],
      points: const [],
      maxSpeedMps: maxMps,
      avgSpeedMps: maxMps * 0.6,
      totalDistanceMeters: distanceMeters,
    );

FreeRideRun _ride({
  String id = 'f',
  String? name,
  String? vehicleId,
  DateTime? startedAt,
  double maxMps = 25,
  double distanceMeters = 8000,
}) =>
    FreeRideRun(
      id: id,
      name: name,
      vehicleId: vehicleId,
      startedAt: startedAt ?? DateTime(2026, 5, 2, 10),
      points: const [],
      maxSpeedMps: maxMps,
      avgSpeedMps: maxMps * 0.5,
      totalDistanceMeters: distanceMeters,
      elevationRangeMeters: null,
    );

SpeedSession _speed({
  String id = 'sp',
  String name = 'Test',
  String? vehicleId,
  DateTime? startedAt,
  double topKmh = 120,
}) =>
    SpeedSession(
      id: id,
      userId: 'u',
      vehicleId: vehicleId,
      name: name,
      selectedMetrics: {SpeedMetric.topSpeed},
      results: {SpeedMetric.topSpeed: topKmh},
      countdownSeconds: 0,
      isPartial: false,
      startedAt: startedAt ?? DateTime(2026, 5, 3, 9),
      finishedAt: null,
      createdAt: DateTime(2026, 5, 3),
      updatedAt: DateTime(2026, 5, 3),
    );

void main() {
  group('HistoryFilters value', () {
    test('default is empty', () {
      const f = HistoryFilters();
      expect(f.isEmpty, isTrue);
      expect(f.activeCount, 0);
    });

    test('activeCount counts structured filters only, not query', () {
      final f = HistoryFilters(
        query: 'jarama',
        kinds: const {HistoryEntryKind.session},
        vehicleIds: const {'v1'},
        dateRange: DateTimeRange(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 2, 1),
        ),
        minMaxSpeedMps: 30,
        minDistanceMeters: 5000,
      );
      expect(f.isEmpty, isFalse);
      expect(f.activeCount, 5);
    });

    test('copyWith preserves untouched fields and updates given ones', () {
      const a = HistoryFilters(query: 'a');
      final b = a.copyWith(minMaxSpeedMps: 10);
      expect(b.query, 'a');
      expect(b.minMaxSpeedMps, 10);
    });

    test('clear returns empty filters', () {
      const a = HistoryFilters(query: 'x', minDistanceMeters: 5);
      expect(a.clear().isEmpty, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/features/history/history_filters_test.dart
```

Expected: compilation error — `history_filters.dart` does not exist.

- [ ] **Step 3: Create `history_filters.dart` with the model and the entry hierarchy**

Create `movile_app/lib/src/features/history/history_filters.dart`:

```dart
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:splitway_core/splitway_core.dart';

import '../../services/speed/speed_metric.dart';
import '../../services/speed/speed_session.dart';

/// Discriminator used by the type filter in the bottom sheet.
enum HistoryEntryKind { session, freeRide }

/// History list adapter that unifies sessions and free rides under a single
/// time-sortable view. Lives here (instead of in [HistoryScreen]) so the
/// filter module can be unit tested without pulling in the screen.
sealed class HistoryEntry implements Comparable<HistoryEntry> {
  DateTime get date;
  String? get vehicleId;
  double get maxSpeedMps;
  double get totalDistanceMeters;
  HistoryEntryKind get kind;

  @override
  int compareTo(HistoryEntry other) => other.date.compareTo(date);
}

class SessionEntry extends HistoryEntry {
  SessionEntry(this.session);
  final SessionRun session;

  @override
  DateTime get date => session.startedAt;
  @override
  String? get vehicleId => session.vehicleId;
  @override
  double get maxSpeedMps => session.maxSpeedMps;
  @override
  double get totalDistanceMeters => session.totalDistanceMeters;
  @override
  HistoryEntryKind get kind => HistoryEntryKind.session;
}

class FreeRideEntry extends HistoryEntry {
  FreeRideEntry(this.ride);
  final FreeRideRun ride;

  @override
  DateTime get date => ride.startedAt;
  @override
  String? get vehicleId => ride.vehicleId;
  @override
  double get maxSpeedMps => ride.maxSpeedMps;
  @override
  double get totalDistanceMeters => ride.totalDistanceMeters;
  @override
  HistoryEntryKind get kind => HistoryEntryKind.freeRide;
}

/// Immutable filter state used by the History screen.
class HistoryFilters {
  const HistoryFilters({
    this.query = '',
    this.kinds = const <HistoryEntryKind>{},
    this.vehicleIds = const <String?>{},
    this.dateRange,
    this.minMaxSpeedMps,
    this.minDistanceMeters,
  });

  final String query;
  final Set<HistoryEntryKind> kinds;
  final Set<String?> vehicleIds; // null sentinel = "Sin vehículo"
  final DateTimeRange? dateRange;
  final double? minMaxSpeedMps;
  final double? minDistanceMeters;

  bool get isEmpty =>
      query.isEmpty &&
      kinds.isEmpty &&
      vehicleIds.isEmpty &&
      dateRange == null &&
      minMaxSpeedMps == null &&
      minDistanceMeters == null;

  bool get hasStructuredFilter =>
      kinds.isNotEmpty ||
      vehicleIds.isNotEmpty ||
      dateRange != null ||
      minMaxSpeedMps != null ||
      minDistanceMeters != null;

  /// Number of structured (non-query) filters that are active. Used for the
  /// badge on the filters icon button.
  int get activeCount =>
      (kinds.isNotEmpty ? 1 : 0) +
      (vehicleIds.isNotEmpty ? 1 : 0) +
      (dateRange != null ? 1 : 0) +
      (minMaxSpeedMps != null ? 1 : 0) +
      (minDistanceMeters != null ? 1 : 0);

  HistoryFilters copyWith({
    String? query,
    Set<HistoryEntryKind>? kinds,
    Set<String?>? vehicleIds,
    Object? dateRange = _sentinel,
    Object? minMaxSpeedMps = _sentinel,
    Object? minDistanceMeters = _sentinel,
  }) {
    return HistoryFilters(
      query: query ?? this.query,
      kinds: kinds ?? this.kinds,
      vehicleIds: vehicleIds ?? this.vehicleIds,
      dateRange: identical(dateRange, _sentinel)
          ? this.dateRange
          : dateRange as DateTimeRange?,
      minMaxSpeedMps: identical(minMaxSpeedMps, _sentinel)
          ? this.minMaxSpeedMps
          : minMaxSpeedMps as double?,
      minDistanceMeters: identical(minDistanceMeters, _sentinel)
          ? this.minDistanceMeters
          : minDistanceMeters as double?,
    );
  }

  HistoryFilters clear() => const HistoryFilters();

  static const _sentinel = Object();
}

/// Diacritic-insensitive, lowercase substring match.
bool _matchesQuery(String haystack, String query) {
  if (query.isEmpty) return true;
  return _fold(haystack).contains(_fold(query));
}

String _fold(String s) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
  const to   = 'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC';
  final buf = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  return buf.toString().toLowerCase();
}

DateTime _endOfDay(DateTime d) =>
    DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

/// Applies [filters] to the Todo-tab list. [routeName] resolves the route id
/// for [SessionEntry] (the entry doesn't carry the name).
List<HistoryEntry> applyHistoryFilters(
  List<HistoryEntry> src,
  HistoryFilters filters,
  String Function(String routeId) routeName,
  String freeRideFallbackName,
) {
  if (filters.isEmpty) return src;
  return src.where((e) {
    if (filters.kinds.isNotEmpty && !filters.kinds.contains(e.kind)) {
      return false;
    }
    if (filters.vehicleIds.isNotEmpty &&
        !filters.vehicleIds.contains(e.vehicleId)) {
      return false;
    }
    if (filters.dateRange != null) {
      final start = filters.dateRange!.start;
      final end = _endOfDay(filters.dateRange!.end);
      if (e.date.isBefore(start) || e.date.isAfter(end)) return false;
    }
    if (filters.minMaxSpeedMps != null &&
        e.maxSpeedMps < filters.minMaxSpeedMps!) {
      return false;
    }
    if (filters.minDistanceMeters != null &&
        e.totalDistanceMeters < filters.minDistanceMeters!) {
      return false;
    }
    if (filters.query.isNotEmpty) {
      final name = switch (e) {
        SessionEntry(:final session) => routeName(session.routeTemplateId),
        FreeRideEntry(:final ride) => ride.name ?? freeRideFallbackName,
      };
      if (!_matchesQuery(name, filters.query)) return false;
    }
    return true;
  }).toList();
}

/// Applies the relevant subset of [filters] to the Velocidad-tab list. The
/// `kinds` and `minDistanceMeters` filters are ignored here because they
/// don't apply to speed sessions.
List<SpeedSession> applySpeedFilters(
  List<SpeedSession> src,
  HistoryFilters filters,
) {
  if (filters.isEmpty) return src;
  return src.where((s) {
    if (filters.vehicleIds.isNotEmpty &&
        !filters.vehicleIds.contains(s.vehicleId)) {
      return false;
    }
    if (filters.dateRange != null) {
      final start = filters.dateRange!.start;
      final end = _endOfDay(filters.dateRange!.end);
      if (s.startedAt.isBefore(start) || s.startedAt.isAfter(end)) {
        return false;
      }
    }
    if (filters.minMaxSpeedMps != null) {
      final topKmh = s.results[SpeedMetric.topSpeed];
      if (topKmh == null) return false;
      final topMps = topKmh / 3.6;
      if (topMps < filters.minMaxSpeedMps!) return false;
    }
    if (filters.query.isNotEmpty &&
        !_matchesQuery(s.name, filters.query)) {
      return false;
    }
    return true;
  }).toList();
}
```

- [ ] **Step 4: Run tests to verify the first group passes**

```bash
flutter test test/features/history/history_filters_test.dart
```

Expected: all 4 tests in the `HistoryFilters value` group pass.

- [ ] **Step 5: Write failing tests for `applyHistoryFilters`**

Append to the test file's `main()`:

```dart
  group('applyHistoryFilters', () {
    String routeName(String id) => id == 'r1' ? 'Jarama Norte' : 'Otra Ruta';

    test('empty filters returns original list', () {
      final entries = <HistoryEntry>[SessionEntry(_session())];
      final out = applyHistoryFilters(
          entries, const HistoryFilters(), routeName, 'Recorrido libre');
      expect(out, entries);
    });

    test('query matches route name (diacritics + case insensitive)', () {
      final entries = <HistoryEntry>[
        SessionEntry(_session(id: 'a', routeId: 'r1')),
        SessionEntry(_session(id: 'b', routeId: 'r2')),
      ];
      final out = applyHistoryFilters(
        entries,
        const HistoryFilters(query: 'JARÁMA'),
        routeName,
        'Recorrido libre',
      );
      expect(out.length, 1);
      expect((out.first as SessionEntry).session.id, 'a');
    });

    test('query matches free-ride name, falling back when null', () {
      final entries = <HistoryEntry>[
        FreeRideEntry(_ride(id: 'f1', name: 'Mountain loop')),
        FreeRideEntry(_ride(id: 'f2', name: null)),
      ];
      final fallback = 'Recorrido libre';
      final out = applyHistoryFilters(
        entries,
        const HistoryFilters(query: 'recorrido'),
        routeName,
        fallback,
      );
      expect(out.length, 1);
      expect((out.first as FreeRideEntry).ride.id, 'f2');
    });

    test('kind filter restricts to selected kinds', () {
      final entries = <HistoryEntry>[
        SessionEntry(_session()),
        FreeRideEntry(_ride()),
      ];
      final out = applyHistoryFilters(
        entries,
        const HistoryFilters(kinds: {HistoryEntryKind.freeRide}),
        routeName,
        'Recorrido libre',
      );
      expect(out.length, 1);
      expect(out.first, isA<FreeRideEntry>());
    });

    test('vehicle filter; null sentinel matches entries without vehicle', () {
      final entries = <HistoryEntry>[
        SessionEntry(_session(id: 'a', vehicleId: 'v1')),
        SessionEntry(_session(id: 'b', vehicleId: null)),
        SessionEntry(_session(id: 'c', vehicleId: 'v2')),
      ];
      final out = applyHistoryFilters(
        entries,
        const HistoryFilters(vehicleIds: {null, 'v1'}),
        routeName,
        'Recorrido libre',
      );
      expect(out.map((e) => (e as SessionEntry).session.id), ['a', 'b']);
    });

    test('date range filter inclusive end-of-day', () {
      final entries = <HistoryEntry>[
        SessionEntry(_session(id: 'a',
            startedAt: DateTime(2026, 5, 1, 23, 30))),
        SessionEntry(_session(id: 'b',
            startedAt: DateTime(2026, 5, 2, 1, 0))),
      ];
      final range = DateTimeRange(
        start: DateTime(2026, 5, 1),
        end: DateTime(2026, 5, 1),
      );
      final out = applyHistoryFilters(
        entries,
        HistoryFilters(dateRange: range),
        routeName,
        'Recorrido libre',
      );
      expect(out.length, 1);
      expect((out.first as SessionEntry).session.id, 'a');
    });

    test('min max-speed excludes slower entries', () {
      final entries = <HistoryEntry>[
        SessionEntry(_session(id: 'a', maxMps: 20)),
        SessionEntry(_session(id: 'b', maxMps: 40)),
      ];
      final out = applyHistoryFilters(
        entries,
        const HistoryFilters(minMaxSpeedMps: 30),
        routeName,
        'Recorrido libre',
      );
      expect(out.length, 1);
      expect((out.first as SessionEntry).session.id, 'b');
    });

    test('min distance excludes shorter entries', () {
      final entries = <HistoryEntry>[
        SessionEntry(_session(id: 'a', distanceMeters: 1000)),
        SessionEntry(_session(id: 'b', distanceMeters: 10000)),
      ];
      final out = applyHistoryFilters(
        entries,
        const HistoryFilters(minDistanceMeters: 5000),
        routeName,
        'Recorrido libre',
      );
      expect(out.length, 1);
      expect((out.first as SessionEntry).session.id, 'b');
    });
  });

  group('applySpeedFilters', () {
    test('vehicle and min max-speed apply correctly (km/h → m/s)', () {
      final sessions = [
        _speed(id: 's1', vehicleId: 'v1', topKmh: 100),
        _speed(id: 's2', vehicleId: 'v2', topKmh: 200),
        _speed(id: 's3', vehicleId: 'v1', topKmh: 150),
      ];
      // 130 km/h = 36.11 m/s
      final out = applySpeedFilters(
        sessions,
        const HistoryFilters(
          vehicleIds: {'v1'},
          minMaxSpeedMps: 36.1,
        ),
      );
      expect(out.map((s) => s.id), ['s3']);
    });

    test('query matches speed-session name (diacritics insensitive)', () {
      final sessions = [
        _speed(id: 's1', name: 'Túnel de viento'),
        _speed(id: 's2', name: 'Otra'),
      ];
      final out = applySpeedFilters(
        sessions,
        const HistoryFilters(query: 'tunel'),
      );
      expect(out.length, 1);
      expect(out.first.id, 's1');
    });
  });
```

- [ ] **Step 6: Run tests; expect new tests to fail (or compile-error on missing exports)**

```bash
flutter test test/features/history/history_filters_test.dart
```

Expected: failing tests in the new groups.

- [ ] **Step 7: Confirm tests now pass**

The implementation in Step 3 already covers everything. Re-run:

```bash
flutter test test/features/history/history_filters_test.dart
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add movile_app/lib/src/features/history/history_filters.dart \
        movile_app/test/features/history/history_filters_test.dart
git commit -m "feat(history): pure filter module with unit tests"
```

---

## Task 3: Wire `history_screen.dart` to the new entry types

This is a refactor-only step: replace the local private `_HistoryEntry` hierarchy with the public one. No behavior change.

**Files:**
- Modify: `movile_app/lib/src/features/history/history_screen.dart`

- [ ] **Step 1: Update imports**

In `history_screen.dart`, add near the existing imports (alongside the other relative imports):

```dart
import 'history_filters.dart';
```

- [ ] **Step 2: Remove the private sealed hierarchy**

Delete lines 26–47 (the `_HistoryEntry`, `_SessionEntry`, `_FreeRideEntry` definitions).

- [ ] **Step 3: Replace usages**

Search-and-replace within this file only:

- `_HistoryEntry` → `HistoryEntry`
- `_SessionEntry` → `SessionEntry`
- `_FreeRideEntry` → `FreeRideEntry`

Also leave the existing `enum _HistoryFilter { all, speed }` as is — this is the unrelated tab discriminator.

- [ ] **Step 4: Run analyzer + existing widget test**

```bash
flutter analyze
flutter test test/features/history/history_screen_l10n_test.dart
```

Expected: no errors; the existing empty-state test still passes (no UI change).

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/history/history_screen.dart
git commit -m "refactor(history): share HistoryEntry hierarchy across screen and filters"
```

---

## Task 4: Add search bar and filter button row (text-only filtering)

This task delivers a working search bar that filters by text in both tabs. The filter button is wired but the bottom sheet comes in Task 5.

**Files:**
- Modify: `movile_app/lib/src/features/history/history_screen.dart`
- Create: `movile_app/test/features/history/history_screen_search_test.dart`

- [ ] **Step 1: Write failing widget test for search**

Create `movile_app/test/features/history/history_screen_search_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/features/history/history_screen.dart';
import 'package:splitway_mobile/src/services/locale/locale_controller.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

Widget _harness({required Locale locale, required Widget child}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

int _dbCounter = 0;

Future<({SplitwayLocalDatabase db, LocalDraftRepository repo})>
    _openRepo() async {
  _dbCounter += 1;
  final db = await SplitwayLocalDatabase.open(
    overridePath: 'file:history_search_test_$_dbCounter?mode=memory&cache=shared',
  );
  return (db: db, repo: LocalDraftRepository(db));
}

Future<void> _seed(LocalDraftRepository repo) async {
  await repo.saveRouteTemplate(RouteTemplate(
    id: 'r-jarama',
    name: 'Jarama Norte',
    sectors: const [],
    startFinishGate: GateDefinition.zero,
    createdAt: DateTime(2026, 5, 1),
    updatedAt: DateTime(2026, 5, 1),
  ));
  await repo.saveRouteTemplate(RouteTemplate(
    id: 'r-other',
    name: 'Circuito Levante',
    sectors: const [],
    startFinishGate: GateDefinition.zero,
    createdAt: DateTime(2026, 5, 1),
    updatedAt: DateTime(2026, 5, 1),
  ));
  await repo.saveSession(SessionRun(
    id: 's1',
    routeTemplateId: 'r-jarama',
    vehicleId: null,
    startedAt: DateTime(2026, 5, 10),
    laps: const [],
    sectorSummaries: const [],
    points: const [],
    maxSpeedMps: 30,
    avgSpeedMps: 20,
    totalDistanceMeters: 4000,
  ));
  await repo.saveSession(SessionRun(
    id: 's2',
    routeTemplateId: 'r-other',
    vehicleId: null,
    startedAt: DateTime(2026, 5, 11),
    laps: const [],
    sectorSummaries: const [],
    points: const [],
    maxSpeedMps: 30,
    avgSpeedMps: 20,
    totalDistanceMeters: 4000,
  ));
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('typing in search filters list by route name', (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _openRepo();
      await _seed(boot.repo);
      settings = await AppSettingsController.load();
    });
    await tester.pumpWidget(_harness(
      locale: const Locale('es'),
      child: HistoryScreen(
        repository: boot.repo,
        settingsController: settings,
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
    }

    expect(find.text('Jarama Norte'), findsOneWidget);
    expect(find.text('Circuito Levante'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'jarama');
    // debounce + pump
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('Jarama Norte'), findsOneWidget);
    expect(find.text('Circuito Levante'), findsNothing);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });
}
```

- [ ] **Step 2: Run the test; expect failure**

```bash
flutter test test/features/history/history_screen_search_test.dart
```

Expected: fails at `find.byType(TextField)` (there is no search field yet).

- [ ] **Step 3: Add filter state to `_HistoryScreenState`**

Inside `_HistoryScreenState` (right after the existing field declarations such as `bool _speedLoading = false;`), add:

```dart
  HistoryFilters _filters = const HistoryFilters();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _fullyLoaded = false;
```

Add to `dispose()` before `super.dispose()`:

```dart
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
```

- [ ] **Step 4: Add the search bar widget and rebuild the `body` Column**

Replace the existing `body: Column(...)` block in `build()` with:

```dart
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: l.historySearchHint,
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixIcon: _searchCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: _clearSearch,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      IconButton(
                        tooltip: l.historyFiltersOpen,
                        icon: const Icon(Icons.tune),
                        onPressed: _openFiltersSheet,
                      ),
                      if (_filters.activeCount > 0)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_filters.activeCount}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
```

- [ ] **Step 5: Add the search handlers and a `routeName` resolver inside `_HistoryScreenState`**

Add anywhere in `_HistoryScreenState`:

```dart
  void _onSearchChanged(String value) {
    setState(() {}); // refresh suffix icon
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _filters = _filters.copyWith(query: value);
      });
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    _searchDebounce?.cancel();
    setState(() {
      _filters = _filters.copyWith(query: '');
    });
  }

  Future<void> _openFiltersSheet() async {
    // Bottom sheet lands in Task 5.
  }

  String _routeName(String id) =>
      _routes[id]?.name ?? AppLocalizations.of(context).historyDeletedRoute;
```

- [ ] **Step 6: Apply filters when building lists**

Replace the body of `_buildMainList(l)` so the filtered entries are used:

```dart
  Widget _buildMainList(AppLocalizations l) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final filtered = applyHistoryFilters(
      _entries,
      _filters,
      _routeName,
      l.historyFreeRideLabel,
    );

    if (filtered.isEmpty) {
      if (!_filters.isEmpty) {
        return EmptyState(
          icon: Icons.search_off,
          title: l.historyFilteredEmptyTitle,
          message: '',
          actionLabel: l.historyFilteredEmptyAction,
          onAction: _clearAllFilters,
        );
      }
      return EmptyState(
        icon: Icons.history_toggle_off,
        title: l.historyNoEntriesTitle,
        message: l.historyNoEntriesMessage,
      );
    }

    final showSentinel = _hasMore && _filters.isEmpty;
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: filtered.length + (showSentinel ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, index) {
        if (index >= filtered.length) {
          _load();
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final entry = filtered[index];
        return switch (entry) {
          SessionEntry(:final session) => _SessionTile(
              session: session,
              route: _routes[session.routeTemplateId],
              repository: widget.repository,
              config: widget.config,
              garageService: widget.garageService,
              settingsController: widget.settingsController,
            ),
          FreeRideEntry(:final ride) => _FreeRideTile(
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
```

Similarly, update `_buildSpeedList`:

```dart
  Widget _buildSpeedList(AppLocalizations l) {
    if (_speedLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final filtered = applySpeedFilters(_speedSessions, _filters);
    if (filtered.isEmpty) {
      if (!_filters.isEmpty) {
        return EmptyState(
          icon: Icons.search_off,
          title: l.historyFilteredEmptyTitle,
          message: '',
          actionLabel: l.historyFilteredEmptyAction,
          onAction: _clearAllFilters,
        );
      }
      return Center(child: Text(l.speedHistoryEmpty));
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
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.speed_outlined)),
          title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(dateLabel),
          trailing: top == null
              ? null
              : Text(
                  '${top.round()} km/h',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
          onTap: () => context.push('/history/speed/${s.id}'),
        );
      },
    );
  }
```

- [ ] **Step 7: Add `_clearAllFilters` and verify `EmptyState` supports an action**

Add to `_HistoryScreenState`:

```dart
  void _clearAllFilters() {
    _searchCtrl.clear();
    _searchDebounce?.cancel();
    setState(() {
      _filters = const HistoryFilters();
    });
  }
```

Check `movile_app/lib/src/shared/widgets/empty_state.dart` — if `EmptyState` does **not** yet accept `actionLabel`/`onAction` parameters, extend it minimally. Open the file first and confirm. If parameters need adding:

```dart
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message = '',
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  // ... in build(), after the existing message Text:
  //   if (actionLabel != null && onAction != null) ...[
  //     const SizedBox(height: 16),
  //     FilledButton(onPressed: onAction, child: Text(actionLabel!)),
  //   ],
}
```

Only add what's missing; don't restructure the widget.

- [ ] **Step 8: Run the search test**

```bash
flutter test test/features/history/history_screen_search_test.dart
```

Expected: passes.

- [ ] **Step 9: Run all existing history tests + analyze**

```bash
flutter analyze
flutter test test/features/history/
```

Expected: all tests pass, no analyzer errors.

- [ ] **Step 10: Commit**

```bash
git add movile_app/lib/src/features/history/history_screen.dart \
        movile_app/lib/src/shared/widgets/empty_state.dart \
        movile_app/test/features/history/history_screen_search_test.dart
git commit -m "feat(history): add search bar and filtered empty state"
```

---

## Task 5: Implement the filters bottom sheet

**Files:**
- Modify: `movile_app/lib/src/features/history/history_screen.dart`
- Modify: `movile_app/test/features/history/history_screen_search_test.dart`

- [ ] **Step 1: Write failing widget test for applying a vehicle filter**

Append to the test file:

```dart
  testWidgets('applying vehicle filter via sheet narrows the list',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;
    late GarageService garage;
    await tester.runAsync(() async {
      boot = await _openRepo();
      // Two routes, two sessions on different vehicles, one route name only.
      await boot.repo.saveRouteTemplate(RouteTemplate(
        id: 'r1',
        name: 'Ruta A',
        sectors: const [],
        startFinishGate: GateDefinition.zero,
        createdAt: DateTime(2026, 5, 1),
        updatedAt: DateTime(2026, 5, 1),
      ));
      await boot.repo.saveSession(SessionRun(
        id: 'sA',
        routeTemplateId: 'r1',
        vehicleId: 'veh-1',
        startedAt: DateTime(2026, 5, 10),
        laps: const [], sectorSummaries: const [], points: const [],
        maxSpeedMps: 30, avgSpeedMps: 20, totalDistanceMeters: 4000,
      ));
      await boot.repo.saveSession(SessionRun(
        id: 'sB',
        routeTemplateId: 'r1',
        vehicleId: 'veh-2',
        startedAt: DateTime(2026, 5, 11),
        laps: const [], sectorSummaries: const [], points: const [],
        maxSpeedMps: 30, avgSpeedMps: 20, totalDistanceMeters: 4000,
      ));
      settings = await AppSettingsController.load();
      garage = GarageService(repository: boot.repo)
        ..addVehicleForTest(Vehicle.testFixture(id: 'veh-1', name: 'Coche A'))
        ..addVehicleForTest(Vehicle.testFixture(id: 'veh-2', name: 'Coche B'));
    });
    await tester.pumpWidget(_harness(
      locale: const Locale('es'),
      child: HistoryScreen(
        repository: boot.repo,
        settingsController: settings,
        garageService: garage,
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
    }

    // Two tiles initially.
    expect(find.text('Ruta A'), findsNWidgets(2));

    // Open sheet.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    // Tap "Coche A" chip then Apply.
    await tester.tap(find.widgetWithText(FilterChip, 'Coche A'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pumpAndSettle();

    expect(find.text('Ruta A'), findsOneWidget);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });
```

> **Note:** If `GarageService.addVehicleForTest` or `Vehicle.testFixture` do not exist, add minimal test helpers in the corresponding source files (mark them `@visibleForTesting`). Inspect `garage_service.dart` and `vehicle.dart` and add only what's missing — do not rework them. If easier, instantiate `Vehicle` directly using its constructor with the required fields.

- [ ] **Step 2: Run; expect failure**

```bash
flutter test test/features/history/history_screen_search_test.dart -p vm
```

Expected: fails — `find.byIcon(Icons.tune)` is found but the sheet doesn't open / `FilterChip` not found.

- [ ] **Step 3: Implement `_openFiltersSheet`**

Replace the placeholder `_openFiltersSheet` body inside `_HistoryScreenState`:

```dart
  Future<void> _openFiltersSheet() async {
    final l = AppLocalizations.of(context);
    final unit = widget.settingsController.unitSystem;
    final vehicles = widget.garageService?.vehicles ?? const <Vehicle>[];

    final result = await showModalBottomSheet<HistoryFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetCtx) => _HistoryFiltersSheet(
        initial: _filters,
        vehicles: vehicles,
        unitSystem: unit,
        showKindSection: _filter == _HistoryFilter.all,
        showDistanceSection: _filter == _HistoryFilter.all,
        l: l,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _filters = result.copyWith(query: _filters.query);
    });
  }
```

- [ ] **Step 4: Add the `_HistoryFiltersSheet` widget at the bottom of `history_screen.dart`**

```dart
class _HistoryFiltersSheet extends StatefulWidget {
  const _HistoryFiltersSheet({
    required this.initial,
    required this.vehicles,
    required this.unitSystem,
    required this.showKindSection,
    required this.showDistanceSection,
    required this.l,
  });

  final HistoryFilters initial;
  final List<Vehicle> vehicles;
  final UnitSystem unitSystem;
  final bool showKindSection;
  final bool showDistanceSection;
  final AppLocalizations l;

  @override
  State<_HistoryFiltersSheet> createState() => _HistoryFiltersSheetState();
}

class _HistoryFiltersSheetState extends State<_HistoryFiltersSheet> {
  late HistoryFilters _draft = widget.initial;
  late final TextEditingController _speedCtrl;
  late final TextEditingController _distanceCtrl;

  @override
  void initState() {
    super.initState();
    _speedCtrl = TextEditingController(
      text: _draft.minMaxSpeedMps == null
          ? ''
          : _formatSpeedInput(_draft.minMaxSpeedMps!, widget.unitSystem),
    );
    _distanceCtrl = TextEditingController(
      text: _draft.minDistanceMeters == null
          ? ''
          : _formatDistanceInput(_draft.minDistanceMeters!, widget.unitSystem),
    );
  }

  @override
  void dispose() {
    _speedCtrl.dispose();
    _distanceCtrl.dispose();
    super.dispose();
  }

  static String _formatSpeedInput(double mps, UnitSystem u) {
    final v = u == UnitSystem.imperial ? mps * 2.23694 : mps * 3.6;
    return v.toStringAsFixed(0);
  }

  static String _formatDistanceInput(double meters, UnitSystem u) {
    final v = u == UnitSystem.imperial
        ? meters / 1609.34
        : meters / 1000.0;
    return v.toStringAsFixed(v >= 10 ? 0 : 1);
  }

  double? _parseSpeed(String s) {
    final v = double.tryParse(s.replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return widget.unitSystem == UnitSystem.imperial ? v / 2.23694 : v / 3.6;
  }

  double? _parseDistance(String s) {
    final v = double.tryParse(s.replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return widget.unitSystem == UnitSystem.imperial ? v * 1609.34 : v * 1000.0;
  }

  void _toggleKind(HistoryEntryKind k) {
    setState(() {
      final next = {..._draft.kinds};
      next.contains(k) ? next.remove(k) : next.add(k);
      _draft = _draft.copyWith(kinds: next);
    });
  }

  void _toggleVehicle(String? id) {
    setState(() {
      final next = {..._draft.vehicleIds};
      next.contains(id) ? next.remove(id) : next.add(id);
      _draft = _draft.copyWith(vehicleIds: next);
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = _draft.dateRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month - 1, now.day),
          end: now,
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
    );
    if (picked != null) {
      setState(() => _draft = _draft.copyWith(dateRange: picked));
    }
  }

  void _setPresetRange(DateTimeRange r) {
    setState(() => _draft = _draft.copyWith(dateRange: r));
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final speedSuffix = widget.unitSystem == UnitSystem.imperial ? 'mph' : 'km/h';
    final distSuffix = widget.unitSystem == UnitSystem.imperial ? 'mi' : 'km';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(l.historyFiltersTitle,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                if (widget.showKindSection) ...[
                  Text(l.historyFilterKindLabel,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: Text(l.historyFilterKindSession),
                        selected:
                            _draft.kinds.contains(HistoryEntryKind.session),
                        onSelected: (_) => _toggleKind(HistoryEntryKind.session),
                      ),
                      FilterChip(
                        label: Text(l.historyFilterKindFreeRide),
                        selected:
                            _draft.kinds.contains(HistoryEntryKind.freeRide),
                        onSelected: (_) =>
                            _toggleKind(HistoryEntryKind.freeRide),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Text(l.historyFilterVehicleLabel,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final v in widget.vehicles)
                      FilterChip(
                        label: Text(v.name),
                        selected: _draft.vehicleIds.contains(v.id),
                        onSelected: (_) => _toggleVehicle(v.id),
                      ),
                    FilterChip(
                      label: Text(l.historyNoVehicle),
                      selected: _draft.vehicleIds.contains(null),
                      onSelected: (_) => _toggleVehicle(null),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(l.historyFilterDateRangeLabel,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton(
                      onPressed: () => _setPresetRange(DateTimeRange(
                        start: today.subtract(const Duration(days: 7)),
                        end: today,
                      )),
                      child: Text(l.historyDateLast7Days),
                    ),
                    OutlinedButton(
                      onPressed: () => _setPresetRange(DateTimeRange(
                        start: today.subtract(const Duration(days: 30)),
                        end: today,
                      )),
                      child: Text(l.historyDateLast30Days),
                    ),
                    OutlinedButton(
                      onPressed: () => _setPresetRange(DateTimeRange(
                        start: DateTime(now.year, 1, 1),
                        end: today,
                      )),
                      child: Text(l.historyDateThisYear),
                    ),
                    OutlinedButton(
                      onPressed: _pickCustomRange,
                      child: Text(l.historyDateCustom),
                    ),
                  ],
                ),
                if (_draft.dateRange != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    () {
                      final r = _draft.dateRange!;
                      final fmt = DateFormat.yMd(l.localeName);
                      return '${fmt.format(r.start)} – ${fmt.format(r.end)}';
                    }(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 16),
                Text(l.historyFilterMinMaxSpeedLabel,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _speedCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    suffixText: speedSuffix,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (widget.showDistanceSection) ...[
                  const SizedBox(height: 16),
                  Text(l.historyFilterMinDistanceLabel,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _distanceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      suffixText: distSuffix,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        setState(() => _draft = const HistoryFilters());
                        _speedCtrl.clear();
                        _distanceCtrl.clear();
                      },
                      child: Text(l.historyFiltersClear),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final committed = _draft.copyWith(
                          minMaxSpeedMps: _parseSpeed(_speedCtrl.text),
                          minDistanceMeters: widget.showDistanceSection
                              ? _parseDistance(_distanceCtrl.text)
                              : _draft.minDistanceMeters,
                        );
                        Navigator.of(context).pop(committed);
                      },
                      child: Text(l.historyFiltersApply),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

No new imports needed — `TextInputType` is reachable through the existing `package:flutter/material.dart` import, and `Vehicle`, `UnitSystem`, `DateFormat` are already imported in this file.

- [ ] **Step 5: Run the new test**

```bash
flutter test test/features/history/history_screen_search_test.dart
```

Expected: passes.

- [ ] **Step 6: Run full history test suite + analyzer**

```bash
flutter analyze
flutter test test/features/history/
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add movile_app/lib/src/features/history/history_screen.dart \
        movile_app/lib/src/services/garage/ \
        movile_app/test/features/history/history_screen_search_test.dart
git commit -m "feat(history): filters bottom sheet (type, vehicle, dates, speed, distance)"
```

---

## Task 6: Active-filter chips row

**Files:**
- Modify: `movile_app/lib/src/features/history/history_screen.dart`
- Modify: `movile_app/test/features/history/history_screen_search_test.dart`

- [ ] **Step 1: Write failing test for active chip + dismiss**

Append to the test file (inside `void main()`):

```dart
  testWidgets('active filter chip can be dismissed to clear that filter',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _openRepo();
      await _seed(boot.repo);
      settings = await AppSettingsController.load();
    });
    await tester.pumpWidget(_harness(
      locale: const Locale('es'),
      child: HistoryScreen(
        repository: boot.repo,
        settingsController: settings,
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
    }

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Últimos 7 días'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pumpAndSettle();

    // Chip is visible.
    expect(find.byType(InputChip), findsOneWidget);

    // Dismiss it.
    await tester.tap(find.descendant(
      of: find.byType(InputChip),
      matching: find.byIcon(Icons.close),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNothing);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });
```

- [ ] **Step 2: Run; expect failure**

```bash
flutter test test/features/history/history_screen_search_test.dart
```

Expected: `InputChip` not found — there is no chip row yet.

- [ ] **Step 3: Insert the chips row into the build tree**

In the `body: Column` children, insert between the search row `Padding(...)` and the SegmentedButton `Padding(...)`:

```dart
            if (_filters.hasStructuredFilter)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: _buildActiveChips(l),
                ),
              ),
```

- [ ] **Step 4: Implement `_buildActiveChips`**

Add to `_HistoryScreenState`:

```dart
  List<Widget> _buildActiveChips(AppLocalizations l) {
    final chips = <Widget>[];
    Widget chip(String label, VoidCallback onDeleted) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InputChip(
            label: Text(label),
            onDeleted: onDeleted,
            deleteIcon: const Icon(Icons.close, size: 16),
          ),
        );

    if (_filters.kinds.isNotEmpty) {
      final names = _filters.kinds.map((k) => switch (k) {
            HistoryEntryKind.session => l.historyFilterKindSession,
            HistoryEntryKind.freeRide => l.historyFilterKindFreeRide,
          });
      chips.add(chip(names.join(', '), () {
        setState(() => _filters = _filters.copyWith(kinds: const {}));
      }));
    }
    // Drop ids for vehicles that no longer exist; matches the spec's
    // "silently dropped" rule for deleted vehicles.
    final knownIds = (widget.garageService?.vehicles ?? const <Vehicle>[])
        .map((v) => v.id)
        .toSet();
    final liveVehicleIds = _filters.vehicleIds
        .where((id) => id == null || knownIds.contains(id))
        .toSet();
    if (liveVehicleIds.isNotEmpty) {
      final n = liveVehicleIds.length;
      String label;
      if (n == 1) {
        final id = liveVehicleIds.first;
        label = id == null
            ? l.historyNoVehicle
            : widget.garageService!.vehicles
                .firstWhere((v) => v.id == id)
                .name;
      } else {
        label = l.historyFilterVehicleChipMany(n);
      }
      chips.add(chip(label, () {
        setState(() => _filters = _filters.copyWith(vehicleIds: const {}));
      }));
    }
    if (_filters.dateRange != null) {
      final r = _filters.dateRange!;
      final fmt = DateFormat.MMMd(l.localeName);
      chips.add(chip('${fmt.format(r.start)} – ${fmt.format(r.end)}', () {
        setState(() => _filters = _filters.copyWith(dateRange: null));
      }));
    }
    if (_filters.minMaxSpeedMps != null) {
      final unit = widget.settingsController.unitSystem;
      final v = unit == UnitSystem.imperial
          ? _filters.minMaxSpeedMps! * 2.23694
          : _filters.minMaxSpeedMps! * 3.6;
      final suffix = unit == UnitSystem.imperial ? 'mph' : 'km/h';
      chips.add(chip(
        l.historyFilterMinSpeedChip('${v.toStringAsFixed(0)} $suffix'),
        () => setState(
            () => _filters = _filters.copyWith(minMaxSpeedMps: null)),
      ));
    }
    if (_filters.minDistanceMeters != null) {
      final unit = widget.settingsController.unitSystem;
      final (v, large) = Formatters.distanceMeters(
        _filters.minDistanceMeters!,
        unit: unit,
      );
      final suffix = unit == UnitSystem.imperial
          ? (large ? 'mi' : 'ft')
          : (large ? 'km' : 'm');
      chips.add(chip(
        l.historyFilterMinDistanceChip(
            '${v.toStringAsFixed(v >= 10 ? 0 : 1)} $suffix'),
        () => setState(
            () => _filters = _filters.copyWith(minDistanceMeters: null)),
      ));
    }
    return chips;
  }
```

- [ ] **Step 5: Run the new test**

```bash
flutter test test/features/history/history_screen_search_test.dart
```

Expected: passes.

- [ ] **Step 6: Commit**

```bash
git add movile_app/lib/src/features/history/history_screen.dart \
        movile_app/test/features/history/history_screen_search_test.dart
git commit -m "feat(history): active filter chips with quick-dismiss"
```

---

## Task 7: Switch to full load when filters are active; restore pagination on clear

**Files:**
- Modify: `movile_app/lib/src/features/history/history_screen.dart`

- [ ] **Step 1: Update `_load()` to honor `_fullyLoaded` and the active-filter signal**

Replace the existing `_load()` body with:

```dart
  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = _entries.isEmpty);

    final useFull = _fullyLoaded || _filters.hasStructuredFilter ||
        _filters.query.isNotEmpty;
    final pageLimit = useFull ? 1000 : _pageSize;
    final sessionOffset = useFull ? 0 : _sessionOffset;
    final freeRideOffset = useFull ? 0 : _freeRideOffset;

    final sessions = await widget.repository.getAllSessions(
      limit: pageLimit,
      offset: sessionOffset,
    );
    final freeRides = await widget.repository.getAllFreeRides(
      limit: pageLimit,
      offset: freeRideOffset,
    );
    final routeList = await widget.repository.getAllRoutes();
    if (!mounted) return;

    final newEntries = <HistoryEntry>[
      ...sessions.map(SessionEntry.new),
      ...freeRides.map(FreeRideEntry.new),
    ]..sort();

    setState(() {
      if (useFull) {
        _entries = newEntries;
        _sessionOffset = sessions.length;
        _freeRideOffset = freeRides.length;
        _hasMore = false;
        _fullyLoaded = true;
      } else {
        if (_sessionOffset == 0 && _freeRideOffset == 0) {
          _entries = newEntries;
        } else {
          _entries = [..._entries, ...newEntries];
        }
        _sessionOffset += sessions.length;
        _freeRideOffset += freeRides.length;
        _hasMore =
            sessions.length == _pageSize || freeRides.length == _pageSize;
      }
      _routes = {for (final r in routeList) r.id: r};
      _loading = false;
    });
  }
```

- [ ] **Step 2: Reload on filter activation; restore pagination on full clear**

Replace `_clearAllFilters` and add a helper:

```dart
  void _clearAllFilters() {
    _searchCtrl.clear();
    _searchDebounce?.cancel();
    setState(() {
      _filters = const HistoryFilters();
    });
    _restorePaginationIfNeeded();
  }

  void _restorePaginationIfNeeded() {
    if (_filters.isEmpty && _fullyLoaded) {
      _fullyLoaded = false;
      _reload();
    }
  }
```

Wherever `_filters` is updated via setState (after sheet apply, after chip dismiss, after debounced search), also call `_ensureFullLoadIfNeeded`. Add the helper:

```dart
  void _ensureFullLoadIfNeeded() {
    if (!_fullyLoaded &&
        (_filters.hasStructuredFilter || _filters.query.isNotEmpty)) {
      _fullyLoaded = true;
      _load();
    } else if (_fullyLoaded && _filters.isEmpty) {
      _restorePaginationIfNeeded();
    }
  }
```

Add calls to `_ensureFullLoadIfNeeded()` at the end of:
- `_onSearchChanged`'s debounced callback (after the `setState`).
- the sheet-apply block in `_openFiltersSheet` (after the `setState`).
- each `onDeleted` of chips that clears a filter via `setState` (after `setState`).
- `_clearSearch`.

- [ ] **Step 3: Manual sanity check via tests**

```bash
flutter test test/features/history/
```

Expected: all tests pass. Filtered-state tests already exercise the full-load path; we just verified it doesn't regress paginated behavior.

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/features/history/history_screen.dart
git commit -m "feat(history): full-load fetch when filters are active, paginated otherwise"
```

---

## Task 8: Filtered-empty action restores full unfiltered list (regression test)

**Files:**
- Modify: `movile_app/test/features/history/history_screen_search_test.dart`

- [ ] **Step 1: Write the regression test**

Append:

```dart
  testWidgets('clear-filters action restores the unfiltered list',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _openRepo();
      await _seed(boot.repo);
      settings = await AppSettingsController.load();
    });
    await tester.pumpWidget(_harness(
      locale: const Locale('es'),
      child: HistoryScreen(
        repository: boot.repo,
        settingsController: settings,
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
    }

    // Type something that matches nothing.
    await tester.enterText(find.byType(TextField), 'zzzzzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('Sin resultados'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Limpiar filtros'));
    await tester.pumpAndSettle();

    expect(find.text('Jarama Norte'), findsOneWidget);
    expect(find.text('Circuito Levante'), findsOneWidget);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });
```

- [ ] **Step 2: Run; expect pass**

```bash
flutter test test/features/history/history_screen_search_test.dart
```

Expected: passes. If it fails, the most likely cause is that the search-field text isn't cleared when `_clearAllFilters` runs — confirm the implementation in Task 7 calls `_searchCtrl.clear()`.

- [ ] **Step 3: Final analyzer + full app test pass**

```bash
flutter analyze
flutter test
```

Expected: green.

- [ ] **Step 4: Commit**

```bash
git add movile_app/test/features/history/history_screen_search_test.dart
git commit -m "test(history): regression for clear-filters action"
```

---

## Task 9: Sanity-run the app locally

Manual smoke test — the screen must look right in both languages and the filter sheet must work end-to-end with a real garage.

- [ ] **Step 1: Run the app**

```bash
cd movile_app && flutter run
```

Use the device/emulator that the user typically targets. Open Historial.

- [ ] **Step 2: Verify behavior**

Tick each item:

- [ ] Search bar visible at the top with hint text in current locale.
- [ ] Typing filters tiles (~250 ms debounce). Clear button appears and works.
- [ ] Filter button opens the bottom sheet; sections render correctly.
- [ ] Type / Distance sections hidden when on the Velocidad tab.
- [ ] Vehicle chips list garage vehicles plus "Sin vehículo".
- [ ] Date presets and Custom range each set the range; chip reflects it.
- [ ] Min-max-speed and min-distance fields accept numbers and respect the current unit system.
- [ ] Apply commits filters; Limpiar clears the draft inside the sheet.
- [ ] Active-filter chips appear below the search row; dismissing one clears that filter.
- [ ] Filtered empty state offers "Limpiar filtros" that restores the original list and re-enables pagination.

- [ ] **Step 3: Note any UI issues; fix small ones inline, file the rest**

If a non-blocking polish issue surfaces (e.g. chip overflow on a narrow screen), fix it now if small. Otherwise note it as a follow-up.

- [ ] **Step 4: Final commit if anything changed**

```bash
git add -A
git commit -m "fix(history): minor polish after manual run"
```

(Skip if nothing changed.)

---

## Out of scope (reminders)

- Persisting filter presets across launches.
- Pushing filters into the repository as SQL `where` clauses.
- Sorting controls beyond descending-by-date.
- Filtering on lap-level data.
