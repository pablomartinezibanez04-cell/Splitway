# Route Expected Time + History Delta Indicator — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each route stores an estimated "normal" completion time (from Mapbox), shown in the route detail and used in history to display a % faster/slower indicator (green ▼ / red ▲) against the actual run.

**Architecture:** The Directions API response already returned during road-snapping carries a `duration`; we capture and sum it at save time (zero extra requests). Freehand routes (not road-snapped) fall back to a single Map Matching request. The value is stored as `Duration? expectedDuration` on `RouteTemplate`, persisted in SQLite + Supabase, and rendered in the route detail and history screens.

**Tech Stack:** Dart/Flutter, `package:splitway_core` (pure Dart), sqflite (local), Supabase (Postgres RPC), Mapbox Directions + Map Matching APIs.

**Spec:** [docs/superpowers/specs/2026-06-19-route-expected-time-design.md](../specs/2026-06-19-route-expected-time-design.md)

**Test commands:**
- Core: `cd packages/splitway_core && dart test`
- App: `cd movile_app && flutter test`
- Analyze: `cd movile_app && flutter analyze`
- Regenerate l10n: `cd movile_app && flutter gen-l10n`

---

## Task 1: Add `expectedDuration` to `RouteTemplate` (core)

**Files:**
- Modify: `packages/splitway_core/lib/src/models/route_template.dart`
- Test: `packages/splitway_core/test/route_template_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `route_template_test.dart`:

```dart
  test('expectedDuration roundtrips and copyWith clears/sets it', () {
    final r = sample().copyWith(expectedDuration: const Duration(seconds: 90));
    expect(r.expectedDuration, const Duration(seconds: 90));

    final restored = RouteTemplate.fromJson(r.toJson());
    expect(restored.expectedDuration, const Duration(seconds: 90));

    // No-arg copyWith keeps the value; explicit null clears it.
    expect(r.copyWith().expectedDuration, const Duration(seconds: 90));
    expect(r.copyWith(expectedDuration: null).expectedDuration, isNull);
  });

  test('expectedDuration defaults to null', () {
    expect(sample().expectedDuration, isNull);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/splitway_core && dart test test/route_template_test.dart`
Expected: FAIL (`The named parameter 'expectedDuration' isn't defined`).

- [ ] **Step 3: Implement the field**

In `route_template.dart`:

Add to the constructor parameter list (after `this.updatedAt,`):
```dart
    this.expectedDuration,
```

Add the field (after `final DateTime? updatedAt;`):
```dart
  /// Estimated time to complete the route once at normal driving speed,
  /// computed from Mapbox. Null when it could not be computed (offline, no
  /// token, no road match).
  final Duration? expectedDuration;
```

Add to `copyWith` signature (after `Object? updatedAt = _sentinel,`):
```dart
    Object? expectedDuration = _sentinel,
```

Add to the `copyWith` body (after the `updatedAt:` line, inside `return RouteTemplate(`):
```dart
      expectedDuration: expectedDuration == _sentinel
          ? this.expectedDuration
          : expectedDuration as Duration?,
```

Add to `toJson` (after `'updatedAt': ...,`):
```dart
        'expectedDurationMs': expectedDuration?.inMilliseconds,
```

Add to `fromJson` (after `updatedAt: ...,` inside the `RouteTemplate(`):
```dart
        expectedDuration: json['expectedDurationMs'] == null
            ? null
            : Duration(milliseconds: (json['expectedDurationMs'] as num).toInt()),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/splitway_core && dart test test/route_template_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/splitway_core/lib/src/models/route_template.dart packages/splitway_core/test/route_template_test.dart
git commit -m "feat(core): add expectedDuration to RouteTemplate"
```

---

## Task 2: Capture duration from Mapbox in `RoutingService`

**Files:**
- Modify: `movile_app/lib/src/services/routing/routing_service.dart`
- Test: `movile_app/test/services/routing/routing_service_test.dart` (create)

We extract the JSON-parsing logic into pure, testable static methods, and change `snapToRoads` to also return the route `duration`.

- [ ] **Step 1: Write the failing test**

Create `movile_app/test/services/routing/routing_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/routing/routing_service.dart';

void main() {
  test('parseDirections extracts path and duration', () {
    final data = {
      'routes': [
        {
          'duration': 73.6,
          'geometry': {
            'coordinates': [
              [-3.70, 40.41],
              [-3.69, 40.42],
            ]
          }
        }
      ]
    };
    final result = RoutingService.parseDirections(data);
    expect(result, isNotNull);
    expect(result!.path.length, 2);
    expect(result.duration, const Duration(milliseconds: 73600));
  });

  test('parseDirections returns null when no routes', () {
    expect(RoutingService.parseDirections({'routes': []}), isNull);
  });

  test('parseMatching sums matching durations when code Ok', () {
    final data = {
      'code': 'Ok',
      'matchings': [
        {'duration': 30.0, 'confidence': 0.9},
        {'duration': 12.5, 'confidence': 0.8},
      ],
    };
    expect(RoutingService.parseMatching(data), const Duration(milliseconds: 42500));
  });

  test('parseMatching returns null when code not Ok', () {
    expect(RoutingService.parseMatching({'code': 'NoMatch', 'matchings': []}), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd movile_app && flutter test test/services/routing/routing_service_test.dart`
Expected: FAIL (`parseDirections`/`SnapResult` not defined).

- [ ] **Step 3: Implement `SnapResult`, parse helpers, and wire them in**

In `routing_service.dart`, add at top-level (after the imports, before `class RoutingService`):

```dart
/// Road-snapped geometry plus the Mapbox-estimated travel time for it.
class SnapResult {
  const SnapResult({required this.path, this.duration});
  final List<GeoPoint> path;
  final Duration? duration;
}
```

Change `snapToRoads` return type and its parsing. Replace the signature line
`Future<List<GeoPoint>?> snapToRoads(` with `Future<SnapResult?> snapToRoads(`.
Replace the success block (the part that builds `geometry` and returns the list,
lines ~66-79) with:

```dart
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return parseDirections(data);
```

Add these static methods inside `RoutingService` (e.g. after `snapToRoads`):

```dart
  /// Parses a Mapbox Directions response into a [SnapResult]. Returns null
  /// when no route is present.
  static SnapResult? parseDirections(Map<String, dynamic> data) {
    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;
    final geometry = routes[0]['geometry']['coordinates'] as List;
    final path = geometry
        .map((c) => GeoPoint(
              latitude: (c[1] as num).toDouble(),
              longitude: (c[0] as num).toDouble(),
            ))
        .toList();
    final durSec = (routes[0]['duration'] as num?)?.toDouble();
    return SnapResult(
      path: path,
      duration: durSec == null
          ? null
          : Duration(milliseconds: (durSec * 1000).round()),
    );
  }

  /// Parses a Mapbox Map Matching response into a total [Duration], summing
  /// every matching's duration. Returns null on a non-Ok code or empty match.
  static Duration? parseMatching(Map<String, dynamic> data) {
    if (data['code'] != 'Ok') return null;
    final matchings = data['matchings'] as List?;
    if (matchings == null || matchings.isEmpty) return null;
    var totalSec = 0.0;
    for (final m in matchings) {
      final d = ((m as Map)['duration'] as num?)?.toDouble();
      if (d != null) totalSec += d;
    }
    if (totalSec <= 0) return null;
    return Duration(milliseconds: (totalSec * 1000).round());
  }

  /// Calls the Map Matching API to estimate the travel time along [path].
  /// Returns null on any failure. [path] is capped to 100 coordinates (the
  /// Map Matching limit) via [_sample].
  Future<Duration?> matchDuration(
    List<GeoPoint> path, {
    String profile = 'driving',
  }) async {
    if (path.length < 2) return null;
    final sampled = _sample(path, 100);
    final coords =
        sampled.map((p) => '${p.longitude},${p.latitude}').join(';');
    final uri = Uri.parse(
      '$_base/matching/v5/mapbox/$profile/$coords'
      '?geometries=geojson&overview=full&access_token=$_token',
    );
    try {
      final response = await logHttp(
        'mapbox',
        uri,
        () => http.get(uri).timeout(const Duration(seconds: 10)),
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return parseMatching(data);
    } catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'mapbox',
        'RoutingService.matchDuration failed',
        error: e,
        stackTrace: st,
        context: {'url': uri.toString()},
      );
      return null;
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd movile_app && flutter test test/services/routing/routing_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/services/routing/routing_service.dart movile_app/test/services/routing/routing_service_test.dart
git commit -m "feat: capture Directions duration + add Map Matching to RoutingService"
```

---

## Task 3: Update `snapToRoads` callsites + compute duration in `saveDraft`

**Files:**
- Modify: `movile_app/lib/src/features/editor/route_editor_controller.dart`

`snapToRoads` now returns `SnapResult?`; two callsites use the geometry, and
`saveDraft` additionally accumulates the duration.

- [ ] **Step 1: Fix the live-snap callsite**

In `_snapPath()` (~line 472), replace:
```dart
    final snapped = await routingService!.snapToRoads(waypoints, profile: _routingProfile);

    if (_snapGeneration != generation) return;

    _snapping = false;
    if (snapped != null && snapped.length >= 2) {
```
with:
```dart
    final result = await routingService!.snapToRoads(waypoints, profile: _routingProfile);
    final snapped = result?.path;

    if (_snapGeneration != generation) return;

    _snapping = false;
    if (snapped != null && snapped.length >= 2) {
```

- [ ] **Step 2: Accumulate duration in `saveDraft`**

In `saveDraft()`, before the `for (final seg in _segments)` loop (~line 499), add:
```dart
    var expectedTotal = Duration.zero;
    var expectedComplete = true;
```

Inside the loop, the `SnappedSegment` case currently does:
```dart
            final snapped = await routingService!.snapToRoads(effective, profile: _routingProfile);
            _snapping = false;
            notifyListeners();
            pathParts.add(snapped ?? effective);
```
Replace with:
```dart
            final result = await routingService!.snapToRoads(effective, profile: _routingProfile);
            _snapping = false;
            notifyListeners();
            pathParts.add(result?.path ?? effective);
            if (result?.duration != null) {
              expectedTotal += result!.duration!;
            } else {
              expectedComplete = false;
            }
```
In the same `SnappedSegment` case, the `else` branch (no routingService / <2 pts)
adds `effective` without a duration — mark incomplete. Change:
```dart
          } else {
            pathParts.add(effective);
          }
```
to:
```dart
          } else {
            pathParts.add(effective);
            expectedComplete = false;
          }
```
In the `FreehandSegment` case, after adding its points, mark incomplete by adding
`expectedComplete = false;` at the end of that case branch.

- [ ] **Step 3: Resolve the final expected duration (with Map Matching fallback)**

After `finalPath` is fully assembled and validated (`if (finalPath.length < 2) return null;`, ~line 534) and before the `RouteTemplate route = ...` construction, add:
```dart
    Duration? expectedDuration;
    if (expectedComplete && expectedTotal > Duration.zero) {
      expectedDuration = expectedTotal;
    } else if (routingService != null) {
      expectedDuration =
          await routingService!.matchDuration(finalPath, profile: _routingProfile);
    }
```

In the `RouteTemplate(` constructor, add the field (after `elevationRangeMeters: elevationRange,`):
```dart
      expectedDuration: expectedDuration,
```

- [ ] **Step 4: Verify it compiles**

Run: `cd movile_app && flutter analyze lib/src/features/editor/route_editor_controller.dart lib/src/services/routing/routing_service.dart`
Expected: No errors.

- [ ] **Step 5: Run the controller tests**

Run: `cd movile_app && flutter test test/features/editor/route_editor_controller_test.dart`
Expected: PASS (the test passes `routingService: null`, so the freehand-fallback branch is skipped and `expectedDuration` stays null).

- [ ] **Step 6: Commit**

```bash
git add movile_app/lib/src/features/editor/route_editor_controller.dart
git commit -m "feat: compute route expected duration on save"
```

---

## Task 4: Persist `expectedDuration` in SQLite

**Files:**
- Modify: `movile_app/lib/src/data/local/splitway_local_database.dart`
- Modify: `movile_app/lib/src/data/repositories/local_draft_repository.dart`

- [ ] **Step 1: Bump schema version + add migration**

In `splitway_local_database.dart`, change:
```dart
  static const int _schemaVersion = 12;
```
to:
```dart
  static const int _schemaVersion = 13;
```

In `_migrate`, after the `if (from < 12 && to >= 12) { ... }` block, add:
```dart
    if (from < 13 && to >= 13) {
      await db.execute(
        'ALTER TABLE route_templates ADD COLUMN expected_duration_ms INTEGER',
      );
    }
```

- [ ] **Step 2: Write on save**

In `local_draft_repository.dart`, in `saveRouteTemplate`'s `fields` map (after `'elevation_range_m': route.elevationRangeMeters,`), add:
```dart
        'expected_duration_ms': route.expectedDuration?.inMilliseconds,
```

- [ ] **Step 3: Read on load**

In `local_draft_repository.dart`, in the `RouteTemplate(...)` construction (after `elevationRangeMeters: (row['elevation_range_m'] as num?)?.toDouble(),`), add:
```dart
      expectedDuration: row['expected_duration_ms'] == null
          ? null
          : Duration(milliseconds: (row['expected_duration_ms'] as num).toInt()),
```

- [ ] **Step 4: Add a targeted update method (for lazy recompute)**

In `local_draft_repository.dart`, after `updateRouteTemplateName` (~line 164), add:
```dart
  /// Updates only the cached Mapbox "normal time" for a route.
  Future<void> updateRouteExpectedDuration(String id, Duration? d) async {
    await _db.update(
      'route_templates',
      {'expected_duration_ms': d?.inMilliseconds},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changes.add(null);
  }
```

- [ ] **Step 5: Verify compile**

Run: `cd movile_app && flutter analyze lib/src/data`
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add movile_app/lib/src/data/local/splitway_local_database.dart movile_app/lib/src/data/repositories/local_draft_repository.dart
git commit -m "feat: persist route expectedDuration in SQLite (schema v13)"
```

---

## Task 5: Sync `expectedDuration` to Supabase

**Files:**
- Create: `supabase/migrations/20260619000000_add_route_expected_duration.sql`
- Modify: `movile_app/lib/src/data/repositories/supabase_repository.dart`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260619000000_add_route_expected_duration.sql`:

```sql
-- Add expected_duration_ms to route_templates so the Mapbox-estimated "normal
-- time" of a route is persisted and synced. Mirrors the elevation_range_m
-- pattern. The upsert RPC gains a new parameter, so the old signature is
-- dropped first to avoid leaving two overloads.

ALTER TABLE public.route_templates
  ADD COLUMN IF NOT EXISTS expected_duration_ms bigint;

drop function if exists public.upsert_route_with_sectors(
  uuid, text, text, jsonb, jsonb, text, text, timestamptz, timestamptz,
  text, double precision, boolean, jsonb
);

create or replace function public.upsert_route_with_sectors(
  p_id uuid,
  p_name text,
  p_description text,
  p_path_json jsonb,
  p_start_finish_gate_json jsonb,
  p_difficulty text,
  p_location_label text,
  p_created_at timestamptz,
  p_updated_at timestamptz,
  p_thumbnail_url text,
  p_elevation_range_m double precision,
  p_is_official boolean,
  p_sectors jsonb,
  p_expected_duration_ms bigint
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

  perform 1 from public.route_templates
  where id = p_id and owner_id <> v_uid;
  if found then
    raise exception 'route % is owned by another user', p_id
      using errcode = '42501';
  end if;

  insert into public.route_templates (
    id, owner_id, name, description, path_json, start_finish_gate_json,
    difficulty, location_label, created_at, updated_at, thumbnail_url,
    elevation_range_m, is_official, expected_duration_ms
  ) values (
    p_id, v_uid, p_name, p_description, p_path_json, p_start_finish_gate_json,
    p_difficulty, p_location_label, p_created_at, p_updated_at, p_thumbnail_url,
    p_elevation_range_m, coalesce(p_is_official, false), p_expected_duration_ms
  )
  on conflict (id) do update set
    name                   = excluded.name,
    description            = excluded.description,
    path_json              = excluded.path_json,
    start_finish_gate_json = excluded.start_finish_gate_json,
    difficulty             = excluded.difficulty,
    location_label         = excluded.location_label,
    updated_at             = excluded.updated_at,
    thumbnail_url          = excluded.thumbnail_url,
    elevation_range_m      = excluded.elevation_range_m,
    is_official            = excluded.is_official,
    expected_duration_ms   = excluded.expected_duration_ms
  where route_templates.owner_id = v_uid;

  delete from public.sectors where route_id = p_id;

  if p_sectors is not null and jsonb_array_length(p_sectors) > 0 then
    insert into public.sectors (id, route_id, order_index, label, gate_json)
    select
      (s->>'id')::uuid,
      p_id,
      (s->>'order_index')::int,
      s->>'label',
      s->'gate_json'
    from jsonb_array_elements(p_sectors) as s;
  end if;
end;
$$;

revoke execute on function public.upsert_route_with_sectors(
  uuid, text, text, jsonb, jsonb, text, text, timestamptz, timestamptz,
  text, double precision, boolean, jsonb, bigint
) from public, anon;
grant execute on function public.upsert_route_with_sectors(
  uuid, text, text, jsonb, jsonb, text, text, timestamptz, timestamptz,
  text, double precision, boolean, jsonb, bigint
) to authenticated;
```

- [ ] **Step 2: Pass the new param from the client**

In `supabase_repository.dart`, in the `rpc('upsert_route_with_sectors', params: {...})` call, add (after `'p_is_official': route.isOfficial,`):
```dart
        'p_expected_duration_ms': route.expectedDuration?.inMilliseconds,
```

- [ ] **Step 3: Read it back in `_parseRoute`**

In `supabase_repository.dart`, find `_parseRoute` (the row→`RouteTemplate` mapper, around the `elevationRangeMeters: (row['elevation_range_m'] as num?)?.toDouble(),` line) and add:
```dart
      expectedDuration: row['expected_duration_ms'] == null
          ? null
          : Duration(milliseconds: (row['expected_duration_ms'] as num).toInt()),
```

- [ ] **Step 4: Verify compile**

Run: `cd movile_app && flutter analyze lib/src/data/repositories/supabase_repository.dart`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260619000000_add_route_expected_duration.sql movile_app/lib/src/data/repositories/supabase_repository.dart
git commit -m "feat: sync route expected_duration_ms to Supabase"
```

---

## Task 6: Run-comparison helper + `TimeDeltaIndicator` widget

**Files:**
- Create: `movile_app/lib/src/features/history/run_comparison.dart`
- Create: `movile_app/lib/src/shared/widgets/time_delta_indicator.dart`
- Test: `movile_app/test/features/history/run_comparison_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `movile_app/test/features/history/run_comparison_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/features/history/run_comparison.dart';

void main() {
  test('percent is negative when faster than expected', () {
    final pct = runDeltaPercent(
      expected: const Duration(seconds: 100),
      actual: const Duration(seconds: 80),
    );
    expect(pct, -20.0);
  });

  test('percent is positive when slower than expected', () {
    final pct = runDeltaPercent(
      expected: const Duration(seconds: 100),
      actual: const Duration(seconds: 110),
    );
    expect(pct, 10.0);
  });

  test('percent is null when expected is zero', () {
    expect(
      runDeltaPercent(
          expected: Duration.zero, actual: const Duration(seconds: 1)),
      isNull,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd movile_app && flutter test test/features/history/run_comparison_test.dart`
Expected: FAIL (`run_comparison.dart` not found).

- [ ] **Step 3: Implement the helper**

Create `movile_app/lib/src/features/history/run_comparison.dart`:

```dart
import 'package:splitway_core/splitway_core.dart';

/// The run time to compare against a route's "normal time": the best completed
/// lap on a closed circuit, or the whole-session duration on an open route.
/// Returns null when no comparable time exists.
Duration? representativeRunTime(RouteTemplate route, SessionRun session) {
  if (route.isClosed) return session.bestLap?.duration;
  return session.totalDuration;
}

/// Signed percentage of [actual] vs [expected]: negative = faster (time saved),
/// positive = slower (time lost). Null when [expected] is non-positive.
double? runDeltaPercent({
  required Duration expected,
  required Duration actual,
}) {
  final e = expected.inMilliseconds;
  if (e <= 0) return null;
  final a = actual.inMilliseconds;
  return (a - e) / e * 100.0;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd movile_app && flutter test test/features/history/run_comparison_test.dart`
Expected: PASS.

- [ ] **Step 5: Implement the widget**

Create `movile_app/lib/src/shared/widgets/time_delta_indicator.dart`:

```dart
import 'package:flutter/material.dart';

import '../../features/history/run_comparison.dart';

/// Shows the % faster/slower of a run vs the route's normal time, with a
/// coloured arrow: faster = green ▼ (less time), slower = red ▲ (more time).
/// Renders nothing when the delta can't be computed.
class TimeDeltaIndicator extends StatelessWidget {
  const TimeDeltaIndicator({
    super.key,
    required this.expected,
    required this.actual,
  });

  final Duration expected;
  final Duration actual;

  @override
  Widget build(BuildContext context) {
    final pct = runDeltaPercent(expected: expected, actual: actual);
    if (pct == null) return const SizedBox.shrink();

    final faster = pct < 0;
    final color = faster ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final icon = faster ? Icons.arrow_downward : Icons.arrow_upward;
    final label = '${pct.abs().toStringAsFixed(0)} %';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: Verify compile**

Run: `cd movile_app && flutter analyze lib/src/shared/widgets/time_delta_indicator.dart lib/src/features/history/run_comparison.dart`
Expected: No errors.

- [ ] **Step 7: Commit**

```bash
git add movile_app/lib/src/features/history/run_comparison.dart movile_app/lib/src/shared/widgets/time_delta_indicator.dart movile_app/test/features/history/run_comparison_test.dart
git commit -m "feat: add run-comparison helper and TimeDeltaIndicator widget"
```

---

## Task 7: i18n string for the route detail tile

**Files:**
- Modify: `movile_app/lib/l10n/app_en.arb`
- Modify: `movile_app/lib/l10n/app_es.arb`

- [ ] **Step 1: Add the English string**

In `app_en.arb`, after the `"elevationRangeLabel": "Elevation",` line, add:
```json
  "routeExpectedTimeLabel": "Normal time",
```

- [ ] **Step 2: Add the Spanish string**

In `app_es.arb`, after the `"elevationRangeLabel": "Desnivel",` line, add:
```json
  "routeExpectedTimeLabel": "Tiempo normal",
```

- [ ] **Step 3: Regenerate localizations**

Run: `cd movile_app && flutter gen-l10n`
Expected: No errors; `app_localizations*.dart` now expose `routeExpectedTimeLabel`.

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/l10n/
git commit -m "feat(i18n): add routeExpectedTimeLabel string"
```

---

## Task 8: Show "Tiempo normal" in the route detail + lazy recompute

**Files:**
- Modify: `movile_app/lib/src/features/editor/route_editor_controller.dart`
- Modify: `movile_app/lib/src/features/editor/route_detail_screen.dart`

- [ ] **Step 1: Add a controller method to recompute when missing**

In `route_editor_controller.dart`, after `updateRouteMetadata` (~line 679), add:
```dart
  /// Lazily fills a route's Mapbox "normal time" when it's missing and the
  /// routing service is available (e.g. the route was created offline).
  Future<void> recomputeExpectedDuration(String routeId) async {
    final svc = routingService;
    if (svc == null) return;
    final route = _routes.where((r) => r.id == routeId).firstOrNull;
    if (route == null || route.expectedDuration != null) return;
    if (route.path.length < 2) return;
    final d = await svc.matchDuration(route.path, profile: _defaultRoutingProfile);
    if (d == null) return;
    await _repo.updateRouteExpectedDuration(routeId, d);
    await load();
  }
```

- [ ] **Step 2: Trigger recompute from the detail screen**

In `route_detail_screen.dart`, in `_RouteDetailScreenState.initState` (after `widget.controller.select(widget.route);`), add:
```dart
    widget.controller.recomputeExpectedDuration(widget.route.id);
```

- [ ] **Step 3: Add the "Tiempo normal" bento tile**

In `route_detail_screen.dart`, in the `Wrap` of bento tiles, after the distance `SizedBox`/`BentoTile` block (the one with `Icons.straighten`), add:
```dart
              SizedBox(
                width: _halfWidth(context),
                child: BentoTile(
                  icon: Icons.timer_outlined,
                  label: l.routeExpectedTimeLabel,
                  value: route.expectedDuration == null
                      ? '—'
                      : Formatters.durationHms(route.expectedDuration!),
                ),
              ),
```

- [ ] **Step 4: Verify compile + analyze**

Run: `cd movile_app && flutter analyze lib/src/features/editor`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/editor/route_editor_controller.dart movile_app/lib/src/features/editor/route_detail_screen.dart
git commit -m "feat: show normal time on route detail with lazy recompute"
```

---

## Task 9: Show the delta indicator in history (list tile + session detail)

**Files:**
- Modify: `movile_app/lib/src/features/history/history_screen.dart`

- [ ] **Step 1: Import the helpers**

At the top of `history_screen.dart`, add to the imports block:
```dart
import '../../shared/widgets/time_delta_indicator.dart';
import 'run_comparison.dart';
```

- [ ] **Step 2: Add the indicator to the session list tile**

In `_SessionTile.build`, compute the comparison just before `return Card(`:
```dart
    final route = this.route;
    final expected = route?.expectedDuration;
    final actual = route == null ? null : representativeRunTime(route, session);
```
Then, inside the `subtitle` `Column`'s `children`, after the first `Text(l.historySessionSubtitle(...))`, add:
```dart
            if (expected != null && actual != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${l.routeExpectedTimeLabel}: '
                      '${Formatters.duration(actual, dotSeparator: settingsController.timeFormatDot)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    TimeDeltaIndicator(expected: expected, actual: actual),
                  ],
                ),
              ),
```

- [ ] **Step 3: Show it in the session detail**

In `_SessionDetailScreenState.build`, inside the `ListView`'s `children`, immediately after the `Row(...)` that contains the date/total-time `Column` and the heatmap toggle (the one ending `const SizedBox(height: 12),`), insert a comparison block. Replace `const SizedBox(height: 12),` with:
```dart
                    const SizedBox(height: 12),
                    Builder(builder: (context) {
                      final route = _route;
                      final expected = route?.expectedDuration;
                      final actual = route == null
                          ? null
                          : representativeRunTime(route, _session!);
                      if (expected == null || actual == null) {
                        return const SizedBox.shrink();
                      }
                      final dot =
                          widget.settingsController?.timeFormatDot ?? true;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Text(
                              '${l.routeExpectedTimeLabel}: '
                              '${Formatters.duration(expected, dotSeparator: dot)}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const Spacer(),
                            Text(
                              Formatters.duration(actual, dotSeparator: dot),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(width: 8),
                            TimeDeltaIndicator(
                                expected: expected, actual: actual),
                          ],
                        ),
                      );
                    }),
```

- [ ] **Step 4: Verify compile + analyze + full test suite**

Run: `cd movile_app && flutter analyze`
Expected: No errors.

Run: `cd movile_app && flutter test`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/history/history_screen.dart
git commit -m "feat: show normal-time delta indicator in history"
```

---

## Final verification

- [ ] **Run all tests across both packages**

```bash
cd packages/splitway_core && dart test
cd ../../movile_app && flutter test && flutter analyze
```
Expected: all green, no analyzer errors.

- [ ] **Manual smoke (optional, requires Mapbox token + device/emulator)**
  1. Draw a road-snapped route by tapping points → save → open detail → "Tiempo normal" shows a value.
  2. Run a session on that route → open it in history → the % indicator (green ▼ / red ▲) appears next to the time.
  3. Draw a freehand route → confirm a single Map Matching call fills the time (or stays "—" off-road).
```

---

## Self-review notes

- **Spec coverage:** model field (T1), Mapbox capture + Map Matching fallback (T2–T3), SQLite persistence + migration (T4), Supabase sync (T5), comparison + indicator (T6), route-detail display + lazy recompute (T7–T8), history display (T9). All spec sections mapped.
- **Type consistency:** `SnapResult.path`/`.duration`, `RoutingService.parseDirections`/`parseMatching`/`matchDuration`, `representativeRunTime`/`runDeltaPercent`, `RouteTemplate.expectedDuration`, `updateRouteExpectedDuration`, column `expected_duration_ms`, RPC param `p_expected_duration_ms` are used consistently across tasks.
- **Edge cases handled:** null routingService, `expected <= 0`, no laps / no totalDuration, freehand-only routes, schema upgrade from v12.
