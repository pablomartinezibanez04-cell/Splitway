# Full-Screen Map Recording UI

**Date**: 2026-05-21
**Scope**: LiveSessionScreen (`_buildRunning`) and FreeRideScreen (`_buildRecording`)

## Goal

Replace the current card-based layout during route recording with a full-screen map and semi-transparent overlays. The map becomes the primary visual element; metrics and controls float on top.

## Scaffold Changes (both screens)

- `extendBodyBehindAppBar: true` and `extendBody: true`
- AppBar: `backgroundColor: Colors.transparent`, `surfaceTintColor: Colors.transparent`, `elevation: 0`
- Drawer leading button gets a circular semi-transparent background for visibility over the map
- Title hidden during recording (no value while actively tracking)

## Body Structure

The body becomes a `Stack`:

1. **Layer 0 — Map**: `Positioned.fill` with `SplitwayMap` directly (no Card wrapper)
2. **Layer 1 — Bottom overlay**: `Positioned(left: 0, right: 0, bottom: 0)` with `SafeArea` wrapping `_BottomOverlay`
3. **Layer 2 — FAB** (FreeRide only): center-on-user button positioned above the overlay, right-aligned

## Overlay Container Style

Reusable `_OverlayContainer` widget:
- `color: theme.colorScheme.surface.withOpacity(0.85)` — more solid than transparent for readability
- `borderRadius: BorderRadius.vertical(top: Radius.circular(20))`
- Internal padding: 16px
- No border or shadow

## FreeRideScreen — Recording Overlay

Contents (top to bottom):
1. **Metrics row**: 3 inline metrics (elapsed, distance, speed) — label above, value below, no individual Cards
2. **Stop button**: `FilledButton` red, full width

Removed:
- `_GpsStatusTile` (point count) — eliminated entirely

Background-denied banner: if applicable, shown as a compact orange semi-transparent banner above the overlay container.

FAB center-on-user: positioned just above the overlay, right corner.

## LiveSessionScreen — Running Overlay

### GPS Real Mode

Contents (top to bottom):
1. **Metrics row**: 3 inline metrics (current lap, lap time, best lap)
2. **Last event tile**: compact row showing last crossed sector and time
3. **Stop button**: `FilledButton` red, full width

### Simulated Mode

Same as GPS real, plus:
4. **Expandable simulation controls**: a toggle button (collapsed by default) that expands to show:
   - Simulate-one-point and auto-lap buttons
   - Speed multiplier selector (1x/5x/10x)
   - Progress bar (when auto-simulating)

Removed:
- `_GpsStatusTile` (point count, coordinates, accuracy) — eliminated entirely

Background-denied banner: same treatment as FreeRide.

## Files to Modify

- `movile_app/lib/src/features/free_ride/free_ride_screen.dart` — `_buildRecording`, `_MetricCard`, `_GpsStatusTile`
- `movile_app/lib/src/features/session/live_session_screen.dart` — `_buildRunning`, `_MetricCard`, `_GpsStatusTile`, `build` (AppBar)
- Localization files if any new keys are needed (unlikely — reusing existing labels)

## Out of Scope

- Changes to idle/ready/finished states (only the active recording state changes)
- Map widget internals (`SplitwayMap` used as-is)
- New packages or dependencies
