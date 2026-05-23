# Demo Route Jarama + Tombstone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fictional oval demo route with the Circuito del Jarama GPS trace, and prevent the demo from re-seeding after the user deliberately deletes it.

**Architecture:** `AppSettingsController` stores a set of dismissed demo IDs in SharedPreferences. `DemoSeed.ensureSeeded()` accepts `AppSettingsController` and bails out if the demo ID is in the dismissed set. `RouteEditorController` fires an `onRouteDeleted` callback on every deletion, which the router wires to `settingsController.dismissDemoRoute`.

**Tech Stack:** Flutter, Dart, `shared_preferences`, `sqflite` (in-memory via `sqflite_common_ffi` for tests).

---

## File Map

| File | Role |
|---|---|
| `movile_app/lib/src/services/settings/app_settings_controller.dart` | Add `dismissedDemoIds` getter + `dismissDemoRoute()` method |
| `movile_app/lib/src/data/demo/demo_seed.dart` | Replace oval with Jarama; tombstone check in `ensureSeeded()` |
| `movile_app/lib/main.dart` | Load settings before seeding; pass `settingsController` to seed |
| `movile_app/lib/src/features/editor/route_editor_controller.dart` | Add `onRouteDeleted` callback + call in `deleteRoute()` |
| `movile_app/lib/src/routing/app_router.dart` | Wire `onRouteDeleted: settingsController.dismissDemoRoute` |
| `movile_app/lib/src/features/settings/settings_screen.dart` | Call `dismissDemoRoute` in `_clearCache()` for each route |
| `movile_app/test/services/settings/app_settings_controller_test.dart` | New tests for dismissed IDs |
| `movile_app/test/data/demo/demo_seed_test.dart` | New test file — tombstone + seed behaviour |
| `movile_app/test/features/editor/route_editor_controller_test.dart` | New test — `onRouteDeleted` fires on delete |

---

## Task 1: Add `dismissDemoRoute` to `AppSettingsController`

**Files:**
- Modify: `movile_app/lib/src/services/settings/app_settings_controller.dart`
- Test: `movile_app/test/services/settings/app_settings_controller_test.dart`

- [ ] **Step 1.1: Write the failing tests**

Add to the end of `test/services/settings/app_settings_controller_test.dart` (before the closing `}`):

```dart
  test('dismissedDemoIds is empty by default', () async {
    final ctrl = await AppSettingsController.load();
    expect(ctrl.dismissedDemoIds, isEmpty);
  });

  test('dismissDemoRoute persists across reloads', () async {
    final ctrl = await AppSettingsController.load();
    await ctrl.dismissDemoRoute('demo-jarama');

    final ctrl2 = await AppSettingsController.load();
    expect(ctrl2.dismissedDemoIds, contains('demo-jarama'));
  });

  test('dismissDemoRoute is idempotent', () async {
    final ctrl = await AppSettingsController.load();
    await ctrl.dismissDemoRoute('demo-jarama');
    await ctrl.dismissDemoRoute('demo-jarama');
    expect(ctrl.dismissedDemoIds, {'demo-jarama'});
  });
```

- [ ] **Step 1.2: Run tests to verify they fail**

```
cd movile_app
flutter test test/services/settings/app_settings_controller_test.dart
```

Expected: 3 tests fail with `NoSuchMethodError: getter 'dismissedDemoIds'`.

- [ ] **Step 1.3: Implement in `app_settings_controller.dart`**

After the existing constants block (after `_kNotificationPermissionAsked`), add:

```dart
  static const _kDismissedDemoIds = 'dismissed_demo_route_ids';
```

After `bool get notificationPermissionAsked => ...` getter, add:

```dart
  Set<String> get dismissedDemoIds =>
      (_prefs.getStringList(_kDismissedDemoIds) ?? []).toSet();

  Future<void> dismissDemoRoute(String id) async {
    final current = dismissedDemoIds;
    if (current.contains(id)) return;
    await _prefs.setStringList(_kDismissedDemoIds, [...current, id]);
  }
```

- [ ] **Step 1.4: Run tests to verify they pass**

```
cd movile_app
flutter test test/services/settings/app_settings_controller_test.dart
```

Expected: All tests pass.

- [ ] **Step 1.5: Commit**

```
git add movile_app/lib/src/services/settings/app_settings_controller.dart \
        movile_app/test/services/settings/app_settings_controller_test.dart
git commit -m "feat(settings): add dismissDemoRoute tombstone to AppSettingsController"
```

---

## Task 2: Replace oval demo route with Circuito del Jarama + tombstone check

**Files:**
- Modify: `movile_app/lib/src/data/demo/demo_seed.dart`
- Create: `movile_app/test/data/demo/demo_seed_test.dart`

- [ ] **Step 2.1: Create the test file**

Create `movile_app/test/data/demo/demo_seed_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:splitway_mobile/src/data/demo/demo_seed.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

int _counter = 0;

Future<LocalDraftRepository> _makeRepo() async {
  _counter++;
  final db = await SplitwayLocalDatabase.open(
    overridePath: 'file:demo_seed_test_$_counter?mode=memory&cache=shared',
  );
  return LocalDraftRepository(db);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('seeds Jarama route into empty DB', () async {
    final repo = await _makeRepo();
    final settings = await AppSettingsController.load();

    await DemoSeed.ensureSeeded(repo, settings);

    final route = await repo.getRouteTemplate('demo-jarama');
    expect(route, isNotNull);
    expect(route!.name, 'Circuito del Jarama');
    expect(route.sectors, hasLength(2));
  });

  test('does not re-seed when route already exists', () async {
    final repo = await _makeRepo();
    final settings = await AppSettingsController.load();

    await DemoSeed.ensureSeeded(repo, settings);
    await DemoSeed.ensureSeeded(repo, settings);

    final routes = await repo.getAllRoutes();
    expect(routes.where((r) => r.id == 'demo-jarama'), hasLength(1));
  });

  test('does not seed when route is dismissed', () async {
    final repo = await _makeRepo();
    final settings = await AppSettingsController.load();
    await settings.dismissDemoRoute('demo-jarama');

    await DemoSeed.ensureSeeded(repo, settings);

    final route = await repo.getRouteTemplate('demo-jarama');
    expect(route, isNull);
  });

  test('does not re-seed after deletion when dismissed', () async {
    final repo = await _makeRepo();
    final settings = await AppSettingsController.load();

    await DemoSeed.ensureSeeded(repo, settings);
    await settings.dismissDemoRoute('demo-jarama');
    await repo.deleteRoute('demo-jarama');

    await DemoSeed.ensureSeeded(repo, settings);

    final route = await repo.getRouteTemplate('demo-jarama');
    expect(route, isNull);
  });
}
```

- [ ] **Step 2.2: Run tests to verify they fail**

```
cd movile_app
flutter test test/data/demo/demo_seed_test.dart
```

Expected: Tests fail — `DemoSeed.ensureSeeded` still takes one argument and creates `demo-oval`.

- [ ] **Step 2.3: Replace `demo_seed.dart` entirely**

Full new content for `movile_app/lib/src/data/demo/demo_seed.dart`:

```dart
import 'package:splitway_core/splitway_core.dart';

import '../../services/settings/app_settings_controller.dart';
import '../repositories/local_draft_repository.dart';

class DemoSeed {
  DemoSeed._();

  static const _jaramaId = 'demo-jarama';

  /// Seeds the Jarama circuit demo route unless the user has already dismissed it.
  static Future<void> ensureSeeded(
    LocalDraftRepository repo,
    AppSettingsController settings,
  ) async {
    if (settings.dismissedDemoIds.contains(_jaramaId)) return;
    final existing = await repo.getRouteTemplate(_jaramaId);
    if (existing != null) return;
    await repo.saveRouteTemplate(_buildJaramaDemo());
  }

  static RouteTemplate _buildJaramaDemo() {
    // Approximate GPS trace of Circuito del Jarama, San Sebastián de los Reyes,
    // Madrid (~40.62°N, ~3.59°W). ~21 waypoints, clockwise direction.
    final path = [
      GeoPoint(latitude: 40.6208, longitude: -3.5862), // Start/finish
      GeoPoint(latitude: 40.6213, longitude: -3.5874),
      GeoPoint(latitude: 40.6220, longitude: -3.5886),
      GeoPoint(latitude: 40.6230, longitude: -3.5897),
      GeoPoint(latitude: 40.6240, longitude: -3.5905),
      GeoPoint(latitude: 40.6248, longitude: -3.5915),
      GeoPoint(latitude: 40.6258, longitude: -3.5925),
      GeoPoint(latitude: 40.6265, longitude: -3.5935),
      GeoPoint(latitude: 40.6268, longitude: -3.5948), // Chicane peak
      GeoPoint(latitude: 40.6265, longitude: -3.5958),
      GeoPoint(latitude: 40.6255, longitude: -3.5965),
      GeoPoint(latitude: 40.6242, longitude: -3.5968),
      GeoPoint(latitude: 40.6230, longitude: -3.5962),
      GeoPoint(latitude: 40.6220, longitude: -3.5950),
      GeoPoint(latitude: 40.6215, longitude: -3.5937),
      GeoPoint(latitude: 40.6213, longitude: -3.5920),
      GeoPoint(latitude: 40.6215, longitude: -3.5905),
      GeoPoint(latitude: 40.6218, longitude: -3.5892),
      GeoPoint(latitude: 40.6214, longitude: -3.5880),
      GeoPoint(latitude: 40.6210, longitude: -3.5872),
      GeoPoint(latitude: 40.6208, longitude: -3.5862), // Close loop
    ];

    final startGate = GateDefinition(
      left: GeoPoint(latitude: 40.6204, longitude: -3.5862),
      right: GeoPoint(latitude: 40.6212, longitude: -3.5862),
    );

    final sector1 = SectorDefinition(
      id: 'demo-jarama-s1',
      order: 0,
      label: 'Sector 1',
      gate: GateDefinition(
        left: GeoPoint(latitude: 40.6270, longitude: -3.5942),
        right: GeoPoint(latitude: 40.6270, longitude: -3.5956),
      ),
    );

    final sector2 = SectorDefinition(
      id: 'demo-jarama-s2',
      order: 1,
      label: 'Sector 2',
      gate: GateDefinition(
        left: GeoPoint(latitude: 40.6212, longitude: -3.5894),
        right: GeoPoint(latitude: 40.6222, longitude: -3.5894),
      ),
    );

    return RouteTemplate(
      id: _jaramaId,
      name: 'Circuito del Jarama',
      description: 'Trazado aproximado del Circuito del Jarama '
          '(San Sebastián de los Reyes, Madrid).',
      path: path,
      startFinishGate: startGate,
      sectors: [sector1, sector2],
      difficulty: RouteDifficulty.hard,
      createdAt: DateTime.now(),
    );
  }
}
```

- [ ] **Step 2.4: Run tests to verify they pass**

```
cd movile_app
flutter test test/data/demo/demo_seed_test.dart
```

Expected: All 4 tests pass.

- [ ] **Step 2.5: Commit**

```
git add movile_app/lib/src/data/demo/demo_seed.dart \
        movile_app/test/data/demo/demo_seed_test.dart
git commit -m "feat(demo): replace oval with Circuito del Jarama; add tombstone check"
```

---

## Task 3: Update `main.dart` — load settings before seeding

**Files:**
- Modify: `movile_app/lib/main.dart`

This task has no dedicated unit test (it's boot wiring); correctness is verified by the existing `demo_seed_test` and end-to-end smoke test.

- [ ] **Step 3.1: Edit `main.dart`**

Find this block (lines 37–47):

```dart
  final database = await SplitwayLocalDatabase.open();
  final seedRepo = LocalDraftRepository(database);
  await DemoSeed.ensureSeeded(seedRepo);
  await seedRepo.dispose();

  final deviceLocale =
      WidgetsBinding.instance.platformDispatcher.locale;
  final localeController =
      await LocaleController.load(deviceLocale: deviceLocale);
  final settingsController = await AppSettingsController.load();
```

Replace with:

```dart
  final database = await SplitwayLocalDatabase.open();
  final settingsController = await AppSettingsController.load();
  final seedRepo = LocalDraftRepository(database);
  await DemoSeed.ensureSeeded(seedRepo, settingsController);
  await seedRepo.dispose();

  final deviceLocale =
      WidgetsBinding.instance.platformDispatcher.locale;
  final localeController =
      await LocaleController.load(deviceLocale: deviceLocale);
```

- [ ] **Step 3.2: Verify it compiles**

```
cd movile_app
flutter build apk --debug 2>&1 | head -20
```

Expected: Compiles without errors (or run `flutter analyze` as a lighter check).

- [ ] **Step 3.3: Commit**

```
git add movile_app/lib/main.dart
git commit -m "fix(boot): load AppSettingsController before DemoSeed.ensureSeeded"
```

---

## Task 4: Add `onRouteDeleted` callback to `RouteEditorController`

**Files:**
- Modify: `movile_app/lib/src/features/editor/route_editor_controller.dart`
- Test: `movile_app/test/features/editor/route_editor_controller_test.dart`

- [ ] **Step 4.1: Write the failing test**

At the end of `test/features/editor/route_editor_controller_test.dart`, add a new group:

```dart
  group('deleteRoute callback', () {
    test('onRouteDeleted fires with correct id when route deleted', () async {
      // Save a route first
      ctrl.startDrawing(name: 'To Delete', difficulty: RouteDifficulty.easy);
      ctrl.handleMapTap(const GeoPoint(latitude: 1.0, longitude: 1.0));
      ctrl.handleMapTap(const GeoPoint(latitude: 1.0, longitude: 1.1));
      ctrl.handleMapTap(const GeoPoint(latitude: 1.0, longitude: 1.2));
      await ctrl.saveRoute();
      await ctrl.load();
      final routeId = ctrl.routes.first.id;

      final captured = <String>[];
      final ctrlWithCallback = RouteEditorController(
        repo,
        onRouteDeleted: (id) async => captured.add(id),
      );
      await ctrlWithCallback.load();

      await ctrlWithCallback.deleteRoute(routeId);

      expect(captured, [routeId]);
    });
  });
```

- [ ] **Step 4.2: Run the test to verify it fails**

```
cd movile_app
flutter test test/features/editor/route_editor_controller_test.dart
```

Expected: The new test fails with `No named parameter with the name 'onRouteDeleted'`.

- [ ] **Step 4.3: Add the callback field and constructor parameter**

In `route_editor_controller.dart`, change the constructor signature from:

```dart
  RouteEditorController(
    this._repo, {
    this.routingService,
    this.geocodingService,
    String defaultRoutingProfile = 'driving',
  }) : _defaultRoutingProfile = defaultRoutingProfile {
```

to:

```dart
  RouteEditorController(
    this._repo, {
    this.routingService,
    this.geocodingService,
    String defaultRoutingProfile = 'driving',
    this.onRouteDeleted,
  }) : _defaultRoutingProfile = defaultRoutingProfile {
```

Right after the `syncService` field declaration (search for `SyncService? _syncService;`), add:

```dart
  final Future<void> Function(String id)? onRouteDeleted;
```

- [ ] **Step 4.4: Call the callback inside `deleteRoute`**

Find `deleteRoute` (around line 594):

```dart
  Future<void> deleteRoute(String id) async {
    if (syncService != null) {
      await syncService!.deleteRoute(id);
    } else {
      await _repo.deleteRoute(id);
    }
    if (_selected?.id == id) {
```

Change to:

```dart
  Future<void> deleteRoute(String id) async {
    if (syncService != null) {
      await syncService!.deleteRoute(id);
    } else {
      await _repo.deleteRoute(id);
    }
    await onRouteDeleted?.call(id);
    if (_selected?.id == id) {
```

- [ ] **Step 4.5: Run tests to verify they pass**

```
cd movile_app
flutter test test/features/editor/route_editor_controller_test.dart
```

Expected: All tests pass, including the new `onRouteDeleted fires` test.

- [ ] **Step 4.6: Commit**

```
git add movile_app/lib/src/features/editor/route_editor_controller.dart \
        movile_app/test/features/editor/route_editor_controller_test.dart
git commit -m "feat(editor): add onRouteDeleted callback to RouteEditorController"
```

---

## Task 5: Wire tombstone in `AppRouter` and `SettingsScreen`

**Files:**
- Modify: `movile_app/lib/src/routing/app_router.dart`
- Modify: `movile_app/lib/src/features/settings/settings_screen.dart`

No new unit tests: `AppRouter` is integration wiring; `SettingsScreen._clearCache` is already covered by widget tests. The tombstone behaviour on bulk delete is verified manually.

- [ ] **Step 5.1: Pass `onRouteDeleted` in `AppRouter`**

In `app_router.dart`, find the `RouteEditorController` constructor call (lines 44–53):

```dart
      : _editorController = RouteEditorController(
          repository,
          routingService: config.hasMapbox
              ? RoutingService(mapboxToken: config.mapboxToken!)
              : null,
          geocodingService: config.hasMapbox
              ? ReverseGeocodingService(accessToken: config.mapboxToken!)
              : null,
          defaultRoutingProfile: settingsController.defaultRoutingProfile,
        ),
```

Change to:

```dart
      : _editorController = RouteEditorController(
          repository,
          routingService: config.hasMapbox
              ? RoutingService(mapboxToken: config.mapboxToken!)
              : null,
          geocodingService: config.hasMapbox
              ? ReverseGeocodingService(accessToken: config.mapboxToken!)
              : null,
          defaultRoutingProfile: settingsController.defaultRoutingProfile,
          onRouteDeleted: settingsController.dismissDemoRoute,
        ),
```

- [ ] **Step 5.2: Dismiss demo routes in `SettingsScreen._clearCache`**

In `settings_screen.dart`, find `_clearCache` (around line 454):

```dart
      final routes = await repository.getAllRoutes();
      for (final r in routes) {
        await repository.deleteRoute(r.id);
      }
```

Change to:

```dart
      final routes = await repository.getAllRoutes();
      for (final r in routes) {
        await repository.deleteRoute(r.id);
        await settingsController.dismissDemoRoute(r.id);
      }
```

- [ ] **Step 5.3: Verify compilation**

```
cd movile_app
flutter analyze
```

Expected: No new issues.

- [ ] **Step 5.4: Run full test suite**

```
cd movile_app
flutter test
```

Expected: All tests pass.

- [ ] **Step 5.5: Commit**

```
git add movile_app/lib/src/routing/app_router.dart \
        movile_app/lib/src/features/settings/settings_screen.dart
git commit -m "feat(demo): wire tombstone on route deletion and bulk cache clear"
```

---

## Self-Review Checklist

- [x] **Spec coverage:** All 6 files from the spec are covered across Tasks 1–5. Both demo route change and tombstone logic are fully implemented.
- [x] **No placeholders:** Every step has concrete code. No TBDs.
- [x] **Type consistency:** `Future<void> Function(String id)?` used in Task 4 matches the `settingsController.dismissDemoRoute` tear-off type wired in Task 5.
- [x] **Test completeness:** `app_settings_controller_test.dart` (Task 1), `demo_seed_test.dart` (Task 2), `route_editor_controller_test.dart` (Task 4) all have failing-first TDD steps.
- [x] **Import added in `demo_seed.dart`:** Task 2 adds `import '../../services/settings/app_settings_controller.dart'` and removes the old `import 'dart:math'` (no longer needed with the Jarama implementation).
