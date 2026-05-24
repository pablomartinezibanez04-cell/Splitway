# Speed heatmap on completed routes — design

## Goal

After finishing a route (normal session or free ride), let the user inspect the
speed they were going at every point of the route. The history detail screen
gains a button that toggles a colored "heatmap" rendering: the route line is
recolored according to speed, with a vertical legend on the right side of the
map mapping color to speed value.

The colored line must look continuous and homogeneous — no visible segment
boundaries.

## Decisions taken during brainstorming

1. **Integration**: a toggle button overlaid on the map switches between normal
   view and heatmap view. Same screen, no new route.
2. **Color palette**: 5-stop rainbow — blue → cyan → green → yellow → red.
3. **Which line is colored**: only the real telemetry (`SessionRun.points` /
   `FreeRideRun.points`). The planned route line (snapped path) is hidden in
   heatmap mode. Rationale: speed only exists at telemetry points, and
   re-projecting onto the snapped path would be misleading.
4. **Legend scale max**: rounded up "nice" value derived from this session's
   maximum speed. Examples: 47 km/h → 50, 87 km/h → 90, 153 km/h → 160. Each
   route fills the full color range without comparing across runs.
5. **Units**: legend always shows km/h or mph based on
   `AppSettingsController.unitSystem`. Never m/s.

## Architecture

### Rendering — why a Mapbox style layer, not annotations

Today `SplitwayMap` renders telemetry as a single `PolylineAnnotation` with a
solid color. The Annotation API has no gradient support — each polyline is one
color. Achieving a gradient by chopping the line into per-point segments would
introduce visible seams and saturate the Pigeon channel (telemetry can be
thousands of points).

Mapbox's `LineLayer` supports `lineGradientExpression`, an interpolation
expression along `line-progress` (0..1) that produces a fully continuous color
ramp on the same single line geometry. This is the natively-supported approach
and the only way to satisfy the "continuous and homogeneous" requirement
without re-implementing the rendering in a Flutter overlay.

Requirements:
- `GeoJsonSource` must be created with `lineMetrics: true` (Mapbox computes
  `line-progress` per vertex).
- `mapbox_maps_flutter` 2.10+ exposes `LineLayer.lineGradientExpression` —
  already on the project's dependency.

### Components (new)

- `lib/src/shared/speed_palette.dart` — pure Dart helpers:
  - `const List<(double, Color)> kSpeedPaletteStops` — the 5 stops at 0.0,
    0.25, 0.5, 0.75, 1.0.
  - `Color speedColor(double t)` — clamps `t` to [0..1] and linearly
    interpolates between the surrounding stops. Used only by the Flutter-side
    legend; the map line is interpolated by Mapbox itself.
  - `double niceMaxMps(double rawMaxMps, UnitSystem unit)` — converts to the
    display unit, rounds up to the next "nice" step (10 km/h or 10 mph for
    values ≤120; 20 above), converts the rounded value back to m/s. Returns
    m/s so callers can keep working in the canonical unit.

- `lib/src/shared/widgets/speed_heatmap_legend.dart`:
  - `SpeedHeatmapLegend({required double maxMps, required UnitSystem unit,
    required AppLocalizations l})`.
  - Vertical bar ~24 px wide × ~180 px tall, painted with a
    `LinearGradient(begin: bottomCenter, end: topCenter, colors: …)` using
    `kSpeedPaletteStops`.
  - Three labels next to it: 0 (bottom), max/2 (middle), max (top).
  - Labels formatted with `Formatters.speedMps(value, unit: unit)` and
    `l.unitKmh(...)` / `l.unitMph(...)` — the same helpers `_speedLabel` uses
    elsewhere in history.

- `lib/src/shared/widgets/speed_heatmap_toggle_button.dart`:
  - Small circular FAB-style button (style consistent with the existing map
    style button), icon `Icons.gradient`, tooltip from l10n.
  - Stateless; takes `bool active` and `VoidCallback onPressed`. When active,
    the button uses the primary color to indicate the toggled state.

### Changes to `SplitwayMap`

- New constructor parameter:
  ```dart
  final bool showSpeedHeatmap;   // default false (backward compatible)
  ```
- `didUpdateWidget` detects `showSpeedHeatmap` changes and re-renders.
- `_renderAnnotationsCore` adds a branch at the start:
  - If `widget.showSpeedHeatmap && hasTelemetryWithSpeeds(widget.telemetry)`:
    1. Skip creating the orange telemetry polyline.
    2. Skip creating the blue planned-route polyline (and sector segments).
    3. Call `_renderHeatmapLayer(widget.telemetry)`.
  - Otherwise, ensure any previous heatmap source/layer is removed and fall
    through to the existing rendering.
- `_renderHeatmapLayer(List<TelemetryPoint> tel)`:
  1. Filter telemetry to points with non-null `speedMps`.
  2. If `length > kMaxHeatmapStops` (e.g. 500), downsample uniformly. The line
     geometry itself can keep all points (it stays continuous); only the
     gradient stops are decimated, because the line-gradient expression grows
     with the number of stops.
  3. Compute cumulative haversine distance per point and normalize to
     `line-progress` in [0..1]. Force the first stop to 0.0 and the last to
     1.0 to avoid floating-point drift.
  4. Compute `maxMps = niceMaxMps(observedMax, unit)` and normalize each
     `speedMps / maxMps`, clamped to [0..1].
  5. Map the normalized value to a color via `speedColor(t)` and convert to
     an `int` ARGB.
  6. Build the `lineGradientExpression`:
     `['interpolate', ['linear'], ['line-progress'],
       p0, c0, p1, c1, …]`
  7. Create/update `GeoJsonSource` (`id: 'splitway-speed-src'`,
     `lineMetrics: true`, data = LineString of *all* telemetry points).
  8. Create/update `LineLayer` (`id: 'splitway-speed-layer'`,
     `lineWidth: 4`, `lineCap: round`, `lineJoin: round`,
     `lineGradientExpression: …`).
- Cleanup: when switching off, remove the layer then the source. When the map
  style changes (`_switchStyle`), the existing `_recreateManagers` path needs
  to also re-create the heatmap layer if active.

### Changes to detail screens

`SessionDetailScreen._SessionDetailScreenState` and
`_FreeRideDetailScreenState`:

- Add `bool _heatmap = false`.
- Compute `bool _canHeatmap` = telemetry has ≥2 points with non-null `speedMps`.
- Wrap the existing map `AspectRatio` in a `Stack`:
  ```dart
  Stack(children: [
    SplitwayMap(..., showSpeedHeatmap: _heatmap),
    if (_canHeatmap)
      Positioned(top: 8, left: 8,
        child: SpeedHeatmapToggleButton(
          active: _heatmap,
          onPressed: () => setState(() => _heatmap = !_heatmap),
        )),
    if (_heatmap && _canHeatmap)
      Positioned(top: 56, right: 12, bottom: 16,
        child: SpeedHeatmapLegend(
          maxMps: niceMaxMps(observedMax, unit),
          unit: unit,
          l: l,
        )),
  ])
  ```
  `top: 56` clears the existing map-style button (which sits at `top: 8,
  right: 8` and is ~40 px tall) so the two controls don't overlap.
- The free ride screen already passes `widget.config` and has access to the
  ride; the session screen needs `widget.settingsController` for the unit
  (it's already optional and read in `_SummaryRow`). For unit selection in the
  legend, default to `UnitSystem.metric` when `settingsController` is null
  (same pattern as `_speedLabel`).

## Data flow

```
TelemetryPoint (speedMps, location)
  → SplitwayMap.showSpeedHeatmap branch
    → downsample stops (cap at 500)
    → cumulative haversine progress per stop
    → niceMaxMps + speedColor mapping per stop
    → lineGradientExpression
    → GeoJsonSource(lineMetrics:true) + LineLayer
```

## Edge cases

- **No telemetry / no speeds**: hide the toggle button; don't render the layer.
- **One usable point**: hide the toggle (need ≥2 for a line).
- **All same speed**: legend max = niceMaxMps(thatSpeed, unit); the line is a
  uniform color near the corresponding stop. That's correct.
- **Style switch while heatmap is on**: `_recreateManagers` must also recreate
  the heatmap source+layer (managers are torn down when the style reloads).
- **Widget disposed mid-render**: same `PlatformException` swallow pattern
  already used in `_renderAnnotationsCore`.
- **Backward compatibility**: existing callers of `SplitwayMap` (route detail,
  live session, free ride live screen, route editor) don't pass
  `showSpeedHeatmap` — default `false` preserves current behavior.

## Localization

New keys in `app_en.arb` and `app_es.arb`:
- `heatmapToggleOn` — "Show speed heatmap" / "Mostrar mapa de calor"
- `heatmapToggleOff` — "Hide speed heatmap" / "Ocultar mapa de calor"
- `heatmapLegendTitle` — "Speed" / "Velocidad"

## Testing

- `test/shared/speed_palette_test.dart`:
  - `speedColor(0)` == blue stop, `speedColor(1)` == red stop, `speedColor(0.5)`
    == green stop (within tolerance for the interpolation), `speedColor(-1)`
    clamps to blue, `speedColor(2)` clamps to red.
  - `niceMaxMps`: 47 km/h → 50 km/h, 87 km/h → 90 km/h, 120 km/h → 120 km/h,
    121 km/h → 140 km/h, 87 mph → 90 mph. Convert back through the m/s
    round-trip and assert within 1e-6.
- `test/shared/heatmap_stops_test.dart`: extract the stops builder into a
  pure helper and assert (a) first progress == 0.0, last == 1.0, (b)
  progress monotonically increases, (c) stop count ≤ cap.
- `test/widgets/speed_heatmap_legend_test.dart`: pump with km/h and mph,
  assert the 0/mid/max labels are present in the expected unit.
- No Mapbox-rendering test (the SDK doesn't boot in the test env — matches
  the existing convention in this codebase).

## Out of scope

- Tap-on-line tooltip showing speed at that point.
- Per-lap or per-sector speed overlays.
- Persisting the user's preferred heatmap state across sessions.
- Heatmap rendering in the live (in-progress) session view.
- Comparing heatmaps across runs (requires fixed scale; rejected per
  decision 4).
