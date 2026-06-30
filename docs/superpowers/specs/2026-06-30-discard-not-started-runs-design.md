# Discard not-started runs

## Problem

When a user starts recording a route session but never crosses the
start/finish gate, the tracking engine stays in `awaitingStart`. Pressing
"Finish" still saves a `SessionRun` with empty `points`/`laps` and
`startedAt == endedAt`. For **open routes** this produces a `totalDuration`
of ~`0:00` (not `null`), so the session:

1. Appears in history as a phantom entry, and
2. Shows an absurd "improved time" percentage (≈100% faster, since the
   measured time is ~0 against the route's normal time).

Closed routes are partially shielded today because `representativeRunTime`
returns the best lap (`null` when none), but open routes are not.

## Definition of "not started"

A session never crossed the start/finish line. The resulting `SessionRun`
has `points` empty **and** `laps` empty. (`points` only accumulate while the
engine is `inLap`, i.e. after the first gate crossing, so their presence is a
reliable "started" signal.)

## Changes

### 1. `splitway_core` — `SessionRun.hasStarted`

```dart
bool get hasStarted => points.isNotEmpty || laps.isNotEmpty;
```

### 2. `splitway_core` — `representativeRunTime`

Return `null` up front when `!session.hasStarted`, so the improvement
percentage never renders for a not-started run — covering both new data and
any legacy 0:00 open-route sessions already in history.

### 3. `LiveSessionController.finishSession()`

After building `session`, if `!session.hasStarted`:

- Do **not** call `_repo.saveSessionRun` (nothing persisted to history).
- Reset the tracker and return to `ready` (reuse `resetForNewSession` logic),
  with `_result = null`.
- Set `_lastRunDiscarded = true` and return `null`.

`_lastRunDiscarded` resets to `false` at the start of `startSession`. The
open-route auto-finish path is unaffected because it only fires from `inLap`.

### 4. `live_session_screen.dart`

In `_onChange`, detect the `running`/`paused` → `ready` transition while
`controller.lastRunDiscarded` is true and show a brief snackbar
("No se registró ninguna ruta…"). No finish overlay or results screen is
shown because the stage returns to `ready`.

### 5. Localization

New key `sessionNotStartedSnackBar` in `app_en.arb` and `app_es.arb`, plus
regenerated `app_localizations_*.dart`.

## Testing

- Unit: `SessionRun.hasStarted` true/false cases.
- Unit: `representativeRunTime` returns `null` for a not-started open-route
  session.
- Controller: finishing while `awaitingStart` persists nothing and returns to
  `ready` with `lastRunDiscarded == true`.
