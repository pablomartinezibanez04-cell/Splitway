# Open-Route Finish Overlay + Trail Trim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Draw the car's trail only between the first node crossing and the route finish, and replace the instant jump to the results screen (open routes) with a semi-transparent finish overlay showing time and delta vs a reference, plus a live reference target during the run.

**Architecture:** The tracking engine already distinguishes `awaitingStart` → `inLap` → `finished`. We (1) make the engine store telemetry only while `inLap`, exposing it as `recordedPoints`; (2) draw that trimmed list as the live trail and freeze the growing "tip" via a new `recording` flag on `SplitwayMap`; (3) add a `referenceDuration` (previous best total, else route normal time) to the session controller, shown both during the run and in (4) a new `summary` stage that overlays a finish panel on the frozen map for open routes.

**Tech Stack:** Flutter, Dart, `splitway_core` package (pure Dart), Mapbox annotations, flutter_test / package:test, sqflite_common_ffi for repo tests.

---

## File Structure

- `packages/splitway_core/lib/src/tracking/tracking_engine.dart` — trim `_points` to `inLap`; add `recordedPoints` getter.
- `movile_app/lib/src/services/tracking/live_tracking_controller.dart` — add `trailPoints` getter.
- `movile_app/lib/src/shared/widgets/splitway_map.dart` — add `recording` flag; gate the growing tip on it.
- `movile_app/lib/src/features/session/live_session_controller.dart` — `_historicalBestTotal`, `referenceDuration`, `LiveSessionStage.summary` routing, `dismissFinishOverlay`.
- `movile_app/lib/src/features/session/live_session_screen.dart` — live trail wiring, `_LapIndicators` reference column, `summary` stage + `_FinishOverlay`.
- `movile_app/lib/l10n/app_en.arb`, `app_es.arb` — 3 new keys.
- Tests: `packages/splitway_core/test/tracking_engine_test.dart`, `movile_app/test/services/tracking/live_tracking_controller_test.dart`, `movile_app/test/features/session/live_session_controller_test.dart`, `movile_app/test/features/session/live_session_screen_finish_overlay_test.dart` (new).

---

## Task 1: Engine stores only in-route telemetry

**Files:**
- Modify: `packages/splitway_core/lib/src/tracking/tracking_engine.dart`
- Test: `packages/splitway_core/test/tracking_engine_test.dart`

- [ ] **Step 1: Write the failing test**

Add inside the existing `group('open route', ...)` block (the group that defines `buildOpenRoute()`), after the last test in that group:

```dart
    test('recordedPoints excludes pre-start and post-finish telemetry',
        () async {
      final route = buildOpenRoute();
      final base = DateTime.parse('2026-04-29T10:00:00Z');
      final engine = TrackingEngine(
          route: route, sessionId: 'open-trim', clock: () => base);

      engine.start();
      // Pre-start: ingested while awaitingStart — must NOT be recorded.
      engine.ingest(_p(-0.0005, 0, base));
      // Cross start gate (opens inLap).
      engine.ingest(_p(0.0005, 0.0008, base.add(const Duration(seconds: 1))));
      // Mid-route point — recorded.
      engine.ingest(_p(0.0015, 0.0008, base.add(const Duration(seconds: 4))));
      // Reach finish (≤20 m of last path point) — this point is recorded,
      // then the engine finishes.
      engine.ingest(_p(0.002, 0.00005, base.add(const Duration(seconds: 7))));
      // Post-finish point — engine is finished, must NOT be recorded.
      engine.ingest(_p(0.003, 0.0, base.add(const Duration(seconds: 9))));

      final recorded = engine.recordedPoints;
      // No pre-start or post-finish points.
      expect(
        recorded.any((p) => p.location.latitude == -0.0005),
        isFalse,
        reason: 'pre-start point must be excluded',
      );
      expect(
        recorded.any((p) => p.location.latitude == 0.003),
        isFalse,
        reason: 'post-finish point must be excluded',
      );
      // The finish point is the last recorded point.
      expect(recorded.last.location.latitude, 0.002);

      await engine.dispose();
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/splitway_core && dart test test/tracking_engine_test.dart -n "recordedPoints excludes"`
Expected: FAIL — `recordedPoints` is not defined (compile error).

- [ ] **Step 3: Add the getter**

In `tracking_engine.dart`, right after the existing `sectorSummaries` getter (the line `List<SectorSummary> get sectorSummaries => List.unmodifiable(_sectorSummaries);`), add:

```dart
  /// Telemetry recorded during the active route — between the first start/finish
  /// crossing (status `inLap`) and the finish. Points ingested before the first
  /// crossing, or after the route finishes, drive crossing detection but are
  /// never stored. This is what the live view and the saved history draw.
  List<TelemetryPoint> get recordedPoints => List.unmodifiable(_points);
```

- [ ] **Step 4: Gate the point recording**

In `tracking_engine.dart`, inside `ingest`, replace the unconditional add:

```dart
    _points.add(point);
```

with:

```dart
    // Only store telemetry that belongs to the active route. While
    // `awaitingStart` (before the first node) and after `finished`, points are
    // still processed for crossing detection / metrics but not stored, so the
    // drawn + saved trail starts at the first node and stops at the finish.
    if (_status == TrackingStatus.inLap) {
      _points.add(point);
    }
```

- [ ] **Step 5: Run the new test + full engine suite**

Run: `cd packages/splitway_core && dart test test/tracking_engine_test.dart`
Expected: PASS — all tests, including the new one. (`totalDistanceMeters`/laps/sectors are unaffected because distance accumulation and crossing detection are unchanged.)

- [ ] **Step 6: Commit**

```bash
git add packages/splitway_core/lib/src/tracking/tracking_engine.dart packages/splitway_core/test/tracking_engine_test.dart
git commit -m "feat(core): store telemetry only during active route (trail trim)"
```

---

## Task 2: Expose trimmed trail from LiveTrackingController

**Files:**
- Modify: `movile_app/lib/src/services/tracking/live_tracking_controller.dart`
- Test: `movile_app/test/services/tracking/live_tracking_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Append a new test in `live_tracking_controller_test.dart`'s `main()` (reuse the existing open-route helper in that file if present; otherwise define a minimal open route inline as below):

```dart
  test('trailPoints exclude points ingested before the first node', () {
    final route = RouteTemplate(
      id: 'r-open',
      name: 'Open',
      path: const [
        GeoPoint(latitude: 40.0, longitude: -3.0),
        GeoPoint(latitude: 40.00018, longitude: -3.0),
        GeoPoint(latitude: 40.00036, longitude: -3.0),
      ],
      startFinishGate: GateDefinition(
        left: GeoPoint(latitude: 40.0, longitude: -3.0001),
        right: GeoPoint(latitude: 40.0, longitude: -2.9999),
      ),
      sectors: const [],
      difficulty: RouteDifficulty.easy,
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final ctrl = LiveTrackingController(route: route)..startSession();
    final base = DateTime(2026, 5, 9, 10);
    TelemetryPoint tp(double lat, DateTime t) => TelemetryPoint(
        timestamp: t, location: GeoPoint(latitude: lat, longitude: -3.0), speedMps: 12);

    // Before crossing the gate.
    ctrl.ingestSimulatedPoint(tp(39.9999, base));
    // Cross the gate (lap begins).
    ctrl.ingestSimulatedPoint(tp(40.00005, base.add(const Duration(seconds: 1))));

    // ingested has both points; trailPoints excludes the pre-start one.
    expect(ctrl.ingested.length, 2);
    expect(ctrl.trailPoints.any((p) => p.location.latitude == 39.9999), isFalse);
  });
```

Ensure the file imports `package:splitway_core/splitway_core.dart` (it already does for the existing tests).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd movile_app && flutter test test/services/tracking/live_tracking_controller_test.dart -n "trailPoints exclude"`
Expected: FAIL — `trailPoints` is not defined.

- [ ] **Step 3: Add the getter**

In `live_tracking_controller.dart`, right after the existing `ingested` getter (`List<TelemetryPoint> get ingested => List.unmodifiable(_ingested);`), add:

```dart
  /// The in-route trail — telemetry recorded between the first node crossing and
  /// the finish. Drives the drawn estela; `ingested` (all points) still drives
  /// the user marker, camera and bearing.
  List<TelemetryPoint> get trailPoints => _engine.recordedPoints;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd movile_app && flutter test test/services/tracking/live_tracking_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/services/tracking/live_tracking_controller.dart movile_app/test/services/tracking/live_tracking_controller_test.dart
git commit -m "feat: expose trimmed trailPoints from LiveTrackingController"
```

---

## Task 3: Add `recording` flag to SplitwayMap (freeze the growing tip)

**Files:**
- Modify: `movile_app/lib/src/shared/widgets/splitway_map.dart`

No unit test: the trail rendering goes through the Mapbox platform channel, which is unavailable in the test environment (the widget falls back to a CustomPaint that ignores the tip). This task is a careful code change verified manually in Task 9 / on device.

- [ ] **Step 1: Add the constructor parameter**

In the `SplitwayMap` constructor parameter list (the `const SplitwayMap({...})` block), add after `this.persistStyle = false,`:

```dart
    this.recording = true,
```

And add the field declaration near `final bool persistStyle;`:

```dart
  /// When false, the recorded trail is drawn fully static and its final segment
  /// does NOT grow toward [userLocation]. The live session sets this false once
  /// the route has finished so the estela freezes at the last in-route point
  /// even if late GPS samples keep updating the user marker. Defaults to true
  /// (every other caller keeps the previous growing-tip behaviour).
  final bool recording;
```

- [ ] **Step 2: Add a `_growsTip` helper and use it**

In `_SplitwayMapState`, replace the existing getter:

```dart
  bool get _hasLivePosition => _animatedUserLocation != null;
```

with:

```dart
  bool get _hasLivePosition => _animatedUserLocation != null;

  /// True while the recorded line's final segment should animate toward the
  /// gliding user marker. False once recording stops, so the trail freezes.
  bool get _growsTip => _animatedUserLocation != null && widget.recording;
```

- [ ] **Step 3: Gate the static/tip split**

In `_renderAnnotationsCore`, change:

```dart
      final staticPoints = _hasLivePosition
          ? tel.sublist(0, tel.length - 1)
          : tel;
```

to:

```dart
      final staticPoints = _growsTip
          ? tel.sublist(0, tel.length - 1)
          : tel;
```

- [ ] **Step 4: Gate the tip annotation**

In `_ensureTelemetryTipCore`, change:

```dart
    final showTip = !useHeatmap && tel.length >= 2 && animated != null;
```

to:

```dart
    final showTip =
        !useHeatmap && tel.length >= 2 && animated != null && widget.recording;
```

- [ ] **Step 5: Re-render when `recording` changes**

In `didUpdateWidget`, add `recording` to the `annotationsChanged` expression. Change the line:

```dart
        oldWidget.finishMarker != widget.finishMarker;
```

to:

```dart
        oldWidget.finishMarker != widget.finishMarker ||
        oldWidget.recording != widget.recording;
```

- [ ] **Step 6: Verify it compiles**

Run: `cd movile_app && flutter analyze lib/src/shared/widgets/splitway_map.dart`
Expected: No new errors.

- [ ] **Step 7: Commit**

```bash
git add movile_app/lib/src/shared/widgets/splitway_map.dart
git commit -m "feat: add recording flag to SplitwayMap to freeze trail tip"
```

---

## Task 4: Wire the trimmed trail into the live map

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_screen.dart` (in `_buildRunning`)

- [ ] **Step 1: Point the live map at the trail and pass `recording`**

In `_buildRunning`, find the `SplitwayMap(...)` call inside the top `Positioned`. Change:

```dart
            telemetry: tracker.ingested,
```

to:

```dart
            // Estela = solo el tramo de ruta (primer nodo → final). El marcador
            // y la cámara siguen usando ingested.last (posición real).
            telemetry: tracker.trailPoints,
```

Then add, right after the `persistStyle: true,` line in that same `SplitwayMap(...)`:

```dart
            recording: tracker.snapshot.status == TrackingStatus.inLap,
```

- [ ] **Step 2: Verify it compiles**

Run: `cd movile_app && flutter analyze lib/src/features/session/live_session_screen.dart`
Expected: No new errors. (`TrackingStatus` is exported by `splitway_core`, already imported.)

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_screen.dart
git commit -m "feat: draw only the in-route trail in the live session map"
```

---

## Task 5: Add l10n keys for the overlay + live target

**Files:**
- Modify: `movile_app/lib/l10n/app_en.arb`, `movile_app/lib/l10n/app_es.arb`

- [ ] **Step 1: Add the English keys**

In `app_en.arb`, after the `"sessionElapsedLabel": "Time",` line, add:

```json
  "sessionTargetLabel": "Target",
  "sessionFinishedOverlayTitle": "Route finished",
  "sessionContinueButton": "Continue",
```

- [ ] **Step 2: Add the Spanish keys**

In `app_es.arb`, after the `"sessionElapsedLabel": "Tiempo",` line, add:

```json
  "sessionTargetLabel": "Objetivo",
  "sessionFinishedOverlayTitle": "Ruta finalizada",
  "sessionContinueButton": "Continuar",
```

- [ ] **Step 3: Regenerate localizations**

Run: `cd movile_app && flutter gen-l10n`
Expected: Regenerates `lib/l10n/app_localizations*.dart` with `sessionTargetLabel`, `sessionFinishedOverlayTitle`, `sessionContinueButton` getters. (If the project generates l10n during `flutter test`/build instead, this step is a no-op; verify the getters exist next.)

- [ ] **Step 4: Verify getters exist**

Run: `cd movile_app && grep -c "sessionFinishedOverlayTitle" lib/l10n/app_localizations.dart`
Expected: `1` (or greater). If `0`, run `flutter gen-l10n` again.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/l10n/
git commit -m "i18n: add finish-overlay and live target strings"
```

---

## Task 6: Reference duration in LiveSessionController

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_controller.dart`
- Test: `movile_app/test/features/session/live_session_controller_test.dart`

- [ ] **Step 1: Write the failing tests**

In `live_session_controller_test.dart`, first extend the `route()` helper to carry an expected duration and add an open-route prior-session seeder. Add these two tests at the end of `main()`:

```dart
  test('referenceDuration uses previous best total when competing', () async {
    // Route with a normal time, plus a prior completed run of 100 s.
    final r = route().copyWith(expectedDuration: const Duration(seconds: 200));
    await repo.saveRouteTemplate(r);
    await repo.saveSessionRun(SessionRun(
      id: 'prev-open',
      routeTemplateId: 'r1',
      startedAt: DateTime.utc(2026, 1, 1, 0, 0, 0),
      endedAt: DateTime.utc(2026, 1, 1, 0, 1, 40), // 100 s
      status: SessionStatus.completed,
      points: const [],
      laps: const [],
      sectorSummaries: const [],
      totalDistanceMeters: 500,
      maxSpeedMps: 12,
      avgSpeedMps: 10,
    ));
    final ctrl = LiveSessionController(repo, headingService: _StubHeadingService());
    await ctrl.load();
    ctrl.selectRoute(r);
    await ctrl.startSession(includeHistorical: true);

    expect(ctrl.referenceDuration, const Duration(seconds: 100));
    ctrl.dispose();
  });

  test('referenceDuration falls back to route normal time', () async {
    // Competing chosen but no prior runs → use expectedDuration.
    final r = route().copyWith(expectedDuration: const Duration(seconds: 200));
    await repo.saveRouteTemplate(r);
    final ctrl = LiveSessionController(repo, headingService: _StubHeadingService());
    await ctrl.load();
    ctrl.selectRoute(r);
    await ctrl.startSession(includeHistorical: true);

    expect(ctrl.referenceDuration, const Duration(seconds: 200));

    // Not competing → also the normal time, even if a prior run exists.
    await ctrl.startSession(includeHistorical: false);
    expect(ctrl.referenceDuration, const Duration(seconds: 200));
    ctrl.dispose();
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd movile_app && flutter test test/features/session/live_session_controller_test.dart -n "referenceDuration"`
Expected: FAIL — `referenceDuration` is not defined.

- [ ] **Step 3: Add the field, getter, loader and helper**

In `live_session_controller.dart`:

(a) After the `_historicalBestLap` field/getter block, add:

```dart
  /// Best total time across the user's previous sessions on the selected route
  /// (used for open routes, which have no laps). Loaded when the session starts
  /// and `includeHistorical` is true; null when there is no prior run.
  Duration? _historicalBestTotal;

  /// Reference time for an open route: the user's previous best total when they
  /// chose to compete against it and one exists, otherwise the route's normal
  /// (expected) time. Null when neither is available.
  Duration? get referenceDuration {
    if (_includeHistorical && _historicalBestTotal != null) {
      return _historicalBestTotal;
    }
    return _selected?.expectedDuration;
  }
```

(b) In `startSession`, inside the `if (includeHistorical) { ... }` block (the `try`), after `_historicalBestLap = _bestHistoricalLap(sessions);`, add:

```dart
        _historicalBestTotal = _bestHistoricalTotal(sessions);
```

In the same `try`'s `catch`, after `_historicalBestLap = null;`, add:

```dart
        _historicalBestTotal = null;
```

In the `else` branch, after `_historicalBestLap = null;`, add:

```dart
      _historicalBestTotal = null;
```

(c) After the existing `_bestHistoricalLap` helper method, add:

```dart
  /// Minimum total run duration across [sessions]; null when none has one.
  Duration? _bestHistoricalTotal(List<SessionRun> sessions) {
    Duration? best;
    for (final session in sessions) {
      final d = session.totalDuration;
      if (d == null) continue;
      if (best == null || d < best) best = d;
    }
    return best;
  }
```

(d) In `resetForNewSession`, after `_historicalBestLap = null;`, add:

```dart
    _historicalBestTotal = null;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd movile_app && flutter test test/features/session/live_session_controller_test.dart -n "referenceDuration"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_controller.dart movile_app/test/features/session/live_session_controller_test.dart
git commit -m "feat: compute referenceDuration (previous best or route normal time)"
```

---

## Task 7: Add the `summary` stage + overlay routing

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_controller.dart`
- Test: `movile_app/test/features/session/live_session_controller_test.dart`

- [ ] **Step 1: Update the existing auto-finish test + add the dismiss test**

In `live_session_controller_test.dart`, in the test `'open route auto-finishes the session when the end is reached'`, replace the assertion:

```dart
    expect(ctrl.stage, LiveSessionStage.finished);
```

with:

```dart
    // Open routes pause on a summary overlay before the results screen.
    expect(ctrl.stage, LiveSessionStage.summary);
    expect(ctrl.result, isNotNull);

    // Continuar → results screen.
    ctrl.dismissFinishOverlay();
    expect(ctrl.stage, LiveSessionStage.finished);
```

(Remove the now-duplicate `expect(ctrl.result, isNotNull);` line that immediately followed the old assertion, so `result` is asserted once.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd movile_app && flutter test test/features/session/live_session_controller_test.dart -n "auto-finishes"`
Expected: FAIL — `LiveSessionStage.summary` / `dismissFinishOverlay` not defined.

- [ ] **Step 3: Add the enum value**

In `live_session_controller.dart`, change the enum:

```dart
enum LiveSessionStage { selecting, ready, running, paused, finished }
```

to:

```dart
enum LiveSessionStage { selecting, ready, running, paused, summary, finished }
```

- [ ] **Step 4: Route open routes to `summary` on finish**

In `finishSession()`, replace:

```dart
    _result = session;
    _stage = LiveSessionStage.finished;
    notifyListeners();
    return session;
```

with:

```dart
    _result = session;
    // Open routes pause on a finish overlay (frozen map + summary) before the
    // results screen; closed routes go straight to results as before.
    _stage = t.route.isClosed
        ? LiveSessionStage.finished
        : LiveSessionStage.summary;
    notifyListeners();
    return session;
```

- [ ] **Step 5: Add `dismissFinishOverlay`**

After `finishSession()`, add:

```dart
  /// Advances from the finish overlay (open routes) to the results screen.
  void dismissFinishOverlay() {
    if (_stage != LiveSessionStage.summary) return;
    _stage = LiveSessionStage.finished;
    notifyListeners();
  }
```

- [ ] **Step 6: Run to verify it passes**

Run: `cd movile_app && flutter test test/features/session/live_session_controller_test.dart`
Expected: PASS (all tests in the file).

- [ ] **Step 7: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_controller.dart movile_app/test/features/session/live_session_controller_test.dart
git commit -m "feat: pause open-route sessions on a summary stage before results"
```

---

## Task 8: Live reference target in `_LapIndicators`

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_screen.dart`

- [ ] **Step 1: Add a `referenceDuration` parameter to `_LapIndicators`**

In the `_LapIndicators` constructor, add a parameter after `this.includeHistorical = false,`:

```dart
    this.referenceDuration,
```

And add the field after `final bool includeHistorical;`:

```dart
  final Duration? referenceDuration;
```

- [ ] **Step 2: Show elapsed | target for open routes**

In `_LapIndicators.build`, replace the open-route branch:

```dart
    final elapsed = Formatters.durationHms(snapshot.currentLapElapsed);
    if (!isClosed) {
      return _BigIndicator(
        label: l.sessionElapsedLabel,
        value: elapsed,
        emphasized: true,
      );
    }
```

with:

```dart
    final elapsed = Formatters.durationHms(snapshot.currentLapElapsed);
    if (!isClosed) {
      final reference = referenceDuration;
      // No reference available → keep the single centered chronometer.
      if (reference == null) {
        return _BigIndicator(
          label: l.sessionElapsedLabel,
          value: elapsed,
          emphasized: true,
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _BigIndicator(
              label: l.sessionElapsedLabel,
              value: elapsed,
              emphasized: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _BigIndicator(
              label: l.sessionTargetLabel,
              value: Formatters.duration(
                reference,
                dotSeparator: settingsController.timeFormatDot,
              ),
              emphasized: false,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      );
    }
```

(`theme` is already defined at the top of this `build` method.)

- [ ] **Step 3: Pass the reference from `_buildRunning`**

In `_buildRunning`, in the `_LapIndicators(...)` call, add after `includeHistorical: ctrl.includeHistorical,`:

```dart
                        referenceDuration: ctrl.referenceDuration,
```

- [ ] **Step 4: Verify it compiles**

Run: `cd movile_app && flutter analyze lib/src/features/session/live_session_screen.dart`
Expected: No new errors.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_screen.dart
git commit -m "feat: show reference target next to the live open-route chronometer"
```

---

## Task 9: Finish overlay UI for the `summary` stage

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_screen.dart`
- Test: `movile_app/test/features/session/live_session_screen_finish_overlay_test.dart` (new)

- [ ] **Step 1: Add the import**

At the top of `live_session_screen.dart`, with the other `../../shared/widgets/...` imports, add:

```dart
import '../../shared/widgets/time_delta_indicator.dart';
```

- [ ] **Step 2: Treat `summary` like a running stage in `build`**

In `build`, change:

```dart
    final isRunning = ctrl.stage == LiveSessionStage.running ||
        ctrl.stage == LiveSessionStage.paused;
```

to:

```dart
    final isRunning = ctrl.stage == LiveSessionStage.running ||
        ctrl.stage == LiveSessionStage.paused ||
        ctrl.stage == LiveSessionStage.summary;
```

And in the `switch (ctrl.stage)` body, add a `summary` arm right before the `finished` arm:

```dart
          LiveSessionStage.summary => _buildRunning(context, ctrl),
```

- [ ] **Step 3: Add the overlay layer to `_buildRunning`**

In `_buildRunning`, the method returns a `Stack(children: [...])`. Add, as the LAST child of that top-level `Stack` (after the bottom `Positioned(...SafeArea...)` child):

```dart
        if (ctrl.stage == LiveSessionStage.summary && ctrl.result != null)
          _FinishOverlay(
            session: ctrl.result!,
            reference: ctrl.referenceDuration,
            onContinue: ctrl.dismissFinishOverlay,
          ),
```

- [ ] **Step 4: Add the `_FinishOverlay` widget**

At the end of `live_session_screen.dart` (top-level, e.g. after `_SessionRecordingActions`), add:

```dart
/// Semi-transparent panel shown over the frozen map when an open route finishes.
/// Shows the total time and its delta vs the reference, with a Continue button
/// that advances to the results screen. While it is visible the map + bottom
/// controls are frozen (the session is already finished and saved).
class _FinishOverlay extends StatelessWidget {
  const _FinishOverlay({
    required this.session,
    required this.reference,
    required this.onContinue,
  });

  final SessionRun session;
  final Duration? reference;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final total = session.totalDuration;
    return Positioned.fill(
      child: GestureDetector(
        // Absorb taps on the backdrop so the frozen controls below stay inert.
        onTap: () {},
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.25),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag, size: 40, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    l.sessionFinishedOverlayTitle,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    total == null ? '--:--' : Formatters.durationHms(total),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (reference != null && total != null) ...[
                    const SizedBox(height: 8),
                    TimeDeltaIndicator(expected: reference!, actual: total),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: onContinue,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(l.sessionContinueButton),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Write the widget test**

This mirrors the proven harness in `live_session_screen_l10n_test.dart` (same delegates, same pump→load→startSession order, `tester.runAsync` for real sqflite I/O). Create `movile_app/test/features/session/live_session_screen_finish_overlay_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:splitway_mobile/src/config/app_config.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/features/session/live_session_controller.dart';
import 'package:splitway_mobile/src/features/session/live_session_screen.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

Widget _harness({required Locale locale, required Widget child}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('es')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

int _dbCounter = 0;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  RouteTemplate openRoute() => RouteTemplate(
        id: 'r-open',
        name: 'Open',
        path: const [
          GeoPoint(latitude: 40.0, longitude: -3.0),
          GeoPoint(latitude: 40.00018, longitude: -3.0),
          GeoPoint(latitude: 40.00036, longitude: -3.0),
        ],
        startFinishGate: GateDefinition(
          left: GeoPoint(latitude: 40.0, longitude: -3.0001),
          right: GeoPoint(latitude: 40.0, longitude: -2.9999),
        ),
        sectors: const [],
        difficulty: RouteDifficulty.easy,
        createdAt: DateTime.utc(2026, 1, 1),
        expectedDuration: const Duration(seconds: 200),
      );

  TelemetryPoint tp(double lat, DateTime t) => TelemetryPoint(
      timestamp: t,
      location: GeoPoint(latitude: lat, longitude: -3.0),
      speedMps: 12);

  testWidgets('finish overlay shows on summary stage and Continue advances',
      (tester) async {
    _dbCounter += 1;
    late SplitwayLocalDatabase db;
    late LiveSessionController ctrl;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      db = await SplitwayLocalDatabase.open(
        overridePath:
            'file:finish_overlay_test_$_dbCounter?mode=memory&cache=shared',
      );
      final repo = LocalDraftRepository(db)..userId = 'user-1';
      await repo.saveRouteTemplate(openRoute());
      ctrl = LiveSessionController(repo);
      settings = await AppSettingsController.load();
    });

    await tester.pumpWidget(_harness(
      locale: const Locale('en'),
      child: LiveSessionScreen(
        controller: ctrl,
        config: const AppConfig(),
        settingsController: settings,
      ),
    ));

    // Let initState's load() settle (stage → ready, route selected).
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
    }

    // Force simulated source so startSession never reaches the GPS plugin.
    await tester.runAsync(() async {
      await ctrl.setSource(TrackingSource.simulated);
      await ctrl.startSession(
          includeHistorical: false, useCompassHeading: false);
    });
    await tester.pump();
    expect(ctrl.stage, LiveSessionStage.running);

    // Drive to the end so the session auto-finishes into the summary stage.
    // finishSession() awaits a real repo save → run it inside runAsync.
    final base = DateTime(2026, 5, 9, 10);
    final t = ctrl.tracker!;
    await tester.runAsync(() async {
      t.ingestSimulatedPoint(tp(39.9999, base));
      t.ingestSimulatedPoint(tp(40.00005, base.add(const Duration(seconds: 1))));
      t.ingestSimulatedPoint(tp(40.00036, base.add(const Duration(seconds: 2))));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(ctrl.stage, LiveSessionStage.summary);
    expect(find.text('Route finished'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(ctrl.stage, LiveSessionStage.finished);
    expect(find.text('Route finished'), findsNothing);

    ctrl.dispose();
    await tester.runAsync(() => db.close());
  });
}
```

- [ ] **Step 6: Run the widget test**

Run: `cd movile_app && flutter test test/features/session/live_session_screen_finish_overlay_test.dart`
Expected: PASS. If it fails on screen construction, diff your setup against `test/features/session/live_session_screen_l10n_test.dart` — it builds the same screen the same way.

- [ ] **Step 7: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_screen.dart movile_app/test/features/session/live_session_screen_finish_overlay_test.dart
git commit -m "feat: finish overlay with time + delta for open routes"
```

---

## Task 10: Full verification

- [ ] **Step 1: Run the core package tests**

Run: `cd packages/splitway_core && dart test`
Expected: All pass.

- [ ] **Step 2: Run the mobile app tests**

Run: `cd movile_app && flutter test`
Expected: All pass (in particular the updated `live_session_controller_test.dart`, the new trail/overlay tests, and the existing `live_session_screen_l10n_test.dart`).

- [ ] **Step 3: Analyze**

Run: `cd movile_app && flutter analyze` and `cd packages/splitway_core && dart analyze`
Expected: No new issues.

- [ ] **Step 4: Manual device check (the parts not unit-testable)**

With a Mapbox token configured, record an open route on a device/emulator:
- Before crossing the first node: no estela is drawn (only the user marker).
- After the first node: estela grows normally; the live panel shows `Time | Target`.
- On reaching the end: the map + estela freeze (no tip past the last node); the semi-transparent "Route finished" overlay appears with the time and the green/red delta; the bottom controls are frozen.
- Tapping Continue shows the results screen, whose map also shows only the trimmed trail.
- Open the session later in History: the saved trail is trimmed too.

- [ ] **Step 5: Final commit (if any cleanup)**

```bash
git add -A
git commit -m "chore: finalize open-route finish overlay + trail trim"
```

---

## Self-Review Notes

- **Spec coverage:** Part 1 trail trim → Tasks 1–4; Part 2 reference → Tasks 5, 6, 8; Part 3 overlay → Tasks 5, 7, 9. Closed routes unchanged (Task 7 routes only open routes to `summary`; Task 8 only changes the open-route branch). History trim is automatic via Task 1 (saved `points` come from `recordedPoints` through `_buildSession`).
- **Type consistency:** `recordedPoints` (engine) → `trailPoints` (controller) → `telemetry:` (map). `recording` flag and `_growsTip` used consistently. `referenceDuration` getter consumed by `_LapIndicators` and `_FinishOverlay`. `LiveSessionStage.summary` added once and handled in `build`, `finishSession`, `dismissFinishOverlay`.
- **Known non-TDD area:** the Mapbox tip freezing (Task 3) is verified manually (Step 4 of Task 10) because the platform channel is unavailable in tests.
