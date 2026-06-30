# Free Ride Expected Time (Mapbox) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every free ride a Mapbox-computed "normal time" (`expectedDuration`), computed once when the ride finishes, shown in history (list + detail) with the same green/red delta indicator as route sessions, synced to Supabase, and inherited (not recomputed) when the ride is saved as a route.

**Architecture:** Mirror the existing route "expected time" feature ([spec](../specs/2026-06-19-route-expected-time-design.md)). A free ride records a raw GPS path with no road-snapping, so the time comes from **one** Map Matching call (`RoutingService.matchDuration`) on the recorded path at finish, with the Mapbox profile chosen from the selected vehicle type. The value is persisted on `FreeRideRun.expectedDuration` through SQLite + Supabase, displayed via the existing `TimeDeltaIndicator`, and lazily recomputed when the detail screen opens if it was missing (e.g. ride finished offline).

**Tech Stack:** Dart/Flutter, `splitway_core` (pure Dart models), sqflite (local), Supabase (Postgres RPC), Mapbox Map Matching API.

**Reference:** Design spec — [docs/superpowers/specs/2026-06-30-free-ride-expected-time-design.md](../specs/2026-06-30-free-ride-expected-time-design.md).

---

## File Structure

**Create:**
- `packages/splitway_core/test/free_ride_run_test.dart` — copyWith semantics for the new field.
- `movile_app/lib/src/services/routing/routing_profile.dart` — pure `routingProfileForVehicle(VehicleType?)` helper.
- `movile_app/test/services/routing/routing_profile_test.dart` — helper tests.
- `supabase/migrations/20260630000000_add_free_ride_expected_duration.sql` — column + RPC update.

**Modify:**
- `packages/splitway_core/lib/src/models/free_ride_run.dart` — new `expectedDuration` field.
- `movile_app/lib/src/data/local/splitway_local_database.dart` — schema v13→v14 migration.
- `movile_app/lib/src/data/repositories/local_draft_repository.dart` — save/read + `updateFreeRideExpectedDuration`.
- `movile_app/test/data/repositories/local_draft_repository_test.dart` — round-trip + update tests.
- `movile_app/lib/src/features/free_ride/free_ride_controller.dart` — inject `RoutingService`, compute on finish.
- `movile_app/lib/src/features/free_ride/free_ride_screen.dart` — resolve vehicle profile, pass to `finishRecording`.
- `movile_app/lib/src/routing/app_router.dart` — wire `routingService` into controller + `HistoryScreen`.
- `movile_app/lib/src/data/repositories/supabase_repository.dart` — RPC param + parse.
- `movile_app/lib/src/features/history/history_screen.dart` — list tile indicator, detail card + indicator, lazy recompute, threading.

---

## Task 1: Core model — `FreeRideRun.expectedDuration`

**Files:**
- Modify: `packages/splitway_core/lib/src/models/free_ride_run.dart`
- Test: `packages/splitway_core/test/free_ride_run_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `packages/splitway_core/test/free_ride_run_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_core/splitway_core.dart';

void main() {
  FreeRideRun sample({Duration? expectedDuration}) => FreeRideRun(
        id: 'fr-1',
        startedAt: DateTime.utc(2026, 1, 1, 10),
        endedAt: DateTime.utc(2026, 1, 1, 10, 30),
        status: FreeRideStatus.completed,
        points: const [],
        totalDistanceMeters: 1000,
        maxSpeedMps: 20,
        avgSpeedMps: 10,
        expectedDuration: expectedDuration,
      );

  test('expectedDuration defaults to null', () {
    expect(sample().expectedDuration, isNull);
  });

  test('copyWith keeps, sets, and clears expectedDuration', () {
    final r = sample(expectedDuration: const Duration(seconds: 90));
    expect(r.expectedDuration, const Duration(seconds: 90));
    // No-arg copyWith preserves the value.
    expect(r.copyWith().expectedDuration, const Duration(seconds: 90));
    // Explicit non-null sets it.
    expect(
      sample().copyWith(expectedDuration: const Duration(seconds: 45)).expectedDuration,
      const Duration(seconds: 45),
    );
    // Explicit null clears it.
    expect(r.copyWith(expectedDuration: null).expectedDuration, isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/splitway_core && flutter test test/free_ride_run_test.dart`
Expected: FAIL — `No named parameter with the name 'expectedDuration'`.

- [ ] **Step 3: Add the field, constructor param, and copyWith (sentinel pattern)**

In `packages/splitway_core/lib/src/models/free_ride_run.dart`:

Add a sentinel at the top of the file, just after the imports:

```dart
const _sentinel = Object();
```

Add the constructor parameter (after `this.vehicleId,`):

```dart
    this.vehicleId,
    this.expectedDuration,
  });
```

Add the field (after `final String? vehicleId;`):

```dart
  final String? vehicleId;

  /// Estimated time to complete this ride's path at normal driving/riding
  /// speed, computed from Mapbox Map Matching. Null when it could not be
  /// computed (offline, no token, no road match, <2 points).
  final Duration? expectedDuration;
```

In `copyWith`, add the parameter (after `String? vehicleId,`):

```dart
    String? vehicleId,
    Object? expectedDuration = _sentinel,
  }) {
```

And in the returned `FreeRideRun(...)`, add (after `vehicleId: vehicleId ?? this.vehicleId,`):

```dart
      vehicleId: vehicleId ?? this.vehicleId,
      expectedDuration: expectedDuration == _sentinel
          ? this.expectedDuration
          : expectedDuration as Duration?,
    );
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/splitway_core && flutter test test/free_ride_run_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add packages/splitway_core/lib/src/models/free_ride_run.dart packages/splitway_core/test/free_ride_run_test.dart
git commit -m "feat(core): add expectedDuration to FreeRideRun"
```

---

## Task 2: Vehicle → Mapbox profile helper

**Files:**
- Create: `movile_app/lib/src/services/routing/routing_profile.dart`
- Test: `movile_app/test/services/routing/routing_profile_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `movile_app/test/services/routing/routing_profile_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/garage/vehicle.dart';
import 'package:splitway_mobile/src/services/routing/routing_profile.dart';

void main() {
  test('null vehicle (on foot) → walking', () {
    expect(routingProfileForVehicle(null), 'walking');
  });

  test('bicycle → cycling', () {
    expect(routingProfileForVehicle(VehicleType.bicycle), 'cycling');
  });

  test('motorized and other → driving', () {
    expect(routingProfileForVehicle(VehicleType.car), 'driving');
    expect(routingProfileForVehicle(VehicleType.motorcycle), 'driving');
    expect(routingProfileForVehicle(VehicleType.goKart), 'driving');
    expect(routingProfileForVehicle(VehicleType.other), 'driving');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd movile_app && flutter test test/services/routing/routing_profile_test.dart`
Expected: FAIL — target of URI doesn't exist (`routing_profile.dart`).

- [ ] **Step 3: Create the helper**

Create `movile_app/lib/src/services/routing/routing_profile.dart`:

```dart
import '../garage/vehicle.dart';

/// Maps the recording vehicle to the Mapbox routing profile used to estimate a
/// free ride's "normal time": bicycles route over bike paths, on-foot rides use
/// walking, and everything motorized (car/motorcycle/kart) — plus the catch-all
/// `other` — uses driving.
String routingProfileForVehicle(VehicleType? type) => switch (type) {
      null => 'walking',
      VehicleType.bicycle => 'cycling',
      VehicleType.car ||
      VehicleType.motorcycle ||
      VehicleType.goKart ||
      VehicleType.other =>
        'driving',
    };
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd movile_app && flutter test test/services/routing/routing_profile_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/services/routing/routing_profile.dart movile_app/test/services/routing/routing_profile_test.dart
git commit -m "feat: vehicle-to-Mapbox-profile helper for free rides"
```

---

## Task 3: SQLite migration v13 → v14

**Files:**
- Modify: `movile_app/lib/src/data/local/splitway_local_database.dart`

The schema is built purely by incremental migrations from version 0 (there is no separate `_onCreate` table list to update). New databases run every `from < N` block in order, so adding the `from < 14` block covers both upgrades and fresh installs.

- [ ] **Step 1: Bump the schema version**

In `movile_app/lib/src/data/local/splitway_local_database.dart`, change line 16:

```dart
  static const int _schemaVersion = 14;
```

- [ ] **Step 2: Add the migration block**

In `_migrate`, immediately after the `if (from < 13 && to >= 13) { ... }` block (ends ~line 241), add:

```dart
    if (from < 14 && to >= 14) {
      await db.execute(
        'ALTER TABLE free_rides ADD COLUMN expected_duration_ms INTEGER',
      );
    }
```

- [ ] **Step 3: Verify the database still opens cleanly**

Run: `cd movile_app && flutter test test/data/repositories/local_draft_repository_test.dart`
Expected: PASS — all existing tests still pass (the in-memory DB now opens at v14 and the new column exists). This is the build/migration smoke check before Task 4 adds the column round-trip test.

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/data/local/splitway_local_database.dart
git commit -m "feat(db): schema v14 — free_rides.expected_duration_ms column"
```

---

## Task 4: Local repository — persist & update `expectedDuration`

**Files:**
- Modify: `movile_app/lib/src/data/repositories/local_draft_repository.dart`
- Test: `movile_app/test/data/repositories/local_draft_repository_test.dart`

- [ ] **Step 1: Write the failing tests**

In `movile_app/test/data/repositories/local_draft_repository_test.dart`, add a `makeFreeRide` helper near the top of `main()` (after the existing `makeRoute` helper, before the first `test(`):

```dart
  FreeRideRun makeFreeRide({
    required String id,
    Duration? expectedDuration,
  }) {
    return FreeRideRun(
      id: id,
      startedAt: DateTime.utc(2026, 1, 1, 10),
      endedAt: DateTime.utc(2026, 1, 1, 10, 30),
      status: FreeRideStatus.completed,
      points: const [],
      totalDistanceMeters: 1000,
      maxSpeedMps: 20,
      avgSpeedMps: 10,
      expectedDuration: expectedDuration,
    );
  }
```

Then add these tests at the end of `main()` (before the closing `}`):

```dart
  test('saveFreeRideRun round-trips expectedDuration', () async {
    final repo = LocalDraftRepository(db);
    repo.userId = 'user-1';

    await repo.saveFreeRideRun(
        makeFreeRide(id: 'fr-1', expectedDuration: const Duration(seconds: 75)));
    final loaded = await repo.getFreeRideRun('fr-1');
    expect(loaded!.expectedDuration, const Duration(seconds: 75));

    await repo.saveFreeRideRun(makeFreeRide(id: 'fr-2'));
    final loaded2 = await repo.getFreeRideRun('fr-2');
    expect(loaded2!.expectedDuration, isNull);
  });

  test('updateFreeRideExpectedDuration stores value and bumps updated_at',
      () async {
    final repo = LocalDraftRepository(db);
    repo.userId = 'user-1';
    await repo.saveFreeRideRun(makeFreeRide(id: 'fr-1'));

    await repo.updateFreeRideExpectedDuration('fr-1', const Duration(seconds: 90));

    final loaded = await repo.getFreeRideRun('fr-1');
    expect(loaded!.expectedDuration, const Duration(seconds: 90));
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd movile_app && flutter test test/data/repositories/local_draft_repository_test.dart`
Expected: FAIL — `getFreeRideRun(...).expectedDuration` is null (not persisted) and `updateFreeRideExpectedDuration` is undefined.

- [ ] **Step 3: Persist on save**

In `saveFreeRideRun` (~line 362), add the column to the inserted map (after `'vehicle_id': ride.vehicleId,`):

```dart
          'vehicle_id': ride.vehicleId,
          'expected_duration_ms': ride.expectedDuration?.inMilliseconds,
          'owner_id': _userId,
```

- [ ] **Step 4: Read it back**

In `_readFreeRide`, in the returned `FreeRideRun(...)` (~line 501), add after `vehicleId: row['vehicle_id'] as String?,`:

```dart
      vehicleId: row['vehicle_id'] as String?,
      expectedDuration: row['expected_duration_ms'] == null
          ? null
          : Duration(milliseconds: (row['expected_duration_ms'] as num).toInt()),
    );
```

- [ ] **Step 5: Add the lazy-update method**

After the `updateFreeRideMetadata` method (~line 442), add:

```dart
  /// Updates the cached Mapbox "normal time" for a free ride and bumps its
  /// `updated_at` so the next sync's last-write-wins push uploads the value.
  /// Mirrors [updateRouteExpectedDuration] for the open-route case.
  Future<void> updateFreeRideExpectedDuration(String id, Duration? d) async {
    await _db.update(
      'free_rides',
      {
        'expected_duration_ms': d?.inMilliseconds,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _changes.add(null);
  }
```

> Note: `free_rides` already has an `updated_at` column server-side; the local table tracks it implicitly through the sync layer. If the local `free_rides` table has no `updated_at` column, drop that key from the map (keep only `expected_duration_ms`). Verify with the schema in `_migrate` before running — the local free_rides table created in `from < 3` does **not** define `updated_at`, so **use only `expected_duration_ms`**:

```dart
  Future<void> updateFreeRideExpectedDuration(String id, Duration? d) async {
    await _db.update(
      'free_rides',
      {'expected_duration_ms': d?.inMilliseconds},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changes.add(null);
  }
```

Use this second version (no `updated_at`).

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd movile_app && flutter test test/data/repositories/local_draft_repository_test.dart`
Expected: PASS (all, including the 2 new tests).

- [ ] **Step 7: Commit**

```bash
git add movile_app/lib/src/data/repositories/local_draft_repository.dart movile_app/test/data/repositories/local_draft_repository_test.dart
git commit -m "feat(db): persist + update free ride expectedDuration locally"
```

---

## Task 5: Controller — inject `RoutingService`, compute on finish

**Files:**
- Modify: `movile_app/lib/src/features/free_ride/free_ride_controller.dart`

`finishRecording` calls `LocationService` statics and the GPS engine, which need platform channels, so it is not unit-tested here; its parts (`matchDuration`, `copyWith`, repo save) are each covered by their own tests. Verify with `flutter analyze` and the manual run in Task 11's verification.

- [ ] **Step 1: Add the import and field**

In `movile_app/lib/src/features/free_ride/free_ride_controller.dart`, add the import (with the other service imports near the top):

```dart
import '../../services/routing/routing_service.dart';
```

Add the constructor parameter and field. Change the constructor (lines 16-25) to:

```dart
class FreeRideController extends ChangeNotifier {
  FreeRideController(
    this._repo, {
    this.geocodingService,
    this.routingService,
    DeviceHeadingService? headingService,
  }) : _headingService = headingService ?? DeviceHeadingService();

  final LocalDraftRepository _repo;
  final ReverseGeocodingService? geocodingService;
  final RoutingService? routingService;
  final DeviceHeadingService _headingService;
```

- [ ] **Step 2: Compute the expected duration on finish**

In `finishRecording` (~line 263), change the signature and the run-build block. The current block is:

```dart
    final run = raw.copyWith(
      name: _sessionName,
      vehicleId: _selectedVehicleId,
      locationLabel: locationLabel,
    );
    await _repo.saveFreeRideRun(run);
```

Replace with (and add the `routingProfile` parameter to the method signature `Future<FreeRideRun?> finishRecording({String routingProfile = 'driving'}) async {`):

```dart
    var run = raw.copyWith(
      name: _sessionName,
      vehicleId: _selectedVehicleId,
      locationLabel: locationLabel,
    );

    // Mapbox "normal time" for the recorded path. One Map Matching call; any
    // failure (offline, no token, no match, <2 points) leaves it null and the
    // ride is saved anyway. Recomputed lazily when the detail screen opens.
    final svc = routingService;
    if (svc != null && run.points.length >= 2) {
      final d = await svc.matchDuration(run.path, profile: routingProfile);
      if (d != null) {
        run = run.copyWith(expectedDuration: d);
      }
    }

    await _repo.saveFreeRideRun(run);
```

Update the method signature line (~line 263) from:

```dart
  Future<FreeRideRun?> finishRecording() async {
```

to:

```dart
  Future<FreeRideRun?> finishRecording({String routingProfile = 'driving'}) async {
```

- [ ] **Step 3: Verify it analyzes**

Run: `cd movile_app && flutter analyze lib/src/features/free_ride/free_ride_controller.dart`
Expected: No issues (0 errors).

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/features/free_ride/free_ride_controller.dart
git commit -m "feat: compute free ride expectedDuration via Mapbox on finish"
```

---

## Task 6: Free ride screen — pass the vehicle profile to finish

**Files:**
- Modify: `movile_app/lib/src/features/free_ride/free_ride_screen.dart`

- [ ] **Step 1: Add the import**

Add near the other imports at the top of `free_ride_screen.dart`:

```dart
import '../../services/routing/routing_profile.dart';
```

- [ ] **Step 2: Add a selected-vehicle-type getter**

Next to `_selectedVehicleIsMotorized` (~line 187), add:

```dart
  /// Mapbox profile for the currently selected vehicle (null id = on foot).
  String get _selectedRoutingProfile {
    final id = widget.controller.selectedVehicleId;
    if (id == null) return routingProfileForVehicle(null);
    for (final v in widget.garageService?.vehicles ?? const <Vehicle>[]) {
      if (v.id == id) return routingProfileForVehicle(v.type);
    }
    return routingProfileForVehicle(null);
  }
```

- [ ] **Step 3: Pass it at the finish call site**

In the `onFinish` callback (~line 484), change:

```dart
                          await ctrl.finishRecording();
```

to:

```dart
                          await ctrl.finishRecording(
                            routingProfile: _selectedRoutingProfile,
                          );
```

- [ ] **Step 4: Verify it analyzes**

Run: `cd movile_app && flutter analyze lib/src/features/free_ride/free_ride_screen.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/free_ride/free_ride_screen.dart
git commit -m "feat: free ride finish uses vehicle-derived Mapbox profile"
```

---

## Task 7: Wire `RoutingService` into the controller and HistoryScreen

**Files:**
- Modify: `movile_app/lib/src/routing/app_router.dart`

- [ ] **Step 1: Pass `routingService` to the FreeRideController**

In `app_router.dart`, the `_freeRideController` is built at ~line 65:

```dart
        _freeRideController = FreeRideController(
          repository,
          geocodingService: config.hasMapbox
              ? ReverseGeocodingService(accessToken: config.mapboxToken!)
              : null,
        ) {
```

Change it to also pass a routing service:

```dart
        _freeRideController = FreeRideController(
          repository,
          geocodingService: config.hasMapbox
              ? ReverseGeocodingService(accessToken: config.mapboxToken!)
              : null,
          routingService: config.hasMapbox
              ? RoutingService(mapboxToken: config.mapboxToken!)
              : null,
        ) {
```

(`RoutingService` is already imported in this file — it is used for `_editorController` at line 55. If the analyzer reports it missing, add `import '../services/routing/routing_service.dart';`.)

- [ ] **Step 2: Pass `routingService` to HistoryScreen**

In the `/history` `GoRoute` builder (~line 341), add the `routingService` argument:

```dart
                builder: (context, state) => HistoryScreen(
                  repository: repository,
                  config: config,
                  authService: authService,
                  profileService: profileService,
                  garageService: garageService,
                  speedRepository: speedRepository,
                  syncService: syncService,
                  settingsController: settingsController,
                  routingService: config.hasMapbox
                      ? RoutingService(mapboxToken: config.mapboxToken!)
                      : null,
                  initialTab: state.uri.queryParameters['tab'] == 'speed'
                      ? 'speed'
                      : null,
                ),
```

(`HistoryScreen.routingService` is added in Task 9, Step 1. This step will not analyze cleanly until then — commit it together with Task 9, or temporarily skip the HistoryScreen argument and add it in Task 9. Recommended: do Task 7 Step 1 now, and add the HistoryScreen argument as part of Task 9.)

- [ ] **Step 3: Verify it analyzes (controller wiring only)**

Run: `cd movile_app && flutter analyze lib/src/routing/app_router.dart`
Expected: No issues for the FreeRideController change (do not add the HistoryScreen argument until Task 9's param exists).

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/routing/app_router.dart
git commit -m "feat: inject RoutingService into FreeRideController"
```

---

## Task 8: Supabase sync — column + RPC + client mapping

**Files:**
- Create: `supabase/migrations/20260630000000_add_free_ride_expected_duration.sql`
- Modify: `movile_app/lib/src/data/repositories/supabase_repository.dart`

- [ ] **Step 1: Write the SQL migration**

Create `supabase/migrations/20260630000000_add_free_ride_expected_duration.sql`:

```sql
-- Add expected_duration_ms (Mapbox "normal time") to free_rides and thread it
-- through the atomic upsert RPC. Mirrors 20260619000000 for route_templates.
--
-- The live function created by 20260614000001_free_ride_upsert_dedupe.sql has a
-- 13-arg signature (… p_vehicle_id text). Drop it and recreate with a 14th
-- argument p_expected_duration_ms, keeping the BUG-4 owner guard and pinned
-- search_path.

alter table public.free_rides
  add column if not exists expected_duration_ms bigint;

drop function if exists public.upsert_free_ride_with_telemetry(
  text, timestamptz, timestamptz, text,
  double precision, double precision, double precision,
  text, text, text, timestamptz, jsonb, text
);

create function public.upsert_free_ride_with_telemetry(
  p_id text,
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_status text,
  p_total_distance_m double precision,
  p_max_speed_mps double precision,
  p_avg_speed_mps double precision,
  p_name text,
  p_description text,
  p_location_label text,
  p_updated_at timestamptz,
  p_points jsonb,
  p_vehicle_id text default null,
  p_expected_duration_ms bigint default null
) returns void
language plpgsql
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  perform 1 from public.free_rides
  where id = p_id and owner_id <> v_uid;
  if found then
    raise exception 'free ride % is owned by another user', p_id
      using errcode = '42501';
  end if;

  insert into public.free_rides (
    id, owner_id, started_at, ended_at, status,
    total_distance_m, max_speed_mps, avg_speed_mps,
    name, description, location_label, updated_at, vehicle_id,
    expected_duration_ms
  ) values (
    p_id, v_uid, p_started_at, p_ended_at, p_status,
    p_total_distance_m, p_max_speed_mps, p_avg_speed_mps,
    p_name, p_description, p_location_label, p_updated_at,
    p_vehicle_id, p_expected_duration_ms
  )
  on conflict (id) do update set
    started_at           = excluded.started_at,
    ended_at             = excluded.ended_at,
    status               = excluded.status,
    total_distance_m     = excluded.total_distance_m,
    max_speed_mps        = excluded.max_speed_mps,
    avg_speed_mps        = excluded.avg_speed_mps,
    name                 = excluded.name,
    description          = excluded.description,
    location_label       = excluded.location_label,
    updated_at           = excluded.updated_at,
    vehicle_id           = excluded.vehicle_id,
    expected_duration_ms = excluded.expected_duration_ms
  where free_rides.owner_id = v_uid;

  delete from public.free_ride_telemetry
  where free_ride_id = p_id and owner_id = v_uid;

  if p_points is not null and jsonb_array_length(p_points) > 0 then
    insert into public.free_ride_telemetry (
      free_ride_id, owner_id, ts, lat, lng,
      speed_mps, accuracy_m, bearing_deg, altitude_m
    )
    select
      p_id,
      v_uid,
      (pt->>'ts')::timestamptz,
      (pt->>'lat')::double precision,
      (pt->>'lng')::double precision,
      (pt->>'speed_mps')::double precision,
      (pt->>'accuracy_m')::double precision,
      (pt->>'bearing_deg')::double precision,
      (pt->>'altitude_m')::double precision
    from jsonb_array_elements(p_points) as pt;
  end if;
end;
$$;

revoke execute on function public.upsert_free_ride_with_telemetry(
  text, timestamptz, timestamptz, text,
  double precision, double precision, double precision,
  text, text, text, timestamptz, jsonb, text, bigint
) from public, anon;
grant execute on function public.upsert_free_ride_with_telemetry(
  text, timestamptz, timestamptz, text,
  double precision, double precision, double precision,
  text, text, text, timestamptz, jsonb, text, bigint
) to authenticated;
```

- [ ] **Step 2: Send the new RPC param from the client**

In `movile_app/lib/src/data/repositories/supabase_repository.dart`, in `upsertFreeRide` (~line 268), add the param after `'p_vehicle_id': ride.vehicleId,`:

```dart
              'p_vehicle_id': ride.vehicleId,
              'p_expected_duration_ms': ride.expectedDuration?.inMilliseconds,
```

- [ ] **Step 3: Parse it back**

In `_parseFreeRide` (~line 466), add after `vehicleId: row['vehicle_id'] as String?,`:

```dart
      vehicleId: row['vehicle_id'] as String?,
      expectedDuration: row['expected_duration_ms'] == null
          ? null
          : Duration(milliseconds: (row['expected_duration_ms'] as num).toInt()),
    );
```

(The free-ride `select()` calls use `select()` with no column list, i.e. `select *`, so the new column is returned automatically — no query change needed.)

- [ ] **Step 4: Verify it analyzes**

Run: `cd movile_app && flutter analyze lib/src/data/repositories/supabase_repository.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260630000000_add_free_ride_expected_duration.sql movile_app/lib/src/data/repositories/supabase_repository.dart
git commit -m "feat(sync): sync free ride expectedDuration to Supabase"
```

---

## Task 9: History list tile — delta indicator + thread routing to detail

**Files:**
- Modify: `movile_app/lib/src/features/history/history_screen.dart`
- Modify: `movile_app/lib/src/routing/app_router.dart` (the HistoryScreen argument deferred from Task 7)

- [ ] **Step 1: Add `routingService` to HistoryScreen**

In `history_screen.dart`, add the import near the others:

```dart
import '../../services/routing/routing_service.dart';
import '../../services/routing/routing_profile.dart';
```

Add the field + constructor param to `HistoryScreen` (after `this.syncService,` ~line 70, and the matching field ~line 80):

```dart
    this.syncService,
    this.routingService,
    this.initialTab,
  });
```
```dart
  final SyncService? syncService;
  final RoutingService? routingService;
```

- [ ] **Step 2: Pass it to `_FreeRideTile`**

In `_buildMainList`, where `_FreeRideTile(...)` is built (~line 675), add `routingService: widget.routingService,`:

```dart
          _FreeRideEntry(:final ride) => _FreeRideTile(
              ride: ride,
              repository: widget.repository,
              config: widget.config,
              garageService: widget.garageService,
              settingsController: widget.settingsController,
              syncService: widget.syncService,
              routingService: widget.routingService,
            ),
```

- [ ] **Step 3: Add the field to `_FreeRideTile` and resolve the profile**

In `_FreeRideTile` (~line 1061), add the constructor param + field:

```dart
    this.garageService,
    this.syncService,
    this.routingService,
  });
```
```dart
  final GarageService? garageService;
  final SyncService? syncService;
  final RoutingService? routingService;

  /// Mapbox profile for this ride's vehicle, used for the lazy recompute on the
  /// detail screen (null vehicle id = on foot → walking).
  String get _routingProfile {
    final id = ride.vehicleId;
    if (id == null) return routingProfileForVehicle(null);
    final v = garageService?.vehicles.where((v) => v.id == id).firstOrNull;
    return routingProfileForVehicle(v?.type);
  }
```

- [ ] **Step 4: Show the delta indicator in the tile subtitle**

In `_FreeRideTile.build`, inside the `subtitle: Column(children: [ ... ])`, after the vehicle/on-foot row block (just before the closing `],` of the children list, ~line 1156), add:

```dart
            Builder(builder: (context) {
              final expected = ride.expectedDuration;
              final actual = ride.totalDuration;
              if (expected == null || actual == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${l.routeExpectedTimeLabel}: '
                      '${Formatters.duration(expected, dotSeparator: settingsController.timeFormatDot)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    TimeDeltaIndicator(expected: expected, actual: actual),
                  ],
                ),
              );
            }),
```

- [ ] **Step 5: Pass `routingService` + profile into `FreeRideDetailScreen` from the tile**

In `_FreeRideTile.build`, the `onTap` builds `FreeRideDetailScreen` (~line 1161). Add the two arguments:

```dart
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => FreeRideDetailScreen(
                rideId: ride.id,
                repository: repository,
                config: config,
                settingsController: settingsController,
                syncService: syncService,
                routingService: routingService,
                routingProfile: _routingProfile,
              ),
            )),
```

- [ ] **Step 6: Add the deferred HistoryScreen argument in app_router**

Apply Task 7, Step 2 now (add `routingService: config.hasMapbox ? RoutingService(mapboxToken: config.mapboxToken!) : null,` to the `HistoryScreen(...)` builder in `app_router.dart`).

- [ ] **Step 7: Verify analyze (FreeRideDetailScreen params land in Task 10)**

`FreeRideDetailScreen.routingService` / `.routingProfile` are added in Task 10. Run analyze after Task 10 for a clean tree. For now:

Run: `cd movile_app && flutter analyze lib/src/features/history/history_screen.dart`
Expected: Only errors about the not-yet-added `FreeRideDetailScreen` named params (`routingService`, `routingProfile`) — resolved by Task 10. No other errors.

- [ ] **Step 8: Commit**

```bash
git add movile_app/lib/src/features/history/history_screen.dart movile_app/lib/src/routing/app_router.dart
git commit -m "feat(history): free ride delta indicator + thread routing to detail"
```

---

## Task 10: Free ride detail — expected-time card, indicator, lazy recompute

**Files:**
- Modify: `movile_app/lib/src/features/history/history_screen.dart`

- [ ] **Step 1: Add `routingService` + `routingProfile` to FreeRideDetailScreen**

In `FreeRideDetailScreen` (~line 1174), add the constructor params + fields (after `this.syncService,`):

```dart
    this.syncService,
    this.routingService,
    this.routingProfile = 'driving',
  });

  final String rideId;
  final LocalDraftRepository repository;
  final AppSettingsController? settingsController;
  final AppConfig config;
  final SyncService? syncService;
  final RoutingService? routingService;
  final String routingProfile;
```

(Keep the existing fields; just add the two new ones. `RoutingService` is imported in Task 9 Step 1.)

- [ ] **Step 2: Lazy recompute in `_load`**

Replace `_FreeRideDetailScreenState._load` (~line 1205) with:

```dart
  Future<void> _load() async {
    final ride = await widget.repository.getFreeRideRun(widget.rideId);
    if (!mounted) return;
    setState(() {
      _ride = ride;
      _loading = false;
    });

    // Lazily compute the Mapbox "normal time" when it is missing (e.g. the ride
    // finished offline) and we now have a routing service. Persist + refresh.
    final svc = widget.routingService;
    if (ride != null &&
        ride.expectedDuration == null &&
        svc != null &&
        ride.points.length >= 2) {
      final d = await svc.matchDuration(ride.path, profile: widget.routingProfile);
      if (d == null || !mounted) return;
      await widget.repository.updateFreeRideExpectedDuration(ride.id, d);
      final refreshed = await widget.repository.getFreeRideRun(widget.rideId);
      if (!mounted) return;
      setState(() => _ride = refreshed);
    }
  }
```

- [ ] **Step 3: Show the normal time + indicator in the summary row**

In `_FreeRideSummaryRow.build` (~line 1360), the method already computes `final duration = ride.totalDuration;`. After the `secondaryEntries` block (the `if (secondaryEntries.isNotEmpty) ...[ ... ]` closes ~line 1423, before the `Column`'s closing `],`), add the normal-time comparison as a new child:

Locate the end of the outer `Column(children: [ ... ])` in `_FreeRideSummaryRow`. Add, as the last child before `]`:

```dart
        if (ride.expectedDuration != null && duration != null) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${l.routeExpectedTimeLabel}: '
                '${Formatters.duration(ride.expectedDuration!, dotSeparator: settingsController?.timeFormatDot ?? true)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(width: 8),
              TimeDeltaIndicator(
                expected: ride.expectedDuration!,
                actual: duration,
              ),
            ],
          ),
        ],
```

- [ ] **Step 4: Verify the whole app analyzes**

Run: `cd movile_app && flutter analyze`
Expected: No issues found (the deferred params from Tasks 7/9 now resolve).

- [ ] **Step 5: Run the full mobile test suite**

Run: `cd movile_app && flutter test`
Expected: PASS (all tests, including the new ones).

- [ ] **Step 6: Commit**

```bash
git add movile_app/lib/src/features/history/history_screen.dart
git commit -m "feat(history): free ride detail normal-time card + lazy recompute"
```

---

## Task 11: Inherit `expectedDuration` when saving a free ride as a route

**Files:**
- Modify: `movile_app/lib/src/features/free_ride/free_ride_controller.dart`

- [ ] **Step 1: Pass the stored value into the new RouteTemplate**

In `saveAsRoute` (~line 328), the `RouteTemplate(...)` is constructed. Add `expectedDuration: run.expectedDuration,` after `elevationRangeMeters: run.elevationRangeMeters,`:

```dart
      createdAt: DateTime.now(),
      locationLabel: resolvedLocation,
      elevationRangeMeters: run.elevationRangeMeters,
      expectedDuration: run.expectedDuration,
    );
```

This reuses the already-computed value (no extra Mapbox call); because the new route is born with a non-null `expectedDuration`, `RouteDetailScreen.recomputeExpectedDuration` will early-return and not recompute. If the ride's value is null (finished offline, never reopened), the route is created with null and `RouteDetailScreen` recomputes it lazily like any route — no regression.

- [ ] **Step 2: Verify it analyzes**

Run: `cd movile_app && flutter analyze lib/src/features/free_ride/free_ride_controller.dart`
Expected: No issues.

- [ ] **Step 3: Manual verification (end-to-end)**

Run the app (`cd movile_app && flutter run`) with a Mapbox token configured:
1. Record a short free ride with a car vehicle selected; finish it.
2. Open History → the free ride tile shows "Tiempo normal: …" with a green/red delta chip.
3. Open the free ride detail → the normal-time row + delta indicator appear.
4. From the free ride, "Save as route" → open the new route's detail → "Tiempo normal" matches the ride's value (no recompute flicker).

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/features/free_ride/free_ride_controller.dart
git commit -m "feat: inherit expectedDuration when saving a free ride as a route"
```

---

## Final verification

- [ ] **Run the full suites**

```bash
cd packages/splitway_core && flutter test
cd movile_app && flutter analyze && flutter test
```

Expected: All green, no analyzer issues.

- [ ] **Deploy the Supabase migration** (per the project's normal migration flow, e.g. `supabase db push` against the target environment) so the RPC and column exist before clients send `p_expected_duration_ms`.
