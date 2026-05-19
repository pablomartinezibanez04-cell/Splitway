# Routing Profile Selector — Design Spec

## Overview

Add a FAB (Floating Action Button) with popup menu to the route drawing view that lets the user choose the Mapbox routing profile before/during route creation. The three profiles — driving, walking, cycling — control how the Directions API snaps waypoints to roads, trails, or bike paths.

## Problem

The app currently hardcodes `profile = 'driving'` in `RoutingService.snapToRoads()`. This means routes always snap to car-suitable roads, making it impossible to trace mountain trails, footpaths, or cycling routes even when Mapbox has that data.

## Design Decisions

- **Control type**: FAB with popup menu (option B from brainstorm).
- **Position**: Bottom-right of the map, in a horizontal row to the left of the existing "center on user" FAB.
- **Three modes**, all using Mapbox Directions API with different `profile` values:

| Label     | Mapbox profile | Icon                          | Use case                     |
|-----------|---------------|-------------------------------|------------------------------|
| Auto      | `driving`     | `Icons.directions_car`        | Roads, highways, circuits    |
| Sendero   | `walking`     | `Icons.directions_walk`       | Trails, footpaths, mountains |
| Ciclista  | `cycling`     | `Icons.directions_bike`       | Bike lanes, rural paths      |

## UI Behavior

### Closed state
- Small FAB (same size as the existing location FAB) with the icon of the currently active profile.
- Background color: `colorScheme.primaryContainer` or `primary` to distinguish it from the location FAB.
- Hero tag: unique (e.g., `'routing_profile'`) to avoid conflicts.

### Open state (popup)
- Tapping the FAB opens a popup menu above-left of it (so it doesn't overflow off-screen).
- Three items, each with icon + label text.
- The active profile has a highlighted background and a check icon trailing.
- Selecting a profile closes the popup and updates the FAB icon.
- Tapping outside the popup closes it without changing the selection.

### Default profile
- Default: `driving` (preserves current behavior).
- The selected profile is held in `RouteEditorController` state and passed to `RoutingService.snapToRoads()`.

### Profile persistence
- The selected profile applies to the current drawing session only.
- It is NOT saved to the route model or database — it's a transient editor preference.
- When the user opens a new drawing session, it resets to `driving`.

## Architecture

### Affected files

1. **`route_editor_controller.dart`** — Add a `routingProfile` state field (String, one of `'driving'`, `'walking'`, `'cycling'`). Expose a setter that calls `notifyListeners()`.

2. **`route_editor_screen.dart` (`_DrawingView`)** — Add the routing profile FAB to the existing `Stack`, positioned in a `Row` with the location FAB. The FAB opens a `PopupMenuButton` or equivalent overlay.

3. **`routing_service.dart`** — Already accepts a `profile` parameter in `snapToRoads()`. No changes needed to the service itself.

4. **The call site** where `snapToRoads()` is invoked — Pass `controller.routingProfile` instead of the hardcoded default.

### Data flow

```
User taps FAB → popup opens → user selects profile
→ controller.routingProfile = 'walking'
→ notifyListeners()
→ FAB icon updates
→ next snapToRoads() call uses 'walking' profile
```

### Widget structure (inside _DrawingView Stack)

```
Stack(
  children: [
    SplitwayMap(...),
    Positioned(
      bottom: 12, right: 12,
      child: Row(
        children: [
          RoutingProfileFab(            // NEW
            profile: controller.routingProfile,
            onChanged: (p) => controller.routingProfile = p,
          ),
          SizedBox(width: 12),
          FloatingActionButton.small(   // EXISTING location FAB
            heroTag: 'center_on_user',
            ...
          ),
        ],
      ),
    ),
  ],
)
```

## Edge cases

- **No internet**: `snapToRoads()` already returns `null` on failure. The profile selector doesn't change error handling.
- **Profile changed mid-drawing**: The new profile applies only to the next snap call. Already-snapped segments keep their geometry. This is acceptable since the user is iterating.
- **Map Matching Edge Function**: The Supabase Edge Function `mapbox-routing` also accepts a `profile` parameter. If map-matching is used instead of Directions, the same profile value is forwarded.

## Out of scope

- Saving the routing profile per route in the database.
- A "free draw" mode that bypasses the API entirely.
- Custom Mapbox profile parameters (e.g., `exclude=tolls`).
- Changing the profile after the route is saved (read-only once saved).
