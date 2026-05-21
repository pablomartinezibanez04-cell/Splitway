# Map Style Switcher

**Date:** 2026-05-21
**Status:** Approved

## Goal

Add a Google Maps-style layers button to the `SplitwayMap` widget that lets the user switch between map styles (Outdoor, Satellite, Dark). The selected style persists across sessions via `SharedPreferences`.

## Requirements

- Button visible on all interactive Mapbox maps (`interactive: true && useMapbox: true`)
- NOT shown on thumbnail/non-interactive maps
- Three styles: OUTDOORS, SATELLITE_STREETS, DARK
- Preference saved in `SharedPreferences` and restored on app launch
- Default: OUTDOORS

## Architecture

### State (self-contained in `_SplitwayMapState`)

- `MapStyle` enum with values: `outdoors`, `satelliteStreets`, `dark`
- `_mapStyle` — current style, initialized from SharedPreferences in `initState`
- `_styleMenuOpen` — boolean controlling the popup visibility
- SharedPreferences key: `'splitway_map_style'`
- If stored value is unrecognized, falls back to `outdoors`

### Style URI mapping

| Enum value         | Mapbox URI                        |
|--------------------|-----------------------------------|
| `outdoors`         | `MapboxStyles.OUTDOORS`           |
| `satelliteStreets` | `MapboxStyles.SATELLITE_STREETS`  |
| `dark`             | `MapboxStyles.DARK`               |

### UI: Button and popup menu

**Button:** Positioned `top: 8, right: 8` in the existing `Stack`. Circular `Material` with `Icons.layers` icon. Shows a tooltip from localization (`mapStyleLayersTooltip`).

**Popup menu:** A `Card` floating near the button. Contains 3 rows, each with:
- Icon on the left (`Icons.terrain`, `Icons.satellite_alt`, `Icons.dark_mode`)
- Localized style name
- Visual highlight (check icon or accent color) for the active style

Tapping an option closes the menu and applies the style. Tapping outside the menu closes it (transparent `GestureDetector` backdrop behind the card).

### Style change flow

1. User taps a style option in the menu
2. `setState` closes menu and updates `_mapStyle`
3. `_map!.loadStyleURI(uri)` — changes the map base layer
4. `SharedPreferences.setString(...)` — persists the choice
5. Recreate annotation managers (`_lineManager`, `_circleManager`) since the old ones are invalidated by the style change
6. `_renderAnnotations()` — redraws routes, points, user location on the new style

### Handling `loadStyleURI` invalidation

When Mapbox loads a new style, existing annotation managers are invalidated (their layers/sources are removed). After `loadStyleURI` completes:
- Recreate `_lineManager` and `_circleManager`
- Call `_renderAnnotations()` to redraw all annotations

The existing coalescing mechanism (`_isRendering` / `_renderPending`) protects against concurrent renders during the style transition.

## Localization

New keys in `app_en.arb` / `app_es.arb`:

| Key                      | EN          | ES              |
|--------------------------|-------------|-----------------|
| `mapStyleOutdoors`       | Outdoor     | Exterior        |
| `mapStyleSatelliteStreets` | Satellite | Satelite       |
| `mapStyleDark`           | Dark        | Oscuro          |
| `mapStyleLayersTooltip`  | Map style   | Estilo del mapa |

## Files changed

1. **`movile_app/lib/src/shared/widgets/splitway_map.dart`** — Enum, state, button, menu, persistence, style switching logic
2. **`movile_app/lib/l10n/app_en.arb`** — 4 new keys
3. **`movile_app/lib/l10n/app_es.arb`** — 4 new keys
4. **`movile_app/lib/l10n/app_localizations.dart`** + `_en.dart` + `_es.dart` — Regenerated

## Files NOT changed

- No parent screens (editor, live session, free ride, history, detail)
- No `AppSettingsController`
- No `pubspec.yaml`
- No test files
