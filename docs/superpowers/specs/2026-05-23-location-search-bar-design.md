# Location Search Bar for Route Editor

## Summary

Add a floating search bar overlay on the route editor map so users can search for cities, streets, or points of interest and fly the map camera to the selected location. Uses the Mapbox Forward Geocoding API v6 — the same provider already used for reverse geocoding.

## Behavior

- User types a location name in the search bar
- After a 400ms debounce, the app queries Mapbox Forward Geocoding
- Up to 5 results appear in a dropdown below the search field
- Each result shows name + region (e.g. "Madrid, Spain")
- Selecting a result flies the map camera to those coordinates
- The search field clears and the dropdown closes after selection
- No pin is dropped; no waypoint is added — camera move only

## Components

### 1. `GeocodingResult` model

**Location:** `packages/splitway_core/lib/src/models/geocoding_result.dart`

```dart
class GeocodingResult {
  const GeocodingResult({required this.name, required this.coordinates});
  final String name;
  final GeoPoint coordinates;
}
```

Simple data class. Exported from `splitway_core.dart` barrel file.

### 2. `ForwardGeocodingService`

**Location:** `movile_app/lib/src/services/geocoding/forward_geocoding_service.dart`

Follows the same pattern as the existing `ReverseGeocodingService`:
- Constructor takes `accessToken` and optional `http.Client`
- Single public method: `Future<List<GeocodingResult>> search(String query)`
- Calls `https://api.mapbox.com/search/geocode/v6/forward?q={query}&limit=5&access_token={token}`
- Parses `features[].properties.full_address` (or `.name`) and `features[].geometry.coordinates`
- Returns empty list on error or empty results
- 5-second timeout per request

### 3. `LocationSearchBar` widget

**Location:** `movile_app/lib/src/features/editor/widgets/location_search_bar.dart`

A `StatefulWidget` with:
- A `TextField` with search icon prefix, clear button suffix
- Debounced input (400ms `Timer`) that triggers `ForwardGeocodingService.search()`
- A dropdown `Material` card below the field showing results as `ListTile`s
- On result tap: calls `onLocationSelected(GeoPoint)` callback, clears field, closes dropdown
- On clear/empty: hides dropdown
- Styled with rounded corners, semi-transparent background to float over the map
- Respects `SafeArea` insets

### 4. Integration in `_DrawingView`

**Location:** `movile_app/lib/src/features/editor/route_editor_screen.dart`

Add `LocationSearchBar` as a `Positioned` widget inside the existing `Stack` in `_DrawingView.build()`:

```
Stack(
  children: [
    SplitwayMap(...),
    // NEW: search bar at top
    Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: LocationSearchBar(
        accessToken: widget.config.mapboxAccessToken,
        onLocationSelected: (point) => _flyToNotifier.flyTo(point),
      ),
    ),
    // Existing FABs at bottom-right
    Positioned(right: 12, bottom: 12, ...),
  ],
)
```

Only shown when `widget.config.hasMapbox` is true (no point searching without Mapbox).

### 5. Localization strings

Add to `app_en.arb` and `app_es.arb`:

| Key | English | Spanish |
|-----|---------|---------|
| `editorSearchLocationHint` | "Search location..." | "Buscar ubicación..." |
| `editorSearchNoResults` | "No results found" | "Sin resultados" |

## What is NOT included

- No pin/marker dropped at searched location
- No route waypoint added from search
- No search history or recent searches
- No offline search capability
- No new package dependencies (uses existing `http` package)
- No new tests (follows existing service pattern which has no HTTP tests)

## Architecture notes

- The `ForwardGeocodingService` is stateless and instantiated in the widget — no global singleton needed
- Debounce is handled at the UI layer (`Timer` in the widget state), not in the service
- The service returns a simple list; the widget manages loading/empty/error states internally
- Uses the existing `FlyToNotifier` mechanism to animate the camera, consistent with the "center on me" button
