# History "Group by Route" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "group by route" toggle to the history filters so the main list collapses into one row per route; tapping a row opens a screen listing every session run on that route.

**Architecture:** A new `groupByRoute` boolean lives on the existing immutable `HistoryFilters` (view-mode flag, excluded from `activeCount`/`isEmpty`). The history screen, when the flag is set, forces a full load (needed to count correctly), groups the already-filtered entries by `routeTemplateId` (free rides collapse into one synthetic "Rutas libres" group), and renders group tiles. Tapping a tile pushes a private `_RouteSessionsScreen` that reuses the existing `_SessionTile`/`_FreeRideTile`.

**Tech Stack:** Flutter, Dart, `intl` (DateFormat), Flutter gen-l10n (ARB files), `flutter_test`.

---

## File Structure

- `movile_app/lib/src/features/history/history_filters.dart` — add `groupByRoute` field + `copyWith` support (pure data, already the home of all filter state).
- `movile_app/lib/l10n/app_en.arb` + `app_es.arb` — new localized strings; regenerate `app_localizations*.dart`.
- `movile_app/lib/src/features/history/history_filters_sheet.dart` — add the toggle (UI only).
- `movile_app/lib/src/features/history/history_screen.dart` — grouping logic, group tiles, active chip, force-full-load wiring, and the new `_RouteSessionsScreen` (kept in this file to reuse the private tile widgets).
- `movile_app/test/features/history/history_filters_test.dart` — unit tests for the new field.
- `movile_app/test/features/history/history_group_by_route_test.dart` — new widget test for the grouped view + drill-in.

---

## Task 1: Add `groupByRoute` to `HistoryFilters`

**Files:**
- Modify: `movile_app/lib/src/features/history/history_filters.dart`
- Test: `movile_app/test/features/history/history_filters_test.dart`

- [ ] **Step 1: Write the failing tests**

Add these tests inside the existing `group('HistoryFilters', () { ... })` block in `history_filters_test.dart` (after the `copyWith` test, before the closing `});` of that group):

```dart
    test('groupByRoute defaults to false and does not affect activeCount', () {
      const f = HistoryFilters();
      expect(f.groupByRoute, isFalse);

      const g = HistoryFilters(groupByRoute: true);
      // It is a view mode, not a structured filter group.
      expect(g.activeCount, 0);
      // isEmpty keeps its current meaning (query + structured groups only).
      expect(g.isEmpty, isTrue);
    });

    test('copyWith toggles groupByRoute and preserves it otherwise', () {
      const f = HistoryFilters(groupByRoute: true);
      expect(f.copyWith(query: 'x').groupByRoute, isTrue); // preserved
      expect(f.copyWith(groupByRoute: false).groupByRoute, isFalse); // overridden
    });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd movile_app && flutter test test/features/history/history_filters_test.dart`
Expected: FAIL — `groupByRoute` is not defined / named parameter `groupByRoute` isn't defined.

- [ ] **Step 3: Add the field to `HistoryFilters`**

In `history_filters.dart`, update the constructor, fields, and `copyWith`. The class currently starts:

```dart
  const HistoryFilters({
    this.query = '',
    this.kinds = const <HistoryEntryKind>{},
    this.vehicleIds = const <String?>{},
    this.dateRange,
    this.minDistanceMeters,
  });
```

Change it to:

```dart
  const HistoryFilters({
    this.query = '',
    this.kinds = const <HistoryEntryKind>{},
    this.vehicleIds = const <String?>{},
    this.dateRange,
    this.minDistanceMeters,
    this.groupByRoute = false,
  });
```

Add the field after `minDistanceMeters`:

```dart
  final double? minDistanceMeters;

  /// View-mode flag: when true the history list collapses into one row per
  /// route. Deliberately excluded from [activeCount] and [isEmpty] — it does
  /// not hide entries, it only changes how they're presented.
  final bool groupByRoute;
```

Update `copyWith` to accept and apply it. The signature gains a `bool? groupByRoute` parameter and the constructor call gains `groupByRoute: groupByRoute ?? this.groupByRoute,`:

```dart
  HistoryFilters copyWith({
    String? query,
    Set<HistoryEntryKind>? kinds,
    Set<String?>? vehicleIds,
    Object? dateRange = _sentinel,
    Object? minDistanceMeters = _sentinel,
    bool? groupByRoute,
  }) {
    return HistoryFilters(
      query: query ?? this.query,
      kinds: kinds ?? this.kinds,
      vehicleIds: vehicleIds ?? this.vehicleIds,
      dateRange: identical(dateRange, _sentinel)
          ? this.dateRange
          : dateRange as DateTimeRange?,
      minDistanceMeters: identical(minDistanceMeters, _sentinel)
          ? this.minDistanceMeters
          : minDistanceMeters as double?,
      groupByRoute: groupByRoute ?? this.groupByRoute,
    );
  }
```

Leave `isEmpty`, `activeCount`, and `clear()` unchanged — `clear()` returns `const HistoryFilters()` so `groupByRoute` resets to `false` for free.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd movile_app && flutter test test/features/history/history_filters_test.dart`
Expected: PASS (all tests in the file).

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/history/history_filters.dart movile_app/test/features/history/history_filters_test.dart
git commit -m "feat: add groupByRoute view-mode flag to HistoryFilters"
```

---

## Task 2: Add localized strings and regenerate

**Files:**
- Modify: `movile_app/lib/l10n/app_en.arb` (template — needs `@`-metadata for placeholders)
- Modify: `movile_app/lib/l10n/app_es.arb`
- Regenerate: `movile_app/lib/l10n/app_localizations*.dart` (via gen-l10n)

- [ ] **Step 1: Add keys to the English template `app_en.arb`**

Insert these keys right after the line `"historyFilteredEmptyAction": "Clear filters",` (line ~434):

```json
  "historyFilterGroupByRoute": "Group by route",
  "historyGroupFreeRides": "Free rides",
  "historyGroupChip": "Grouped by route",
  "historyGroupSubtitle": "{count, plural, =1{1 session} other{{count} sessions}} · last {date}",
  "@historyGroupSubtitle": { "placeholders": { "count": { "type": "int" }, "date": { "type": "String" } } },
```

- [ ] **Step 2: Add the same keys to `app_es.arb`**

Insert right after the line `"historyFilteredEmptyAction": "Limpiar filtros",` (line ~434):

```json
  "historyFilterGroupByRoute": "Agrupar por ruta",
  "historyGroupFreeRides": "Rutas libres",
  "historyGroupChip": "Agrupado por ruta",
  "historyGroupSubtitle": "{count, plural, =1{1 sesión} other{{count} sesiones}} · última {date}",
  "@historyGroupSubtitle": { "placeholders": { "count": { "type": "int" }, "date": { "type": "String" } } },
```

Note: `@`-metadata only needs to live in the template (`app_en.arb`), but adding it to `app_es.arb` too is harmless and matches the existing convention in this file (see `historyFilterMinDistanceChip`).

- [ ] **Step 3: Regenerate localizations**

Run: `cd movile_app && flutter gen-l10n`
Expected: completes without error; `lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_es.dart` now contain getters `historyFilterGroupByRoute`, `historyGroupFreeRides`, `historyGroupChip`, and method `historyGroupSubtitle(int count, String date)`.

- [ ] **Step 4: Verify the generated getters exist**

Run: `cd movile_app && grep -c "historyGroupSubtitle" lib/l10n/app_localizations.dart`
Expected: a number `>= 1` (the abstract declaration is present).

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/l10n/
git commit -m "feat: add i18n strings for history group-by-route"
```

---

## Task 3: Add the toggle to the filters sheet

**Files:**
- Modify: `movile_app/lib/src/features/history/history_filters_sheet.dart`

This is UI wiring with no separate unit test; it is exercised by the widget test in Task 5. Verify via `flutter analyze` and that test.

- [ ] **Step 1: Add the `SwitchListTile` to the sheet body**

In `history_filters_sheet.dart`, inside `_FiltersSheetBodyState.build`, the header `Row` (the one ending with the close `IconButton`) is followed by `// ------- Kind filter (hidden on speed tab) -------`. Insert the toggle between the header `Row` and the kind-filter block. The toggle is hidden on the speed tab (routes don't apply to speed sessions):

Find:

```dart
            // ------- Kind filter (hidden on speed tab) -------
            if (!widget.isSpeedTab) ...[
```

Insert immediately before it:

```dart
            // ------- Group-by-route toggle (hidden on speed tab) -------
            if (!widget.isSpeedTab)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.historyFilterGroupByRoute),
                  value: _draft.groupByRoute,
                  onChanged: (on) {
                    setState(
                        () => _draft = _draft.copyWith(groupByRoute: on));
                  },
                ),
              ),

```

- [ ] **Step 2: Verify it analyzes cleanly**

Run: `cd movile_app && flutter analyze lib/src/features/history/history_filters_sheet.dart`
Expected: "No issues found!" (or only pre-existing unrelated infos).

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/features/history/history_filters_sheet.dart
git commit -m "feat: add group-by-route toggle to history filters sheet"
```

---

## Task 4: Group the history list and add the route-sessions screen

**Files:**
- Modify: `movile_app/lib/src/features/history/history_screen.dart`

Behaviour is verified by the widget test in Task 5; this task is the production wiring. Run `flutter analyze` after.

- [ ] **Step 1: Add a full-load helper and wire it into the load triggers**

In `_HistoryScreenState`, add a getter near the top of the state class (e.g. just after the `_filters`/`_searchDebounce` field declarations, before `initState`):

```dart
  /// Whether we must hold the entire history in memory rather than paginate.
  /// True when any filter narrows the list, or when grouping is on (we need
  /// every entry to count sessions per route correctly).
  bool get _needsFullLoad => !_filters.isEmpty || _filters.groupByRoute;
```

In `initState`, the changes listener currently reads:

```dart
        if (!_filters.isEmpty) {
          _fullyLoaded = false; // force the next _loadAll to run
          _loadAll();
        } else {
          _reload();
        }
```

Replace the `if (!_filters.isEmpty) {` line with `if (_needsFullLoad) {`.

In `_onFiltersChanged`, replace the whole body:

```dart
  Future<void> _onFiltersChanged() async {
    if (!_filters.isEmpty && !_fullyLoaded) {
      await _loadAll();
    } else if (_filters.isEmpty && _fullyLoaded) {
      _reload();
    }
  }
```

with:

```dart
  Future<void> _onFiltersChanged() async {
    if (_needsFullLoad && !_fullyLoaded) {
      await _loadAll();
    } else if (!_needsFullLoad && _fullyLoaded) {
      _reload();
    }
  }
```

- [ ] **Step 2: Add the grouping model and helper**

Add this small value type at the end of the file (top-level, after the last class), and the grouping helper as a method on `_HistoryScreenState`.

Top-level type (place near the other top-level helpers at the bottom of the file):

```dart
/// One route's worth of history entries for the grouped view. `entries` are
/// pre-sorted most-recent-first (they inherit [_HistoryEntry.compareTo]).
class _RouteGroup {
  _RouteGroup({required this.title, required this.entries});
  final String title;
  final List<_HistoryEntry> entries;

  int get count => entries.length;
  DateTime get lastDate => entries.first.date;
}
```

Method on `_HistoryScreenState` (place it right after `_buildMainList`):

```dart
  /// Groups already-filtered entries by route. Sessions are bucketed by
  /// `routeTemplateId`; every free ride collapses into one synthetic
  /// "Rutas libres" group. Groups are ordered by their most-recent entry.
  List<_RouteGroup> _groupByRoute(
      AppLocalizations l, List<_HistoryEntry> entries) {
    final byRoute = <String, List<_HistoryEntry>>{};
    final freeRides = <_HistoryEntry>[];
    for (final e in entries) {
      switch (e) {
        case _SessionEntry(:final session):
          byRoute.putIfAbsent(session.routeTemplateId, () => []).add(e);
        case _FreeRideEntry():
          freeRides.add(e);
      }
    }

    final groups = <_RouteGroup>[];
    byRoute.forEach((routeId, list) {
      list.sort();
      groups.add(_RouteGroup(
        title: _routes[routeId]?.name ?? l.historyDeletedRoute,
        entries: list,
      ));
    });
    if (freeRides.isNotEmpty) {
      freeRides.sort();
      groups.add(_RouteGroup(title: l.historyGroupFreeRides, entries: freeRides));
    }

    // Most-recent group first.
    groups.sort((a, b) => b.lastDate.compareTo(a.lastDate));
    return groups;
  }
```

- [ ] **Step 3: Render the grouped list when the flag is set**

In `_buildMainList`, the current tail computes `filtered`, then the filtered-empty check, then `showSentinel`, then returns the `ListView.separated`. Insert a grouped branch immediately after the filtered-empty check. Find:

```dart
    if (filtered.isEmpty) {
      return _filteredEmptyState(l);
    }

    // Hide the load-more sentinel when any filter is active to avoid loading
```

Insert between the `}` of the empty check and the `// Hide the load-more sentinel` comment:

```dart
    if (_filters.groupByRoute) {
      final groups = _groupByRoute(l, filtered);
      return ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (_, index) {
          final group = groups[index];
          final dateStr =
              DateFormat.yMMMd(l.localeName).format(group.lastDate);
          return Card(
            child: ListTile(
              leading: const Icon(Icons.route),
              title: Text(group.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(l.historyGroupSubtitle(group.count, dateStr)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _RouteSessionsScreen(
                  title: group.title,
                  entries: group.entries,
                  routes: _routes,
                  repository: widget.repository,
                  config: widget.config,
                  settingsController: widget.settingsController,
                  garageService: widget.garageService,
                  syncService: widget.syncService,
                ),
              )),
            ),
          );
        },
      );
    }

```

- [ ] **Step 4: Show a removable "Grouped by route" chip**

In `_buildActiveFilterChips`, the method opens with:

```dart
    if (_filters.activeCount == 0) return const SizedBox.shrink();

    final unit = widget.settingsController.unitSystem;
    final chips = <Widget>[];
```

Replace the early-return line so the chip row also appears when only grouping is on, and add the group chip first:

```dart
    if (_filters.activeCount == 0 && !_filters.groupByRoute) {
      return const SizedBox.shrink();
    }

    final unit = widget.settingsController.unitSystem;
    final chips = <Widget>[];

    // Group-by-route view-mode chip (not counted in the badge).
    if (_filters.groupByRoute) {
      chips.add(InputChip(
        label: Text(l.historyGroupChip),
        onDeleted: () =>
            _updateFilters(_filters.copyWith(groupByRoute: false)),
      ));
    }
```

- [ ] **Step 5: Add the `_RouteSessionsScreen` widget**

Add this private widget at the end of the file (top-level). It reuses `_SessionTile`/`_FreeRideTile`, which live in this same library:

```dart
/// Lists every history entry in a single route group (or the "free rides"
/// group). Reached from the grouped history view; reuses the standard tiles.
class _RouteSessionsScreen extends StatelessWidget {
  const _RouteSessionsScreen({
    required this.title,
    required this.entries,
    required this.routes,
    required this.repository,
    required this.config,
    required this.settingsController,
    this.garageService,
    this.syncService,
  });

  final String title;
  final List<_HistoryEntry> entries;
  final Map<String, RouteTemplate> routes;
  final LocalDraftRepository repository;
  final AppConfig config;
  final AppSettingsController settingsController;
  final GarageService? garageService;
  final SyncService? syncService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (_, index) {
          final entry = entries[index];
          return switch (entry) {
            _SessionEntry(:final session) => _SessionTile(
                session: session,
                route: routes[session.routeTemplateId],
                repository: repository,
                config: config,
                garageService: garageService,
                settingsController: settingsController,
                syncService: syncService,
              ),
            _FreeRideEntry(:final ride) => _FreeRideTile(
                ride: ride,
                repository: repository,
                config: config,
                garageService: garageService,
                settingsController: settingsController,
                syncService: syncService,
              ),
          };
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Verify it analyzes cleanly**

Run: `cd movile_app && flutter analyze lib/src/features/history/history_screen.dart`
Expected: "No issues found!" (or only pre-existing unrelated infos).

- [ ] **Step 7: Commit**

```bash
git add movile_app/lib/src/features/history/history_screen.dart
git commit -m "feat: render history grouped by route with drill-in screen"
```

---

## Task 5: Widget test for the grouped view + drill-in

**Files:**
- Create: `movile_app/test/features/history/history_group_by_route_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `movile_app/test/features/history/history_group_by_route_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/features/history/history_screen.dart';
import 'package:splitway_mobile/src/services/locale/locale_controller.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

Widget _harness({required Widget child}) => MaterialApp(
      locale: const Locale('es'),
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
    overridePath:
        'file:history_group_test_$_dbCounter?mode=memory&cache=shared',
  );
  return (db: db, repo: LocalDraftRepository(db));
}

RouteTemplate _makeRoute(String id, String name) => RouteTemplate(
      id: id,
      name: name,
      path: const [
        GeoPoint(latitude: 40.0, longitude: -3.0),
        GeoPoint(latitude: 40.001, longitude: -3.0),
      ],
      startFinishGate: GateDefinition(
        left: const GeoPoint(latitude: 40.0, longitude: -3.0),
        right: const GeoPoint(latitude: 40.001, longitude: -3.0),
      ),
      sectors: const [],
      difficulty: RouteDifficulty.medium,
      createdAt: DateTime(2024, 1, 1),
    );

SessionRun _makeSession(String id, String routeId, DateTime startedAt) =>
    SessionRun(
      id: id,
      routeTemplateId: routeId,
      startedAt: startedAt,
      status: SessionStatus.completed,
      points: const [],
      laps: const [],
      sectorSummaries: const [],
      totalDistanceMeters: 1000,
      maxSpeedMps: 30,
      avgSpeedMps: 20,
    );

FreeRideRun _makeFreeRide(String id, String name) => FreeRideRun(
      id: id,
      startedAt: DateTime(2024, 6, 2, 10, 0),
      status: FreeRideStatus.completed,
      points: const [],
      totalDistanceMeters: 5000,
      maxSpeedMps: 15,
      avgSpeedMps: 10,
      name: name,
    );

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('grouping by route collapses sessions and drills in',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _openRepo();
      settings = await AppSettingsController.load();
      boot.repo.userId = 'test-user';
      await boot.repo.saveRouteTemplate(_makeRoute('route-a', 'Ruta A'));
      await boot.repo.saveRouteTemplate(_makeRoute('route-b', 'Ruta B'));
      // Two sessions on Ruta A, one on Ruta B, plus a free ride.
      await boot.repo
          .saveSessionRun(_makeSession('s-a1', 'route-a', DateTime(2024, 6, 3)));
      await boot.repo
          .saveSessionRun(_makeSession('s-a2', 'route-a', DateTime(2024, 6, 1)));
      await boot.repo
          .saveSessionRun(_makeSession('s-b1', 'route-b', DateTime(2024, 6, 4)));
      await boot.repo.saveFreeRideRun(_makeFreeRide('fr-1', 'Paseo casual'));
    });

    await tester.pumpWidget(_harness(
      child: HistoryScreen(
        repository: boot.repo,
        settingsController: settings,
      ),
    ));
    await _pumpUntilLoaded(tester);

    // Open filters, enable "Agrupar por ruta", apply.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agrupar por ruta'));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await _pumpUntilLoaded(tester);

    // One row per route + a "Rutas libres" group. Ruta A shows 2 sessions.
    expect(find.widgetWithText(Card, 'Ruta A'), findsOneWidget);
    expect(find.widgetWithText(Card, 'Ruta B'), findsOneWidget);
    expect(find.widgetWithText(Card, 'Rutas libres'), findsOneWidget);
    expect(find.textContaining('2 sesiones'), findsOneWidget);

    // Drill into Ruta A → both of its sessions are listed.
    await tester.tap(find.widgetWithText(Card, 'Ruta A'));
    await tester.pumpAndSettle();
    await _pumpUntilLoaded(tester);

    // The detail screen shows two session tiles for Ruta A.
    expect(find.widgetWithText(Card, 'Ruta A'), findsNWidgets(2));

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });
}
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `cd movile_app && flutter test test/features/history/history_group_by_route_test.dart`
Expected: PASS.

If `find.textContaining('2 sesiones')` fails, print the rendered subtitle to confirm the plural form (`flutter test` shows the widget tree on failure) and adjust the expectation to match the generated string — do not change the production string.

- [ ] **Step 3: Run the full history test suite for regressions**

Run: `cd movile_app && flutter test test/features/history/`
Expected: all tests PASS (the existing search/filter tests are unaffected because grouping is off by default).

- [ ] **Step 4: Commit**

```bash
git add movile_app/test/features/history/history_group_by_route_test.dart
git commit -m "test: cover history group-by-route view and drill-in"
```

---

## Final verification

- [ ] Run `cd movile_app && flutter analyze` — expect no new issues.
- [ ] Run `cd movile_app && flutter test` — expect the whole suite green.
</content>
