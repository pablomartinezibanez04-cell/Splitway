# Routing Profile Selector — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a FAB with popup menu to the route drawing view that lets the user choose between Mapbox driving/walking/cycling routing profiles.

**Architecture:** Add a `routingProfile` field to `RouteEditorController`, create a `RoutingProfileFab` widget that renders a FAB with `PopupMenuButton`, position it in a `Row` alongside the existing location FAB, and pass the profile to both `snapToRoads()` call sites.

**Tech Stack:** Flutter, Material 3, Mapbox Directions API

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `movile_app/lib/src/features/editor/route_editor_controller.dart` | Modify | Add `routingProfile` state field + setter |
| `movile_app/lib/src/features/editor/route_editor_screen.dart` | Modify | Add `RoutingProfileFab` widget, restructure FAB positioning |
| `movile_app/lib/l10n/app_en.arb` | Modify | Add 3 routing profile label strings |
| `movile_app/lib/l10n/app_es.arb` | Modify | Add 3 routing profile label strings (Spanish) |
| `movile_app/test/features/editor/route_editor_controller_test.dart` | Modify | Add tests for `routingProfile` state |

---

### Task 1: Add `routingProfile` state to `RouteEditorController`

**Files:**
- Modify: `movile_app/lib/src/features/editor/route_editor_controller.dart`
- Modify: `movile_app/test/features/editor/route_editor_controller_test.dart`

- [ ] **Step 1: Write the failing tests**

Add a new test group at the bottom of `route_editor_controller_test.dart`:

```dart
group('routingProfile', () {
  test('defaults to driving', () {
    expect(ctrl.routingProfile, 'driving');
  });

  test('setter updates value and notifies listeners', () {
    int notifications = 0;
    ctrl.addListener(() => notifications++);
    ctrl.routingProfile = 'walking';
    expect(ctrl.routingProfile, 'walking');
    expect(notifications, 1);
  });

  test('resets to driving on cancelDrawing', () {
    ctrl.routingProfile = 'cycling';
    ctrl.cancelDrawing();
    expect(ctrl.routingProfile, 'driving');
  });

  test('resets to driving on startDrawing', () {
    ctrl.routingProfile = 'walking';
    ctrl.startDrawing(name: 'New', difficulty: RouteDifficulty.easy);
    expect(ctrl.routingProfile, 'driving');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd movile_app && flutter test test/features/editor/route_editor_controller_test.dart`
Expected: Compilation error — `routingProfile` does not exist on `RouteEditorController`.

- [ ] **Step 3: Implement `routingProfile` in the controller**

In `route_editor_controller.dart`, add the field and setter in the "Draw mode state" section (after line 142, near `_inputMode`):

```dart
String _routingProfile = 'driving';
String get routingProfile => _routingProfile;
set routingProfile(String value) {
  if (_routingProfile == value) return;
  _routingProfile = value;
  notifyListeners();
}
```

In `startDrawing()`, add this line after `_inputMode = DrawInputMode.appendPath;` (line 228):

```dart
_routingProfile = 'driving';
```

In `cancelDrawing()`, add the same reset after `_inputMode = DrawInputMode.appendPath;` (line 244):

```dart
_routingProfile = 'driving';
```

In `saveDraft()`, add the same reset in the cleanup block after `_inputMode = DrawInputMode.appendPath;` (line 541):

```dart
_routingProfile = 'driving';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd movile_app && flutter test test/features/editor/route_editor_controller_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/editor/route_editor_controller.dart movile_app/test/features/editor/route_editor_controller_test.dart
git commit -m "feat(editor): add routingProfile state to RouteEditorController"
```

---

### Task 2: Pass `routingProfile` to `snapToRoads()` call sites

**Files:**
- Modify: `movile_app/lib/src/features/editor/route_editor_controller.dart`

- [ ] **Step 1: Update `_snapPath()` call site (line 426)**

Change:

```dart
final snapped = await routingService!.snapToRoads(waypoints);
```

To:

```dart
final snapped = await routingService!.snapToRoads(waypoints, profile: _routingProfile);
```

- [ ] **Step 2: Update `saveDraft()` call site (line 461)**

Change:

```dart
final snapped = await routingService!.snapToRoads(effective);
```

To:

```dart
final snapped = await routingService!.snapToRoads(effective, profile: _routingProfile);
```

- [ ] **Step 3: Run existing tests to verify no regressions**

Run: `cd movile_app && flutter test test/features/editor/route_editor_controller_test.dart`
Expected: All tests PASS (no `routingService` is injected in tests, so these calls are never reached).

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/features/editor/route_editor_controller.dart
git commit -m "feat(editor): pass routingProfile to snapToRoads call sites"
```

---

### Task 3: Add localization strings

**Files:**
- Modify: `movile_app/lib/l10n/app_en.arb`
- Modify: `movile_app/lib/l10n/app_es.arb`

- [ ] **Step 1: Add English strings to `app_en.arb`**

Add these entries after the `"editorSnapFailedMessage"` line (line 119):

```json
  "editorRoutingProfileTooltip": "Routing mode",
  "editorRoutingProfileDriving": "Road",
  "editorRoutingProfileWalking": "Trail",
  "editorRoutingProfileCycling": "Cycling",
```

- [ ] **Step 2: Add Spanish strings to `app_es.arb`**

Add the corresponding entries at the same position in `app_es.arb`:

```json
  "editorRoutingProfileTooltip": "Modo de ruta",
  "editorRoutingProfileDriving": "Carretera",
  "editorRoutingProfileWalking": "Sendero",
  "editorRoutingProfileCycling": "Ciclista",
```

- [ ] **Step 3: Regenerate localizations**

Run: `cd movile_app && flutter gen-l10n`
Expected: No errors. New getters appear in the generated `app_localizations.dart`.

- [ ] **Step 4: Verify build compiles**

Run: `cd movile_app && flutter analyze --no-fatal-infos`
Expected: No new errors.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/l10n/
git commit -m "feat(l10n): add routing profile selector strings (en/es)"
```

---

### Task 4: Build the `RoutingProfileFab` widget and integrate into `_DrawingView`

**Files:**
- Modify: `movile_app/lib/src/features/editor/route_editor_screen.dart`

- [ ] **Step 1: Add the `_RoutingProfileFab` widget**

Add this private widget class at the bottom of `route_editor_screen.dart`, before the `_NewRouteResult` class (before line 550):

```dart
class _RoutingProfileFab extends StatelessWidget {
  const _RoutingProfileFab({
    required this.profile,
    required this.onChanged,
  });

  final String profile;
  final ValueChanged<String> onChanged;

  static const _profiles = [
    ('driving', Icons.directions_car),
    ('walking', Icons.directions_walk),
    ('cycling', Icons.directions_bike),
  ];

  IconData get _activeIcon =>
      _profiles.firstWhere((p) => p.$1 == profile).$2;

  String _label(AppLocalizations l, String key) => switch (key) {
        'driving' => l.editorRoutingProfileDriving,
        'walking' => l.editorRoutingProfileWalking,
        'cycling' => l.editorRoutingProfileCycling,
        _ => key,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      onSelected: onChanged,
      tooltip: l.editorRoutingProfileTooltip,
      position: PopupMenuPosition.over,
      offset: const Offset(0, -160),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => [
        for (final (key, icon) in _profiles)
          PopupMenuItem<String>(
            value: key,
            child: Row(
              children: [
                Icon(icon, color: key == profile
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(child: Text(_label(l, key))),
                if (key == profile)
                  Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
              ],
            ),
          ),
      ],
      child: FloatingActionButton.small(
        heroTag: 'routing_profile',
        onPressed: null,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(_activeIcon, color: theme.colorScheme.onPrimaryContainer),
      ),
    );
  }
}
```

- [ ] **Step 2: Replace the existing `Positioned` FAB in `_DrawingViewState.build()`**

In the `Stack` children, replace lines 373–381:

```dart
Positioned(
  right: 12,
  bottom: 12,
  child: FloatingActionButton.small(
    heroTag: 'center_on_user',
    onPressed: _centerOnUser,
    child: const Icon(Icons.my_location),
  ),
),
```

With:

```dart
Positioned(
  right: 12,
  bottom: 12,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _RoutingProfileFab(
        profile: controller.routingProfile,
        onChanged: (p) => controller.routingProfile = p,
      ),
      const SizedBox(width: 12),
      FloatingActionButton.small(
        heroTag: 'center_on_user',
        onPressed: _centerOnUser,
        child: const Icon(Icons.my_location),
      ),
    ],
  ),
),
```

- [ ] **Step 3: Verify build compiles**

Run: `cd movile_app && flutter analyze --no-fatal-infos`
Expected: No new errors.

- [ ] **Step 4: Run all editor tests**

Run: `cd movile_app && flutter test test/features/editor/`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/editor/route_editor_screen.dart
git commit -m "feat(editor): add routing profile FAB with popup menu"
```

---

### Task 5: Manual verification

- [ ] **Step 1: Launch the app**

Run: `cd movile_app && flutter run`

- [ ] **Step 2: Test golden path**

1. Create a new route.
2. Verify the routing profile FAB appears to the left of the location FAB.
3. Tap the routing profile FAB — verify the popup shows 3 options with icons.
4. Verify "Road" is selected by default (check icon visible).
5. Select "Trail" — verify the FAB icon changes to walking icon.
6. Tap some waypoints on a trail/path visible on the map — verify the route snaps to the trail.
7. Switch to "Cycling" — verify icon changes, next snaps use cycling profile.
8. Save the route — verify it saves correctly.

- [ ] **Step 3: Test edge cases**

1. Open a new drawing session — verify profile resets to "Road".
2. Cancel a drawing session — verify profile resets to "Road".
3. Change profile mid-drawing — verify only new snaps use the new profile.
4. Test with no internet — verify snap failure banner still shows correctly.
5. Test that tapping outside the popup closes it without changing the selection.
