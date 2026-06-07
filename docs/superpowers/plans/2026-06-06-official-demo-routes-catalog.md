# Official Demo Routes Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hardcoded `DemoSeed` with a Supabase-backed catalog of official routes owned by `splitwayoficial@gmail.com`, persisted locally and dismissable per device with reappear-on-modify semantics.

**Architecture:** Add an `is_official` flag and `updated_at` timestamp to both Supabase and local SQLite `route_templates`. A new `OfficialRoutesService` fetches the catalog (using the anon-readable RLS policy) and reconciles local state, applying per-device dismissal stored in `SharedPreferences` as `Map<routeId, updatedAtMillis>`. The service runs on cold start, on auth transitions, and on pull-to-refresh. The hardcoded `DemoSeed` is deleted.

**Tech Stack:** Flutter, Dart, Supabase (Postgres + RLS), SQLite (sqflite), SharedPreferences.

---

## File Structure

| File | Purpose | Action |
|---|---|---|
| `packages/splitway_core/lib/src/models/route_template.dart` | Domain model — add `isOfficial` and `updatedAt` fields | Modify |
| `packages/splitway_core/test/route_template_test.dart` | Cover `copyWith` and serialization of new fields | Create or extend |
| `movile_app/lib/src/data/local/splitway_local_database.dart` | Bump schema to v10, add `is_official` and `updated_at` columns to `route_templates` | Modify |
| `movile_app/lib/src/data/repositories/local_draft_repository.dart` | Read/write new columns, generalize `demo-espana` literals to `is_official=1` | Modify |
| `movile_app/lib/src/data/repositories/supabase_repository.dart` | Read/write `is_official` + `updated_at`, add `fetchOfficialRoutes()` | Modify |
| `movile_app/lib/src/services/settings/app_settings_controller.dart` | Replace `dismissedDemoIds` API with `dismissedOfficialRoutes` map + legacy migration | Modify |
| `movile_app/lib/src/services/official_routes/official_routes_service.dart` | New service — fetch, reconcile, dismiss | Create |
| `movile_app/lib/src/services/sync/sync_service.dart` | Skip `isOfficial==true` routes (generalize from `demo-espana` literal) | Modify |
| `movile_app/lib/src/features/editor/route_editor_controller.dart` | Route delete: dispatch to `OfficialRoutesService.dismiss` when official | Modify |
| `movile_app/lib/src/routing/app_router.dart` | Wire `OfficialRoutesService` into `RouteEditorController` (replacing `onRouteDeleted: settings.dismissDemoRoute`) | Modify |
| `movile_app/lib/src/features/editor/route_editor_screen.dart` | Add `RefreshIndicator` that calls `service.refresh()` | Modify |
| `movile_app/lib/main.dart` | Instantiate `OfficialRoutesService`, kick off initial refresh in background | Modify |
| `movile_app/lib/src/app.dart` | Inject service to `AppRouter`; call `refresh()` on auth transitions in `_onAuthStateChanged` | Modify |
| `movile_app/lib/src/data/demo/demo_seed.dart` | Delete | Delete |
| `movile_app/test/data/demo/demo_seed_test.dart` | Delete | Delete |
| `movile_app/test/services/settings/app_settings_controller_test.dart` | Replace `dismissDemoRoute` tests with new API tests + migration test | Modify |
| `movile_app/test/services/official_routes/official_routes_service_test.dart` | Full coverage of refresh + dismiss | Create |
| `movile_app/test/data/repositories/local_draft_repository_test.dart` | Cover new `is_official`/`updated_at` columns and guardrail | Extend |
| `supabase/migrations/<timestamp>_official_routes_policy.sql` | RLS policy + enforce-owner trigger | Create |

---

## Task 1: Add `isOfficial` and `updatedAt` to `RouteTemplate`

**Files:**
- Modify: `packages/splitway_core/lib/src/models/route_template.dart`
- Create or extend: `packages/splitway_core/test/route_template_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/splitway_core/test/route_template_test.dart` (or extend if it exists):

```dart
import 'package:splitway_core/splitway_core.dart';
import 'package:test/test.dart';

void main() {
  RouteTemplate sample({
    bool isOfficial = false,
    DateTime? updatedAt,
  }) {
    return RouteTemplate(
      id: 'r1',
      name: 'X',
      path: const [],
      startFinishGate: GateDefinition(
        left: GeoPoint(latitude: 0, longitude: 0),
        right: GeoPoint(latitude: 0, longitude: 0),
      ),
      sectors: const [],
      difficulty: RouteDifficulty.medium,
      createdAt: DateTime.utc(2026, 1, 1),
      isOfficial: isOfficial,
      updatedAt: updatedAt,
    );
  }

  test('isOfficial defaults to false and updatedAt defaults to null', () {
    final r = RouteTemplate(
      id: 'r1', name: 'X', path: const [],
      startFinishGate: GateDefinition(
        left: GeoPoint(latitude: 0, longitude: 0),
        right: GeoPoint(latitude: 0, longitude: 0),
      ),
      sectors: const [],
      difficulty: RouteDifficulty.medium,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    expect(r.isOfficial, isFalse);
    expect(r.updatedAt, isNull);
  });

  test('copyWith updates isOfficial and updatedAt', () {
    final ts = DateTime.utc(2026, 2, 1);
    final r = sample().copyWith(isOfficial: true, updatedAt: ts);
    expect(r.isOfficial, isTrue);
    expect(r.updatedAt, ts);
  });

  test('toJson/fromJson roundtrip preserves new fields', () {
    final ts = DateTime.utc(2026, 2, 1);
    final original = sample(isOfficial: true, updatedAt: ts);
    final restored = RouteTemplate.fromJson(original.toJson());
    expect(restored.isOfficial, isTrue);
    expect(restored.updatedAt, ts);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/splitway_core && dart test test/route_template_test.dart`
Expected: FAIL — `isOfficial` and `updatedAt` parameters not defined.

- [ ] **Step 3: Add fields to `RouteTemplate`**

In `packages/splitway_core/lib/src/models/route_template.dart`:

```dart
class RouteTemplate {
  const RouteTemplate({
    required this.id,
    required this.name,
    required this.path,
    required this.startFinishGate,
    required this.sectors,
    required this.difficulty,
    required this.createdAt,
    this.description,
    this.locationLabel,
    this.thumbnailUrl,
    this.elevationRangeMeters,
    this.isOfficial = false,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final String? locationLabel;
  final String? thumbnailUrl;
  final List<GeoPoint> path;
  final GateDefinition startFinishGate;
  final List<SectorDefinition> sectors;
  final RouteDifficulty difficulty;
  final DateTime createdAt;
  final double? elevationRangeMeters;
  final bool isOfficial;
  final DateTime? updatedAt;
  // ... isClosed and totalDistanceMeters unchanged
```

Update `copyWith` to accept the two new fields (use the `_sentinel` pattern for `updatedAt` so `null` can be explicitly set):

```dart
RouteTemplate copyWith({
  String? id,
  String? name,
  String? description,
  String? locationLabel,
  Object? thumbnailUrl = _sentinel,
  List<GeoPoint>? path,
  GateDefinition? startFinishGate,
  List<SectorDefinition>? sectors,
  RouteDifficulty? difficulty,
  DateTime? createdAt,
  Object? elevationRangeMeters = _sentinel,
  bool? isOfficial,
  Object? updatedAt = _sentinel,
}) {
  return RouteTemplate(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    locationLabel: locationLabel ?? this.locationLabel,
    thumbnailUrl: thumbnailUrl == _sentinel
        ? this.thumbnailUrl
        : thumbnailUrl as String?,
    path: path ?? this.path,
    startFinishGate: startFinishGate ?? this.startFinishGate,
    sectors: sectors ?? this.sectors,
    difficulty: difficulty ?? this.difficulty,
    createdAt: createdAt ?? this.createdAt,
    elevationRangeMeters: elevationRangeMeters == _sentinel
        ? this.elevationRangeMeters
        : elevationRangeMeters as double?,
    isOfficial: isOfficial ?? this.isOfficial,
    updatedAt: updatedAt == _sentinel
        ? this.updatedAt
        : updatedAt as DateTime?,
  );
}
```

Update `toJson`:

```dart
Map<String, dynamic> toJson() => {
      'id': id,
      'name': name,
      'description': description,
      'locationLabel': locationLabel,
      'thumbnailUrl': thumbnailUrl,
      'path': path.map((p) => p.toJson()).toList(),
      'startFinishGate': startFinishGate.toJson(),
      'sectors': sectors.map((s) => s.toJson()).toList(),
      'difficulty': difficulty.id,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'elevationRangeMeters': elevationRangeMeters,
      'isOfficial': isOfficial,
      'updatedAt': updatedAt?.toUtc().toIso8601String(),
    };
```

Update `fromJson`:

```dart
factory RouteTemplate.fromJson(Map<String, dynamic> json) => RouteTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      locationLabel: json['locationLabel'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      path: (json['path'] as List<dynamic>)
          .map((e) => GeoPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      startFinishGate: GateDefinition.fromJson(
          json['startFinishGate'] as Map<String, dynamic>),
      sectors: (json['sectors'] as List<dynamic>)
          .map((e) => SectorDefinition.fromJson(e as Map<String, dynamic>))
          .toList(),
      difficulty:
          RouteDifficultyX.fromId(json['difficulty'] as String? ?? 'medium'),
      createdAt: DateTime.parse(json['createdAt'] as String),
      elevationRangeMeters:
          (json['elevationRangeMeters'] as num?)?.toDouble(),
      isOfficial: json['isOfficial'] as bool? ?? false,
      updatedAt: json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String),
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/splitway_core && dart test test/route_template_test.dart`
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add packages/splitway_core/lib/src/models/route_template.dart \
        packages/splitway_core/test/route_template_test.dart
git commit -m "feat(core): add isOfficial and updatedAt to RouteTemplate"
```

---

## Task 2: Bump SQLite schema, add `is_official` and `updated_at` columns

**Files:**
- Modify: `movile_app/lib/src/data/local/splitway_local_database.dart`

This task is migration-only — no test. Coverage comes via the repository tests in later tasks.

- [ ] **Step 1: Add the migration block**

In `splitway_local_database.dart`, change `_schemaVersion`:

```dart
static const int _schemaVersion = 10;
```

Add at the end of `_migrate`, after the existing `if (from < 9 && to >= 9)` block:

```dart
if (from < 10 && to >= 10) {
  await db.execute(
    'ALTER TABLE route_templates ADD COLUMN is_official INTEGER NOT NULL DEFAULT 0',
  );
  await db.execute(
    'ALTER TABLE route_templates ADD COLUMN updated_at INTEGER',
  );
}
```

- [ ] **Step 2: Sanity check — run existing repository tests**

Run: `cd movile_app && flutter test test/data/repositories/`
Expected: PASS — existing tests still green; the new columns have safe defaults and are not read yet.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/data/local/splitway_local_database.dart
git commit -m "feat(db): bump schema to v10, add is_official and updated_at columns"
```

---

## Task 3: Update `LocalDraftRepository` for new columns

**Files:**
- Modify: `movile_app/lib/src/data/repositories/local_draft_repository.dart`
- Extend: `movile_app/test/data/repositories/local_draft_repository_test.dart`

If the test file does not exist yet, create it with a `setUp` that opens an in-memory database; the rest of this task assumes you can add `test(...)` blocks.

- [ ] **Step 1: Write the failing tests**

Add to `movile_app/test/data/repositories/local_draft_repository_test.dart`:

```dart
test('saveRouteTemplate persists isOfficial and updatedAt', () async {
  final repo = LocalDraftRepository(db);
  repo.userId = 'user-1';
  final ts = DateTime.utc(2026, 5, 1);
  final route = makeRoute(id: 'r1', isOfficial: false, updatedAt: ts);
  await repo.saveRouteTemplate(route);
  final loaded = await repo.getRouteTemplate('r1');
  expect(loaded!.isOfficial, isFalse);
  expect(loaded.updatedAt, ts);
});

test('saveRouteTemplate allows owner_id NULL only for official routes',
    () async {
  final repo = LocalDraftRepository(db);
  // No userId set → simulates anonymous / cold-start writes
  final official = makeRoute(id: 'official-1', isOfficial: true);
  await repo.saveRouteTemplate(official);
  expect(await repo.getRouteTemplate('official-1'), isNotNull);

  // Non-official write with no userId must be rejected by the assert
  final userRoute = makeRoute(id: 'user-1', isOfficial: false);
  expect(
    () => repo.saveRouteTemplate(userRoute),
    throwsA(isA<AssertionError>()),
  );
});

test('clearUserData keeps all is_official=1 routes', () async {
  final repo = LocalDraftRepository(db);
  await repo.saveRouteTemplate(
      makeRoute(id: 'off-1', isOfficial: true));
  await repo.saveRouteTemplate(
      makeRoute(id: 'off-2', isOfficial: true));
  repo.userId = 'user-1';
  await repo.saveRouteTemplate(
      makeRoute(id: 'user-route', isOfficial: false));

  await repo.clearUserData();

  repo.userId = null;
  final remaining = await repo.getAllRoutes();
  final ids = remaining.map((r) => r.id).toSet();
  expect(ids, {'off-1', 'off-2'});
});

test('purgeLegacyPublicRoutes removes orphan NULL-owner non-official routes',
    () async {
  // Insert a legacy orphan directly (bypassing the guardrail).
  await db.raw.insert('route_templates', {
    'id': 'legacy-orphan',
    'name': 'Old Demo',
    'description': null,
    'path_json': '[]',
    'start_finish_gate_json':
        '{"left":{"latitude":0,"longitude":0},"right":{"latitude":0,"longitude":0}}',
    'difficulty': 'medium',
    'created_at': 0,
    'location_label': null,
    'owner_id': null,
    'thumbnail_url': null,
    'elevation_range_m': null,
    'is_official': 0,
    'updated_at': null,
  });
  final repo = LocalDraftRepository(db);
  await repo.saveRouteTemplate(
      makeRoute(id: 'official-keep', isOfficial: true));

  await repo.purgeLegacyPublicRoutes();

  final remaining = await repo.getAllRoutes();
  final ids = remaining.map((r) => r.id).toSet();
  expect(ids, {'official-keep'});
});
```

Add a helper:

```dart
RouteTemplate makeRoute({
  required String id,
  bool isOfficial = false,
  DateTime? updatedAt,
}) {
  return RouteTemplate(
    id: id,
    name: 'Route $id',
    path: const [],
    startFinishGate: GateDefinition(
      left: GeoPoint(latitude: 0, longitude: 0),
      right: GeoPoint(latitude: 0, longitude: 0),
    ),
    sectors: const [],
    difficulty: RouteDifficulty.medium,
    createdAt: DateTime.utc(2026, 1, 1),
    isOfficial: isOfficial,
    updatedAt: updatedAt,
  );
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd movile_app && flutter test test/data/repositories/local_draft_repository_test.dart`
Expected: FAIL — `is_official` and `updated_at` not read/written by repo; `clearUserData` still uses `demo-espana`.

- [ ] **Step 3: Update `LocalDraftRepository`**

Remove the constant `_activeDemoId` (line 506). Replace `clearUserData` (lines 513-520):

```dart
/// Deletes all user-owned data (routes, sessions, free rides and their
/// telemetry) from the local database. Every route marked `is_official = 1`
/// is preserved (the official catalog is shared between anon and any
/// signed-in user). Called on login/logout to avoid stale data from a
/// different account.
Future<void> clearUserData() async {
  await _db.transaction((txn) async {
    await txn.delete('route_templates', where: 'is_official = 0');
    await txn.delete('session_runs', where: '1=1');
    await txn.delete('free_rides', where: '1=1');
  });
  _changes.add(null);
}
```

Replace `purgeLegacyPublicRoutes` (lines 527-534):

```dart
/// Removes any route with `owner_id IS NULL` and `is_official = 0`. These
/// only exist on installs upgraded from before the official-catalog feature,
/// where the seeded demo lived in a public/null-owner row without the
/// is_official flag. Idempotent and safe to call on every cold start.
Future<void> purgeLegacyPublicRoutes() async {
  final deleted = await _db.delete(
    'route_templates',
    where: 'owner_id IS NULL AND is_official = 0',
  );
  if (deleted > 0) _changes.add(null);
}
```

Update the guardrail in `saveRouteTemplate` (lines 42-49):

```dart
// Guardrail: a route can only be persisted with `owner_id IS NULL` if
// it is marked is_official. Anything else (a user route saved while the
// session silently expired, a pull that raced with a sign-out, etc.)
// would become an orphan public-looking route on the next start.
if (_userId == null && !route.isOfficial) {
  assert(
    false,
    'Refusing to save route ${route.id} with NULL owner_id '
    '(only is_official routes may be public). Caller must set userId first.',
  );
  return;
}
```

Add `is_official` and `updated_at` to the `fields` map (after `elevation_range_m`):

```dart
final fields = {
  'id': route.id,
  'name': route.name,
  'description': route.description,
  'path_json': jsonEncode(route.path.map((p) => p.toJson()).toList()),
  'start_finish_gate_json':
      jsonEncode(route.startFinishGate.toJson()),
  'difficulty': route.difficulty.id,
  'created_at': route.createdAt.toUtc().millisecondsSinceEpoch,
  'location_label': route.locationLabel,
  'owner_id': route.isOfficial ? null : _userId,
  'thumbnail_url': route.thumbnailUrl,
  'elevation_range_m': route.elevationRangeMeters,
  'is_official': route.isOfficial ? 1 : 0,
  'updated_at': route.updatedAt?.toUtc().millisecondsSinceEpoch,
};
```

Update `_readRoute` (after `elevationRangeMeters`):

```dart
return RouteTemplate(
  id: routeId,
  name: row['name']! as String,
  description: row['description'] as String?,
  path: pathJson
      .map((e) => GeoPoint.fromJson(e as Map<String, dynamic>))
      .toList(),
  startFinishGate: GateDefinition.fromJson(gateJson),
  sectors: sectors,
  difficulty: RouteDifficultyX.fromId(row['difficulty']! as String),
  createdAt: DateTime.fromMillisecondsSinceEpoch(
    row['created_at']! as int,
    isUtc: true,
  ).toLocal(),
  locationLabel: row['location_label'] as String?,
  thumbnailUrl: row['thumbnail_url'] as String?,
  elevationRangeMeters: (row['elevation_range_m'] as num?)?.toDouble(),
  isOfficial: ((row['is_official'] as int?) ?? 0) == 1,
  updatedAt: row['updated_at'] == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          row['updated_at']! as int,
          isUtc: true,
        ).toLocal(),
);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd movile_app && flutter test test/data/repositories/local_draft_repository_test.dart`
Expected: PASS — 4 new tests + existing ones.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/data/repositories/local_draft_repository.dart \
        movile_app/test/data/repositories/local_draft_repository_test.dart
git commit -m "feat(repo): generalize demo handling to is_official flag"
```

---

## Task 4: Update `SupabaseRepository` for `is_official` and add `fetchOfficialRoutes`

**Files:**
- Modify: `movile_app/lib/src/data/repositories/supabase_repository.dart`

There is no test harness yet for `SupabaseRepository` (it requires a live client). Coverage comes from the service tests in Task 6, which inject a fake repo. No test in this task.

- [ ] **Step 1: Update `upsertRoute` to include `is_official`**

In `supabase_repository.dart`, modify the `.upsert({...})` call inside `upsertRoute` to add the flag (the trigger on the DB side enforces ownership):

```dart
await logSupabase('upsertRoute', () => _client.from('route_templates').upsert({
  'id': route.id,
  'owner_id': _uid,
  'name': route.name,
  'description': route.description,
  'path_json': route.path.map((p) => p.toJson()).toList(),
  'start_finish_gate_json': route.startFinishGate.toJson(),
  'difficulty': route.difficulty.id,
  'location_label': route.locationLabel,
  'created_at': route.createdAt.toUtc().toIso8601String(),
  'updated_at': DateTime.now().toUtc().toIso8601String(),
  'thumbnail_url': route.thumbnailUrl,
  'elevation_range_m': route.elevationRangeMeters,
  'is_official': route.isOfficial,
}));
```

- [ ] **Step 2: Update `_parseRoute` to read `is_official` and `updated_at`**

Find the `_parseRoute` method (private helper used by `fetchAllRoutes`) and ensure it reads:

```dart
isOfficial: (row['is_official'] as bool?) ?? false,
updatedAt: row['updated_at'] == null
    ? null
    : DateTime.parse(row['updated_at'] as String),
```

- [ ] **Step 3: Add `fetchOfficialRoutes`**

Below `fetchAllRoutes`, add:

```dart
/// Fetches every official route (`is_official = true`) along with its
/// sectors. Readable by both anon and authenticated clients via the
/// `official_routes_public_read` RLS policy.
Future<List<RouteTemplate>> fetchOfficialRoutes() async {
  final rows = await logSupabase(
    'fetchOfficialRoutes',
    () => _client
        .from('route_templates')
        .select()
        .eq('is_official', true)
        .order('created_at', ascending: false),
  );

  final routes = <RouteTemplate>[];
  for (final row in rows) {
    final sectorRows = await logSupabase(
      'fetchOfficialRoutes.sectors',
      () => _client
          .from('sectors')
          .select()
          .eq('route_id', row['id'] as String)
          .order('order_index'),
    );
    routes.add(_parseRoute(row, sectorRows));
  }
  return routes;
}
```

Note: `_parseRoute` is the existing private parser. If it currently does not exist (signature differs from what is referenced above), inline an equivalent parser here that maps remote columns to `RouteTemplate.fromJson`-shaped fields, including `isOfficial: true` and `updatedAt` parsed from the row.

- [ ] **Step 4: Make sure existing app compiles**

Run: `cd movile_app && flutter analyze lib/src/data/repositories/supabase_repository.dart`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/data/repositories/supabase_repository.dart
git commit -m "feat(supabase): persist is_official and add fetchOfficialRoutes"
```

---

## Task 5: Update `AppSettingsController` — new dismissal map API + migration

**Files:**
- Modify: `movile_app/lib/src/services/settings/app_settings_controller.dart`
- Modify: `movile_app/test/services/settings/app_settings_controller_test.dart`

- [ ] **Step 1: Write failing tests**

Replace the existing `dismissDemoRoute` tests in `app_settings_controller_test.dart` with:

```dart
test('recordDismissal persists across reloads', () async {
  final ctrl = await AppSettingsController.load();
  await ctrl.recordDismissal('route-1', 1234567890);

  final ctrl2 = await AppSettingsController.load();
  expect(ctrl2.dismissedOfficialRoutes, {'route-1': 1234567890});
});

test('recordDismissal overwrites previous value', () async {
  final ctrl = await AppSettingsController.load();
  await ctrl.recordDismissal('route-1', 100);
  await ctrl.recordDismissal('route-1', 200);
  expect(ctrl.dismissedOfficialRoutes, {'route-1': 200});
});

test('clearDismissal removes the entry', () async {
  final ctrl = await AppSettingsController.load();
  await ctrl.recordDismissal('route-1', 100);
  await ctrl.clearDismissal('route-1');
  expect(ctrl.dismissedOfficialRoutes, isEmpty);
});

test('migrates legacy dismissed_demo_route_ids set to map with epoch values',
    () async {
  SharedPreferences.setMockInitialValues({
    'dismissed_demo_route_ids': ['demo-espana', 'demo-jarama'],
  });
  final ctrl = await AppSettingsController.load();
  expect(ctrl.dismissedOfficialRoutes,
      {'demo-espana': 0, 'demo-jarama': 0});

  // Old key is gone
  final ctrl2 = await AppSettingsController.load();
  expect(ctrl2.dismissedOfficialRoutes,
      {'demo-espana': 0, 'demo-jarama': 0});
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd movile_app && flutter test test/services/settings/app_settings_controller_test.dart`
Expected: FAIL — `recordDismissal`, `clearDismissal`, `dismissedOfficialRoutes` not defined.

- [ ] **Step 3: Update `AppSettingsController`**

Add the new constant and remove the old key constant:

```dart
static const _kDismissedOfficialRoutes = 'dismissed_official_routes';
```

(Remove `_kDismissedDemoIds` at the bottom of the constant block — it is replaced.)

Add a private migration in the constructor — call it after the existing field initializations:

```dart
AppSettingsController._(this._prefs) {
  // ... existing field assignments ...
  _remoteLogsEnabled = _prefs.getBool(_kRemoteLogsEnabled) ?? true;
  _maybeMigrateLegacyDismissals();
}

void _maybeMigrateLegacyDismissals() {
  const legacyKey = 'dismissed_demo_route_ids';
  if (!_prefs.containsKey(legacyKey)) return;
  final legacy = _prefs.getStringList(legacyKey) ?? const [];
  final migrated = <String, int>{
    for (final id in legacy) id: 0,
  };
  _prefs.setString(_kDismissedOfficialRoutes, jsonEncode(migrated));
  _prefs.remove(legacyKey);
}
```

Add the new API (replace the old `dismissedDemoIds` getter and `dismissDemoRoute` method):

```dart
Map<String, int> get dismissedOfficialRoutes {
  final raw = _prefs.getString(_kDismissedOfficialRoutes);
  if (raw == null || raw.isEmpty) return const {};
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
}

Future<void> recordDismissal(String routeId, int updatedAtMillis) async {
  final current = Map<String, int>.from(dismissedOfficialRoutes);
  current[routeId] = updatedAtMillis;
  await _prefs.setString(_kDismissedOfficialRoutes, jsonEncode(current));
}

Future<void> clearDismissal(String routeId) async {
  final current = Map<String, int>.from(dismissedOfficialRoutes);
  if (current.remove(routeId) == null) return;
  await _prefs.setString(_kDismissedOfficialRoutes, jsonEncode(current));
}
```

Add the import at the top:

```dart
import 'dart:convert';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd movile_app && flutter test test/services/settings/app_settings_controller_test.dart`
Expected: PASS — 4 new tests; old `dismissDemoRoute` tests are gone.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/services/settings/app_settings_controller.dart \
        movile_app/test/services/settings/app_settings_controller_test.dart
git commit -m "feat(settings): replace dismissedDemoIds with map keyed by updated_at"
```

---

## Task 6: Create `OfficialRoutesService`

**Files:**
- Create: `movile_app/lib/src/services/official_routes/official_routes_service.dart`
- Create: `movile_app/test/services/official_routes/official_routes_service_test.dart`

- [ ] **Step 1: Write failing tests**

Create `movile_app/test/services/official_routes/official_routes_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:movile_app/src/data/local/splitway_local_database.dart';
import 'package:movile_app/src/data/repositories/local_draft_repository.dart';
import 'package:movile_app/src/services/official_routes/official_routes_service.dart';
import 'package:movile_app/src/services/settings/app_settings_controller.dart';

class _FakeRemote implements OfficialRoutesRemote {
  _FakeRemote(this.routes);
  List<RouteTemplate> routes;
  int callCount = 0;
  @override
  Future<List<RouteTemplate>> fetchOfficialRoutes() async {
    callCount++;
    return routes;
  }
}

RouteTemplate official(String id, DateTime updatedAt) => RouteTemplate(
      id: id,
      name: 'Official $id',
      path: const [],
      startFinishGate: GateDefinition(
        left: GeoPoint(latitude: 0, longitude: 0),
        right: GeoPoint(latitude: 0, longitude: 0),
      ),
      sectors: const [],
      difficulty: RouteDifficulty.medium,
      createdAt: DateTime.utc(2026, 1, 1),
      isOfficial: true,
      updatedAt: updatedAt,
    );

void main() {
  late SplitwayLocalDatabase database;
  late LocalDraftRepository repo;
  late AppSettingsController settings;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    database = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    repo = LocalDraftRepository(database);
    settings = await AppSettingsController.load();
  });

  tearDown(() async {
    await repo.dispose();
    await database.close();
  });

  test('refresh inserts new remote official routes locally', () async {
    final remote = _FakeRemote([official('r1', DateTime.utc(2026, 5, 1))]);
    final svc = OfficialRoutesService(
        remote: remote, local: repo, settings: settings);
    await svc.refresh();
    final loaded = await repo.getRouteTemplate('r1');
    expect(loaded, isNotNull);
    expect(loaded!.isOfficial, isTrue);
    expect(loaded.updatedAt, DateTime.utc(2026, 5, 1));
  });

  test('refresh prunes local official routes absent in remote', () async {
    await repo.saveRouteTemplate(
        official('stale', DateTime.utc(2026, 4, 1)));
    final remote = _FakeRemote([]);
    final svc = OfficialRoutesService(
        remote: remote, local: repo, settings: settings);
    await svc.refresh();
    expect(await repo.getRouteTemplate('stale'), isNull);
  });

  test('refresh applies dismissal: remote updated > dismissedAt -> reappears',
      () async {
    final dismissedAt =
        DateTime.utc(2026, 4, 1).millisecondsSinceEpoch;
    await settings.recordDismissal('r1', dismissedAt);

    final remote = _FakeRemote([official('r1', DateTime.utc(2026, 5, 1))]);
    final svc = OfficialRoutesService(
        remote: remote, local: repo, settings: settings);
    await svc.refresh();

    expect(await repo.getRouteTemplate('r1'), isNotNull);
    expect(settings.dismissedOfficialRoutes.containsKey('r1'), isFalse);
  });

  test('refresh applies dismissal: remote updated <= dismissedAt -> removed',
      () async {
    final updatedAt = DateTime.utc(2026, 4, 1);
    await settings.recordDismissal('r1', updatedAt.millisecondsSinceEpoch);

    final remote = _FakeRemote([official('r1', updatedAt)]);
    final svc = OfficialRoutesService(
        remote: remote, local: repo, settings: settings);
    await svc.refresh();

    expect(await repo.getRouteTemplate('r1'), isNull);
    expect(settings.dismissedOfficialRoutes['r1'],
        updatedAt.millisecondsSinceEpoch);
  });

  test('dismiss records updated_at and deletes from local', () async {
    final updatedAt = DateTime.utc(2026, 5, 1);
    await repo.saveRouteTemplate(official('r1', updatedAt));

    final svc = OfficialRoutesService(
        remote: _FakeRemote([]), local: repo, settings: settings);
    await svc.dismiss('r1');

    expect(await repo.getRouteTemplate('r1'), isNull);
    expect(settings.dismissedOfficialRoutes['r1'],
        updatedAt.millisecondsSinceEpoch);
  });

  test('refresh swallows fetch errors and leaves local unchanged', () async {
    await repo.saveRouteTemplate(
        official('r1', DateTime.utc(2026, 4, 1)));

    final svc = OfficialRoutesService(
      remote: _ThrowingRemote(),
      local: repo,
      settings: settings,
    );
    await svc.refresh(); // must not throw

    expect(await repo.getRouteTemplate('r1'), isNotNull);
  });

  test('concurrent refresh calls coalesce — only one fetch in flight',
      () async {
    final remote = _FakeRemote([]);
    final svc = OfficialRoutesService(
        remote: remote, local: repo, settings: settings);
    await Future.wait([svc.refresh(), svc.refresh(), svc.refresh()]);
    expect(remote.callCount, 1);
  });
}

class _ThrowingRemote implements OfficialRoutesRemote {
  @override
  Future<List<RouteTemplate>> fetchOfficialRoutes() async {
    throw StateError('boom');
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd movile_app && flutter test test/services/official_routes/official_routes_service_test.dart`
Expected: FAIL — `OfficialRoutesService` and `OfficialRoutesRemote` not defined.

- [ ] **Step 3: Implement the service**

Create `movile_app/lib/src/services/official_routes/official_routes_service.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:splitway_core/splitway_core.dart';

import '../../data/repositories/local_draft_repository.dart';
import '../logging/app_logger.dart';
import '../settings/app_settings_controller.dart';

/// Thin interface over the remote source so the service can be tested
/// without a live Supabase client. Implemented by [SupabaseRepository].
abstract class OfficialRoutesRemote {
  Future<List<RouteTemplate>> fetchOfficialRoutes();
}

/// Owns the lifecycle of the official-routes catalog on the device.
///
/// Pulls the catalog from Supabase (anon-readable), reconciles it with the
/// local SQLite store, and applies per-device dismissal state stored in
/// [AppSettingsController.dismissedOfficialRoutes].
class OfficialRoutesService extends ChangeNotifier {
  OfficialRoutesService({
    required OfficialRoutesRemote remote,
    required LocalDraftRepository local,
    required AppSettingsController settings,
  })  : _remote = remote,
        _local = local,
        _settings = settings;

  final OfficialRoutesRemote _remote;
  final LocalDraftRepository _local;
  final AppSettingsController _settings;

  Future<void>? _inFlight;

  /// Fetches the official catalog from Supabase and reconciles the local
  /// store. Concurrent calls share the same in-flight future. Network/Supabase
  /// errors are logged and swallowed.
  Future<void> refresh() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final fut = _doRefresh();
    _inFlight = fut;
    return fut.whenComplete(() => _inFlight = null);
  }

  Future<void> _doRefresh() async {
    final List<RouteTemplate> remote;
    try {
      remote = await _remote.fetchOfficialRoutes();
    } catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'official_routes',
        'fetch failed; keeping local state',
        error: e,
        stackTrace: st,
      );
      return;
    }

    final remoteById = {for (final r in remote) r.id: r};

    // Upsert remote rows locally.
    for (final r in remote) {
      await _local.saveRouteTemplate(r);
    }

    // Prune local officials that no longer exist remotely.
    final localRoutes = await _local.getAllRoutes();
    for (final r in localRoutes) {
      if (!r.isOfficial) continue;
      if (remoteById.containsKey(r.id)) continue;
      await _local.deleteRoute(r.id);
    }

    // Apply dismissals: if remote.updated_at > dismissedAt, the user
    // should see the route again; otherwise keep it dismissed.
    final dismissals = _settings.dismissedOfficialRoutes;
    for (final entry in dismissals.entries) {
      final id = entry.key;
      final dismissedAt = entry.value;
      final remoteRoute = remoteById[id];
      if (remoteRoute == null) continue; // not in catalog anymore — leave entry
      final remoteMillis = remoteRoute.updatedAt?.millisecondsSinceEpoch ?? 0;
      if (remoteMillis > dismissedAt) {
        await _settings.clearDismissal(id);
      } else {
        await _local.deleteRoute(id);
      }
    }
    notifyListeners();
  }

  /// Dismisses an official route on this device. Records its current
  /// `updated_at` in settings and deletes the row locally. A future refresh
  /// with a newer `updated_at` will bring it back.
  Future<void> dismiss(String routeId) async {
    final route = await _local.getRouteTemplate(routeId);
    final stamp = route?.updatedAt?.millisecondsSinceEpoch ?? 0;
    await _settings.recordDismissal(routeId, stamp);
    await _local.deleteRoute(routeId);
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd movile_app && flutter test test/services/official_routes/official_routes_service_test.dart`
Expected: PASS — 7 tests.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/services/official_routes/ \
        movile_app/test/services/official_routes/
git commit -m "feat(official-routes): add catalog service with refresh and dismiss"
```

---

## Task 7: Make `SupabaseRepository` implement `OfficialRoutesRemote`

**Files:**
- Modify: `movile_app/lib/src/data/repositories/supabase_repository.dart`

- [ ] **Step 1: Update class signature and import**

In `supabase_repository.dart`, add the import:

```dart
import '../../services/official_routes/official_routes_service.dart';
```

Change the class declaration:

```dart
class SupabaseRepository implements OfficialRoutesRemote {
```

(`fetchOfficialRoutes` was already added in Task 4 and satisfies the interface.)

- [ ] **Step 2: Verify compilation**

Run: `cd movile_app && flutter analyze lib/src/data/repositories/supabase_repository.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/data/repositories/supabase_repository.dart
git commit -m "refactor(supabase): implement OfficialRoutesRemote interface"
```

---

## Task 8: Generalize `SyncService` to skip every `is_official` route

**Files:**
- Modify: `movile_app/lib/src/services/sync/sync_service.dart`

- [ ] **Step 1: Replace literal `demo-espana` references**

In `_doSync`, replace the push loop's special case (lines around 157-179) — change the literal `route.id == 'demo-espana'` to `route.isOfficial`:

```dart
for (final route in localRoutes) {
  if (route.isOfficial) {
    // Never push official routes; they are owned by Splitway and curated
    // via OfficialRoutesService. Skip thumbnail generation here too —
    // OfficialRoutesService is responsible for the catalog.
    continue;
  }
  final remoteUpdated = remoteRouteTs[route.id];
  final needsPush = remoteUpdated == null ||
      route.createdAt.isAfter(remoteUpdated);
  final needsThumbnail = route.thumbnailUrl == null;
  if (needsPush || needsThumbnail) {
    final updated = await remote.upsertRoute(route);
    pushedRouteIds.add(route.id);
    if (updated.thumbnailUrl != null &&
        updated.thumbnailUrl != route.thumbnailUrl) {
      routesWithNewThumbnails.add(updated);
    }
    transferred++;
  }
}
```

In the reconcile-prune block (lines around 203-209), replace the literal:

```dart
for (final route in localRoutes) {
  if (route.isOfficial) continue;
  if (pushedRouteIds.contains(route.id)) continue;
  if (!remoteRouteTs.containsKey(route.id)) {
    await local.deleteRoute(route.id);
  }
}
```

The pull-from-remote loop already trusts RLS scoping to the current user, so official routes do not arrive in `fetchAllRoutes` for a regular user — no change needed there.

- [ ] **Step 2: Verify existing sync tests still pass**

Run: `cd movile_app && flutter test test/services/sync/`
Expected: PASS — if the tests rely on `demo-espana` literal IDs, update them to use any non-official id; if they did not assert on demo behavior, no changes needed.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/services/sync/sync_service.dart
git commit -m "refactor(sync): skip is_official routes instead of demo-espana literal"
```

---

## Task 9: Wire `OfficialRoutesService` into `SplitwayApp`

**Files:**
- Modify: `movile_app/lib/src/app.dart`
- Modify: `movile_app/lib/main.dart`

The service must share the same `LocalDraftRepository` instance as the rest of the app so that its writes notify the `_changes` stream that drives UI rebuilds. We therefore create it in `_SplitwayAppState.initState` (right after `_repository`), not in `main.dart`.

- [ ] **Step 1: Remove the seed call from `main.dart`**

In `movile_app/lib/main.dart`, remove the imports:

```dart
import 'src/data/demo/demo_seed.dart';
import 'src/services/routing/elevation_service.dart';
```

Replace lines 110-121 (the `DemoSeed.ensureSeeded` + `purgeLegacyPublicRoutes` block) with:

```dart
final seedRepo = LocalDraftRepository(database);
// Remove any leftover orphan demo routes from older builds (null owner_id +
// is_official=0). The official catalog is now hydrated from Supabase by
// OfficialRoutesService inside SplitwayApp.
await seedRepo.purgeLegacyPublicRoutes();
await seedRepo.dispose();
```

(No `OfficialRoutesService` instantiation here — that happens inside `SplitwayApp`.)

- [ ] **Step 2: Add the service to `_SplitwayAppState`**

In `movile_app/lib/src/app.dart`, add the import:

```dart
import 'services/official_routes/official_routes_service.dart';
import 'data/repositories/supabase_repository.dart';
```

Add a field:

```dart
OfficialRoutesService? _officialRoutesService;
```

In `initState`, after `_repository = LocalDraftRepository(widget.database);` and after Supabase is known to be initialized (gate on `widget.config.hasSupabase`), instantiate the service and kick off the cold-start refresh:

```dart
if (widget.config.hasSupabase) {
  final client = Supabase.instance.client;
  _officialRoutesService = OfficialRoutesService(
    remote: SupabaseRepository(client),
    local: _repository,
    settings: widget.settingsController,
  );
  // Fire and forget — must not block the first frame.
  unawaited(_officialRoutesService!.refresh());
}
```

This block must run BEFORE `_AuthService` is wired so the `_onAuthStateChanged` handler (updated in Task 10) can read `_officialRoutesService`.

In `dispose`, add:

```dart
_officialRoutesService?.dispose();
```

- [ ] **Step 3: Verify compilation**

Run: `cd movile_app && flutter analyze lib/main.dart lib/src/app.dart`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/main.dart movile_app/lib/src/app.dart
git commit -m "feat(app): instantiate OfficialRoutesService and fetch on cold start"
```

---

## Task 10: Trigger refresh on auth transitions

**Files:**
- Modify: `movile_app/lib/src/app.dart`

- [ ] **Step 1: Hook the service into `_onAuthStateChanged`**

In `movile_app/lib/src/app.dart`, locate `_onAuthStateChanged`. In the login branch, after the inner `proceed()` lambda runs (so after `clearUserData` completes when it does fire), refresh the catalog:

```dart
void proceed() {
  _repository.userId = newUid;
  _createSyncService(client);
  _router.syncService = _syncService;
  if (_profileService == null && widget.config.hasSupabase) {
    _createProfileService(client);
  }
  // Refresh the official catalog now that we are signed in. The service
  // does its own concurrency guard; if the cold-start refresh is still
  // in flight, this call returns the same future.
  unawaited(_officialRoutesService?.refresh());
}
```

In the sign-out branch (after `_repository.userId = null;` and before `_router.router.go('/routes')`), also kick off a refresh:

```dart
_repository.userId = null;
unawaited(_officialRoutesService?.refresh());
_router.router.go('/routes');
```

- [ ] **Step 2: Verify compilation**

Run: `cd movile_app && flutter analyze lib/src/app.dart`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/app.dart
git commit -m "feat(app): refresh official routes on auth transitions"
```

---

## Task 11: Route the delete flow through `OfficialRoutesService.dismiss`

**Files:**
- Modify: `movile_app/lib/src/features/editor/route_editor_controller.dart`
- Modify: `movile_app/lib/src/routing/app_router.dart`

The controller's existing `onRouteDeleted` callback (wired to `settings.dismissDemoRoute`) is replaced by direct dispatch through `OfficialRoutesService` for official routes.

- [ ] **Step 1: Add `officialRoutesService` to `RouteEditorController`**

In `route_editor_controller.dart`, add the field to the constructor:

```dart
RouteEditorController(
  this._repo, {
  this.syncService,
  this.routingService,
  this.geocodingService,
  this.elevationService,
  String defaultRoutingProfile = 'driving',
  this.officialRoutesService,
}) : _defaultRoutingProfile = defaultRoutingProfile {
  // ...
}

final OfficialRoutesService? officialRoutesService;
```

Add the import:

```dart
import '../../services/official_routes/official_routes_service.dart';
```

Delete the existing `onRouteDeleted` field and its docstring (around lines 38, 66-68).

Update `deleteRoute` (around line 626):

```dart
Future<void> deleteRoute(String id) async {
  // For official routes, dismissal lives in OfficialRoutesService so the
  // route can reappear if Splitway publishes a newer version. Going through
  // the sync service would attempt a remote DELETE that RLS rejects.
  final existing = await _repo.getRouteTemplate(id);
  if (existing != null && existing.isOfficial) {
    if (officialRoutesService != null) {
      await officialRoutesService!.dismiss(id);
    } else {
      await _repo.deleteRoute(id);
    }
  } else if (syncService != null) {
    await syncService!.deleteRoute(id);
  } else {
    await _repo.deleteRoute(id);
  }
  if (_selected?.id == id) {
    _selected = null;
  }
  // ... rest unchanged
}
```

- [ ] **Step 2: Update `AppRouter` wiring**

In `movile_app/lib/src/routing/app_router.dart`, find the `RouteEditorController` instantiation (around line 55-60). Remove `onRouteDeleted: settingsController.dismissDemoRoute` and pass `officialRoutesService` instead. The `AppRouter` constructor needs a new field `officialRoutesService`:

```dart
class AppRouter {
  AppRouter({
    required LocalDraftRepository repository,
    // ...
    this.officialRoutesService,
  }) : // ...
        _routeController = RouteEditorController(
          repository,
          routingService: RoutingService(config: config),
          geocodingService: ForwardGeocodingService(config: config),
          elevationService: ElevationService(),
          defaultRoutingProfile: settingsController.defaultRoutingProfile,
          officialRoutesService: officialRoutesService,
        ),
        // ...

  OfficialRoutesService? officialRoutesService;
  // ...
}
```

- [ ] **Step 3: Pass the service through `SplitwayApp` to `AppRouter`**

In `app.dart`, when constructing `AppRouter`, pass the service (the field is `_officialRoutesService`, created in Task 9):

```dart
_router = AppRouter(
  repository: _repository,
  speedRepository: _speedRepository,
  config: widget.config,
  authService: _authService,
  syncService: _syncService,
  profileService: _profileService,
  garageService: _garageService,
  localeController: widget.localeController,
  settingsController: widget.settingsController,
  refreshListenable: _routerRefresh,
  officialRoutesService: _officialRoutesService,
);
```

- [ ] **Step 4: Verify compilation**

Run: `cd movile_app && flutter analyze lib/src/features/editor/route_editor_controller.dart lib/src/routing/app_router.dart lib/src/app.dart`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/editor/route_editor_controller.dart \
        movile_app/lib/src/routing/app_router.dart \
        movile_app/lib/src/app.dart
git commit -m "feat(editor): dismiss official routes via OfficialRoutesService"
```

---

## Task 12: Pull-to-refresh on the routes screen

**Files:**
- Modify: `movile_app/lib/src/features/editor/route_editor_screen.dart`

The routes list is the primary surface where the official catalog is visible. Adding `RefreshIndicator` gives the user a manual way to trigger a fetch.

- [ ] **Step 1: Locate the scrollable that lists routes**

Open `route_editor_screen.dart` and identify the widget that renders the list/grid of routes (likely a `ListView` or `GridView` inside a tab or body). The exact widget tree differs per build; the change is: wrap that scrollable with `RefreshIndicator`.

- [ ] **Step 2: Add an `OfficialRoutesService` accessor**

The screen reads the service from the controller. Add this near the build method:

```dart
OfficialRoutesService? get _officialRoutesService =>
    widget.controller.officialRoutesService;
```

Add the import:

```dart
import '../../services/official_routes/official_routes_service.dart';
```

- [ ] **Step 3: Wrap the list with `RefreshIndicator`**

Replace the existing scrollable widget tree (e.g. `ListView(...)`) with:

```dart
RefreshIndicator(
  onRefresh: () async {
    final svc = _officialRoutesService;
    if (svc == null) return;
    await svc.refresh();
  },
  child: ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    // ...existing children...
  ),
)
```

If the existing widget is a `GridView` or a `CustomScrollView`, the same pattern applies — just make sure the scrollable inherits `AlwaysScrollableScrollPhysics` so pull works even when the content is short.

- [ ] **Step 4: Run the app smoke test**

Run: `cd movile_app && flutter analyze lib/src/features/editor/route_editor_screen.dart`
Expected: No errors.

If integration tests exist for this screen, run them:

`cd movile_app && flutter test integration_test/app_test.dart`

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/editor/route_editor_screen.dart
git commit -m "feat(routes): add pull-to-refresh that refetches the official catalog"
```

---

## Task 13: Supabase migration — RLS policy + enforce-owner trigger

**Files:**
- Create: `supabase/migrations/<timestamp>_official_routes_policy.sql`

Generate a timestamped migration filename using `npx supabase migration new official_routes_policy` from `supabase/` (or follow the local convention; existing migrations show the format).

The Splitway official-account UUID needs to be looked up once with the Supabase dashboard (or via SQL: `SELECT id FROM auth.users WHERE email = 'splitwayoficial@gmail.com'`). Substitute it for `<UUID_SPLITWAYOFICIAL>` below before applying.

- [ ] **Step 1: Author the migration**

Contents:

```sql
-- Public read for any official route.
CREATE POLICY "official_routes_public_read" ON public.route_templates
  FOR SELECT TO anon, authenticated
  USING (is_official = true);

-- Public read for the sectors of an official route.
CREATE POLICY "official_sectors_public_read" ON public.sectors
  FOR SELECT TO anon, authenticated
  USING (EXISTS (
    SELECT 1 FROM public.route_templates rt
    WHERE rt.id = sectors.route_id AND rt.is_official = true
  ));

-- Safeguard: only the Splitway official account can publish an official
-- route. Any other account attempting to set is_official=true is rejected.
CREATE OR REPLACE FUNCTION public.enforce_official_owner()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.is_official = true
     AND NEW.owner_id <> '<UUID_SPLITWAYOFICIAL>'::uuid THEN
    RAISE EXCEPTION
      'Only the Splitway official account can publish official routes';
  END IF;
  RETURN NEW;
END$$;

DROP TRIGGER IF EXISTS enforce_official_owner_trg ON public.route_templates;
CREATE TRIGGER enforce_official_owner_trg
  BEFORE INSERT OR UPDATE ON public.route_templates
  FOR EACH ROW EXECUTE FUNCTION public.enforce_official_owner();
```

- [ ] **Step 2: Apply locally and verify**

Run: `cd supabase && npx supabase db reset` (in dev) — or `db push` against the linked project.
Expected: Migration applies cleanly.

Manual check with `psql` or the dashboard:

```sql
-- Should return >0 rows when the splitway account has at least one
-- official route published, with anon role:
SET ROLE anon;
SELECT id, name, is_official FROM route_templates WHERE is_official = true;
RESET ROLE;
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/<timestamp>_official_routes_policy.sql
git commit -m "feat(supabase): add official-routes RLS + enforce-owner trigger"
```

---

## Task 14: Delete `DemoSeed` and the legacy test

**Files:**
- Delete: `movile_app/lib/src/data/demo/demo_seed.dart`
- Delete: `movile_app/test/data/demo/demo_seed_test.dart`

- [ ] **Step 1: Confirm there are no remaining references**

Run: `cd movile_app && grep -r "DemoSeed\|demo-espana" lib/ test/ integration_test/`
Expected: Only matches inside `widget_test.dart`, `integration_test/app_test.dart`, or historic plans. Any code reference must be removed in the appropriate task above before continuing. (If `widget_test.dart` or `app_test.dart` still imports DemoSeed or asserts on `demo-espana`, replace those assertions with a call that exercises `OfficialRoutesService` against an injected fake remote, or simply remove the assertion.)

- [ ] **Step 2: Delete the files**

Run: `rm movile_app/lib/src/data/demo/demo_seed.dart movile_app/test/data/demo/demo_seed_test.dart`

Try to remove the now-empty parent directories (silently — they may still hold other files):

`rmdir movile_app/lib/src/data/demo 2>/dev/null; rmdir movile_app/test/data/demo 2>/dev/null`

- [ ] **Step 3: Run the full test suite**

Run: `cd movile_app && flutter test`
Expected: All green. Any failure points to a lingering reference to the deleted symbols — fix and re-run.

- [ ] **Step 4: Commit**

```bash
git add -u movile_app/lib/src/data/demo/ movile_app/test/data/demo/
git commit -m "chore: remove hardcoded DemoSeed in favor of Supabase catalog"
```

---

## Self-Review Notes

- **Spec coverage**: every section of the spec maps to a task — model fields (T1), local schema (T2), local repo (T3), Supabase repo (T4), settings + migration (T5), service (T6, T7), sync skip (T8), main wiring (T9), auth-transition refresh (T10), dismiss flow (T11), pull-to-refresh (T12), Supabase migration (T13), cleanup (T14).
- **Anon read policy** is scoped to `SELECT` only — INSERT/UPDATE/DELETE rely on existing owner policies, satisfying "todos pueden leerla pero no modificarla".
- **Reappear-on-modify** is exercised in T6 step 1 with the `remote updated > dismissedAt` test.
- **Per-device dismissal** is intentional — no new Supabase table, only `SharedPreferences`. T5 covers the legacy `Set<String>` → `Map<String,int>` migration with epoch fallback so descartes legacy reaparecen tras el primer fetch.
- **`clearUserData` semantics**: the existing `app.dart` only calls it when a *different* user logs in, not on plain signOut. T10 still refreshes on both branches so the catalog reconciles after any auth change, but does not introduce a new `clearUserData` call.
