# GPS Gap Detection — Design Spec

## Problem

When the app goes to background or the phone is turned off during a tracking
session, GPS updates stop. Upon resume the first points may carry:

1. **Stale or erratic `speedMps`** — the GPS chip needs a few seconds to
   re-acquire satellites and stabilise Doppler-based speed.
2. **A large position jump** — the straight-line Haversine distance between the
   last pre-gap point and the first post-gap point inflates distance accumulators
   and may produce an unrealistic `maxSpeedMps`.

Neither `TrackingEngine` nor `FreeRideEngine` currently distinguish a 1-second
interval from a 10-minute gap between consecutive `TelemetryPoint`s.

## Design

### Approach

Add a **guard clause** at the top of the `ingest()` method in both engines.
When the elapsed time between `_previous.timestamp` and the incoming
`point.timestamp` exceeds a gap threshold, the engine enters a short
**recovery window** during which telemetry points are recorded (appended to
`_points`) but do not affect any metric (distance, speed, max speed).

### Constants

| Name                | Value              | Rationale                                              |
|---------------------|--------------------|--------------------------------------------------------|
| `_gapThreshold`     | `Duration(seconds: 5)`  | GPS samples arrive ~1 Hz; 5 s means ≥ 4 missed samples |
| `_recoveryDuration` | `Duration(seconds: 3)`  | Covers a warm-start GPS re-lock (typical 2-5 s)        |

Both are `static const` on the engine class, mirroring the existing
`_crossingCooldown` pattern in `TrackingEngine`.

### State

A single nullable field: `DateTime? _recoveringUntil`.

- **`null`** — normal operation.
- **non-null** — the engine is in recovery mode; points are stored but metrics
  are frozen until `point.timestamp >= _recoveringUntil`.

### Behaviour during gap / recovery

| Action                         | Gap point | Recovery points | Normal points |
|-------------------------------|-----------|-----------------|---------------|
| Append to `_points`            | yes        | yes              | yes            |
| Accumulate distance            | no         | no               | yes            |
| Update `_lastSpeedMps`         | no         | no               | yes            |
| Update `_maxSpeedMps`          | no         | no               | yes            |
| Update `_previous`             | yes        | yes              | yes            |
| Detect gate crossings          | no         | no               | yes            |

### Pseudocode (TrackingEngine)

```dart
void ingest(TelemetryPoint point) {
  if (_status == TrackingStatus.idle || _status == TrackingStatus.finished) return;
  _points.add(point);

  final prev = _previous;
  if (prev != null) {
    final elapsed = point.timestamp.difference(prev.timestamp);
    if (elapsed >= _gapThreshold) {
      _recoveringUntil = point.timestamp.add(_recoveryDuration);
      _previous = point;
      return;
    }
  }

  if (_recoveringUntil != null) {
    if (point.timestamp.isBefore(_recoveringUntil!)) {
      _previous = point;
      return;
    }
    _recoveringUntil = null;
  }

  // — normal metric updates below (unchanged) —
  _lastSpeedMps = point.speedMps ?? _lastSpeedMps;
  // ... distance, max speed, gate crossings ...
  _previous = point;
}
```

`FreeRideEngine.ingest()` follows the same pattern but without gate-crossing
logic.

## Scope

### In scope
- Gap detection + recovery in `TrackingEngine.ingest()`
- Gap detection + recovery in `FreeRideEngine.ingest()`
- Unit tests for both engines covering gap and recovery scenarios

### Out of scope
- Background location (foreground service / iOS background modes) — separate
  feature, tracked independently.
- Filtering by `accuracyMeters` — complementary but not required for this fix.
- UI indication of "GPS reconnecting" — nice-to-have for a future iteration.

## Testing

1. **Gap skips metrics** — inject a point with a >5 s gap; verify distance,
   lastSpeed, and maxSpeed are unchanged.
2. **Recovery skips metrics** — inject points within the 3 s recovery window;
   verify metrics remain frozen.
3. **Normal resumes after recovery** — inject a point after recovery expires;
   verify metrics update normally.
4. **No regression on normal flow** — existing test suites pass unchanged.
