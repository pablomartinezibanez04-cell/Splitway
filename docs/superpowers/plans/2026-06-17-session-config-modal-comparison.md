# Session Config Modal + Comparison Choice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After pressing "Start recording", show a configuration modal (vehicle, optional name, telemetry source for admins, and a "compete against my best on this route" checkbox) and let that checkbox control whether the session compares against the user's historical best (sector ghosts + reference lap).

**Architecture:** The "ready" screen is slimmed to route picker + button. The button opens a `SessionConfigSheet` (modal bottom sheet) that returns a `SessionConfig`. The session controller gains an `includeHistorical` flag (gates loading of historical sector records and a new historical best-lap) and persists an optional session `name` through the full stack (core model → local sqflite v12 → Supabase RPC). The closed-circuit "best lap" indicator shows the reference lap to beat.

**Tech Stack:** Flutter (Dart), sqflite (local DB), Supabase Postgres (RPC `upsert_session_with_telemetry`), Flutter `gen-l10n` for i18n.

**Conventions for this plan:**
- Mobile app commands run from `movile_app/`: `flutter test <path>`.
- Core package commands run from `packages/splitway_core/`: `dart test <path>`.
- Commit after each task. Use the message shown in the final step.

---

### Task 1: Add optional `name` to core `SessionRun`

**Files:**
- Modify: `packages/splitway_core/lib/src/models/session_run.dart`
- Test: `packages/splitway_core/test/session_run_test.dart`

- [ ] **Step 1: Write the failing test**

Create `packages/splitway_core/test/session_run_test.dart`:

```dart
import 'package:splitway_core/splitway_core.dart';
import 'package:test/test.dart';

SessionRun _base() => SessionRun(
      id: 's1',
      routeTemplateId: 'r1',
      startedAt: DateTime.utc(2026, 1, 1),
      status: SessionStatus.completed,
      points: const [],
      laps: const [],
      sectorSummaries: const [],
      totalDistanceMeters: 0,
      maxSpeedMps: 0,
      avgSpeedMps: 0,
    );

void main() {
  test('name defaults to null and survives copyWith', () {
    final s = _base();
    expect(s.name, isNull);

    final named = s.copyWith(name: 'Morning run');
    expect(named.name, 'Morning run');
    // copyWith without name keeps the existing value.
    expect(named.copyWith(maxSpeedMps: 10).name, 'Morning run');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/session_run_test.dart` (from `packages/splitway_core/`)
Expected: FAIL — `The named parameter 'name' isn't defined` / `s.name` undefined.

- [ ] **Step 3: Add the field**

In `session_run.dart`, add to the constructor parameter list (after `this.vehicleId,`):

```dart
    this.vehicleId,
    this.name,
```

Add the field (after `final String? vehicleId;`):

```dart
  final String? vehicleId;

  /// Optional user-given label for this session. Null/empty when unnamed.
  final String? name;
```

In `copyWith`, add the parameter (after `String? vehicleId,`):

```dart
    String? vehicleId,
    String? name,
```

and the assignment (after `vehicleId: vehicleId ?? this.vehicleId,`):

```dart
      vehicleId: vehicleId ?? this.vehicleId,
      name: name ?? this.name,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dart test test/session_run_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/splitway_core/lib/src/models/session_run.dart packages/splitway_core/test/session_run_test.dart
git commit -m "feat(core): add optional name to SessionRun"
```

---

### Task 2: Persist `name` in the local sqflite database

**Files:**
- Modify: `movile_app/lib/src/data/local/splitway_local_database.dart`
- Modify: `movile_app/lib/src/data/repositories/local_draft_repository.dart:181-222` (saveSessionRun) and `:303-324` (_readSession return)
- Test: `movile_app/test/data/repositories/local_draft_repository_test.dart`

- [ ] **Step 1: Write the failing test**

Append this test inside the existing `main()` in `local_draft_repository_test.dart` (it already has `setUpAll`/`setUp` opening an in-memory DB). Add a small session factory + test:

```dart
  SessionRun makeSession({required String id, String? name}) => SessionRun(
        id: id,
        routeTemplateId: 'r1',
        startedAt: DateTime.utc(2026, 1, 1),
        status: SessionStatus.completed,
        points: const [],
        laps: const [],
        sectorSummaries: const [],
        totalDistanceMeters: 0,
        maxSpeedMps: 0,
        avgSpeedMps: 0,
        name: name,
      );

  test('saveSessionRun round-trips the optional name', () async {
    final repo = LocalDraftRepository(db);
    repo.userId = 'user-1';
    await repo.saveRouteTemplate(makeRoute(id: 'r1'));

    await repo.saveSessionRun(makeSession(id: 's1', name: 'Hot lap'));
    expect((await repo.getSessionRun('s1'))!.name, 'Hot lap');

    await repo.saveSessionRun(makeSession(id: 's2', name: null));
    expect((await repo.getSessionRun('s2'))!.name, isNull);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/local_draft_repository_test.dart` (from `movile_app/`)
Expected: FAIL — `name` not defined on SessionRun is resolved (Task 1), but the column doesn't exist / value is null for `s1` → `expect 'Hot lap'` fails (or a `no such column: name` error).

- [ ] **Step 3a: Add the migration (schema v12)**

In `splitway_local_database.dart`, bump the version constant:

```dart
  static const int _schemaVersion = 12;
```

Add a new migration block at the end of `_migrate`, right after the `from < 11` block:

```dart
    if (from < 12 && to >= 12) {
      await db.execute(
        'ALTER TABLE session_runs ADD COLUMN name TEXT',
      );
    }
```

- [ ] **Step 3b: Write and read the column in the repository**

In `local_draft_repository.dart`, in `saveSessionRun`'s insert map (after `'vehicle_id': session.vehicleId,`):

```dart
          'vehicle_id': session.vehicleId,
          'name': session.name,
```

In `_readSession`'s returned `SessionRun(...)` (after `vehicleId: row['vehicle_id'] as String?,`):

```dart
      vehicleId: row['vehicle_id'] as String?,
      name: row['name'] as String?,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/repositories/local_draft_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/data/local/splitway_local_database.dart movile_app/lib/src/data/repositories/local_draft_repository.dart movile_app/test/data/repositories/local_draft_repository_test.dart
git commit -m "feat: persist session name in local db (schema v12)"
```

---

### Task 3: Persist `name` in Supabase (column + RPC + remote repo)

**Files:**
- Create: `supabase/migrations/20260617000000_session_name.sql`
- Modify: `movile_app/lib/src/data/repositories/supabase_repository.dart:159-184` (upsertSession) and `:421-441` (_parseSession)

> No automated test here — this mirrors the existing `vehicle_id` plumbing exactly. Verification is by code review + the next `flutter test` run compiling.

- [ ] **Step 1: Write the Supabase migration**

Create `supabase/migrations/20260617000000_session_name.sql`. It adds the column and re-creates the RPC with a `p_name` parameter appended (keeping the uuid id params and the BUG-4 owner guard from `20260614000000_session_upsert_uuid_params.sql`):

```sql
-- Add an optional user-given name to sessions and thread it through the
-- session upsert RPC. Mirrors how free_rides.name already works.

alter table public.session_runs
  add column if not exists name text;

-- Drop the current 13-arg overload (uuid ids, with p_vehicle_id) so we can
-- replace it with a 14-arg version that also accepts p_name.
drop function if exists public.upsert_session_with_telemetry(
  uuid, uuid, timestamptz, timestamptz, text, jsonb, jsonb,
  double precision, double precision, double precision, timestamptz, jsonb, text
);

create function public.upsert_session_with_telemetry(
  p_id uuid,
  p_route_id uuid,
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_status text,
  p_lap_summaries jsonb,
  p_sector_summaries jsonb,
  p_total_distance_m double precision,
  p_max_speed_mps double precision,
  p_avg_speed_mps double precision,
  p_updated_at timestamptz,
  p_points jsonb,
  p_vehicle_id text default null,
  p_name text default null
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

  perform 1 from public.session_runs
  where id = p_id and owner_id <> v_uid;
  if found then
    raise exception 'session % is owned by another user', p_id
      using errcode = '42501';
  end if;

  insert into public.session_runs (
    id, owner_id, route_id, started_at, ended_at, status,
    lap_summaries_json, sector_summaries_json,
    total_distance_m, max_speed_mps, avg_speed_mps, updated_at, vehicle_id, name
  ) values (
    p_id, v_uid, p_route_id, p_started_at, p_ended_at, p_status,
    p_lap_summaries, p_sector_summaries,
    p_total_distance_m, p_max_speed_mps, p_avg_speed_mps, p_updated_at,
    p_vehicle_id, p_name
  )
  on conflict (id) do update set
    route_id              = excluded.route_id,
    started_at            = excluded.started_at,
    ended_at              = excluded.ended_at,
    status                = excluded.status,
    lap_summaries_json    = excluded.lap_summaries_json,
    sector_summaries_json = excluded.sector_summaries_json,
    total_distance_m      = excluded.total_distance_m,
    max_speed_mps         = excluded.max_speed_mps,
    avg_speed_mps         = excluded.avg_speed_mps,
    updated_at            = excluded.updated_at,
    vehicle_id            = excluded.vehicle_id,
    name                  = excluded.name
  where session_runs.owner_id = v_uid;

  delete from public.telemetry_points
  where session_id = p_id and owner_id = v_uid;

  if p_points is not null and jsonb_array_length(p_points) > 0 then
    insert into public.telemetry_points (
      session_id, owner_id, ts, lat, lng,
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

revoke execute on function public.upsert_session_with_telemetry(
  uuid, uuid, timestamptz, timestamptz, text, jsonb, jsonb,
  double precision, double precision, double precision, timestamptz, jsonb, text, text
) from public, anon;
grant execute on function public.upsert_session_with_telemetry(
  uuid, uuid, timestamptz, timestamptz, text, jsonb, jsonb,
  double precision, double precision, double precision, timestamptz, jsonb, text, text
) to authenticated;
```

- [ ] **Step 2: Send `p_name` from the client**

In `supabase_repository.dart`, `upsertSession`, add to the `params` map (after `'p_vehicle_id': session.vehicleId,`):

```dart
              'p_vehicle_id': session.vehicleId,
              'p_name': session.name,
```

- [ ] **Step 3: Read `name` back when parsing remote rows**

In `_parseSession`'s returned `SessionRun(...)` (after `vehicleId: row['vehicle_id'] as String?,`):

```dart
      vehicleId: row['vehicle_id'] as String?,
      name: row['name'] as String?,
```

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze lib/src/data/repositories/supabase_repository.dart` (from `movile_app/`)
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260617000000_session_name.sql movile_app/lib/src/data/repositories/supabase_repository.dart
git commit -m "feat: sync session name to Supabase via RPC param"
```

---

### Task 4: Controller — `includeHistorical` flag, historical best-lap, name passthrough

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_controller.dart`
- Test: `movile_app/test/features/session/live_session_controller_test.dart` (create if absent)

The controller currently always loads `_historicalSectorRecords` in `startSession`. We gate that on a new `includeHistorical` param, add a `_historicalBestLap`, and store the session `name` so `finishSession` writes it.

- [ ] **Step 1: Write the failing test**

Create `movile_app/test/features/session/live_session_controller_test.dart`. It uses a real in-memory DB + repository, seeds a route and a prior session with sector summaries and a completed lap, then checks the gating:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/features/session/live_session_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SplitwayLocalDatabase db;
  late LocalDraftRepository repo;

  setUp(() async {
    db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
    repo = LocalDraftRepository(db)..userId = 'user-1';
  });

  tearDown(() async => db.close());

  RouteTemplate route() => RouteTemplate(
        id: 'r1',
        name: 'R1',
        path: const [],
        startFinishGate: GateDefinition(
          left: GeoPoint(latitude: 0, longitude: 0),
          right: GeoPoint(latitude: 0, longitude: 0),
        ),
        sectors: const [],
        difficulty: RouteDifficulty.medium,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  Future<void> seedPriorSession() async {
    await repo.saveRouteTemplate(route());
    await repo.saveSessionRun(SessionRun(
      id: 'prev',
      routeTemplateId: 'r1',
      startedAt: DateTime.utc(2026, 1, 1),
      endedAt: DateTime.utc(2026, 1, 1, 0, 2),
      status: SessionStatus.completed,
      points: const [],
      laps: [
        LapSummary(
          lapNumber: 1,
          duration: const Duration(seconds: 90),
          startedAt: DateTime.utc(2026, 1, 1),
          endedAt: DateTime.utc(2026, 1, 1, 0, 1, 30),
          distanceMeters: 1000,
          avgSpeedMps: 11,
        ),
      ],
      sectorSummaries: [
        SectorSummary(
          sectorId: 'sec-1',
          lapNumber: 1,
          duration: const Duration(seconds: 30),
          startedAt: DateTime.utc(2026, 1, 1),
          endedAt: DateTime.utc(2026, 1, 1, 0, 0, 30),
          distanceMeters: 300,
          avgSpeedMps: 10,
        ),
      ],
      totalDistanceMeters: 1000,
      maxSpeedMps: 12,
      avgSpeedMps: 11,
    ));
  }

  test('includeHistorical=true loads sector records and best lap', () async {
    await seedPriorSession();
    final ctrl = LiveSessionController(repo);
    await ctrl.load();
    ctrl.selectRoute(route());
    await ctrl.startSession(includeHistorical: true);

    expect(ctrl.historicalSectorRecords['sec-1'], const Duration(seconds: 30));
    expect(ctrl.historicalBestLap, const Duration(seconds: 90));
    ctrl.dispose();
  });

  test('includeHistorical=false leaves history empty', () async {
    await seedPriorSession();
    final ctrl = LiveSessionController(repo);
    await ctrl.load();
    ctrl.selectRoute(route());
    await ctrl.startSession(includeHistorical: false);

    expect(ctrl.historicalSectorRecords, isEmpty);
    expect(ctrl.historicalBestLap, isNull);
    ctrl.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/session/live_session_controller_test.dart` (from `movile_app/`)
Expected: FAIL — `startSession` has no `includeHistorical` param / `historicalBestLap` getter undefined.

- [ ] **Step 3a: Add the historical best-lap state + getter**

In `live_session_controller.dart`, after the `_historicalSectorRecords` field/getter block (around line 57-58):

```dart
  Map<String, Duration> get historicalSectorRecords => _historicalSectorRecords;

  /// Best completed-lap duration across the user's previous sessions on the
  /// selected route, or null when the user opted out (includeHistorical=false)
  /// or has no completed laps. Drives the closed-circuit reference lap.
  Duration? _historicalBestLap;
  Duration? get historicalBestLap => _historicalBestLap;

  /// Whether this session competes against the user's historical best on the
  /// route. Set from the config modal when the session starts.
  bool _includeHistorical = true;
  bool get includeHistorical => _includeHistorical;

  /// Optional user-given name for the current session.
  String? _sessionName;
```

- [ ] **Step 3b: Gate loading in `startSession`**

Change the signature of `startSession` (around line 162) to add the new params:

```dart
  Future<void> startSession({
    int distanceFilterMeters = 0,
    bool backgroundActive = false,
    bool useCompassHeading = true,
    bool includeHistorical = true,
    String? name,
  }) async {
    final route = _selected;
    if (route == null) return;
    _distanceFilterMeters = distanceFilterMeters;
    _useCompassHeading = useCompassHeading;
    _includeHistorical = includeHistorical;
    _sessionName = (name != null && name.trim().isNotEmpty) ? name.trim() : null;
    if (includeHistorical) {
      _historicalSectorRecords = await _loadHistoricalSectorRecords(route.id);
      _historicalBestLap = await _loadHistoricalBestLap(route.id);
    } else {
      _historicalSectorRecords = const {};
      _historicalBestLap = null;
    }
    _tracker?.dispose();
```

(Leave the rest of the method body unchanged — i.e. remove only the old
unconditional `_historicalSectorRecords = await _loadHistoricalSectorRecords(route.id);`
line, which is replaced by the block above.)

- [ ] **Step 3c: Add `_loadHistoricalBestLap`**

Immediately after the existing `_loadHistoricalSectorRecords` method (after its closing brace near line 215):

```dart
  /// Minimum completed-lap duration across the user's previous sessions on
  /// [routeId]. Returns null when there is no completed lap. Degrades to null
  /// on error so a failed lookup never blocks starting a session.
  Future<Duration?> _loadHistoricalBestLap(String routeId) async {
    try {
      final sessions = await _repo.getSessionsByRoute(routeId);
      Duration? best;
      for (final session in sessions) {
        final lap = session.bestLap;
        if (lap == null) continue;
        if (best == null || lap.duration < best) best = lap.duration;
      }
      return best;
    } catch (_) {
      return null;
    }
  }
```

- [ ] **Step 3d: Persist the name + reset the new state**

In `finishSession`, change the `copyWith` (around line 368) to include the name:

```dart
    final session = raw.copyWith(vehicleId: _selectedVehicleId, name: _sessionName);
```

In `resetForNewSession`, after `_historicalSectorRecords = const {};` (around line 384):

```dart
    _historicalSectorRecords = const {};
    _historicalBestLap = null;
    _sessionName = null;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/session/live_session_controller_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_controller.dart movile_app/test/features/session/live_session_controller_test.dart
git commit -m "feat: gate historical comparison and best-lap on includeHistorical"
```

---

### Task 5: Localization strings for the config modal

**Files:**
- Modify: `movile_app/lib/l10n/app_en.arb`
- Modify: `movile_app/lib/l10n/app_es.arb`
- Generated (do not hand-edit): `movile_app/lib/l10n/app_localizations*.dart`

- [ ] **Step 1: Add the English keys**

In `app_en.arb`, add these keys (near the other `session*` keys, before the closing brace of the JSON object — keep valid JSON, mind trailing commas):

```json
  "sessionConfigTitle": "Session setup",
  "sessionConfigNameLabel": "Session name (optional)",
  "sessionConfigNameHint": "e.g. Morning practice",
  "sessionConfigIncludeHistoricalTitle": "Compete against my best on this route",
  "sessionConfigIncludeHistoricalSubtitle": "When on, your best previous sector and lap times on this route are shown as the target to beat. When off, you only compete against this session.",
  "sessionConfigStartButton": "Start",
  "sessionReferenceLapLabel": "To beat",
```

- [ ] **Step 2: Add the Spanish keys**

In `app_es.arb`, add the matching keys:

```json
  "sessionConfigTitle": "Configurar sesión",
  "sessionConfigNameLabel": "Nombre de la sesión (opcional)",
  "sessionConfigNameHint": "p. ej. Práctica de la mañana",
  "sessionConfigIncludeHistoricalTitle": "Competir contra mi mejor tiempo en esta ruta",
  "sessionConfigIncludeHistoricalSubtitle": "Si está activo, tus mejores tiempos previos por sector y vuelta en esta ruta se muestran como objetivo a batir. Si está desactivado, solo compites contra esta sesión.",
  "sessionConfigStartButton": "Empezar",
  "sessionReferenceLapLabel": "A batir",
```

- [ ] **Step 3: Regenerate localizations**

Run: `flutter gen-l10n` (from `movile_app/`)
Expected: regenerates `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_es.dart` with the new getters; no errors.

- [ ] **Step 4: Verify the getters exist**

Run: `flutter analyze lib/l10n` (from `movile_app/`)
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/l10n/app_en.arb movile_app/lib/l10n/app_es.arb movile_app/lib/l10n/app_localizations*.dart
git commit -m "i18n: strings for session config modal"
```

---

### Task 6: `SessionConfig` + `SessionConfigSheet` widget

**Files:**
- Create: `movile_app/lib/src/features/session/session_config_sheet.dart`
- Test: `movile_app/test/features/session/session_config_sheet_test.dart`

The sheet is a self-contained widget: it holds local form state and calls
`onStart(SessionConfig)` when the user taps Start. It does NOT start the session
itself (the screen wires that up in Task 7).

- [ ] **Step 1: Write the failing test**

Create `movile_app/test/features/session/session_config_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:splitway_mobile/src/features/session/live_session_controller.dart';
import 'package:splitway_mobile/src/features/session/session_config_sheet.dart';

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('checkbox starts on and Start returns the config', (tester) async {
    SessionConfig? captured;
    await tester.pumpWidget(_host(SessionConfigSheet(
      vehicles: const [],
      initialVehicleId: null,
      isAdmin: false,
      initialSource: TrackingSource.realGps,
      onStart: (c) => captured = c,
    )));
    await tester.pumpAndSettle();

    // Telemetry segmented control is hidden for non-admins.
    expect(find.text('Telemetry source'), findsNothing);

    // Type a name.
    await tester.enterText(find.byType(TextField).first, 'Hot lap');

    // Tap Start.
    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.name, 'Hot lap');
    expect(captured!.includeHistorical, isTrue);
    expect(captured!.source, TrackingSource.realGps);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/session/session_config_sheet_test.dart` (from `movile_app/`)
Expected: FAIL — `session_config_sheet.dart` / `SessionConfigSheet` / `SessionConfig` don't exist.

- [ ] **Step 3: Implement the widget**

Create `movile_app/lib/src/features/session/session_config_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/garage/vehicle.dart';
import '../../shared/widgets/vehicle_picker_tile.dart';
import 'live_session_controller.dart';

/// Configuration gathered from [SessionConfigSheet] before a session starts.
class SessionConfig {
  const SessionConfig({
    required this.vehicleId,
    required this.name,
    required this.source,
    required this.includeHistorical,
  });

  final String? vehicleId;
  final String? name;
  final TrackingSource source;
  final bool includeHistorical;
}

/// Modal sheet shown after the user taps "Start recording". Collects the
/// vehicle, an optional name, the telemetry source (admins only) and whether
/// to compete against the user's historical best on the route. Calls [onStart]
/// with the resulting [SessionConfig]; it does not start the session itself.
class SessionConfigSheet extends StatefulWidget {
  const SessionConfigSheet({
    super.key,
    required this.vehicles,
    required this.initialVehicleId,
    required this.isAdmin,
    required this.initialSource,
    required this.onStart,
  });

  final List<Vehicle> vehicles;
  final String? initialVehicleId;
  final bool isAdmin;
  final TrackingSource initialSource;
  final ValueChanged<SessionConfig> onStart;

  @override
  State<SessionConfigSheet> createState() => _SessionConfigSheetState();
}

class _SessionConfigSheetState extends State<SessionConfigSheet> {
  late String? _vehicleId = widget.initialVehicleId;
  late TrackingSource _source = widget.initialSource;
  final TextEditingController _nameController = TextEditingController();
  bool _includeHistorical = true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(l.sessionConfigTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              if (widget.vehicles.isNotEmpty) ...[
                Text(l.vehiclePickerLabel, style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                VehiclePickerTile(
                  selectedVehicleId: _vehicleId,
                  vehicles: widget.vehicles,
                  onSelected: (id) => setState(() => _vehicleId = id),
                ),
                const SizedBox(height: 16),
              ],
              Text(l.sessionConfigNameLabel, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: l.sessionConfigNameHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.isAdmin) ...[
                Text(l.sessionTelemetrySource,
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<TrackingSource>(
                  segments: [
                    ButtonSegment(
                      value: TrackingSource.simulated,
                      label: Text(l.sessionSourceSimulated),
                      icon: const Icon(Icons.science_outlined),
                    ),
                    ButtonSegment(
                      value: TrackingSource.realGps,
                      label: Text(l.sessionSourceRealGps),
                      icon: const Icon(Icons.gps_fixed),
                    ),
                  ],
                  selected: {_source},
                  onSelectionChanged: (s) =>
                      setState(() => _source = s.first),
                ),
                const SizedBox(height: 16),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeHistorical,
                onChanged: (v) => setState(() => _includeHistorical = v),
                title: Text(l.sessionConfigIncludeHistoricalTitle),
                subtitle: Text(l.sessionConfigIncludeHistoricalSubtitle),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => widget.onStart(SessionConfig(
                  vehicleId: _vehicleId,
                  name: _nameController.text,
                  source: _source,
                  includeHistorical: _includeHistorical,
                )),
                icon: const Icon(Icons.play_arrow),
                label: Text(l.sessionConfigStartButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

> The test taps a checkbox-equivalent only implicitly (default on). `SwitchListTile`
> defaults to `_includeHistorical = true`, satisfying the assertion. If you prefer
> an actual `CheckboxListTile`, swap the widget — keep the default `true`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/session/session_config_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/session/session_config_sheet.dart movile_app/test/features/session/session_config_sheet_test.dart
git commit -m "feat: SessionConfigSheet modal for pre-recording setup"
```

---

### Task 7: Wire the sheet into the session screen + reference lap indicator

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_screen.dart`

This task (a) slims `_buildReady` to route + button, (b) opens the sheet on tap
and runs the existing start flow with the returned `SessionConfig`, and (c)
updates `_LapIndicators` to show the reference lap on closed circuits.

- [ ] **Step 1: Slim `_buildReady` and open the sheet**

In `live_session_screen.dart`, replace the body of `_buildReady` so it keeps only
the title, route picker, preview map, permission banner and the Start button.
Remove the inline telemetry `SegmentedButton`, the `VehiclePickerTile` block and
the trailing source hint `Text`. The Start button's `onPressed` opens the sheet:

```dart
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: ctrl.selected == null
                ? null
                : () => _openConfigAndStart(context, ctrl),
            icon: const Icon(Icons.play_arrow),
            label: Text(l.sessionStartButton),
          ),
```

Add the import near the other feature imports:

```dart
import 'session_config_sheet.dart';
```

- [ ] **Step 2: Add `_openConfigAndStart`**

Add this method to `_LiveSessionScreenState` (it reuses the auth/background flow
that previously lived inline in the button, now driven by the `SessionConfig`):

```dart
  Future<void> _openConfigAndStart(
    BuildContext context, LiveSessionController ctrl) async {
    final config = await showModalBottomSheet<SessionConfig>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SessionConfigSheet(
        vehicles: widget.garageService?.vehicles ?? const [],
        initialVehicleId: ctrl.selectedVehicleId,
        isAdmin: widget.profileService?.isAdmin == true,
        initialSource: ctrl.source,
        onStart: (c) => Navigator.pop(ctx, c),
      ),
    );
    if (config == null || !mounted) return;

    // Apply the picked vehicle + source to the controller.
    ctrl.selectVehicle(config.vehicleId);
    if (widget.profileService?.isAdmin == true) {
      await ctrl.setSource(config.source);
      if (!mounted) return;
    }

    // Auth guard: require login before recording.
    final allowed = await requireAuth(
      context,
      widget.authService,
      message: AppLocalizations.of(context).loginBannerDefault,
    );
    if (!allowed || !mounted) return;

    var hasBackground = false;
    if (ctrl.source == TrackingSource.realGps) {
      final bgPermission = await LocationService.ensureBackgroundPermission();
      hasBackground = bgPermission == LocationPermissionStatus.granted;
      if (!hasBackground && mounted) {
        final action = await _showBackgroundPermissionDialog(context);
        if (!mounted) return;
        if (action == null || action == true) return;
      }
    }

    if (!mounted) return;
    _lastEventCount = 0;
    // ignore: discarded_futures
    ctrl.startSession(
      distanceFilterMeters: widget.settingsController.gpsSamplingDistanceFilter,
      backgroundActive: hasBackground,
      useCompassHeading: !_selectedVehicleIsMotorized,
      includeHistorical: config.includeHistorical,
      name: config.name,
    );
  }
```

- [ ] **Step 3: Pass the reference lap into `_LapIndicators`**

In `_buildRunning`, update the `_LapIndicators(...)` call (around line 585) to pass
the historical best lap and the flag:

```dart
                      _LapIndicators(
                        snapshot: snapshot,
                        isClosed: route.isClosed,
                        settingsController: widget.settingsController,
                        historicalBestLap: ctrl.historicalBestLap,
                        includeHistorical: ctrl.includeHistorical,
                      ),
```

- [ ] **Step 4: Update `_LapIndicators` to show the reference lap**

Replace the `_LapIndicators` class fields/constructor and the closed-circuit
branch so the right indicator shows the reference lap to beat:

Constructor + fields:

```dart
  const _LapIndicators({
    required this.snapshot,
    required this.isClosed,
    required this.settingsController,
    this.historicalBestLap,
    this.includeHistorical = false,
  });

  final TrackingSnapshot snapshot;
  final bool isClosed;
  final AppSettingsController settingsController;
  final Duration? historicalBestLap;
  final bool includeHistorical;
```

Closed-circuit branch (replace the block starting at `final best = snapshot.bestLap;`
through the end of the returned `Row`):

```dart
    final sessionBest = snapshot.bestLap;
    final histBest =
        includeHistorical ? historicalBestLap : null;
    // Reference lap = the best of session + historical (when included).
    Duration? reference = sessionBest;
    if (histBest != null) {
      reference = (sessionBest == null || histBest < sessionBest)
          ? histBest
          : sessionBest;
    }
    // Highlight as a record when the reference is the historical best that the
    // session has not beaten yet (consistent with the purple sector tier).
    final isRecordReference = histBest != null &&
        (sessionBest == null || histBest <= sessionBest);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _BigIndicator(
            label: l.sessionCurrentLapLabel,
            value: elapsed,
            emphasized: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BigIndicator(
            label: isRecordReference
                ? l.sessionReferenceLapLabel
                : l.sessionBestLapLabel,
            value: reference == null
                ? l.sessionNoLapYet
                : Formatters.duration(
                    reference,
                    dotSeparator: settingsController.timeFormatDot,
                  ),
            emphasized: false,
            color: reference == null ? null : theme.colorScheme.primary,
          ),
        ),
      ],
    );
```

- [ ] **Step 5: Run the session-screen tests + analyze**

Run: `flutter test test/features/session/` and `flutter analyze lib/src/features/session/` (from `movile_app/`)
Expected: PASS / no errors. (If a pre-existing widget test asserted on the old
in-screen vehicle/telemetry controls, update it to drive the sheet instead.)

- [ ] **Step 6: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_screen.dart movile_app/test/features/session/
git commit -m "feat: open session config sheet on start; show reference lap"
```

---

### Task 8: Show the session name in history

**Files:**
- Modify: `movile_app/lib/src/features/history/history_screen.dart:861`

- [ ] **Step 1: Prefer the session name in the list tile**

At line 861, change:

```dart
        title: Text(route?.name ?? l.historyDeletedRoute),
```

to:

```dart
        title: Text(
          (session.name != null && session.name!.isNotEmpty)
              ? session.name!
              : (route?.name ?? l.historyDeletedRoute),
        ),
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/src/features/history/history_screen.dart` (from `movile_app/`)
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/features/history/history_screen.dart
git commit -m "feat: show session name in history list"
```

---

### Final verification

- [ ] **Run the full test suites**

Run (from `movile_app/`): `flutter test`
Run (from `packages/splitway_core/`): `dart test`
Expected: all green.

- [ ] **Analyze the whole app**

Run (from `movile_app/`): `flutter analyze`
Expected: no new issues.

---

## Notes on the Supabase migration

The migration in Task 3 must be applied to the remote project (e.g. `supabase db push`
or your normal deploy path) for name sync to work end-to-end. The client sends
`p_name` regardless; an un-migrated backend would reject the call (unknown
parameter), so deploy the migration before shipping the client change.
