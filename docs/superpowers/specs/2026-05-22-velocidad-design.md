# Velocidad (Drag-style speed measurement) — Design Spec

**Date:** 2026-05-22
**Status:** Approved
**Branch:** `feat/velocidad`

## 1. Overview

A new feature accessible from the drawer (immediately below the existing "Garaje" entry) that lets the user run a drag-strip-style measurement session for a selected vehicle. The user picks which metrics to measure, an optional name, and a countdown length, then runs a session whose UI is a large live speed readout plus a list/grid of the selected metric results.

Sessions are persisted locally and synced to Supabase, and they show up in the existing History screen behind a new "Velocidad" tab.

## 2. User-facing flow

### 2.1 Entry point
- New `_MenuItem` in `app_drawer.dart` (logged-in section), icon `Icons.speed_outlined`, placed immediately after the "Garaje" item.
- Tapping it pushes the `/speed` route. Requires login (uses the existing `requireAuth` helper).

### 2.2 Setup screen — `/speed`
Sections (top to bottom):

1. **Vehículo**: vehicle picker reusing `vehicle_picker_tile`. Walking-only entries are excluded — only motorized vehicles. Required.
2. **Qué medir**: checkboxes for each `SpeedMetric` (see §4.1). At least one must be selected; the Continue button is disabled with 0 selected.
3. **Cuenta atrás**: ChoiceChips with values `3 / 5 / 10` seconds. Default `3`. Required.
4. **Nombre** (opcional): TextField. Empty value resolves at save time to `${vehicle.name}-yyyy-MM-dd_HH-mm-ss`.
5. **Vista de resultados**: ChoiceChips `Lista / Grid`, persisted as a local preference (same pattern as the existing sessions view toggle).
6. **Continuar** button → pushes the Ready screen.

### 2.3 Ready screen
- Full-screen text centered: "Cuando estés listo, pulsa Start".
- Large primary button "START" at the bottom. Pushes the Session screen and arms the measurement.

### 2.4 Session screen — phases
The screen has five phases, controlled by the controller via a `_phase` field:

- **arming**: sensors are subscribed in arm mode (see §5.2). No samples stored yet. Countdown timer not yet visible.
- **countdown**: large centered numbers (3→2→1) with a scale animation. Each second emits a short beep (`beep.mp3`). At second 0, a different sound (`beep_go.mp3`) plays, the overlay disappears, and the service transitions to running.
- **falseStart**: full-screen red overlay (see §6).
- **running**: header shows instantaneous speed in a very large font (~96 px). The body below shows the selected metrics in list or grid layout per the user preference. Each tile has the metric title on the right and the value on the left, initial value `-`. As the service detects each milestone, the tile animates to its final value with a brief highlight.
- **finished**: a discreet "Sesión completada" banner appears, plus "Guardar" and "Descartar" buttons.

### 2.5 Save / discard
- **Guardar**: persists the session locally (SQLite DAO), enqueues sync to Supabase, and navigates to the read-only detail view at `/history/speed/:id`.
- **Descartar**: drops the session in memory and pops back to the drawer/home.

### 2.6 History integration
- `history_screen.dart` gains a new top-level tab / filter chip "Velocidad".
- The Velocidad list shows cards with: vehicle, name, date, and 2–3 highlight metrics (whatever was measured — typically Top Speed and 0-100 or quarter mile).
- Tapping a card opens `/history/speed/:id`, which renders the same final-state layout as the Session screen (large speed at top reads `—`, body shows all measured metrics).

## 3. Architecture

New code lives in two trees:

```
lib/src/features/speed/
  speed_setup_screen.dart
  speed_ready_screen.dart
  speed_session_screen.dart
  speed_session_detail_screen.dart        # read-only history view
  widgets/
    speed_metric_tile.dart                # one metric in list mode
    speed_metric_card.dart                # one metric in grid mode
    countdown_overlay.dart                # 3-2-1-GO numbers
    false_start_overlay.dart              # red overlay with retry/cancel

lib/src/services/speed/
  speed_measurement_service.dart          # GPS + IMU fusion, milestone detection
  speed_session.dart                      # model
  speed_metric.dart                       # enum + helpers
  speed_repository.dart                   # local + Supabase sync
  beep_player.dart                        # short audio cues

lib/src/data/local/
  speed_session_dao.dart                  # SQLite table speed_sessions
```

The Sync service grows `_pushSpeedSessions()` and `_pullSpeedSessions()` to mirror the existing `free_rides` flow.

## 4. Data model

### 4.1 SpeedMetric enum

| key            | unit  | description                                  |
|----------------|-------|----------------------------------------------|
| `reactionTime` | s     | Time from GO beep to detected vehicle motion |
| `sixtyFoot`    | s     | Time to cover 18.29 m                        |
| `eighthMile`   | s     | Time to cover 201.17 m                       |
| `quarterMile`  | s     | Time to cover 402.34 m                       |
| `zeroTo50`     | s     | Time to reach 50 km/h                        |
| `zeroTo100`    | s     | Time to reach 100 km/h                       |
| `zeroTo200`    | s     | Time to reach 200 km/h                       |
| `topSpeed`     | km/h  | Maximum sustained speed during recording     |

Each metric carries an l10n label, an l10n short label, and a value formatter.

### 4.2 SpeedSession model

```
SpeedSession {
  id: String (uuid)
  userId: String?
  vehicleId: String? (nullable so vehicle deletion doesn't drop history)
  name: String
  selectedMetrics: Set<SpeedMetric>
  results: Map<SpeedMetric, double?>   // null = not completed
  countdownSeconds: int                // 3, 5, or 10
  isPartial: bool                      // true if interrupted
  startedAt: DateTime
  finishedAt: DateTime?
  createdAt: DateTime
  updatedAt: DateTime
  deletedAt: DateTime?
}
```

### 4.3 Local DB — `speed_sessions` SQLite table

Columns mirror the model. `selected_metrics` stored as a CSV of metric keys. `results` stored as a JSON map of `{key: value}`.

### 4.4 Supabase — new migration `20260522000000_add_speed_sessions.sql`

- Table `public.speed_sessions` with the same columns.
- `selected_metrics text[]`, `results jsonb`.
- Foreign key `vehicle_id -> public.vehicles(id) on delete set null`.
- Foreign key `user_id -> auth.users(id) on delete cascade`.
- RLS policies for select/insert/update/delete restricted to `auth.uid() = user_id`.
- Indexes: `(user_id, created_at desc)` for history listing.
- Soft-delete via `deleted_at` (same pattern as other tables in this repo).

## 5. Measurement service

### 5.1 Inputs

- `Geolocator.getPositionStream` with `LocationAccuracy.best`, `distanceFilter: 0`, `intervalDuration: 100 ms`. Effective rate ~5–10 Hz on Android, ~1 Hz on iOS.
- `sensors_plus` package: `accelerometerEvents` and `gyroscopeEvents` at the device's default high rate.

### 5.2 Modes

- **arm()**: sensors subscribed, samples NOT recorded. Used during the countdown to detect false starts (§6).
- **start()**: starts recording samples and the milestone-detection loop. `t = 0` is set at the moment `start()` is called (synchronous with the GO beep).
- **stop()**: finalizes results, unsubscribes, returns a `SpeedSession` snapshot.
- **cancel()**: discards state, unsubscribes, no result.

### 5.3 Fusion algorithm (longitudinal velocity)

A simple 1D Kalman filter:
- State: `[v, x]` (longitudinal velocity in m/s, distance traveled in m).
- Predict step (every IMU sample, ~50–100 Hz): integrate longitudinal acceleration. Longitudinal axis is estimated as the dominant axis of the gravity-compensated accelerometer reading, smoothed with the gyroscope.
- Correct step (every GPS sample): use GPS speed as measurement.
- Measurement noise tuned conservatively so GPS dominates above ~3 km/h and IMU dominates from 0 to ~3 km/h (where GPS speed is unreliable).

The service emits a `SpeedSample` every IMU tick (capped at 50 Hz to avoid UI thrash) with:
```
SpeedSample {
  tSinceStart: Duration,
  speedKmh: double,
  distanceM: double,
  accelMs2: double,
}
```

### 5.4 Milestone detection

The service receives `Set<SpeedMetric> targets`. For each unresolved target, linear interpolation between the previous and current sample resolves the exact crossing time:

- `reactionTime`: first sample where `speedKmh > 0.5` AND sustained for ≥150 ms.
- `sixtyFoot`: instant `distanceM` crosses 18.29.
- `eighthMile`: instant `distanceM` crosses 201.17.
- `quarterMile`: instant `distanceM` crosses 402.34.
- `zeroTo50` / `zeroTo100` / `zeroTo200`: instant `speedKmh` crosses 50/100/200.
- `topSpeed`: running maximum of `speedKmh`; finalized at stop.

The service exposes a `ValueListenable<Map<SpeedMetric, double?>>` of resolved results so the UI can rebuild incrementally.

### 5.5 Auto-stop

When every selected target is resolved (and `topSpeed` is finalized via a 1.5 s plateau check), the service emits `done`. The UI transitions to the `finished` phase. The user can also stop manually at any time.

## 6. False-start detection

### 6.1 Definition
During the countdown (before the GO beep), the service is in `arm` mode. If motion exceeds either threshold below, sustained for ≥150 ms (to filter out GPS jitter and suspension wobble), it is treated as a false start.

### 6.2 Thresholds (constants in `SpeedMeasurementService`)
- `falseStartSpeedKmh = 1.5` — GPS speed.
- `falseStartAccelMs2 = 1.5` — IMU longitudinal acceleration.
- `falseStartSustainMs = 150`.

### 6.3 Behavior
1. Service emits `FalseStartDetected`.
2. Countdown timer is cancelled; any pending beeps are silenced.
3. Full-screen red overlay (`Colors.red.withOpacity(0.85)`) appears:
   - Title (~64 px, bold): **"SALIDA EN FALSO"**.
   - Subtitle: "Has arrancado antes del pitido final".
   - Primary button "REINTENTAR" → resets the service to `arm` mode and restarts the countdown from the originally chosen value (3/5/10). Does NOT persist a session.
   - Secondary button "Cancelar" → returns to the Setup screen.
4. `HapticFeedback.heavyImpact()` fires, and `beep_false.mp3` plays once.
5. While the overlay is visible, no further false-start checks run. Hardware back button equals "Cancelar".

### 6.4 Out of scope
Once the service is in `running` mode (post-GO), false-start detection is disabled. Any movement is treated as legitimate.

## 7. Integration points

| Area              | Change                                                                                             |
|-------------------|----------------------------------------------------------------------------------------------------|
| `app_router.dart` | New `/speed`, `/speed/ready`, `/speed/session`, `/history/speed/:id` routes outside the shell tabs |
| `app_drawer.dart` | New `_MenuItem` after Garaje, both for logged-in entry only                                        |
| `history_screen.dart` | New "Velocidad" tab/filter with custom card layout                                              |
| `sync_service.dart` | `_pushSpeedSessions()` and `_pullSpeedSessions()` matching `free_rides` pattern                  |
| L10n (en + es) | Keys: `navSpeed`, `speedSetupTitle`, `speedSetupVehicleSection`, `speedSetupMetricsSection`, `speedSetupCountdownSection`, `speedSetupNameSection`, `speedSetupViewSection`, `speedSetupContinue`, `speedReadyMessage`, `speedReadyStart`, `speedFinishedTitle`, `speedFinishedSave`, `speedFinishedDiscard`, `speedFalseStartTitle`, `speedFalseStartSubtitle`, `speedFalseStartRetry`, `speedFalseStartCancel`, `speedMetricReactionTime`, `speedMetricSixtyFoot`, `speedMetricEighthMile`, `speedMetricQuarterMile`, `speedMetricZeroTo50`, `speedMetricZeroTo100`, `speedMetricZeroTo200`, `speedMetricTopSpeed`, `speedUnitsSeconds`, `speedUnitsKmh`, `speedHistoryTab` |
| Assets            | `assets/sounds/beep.mp3`, `assets/sounds/beep_go.mp3`, `assets/sounds/beep_false.mp3` (placeholders generated as short sine tones if not provided) |
| Dependencies      | Add `sensors_plus`, `audioplayers` (if not present), `wakelock_plus` (if not present)              |
| Permissions       | Location already requested by the existing tracking flow; IMU sensors require none on Android/iOS |
| Wakelock          | `WakelockPlus.enable()` on entering Session screen, `disable()` on leaving                         |

## 8. Edge cases

- **GPS without a fix on Ready**: Ready screen shows a non-blocking warning if `accuracy > 10 m`. Start is still allowed (IMU works without GPS), but the warning makes the user aware that some metrics will be less accurate.
- **Session interrupted** (app backgrounded, phone call, lifecycle pause): the service stops cleanly, the session is persisted with `is_partial = true`, and the user is taken to the finished phase showing whatever was captured.
- **Vehicle deleted while a session exists**: `vehicle_id` becomes null in the joined view; History card shows the label "Vehículo eliminado".
- **Countdown cancelled via back button** (before GO): cancel timer + service `cancel()`, pop to Setup. No session persisted.
- **Time drift between IMU and GPS**: each sample is timestamped at receipt; fusion uses the system monotonic clock, not the device-reported timestamps (those drift on some Android OEMs).

## 9. Testing

- **Unit**:
  - `SpeedMeasurementService` with synthetic sample streams: verify each milestone resolves at the correct interpolated time.
  - False-start detector: synthetic stream with speed > threshold during arm phase emits `FalseStartDetected`; sub-threshold jitter does not.
  - Name default formatter: `${vehicle.name}-yyyy-MM-dd_HH-mm-ss` with edge cases.
  - Result formatters (seconds with 2 decimals, km/h integer).
- **Widget**:
  - Setup screen disables Continue with 0 metrics selected.
  - Session screen transitions: arming → countdown → running → finished, and arming → falseStart → countdown on retry.
- **Manual**:
  - End-to-end run with a real GPS trace replay (mock provider) to validate 0-100 detection across a 5 s acceleration.

## 10. Out of scope (future work)

- Per-sample raw trace persistence and post-session speed/accel graphs.
- Multi-run comparison view ("best of 5 attempts").
- Custom distance/speed targets configurable by the user.
- Exporting results as image/CSV.
- Imperial-unit display (always metric for now).
