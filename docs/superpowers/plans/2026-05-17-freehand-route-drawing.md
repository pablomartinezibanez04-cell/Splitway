# Freehand Route Drawing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a freehand drawing mode so users can draw route segments by dragging their finger on the map, for off-road paths or streets Mapbox doesn't recognise.

**Architecture:** The flat `_rawWaypoints`/`_draftPath` model becomes a `List<DraftSegment>` where each segment is either `SnappedSegment` (tap-based, Mapbox-snapped) or `FreehandSegment` (hand-drawn, stored as-is). A new Douglas-Peucker helper in `splitway_core` simplifies the raw freehand trace. `SplitwayMap` gains a gesture overlay that captures single-finger drag when freehand mode is active (pan disabled, pinch-zoom kept).

**Tech Stack:** Flutter, Dart, mapbox_maps_flutter, splitway_core (pure Dart)

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `packages/splitway_core/lib/src/path_simplifier.dart` | `simplifyPath()` — Douglas-Peucker using GeoPoint.distanceTo |
| Create | `packages/splitway_core/test/path_simplifier_test.dart` | Unit tests for simplifyPath |
| Modify | `packages/splitway_core/lib/splitway_core.dart` | Export `path_simplifier.dart` |
| Create | `movile_app/lib/src/features/editor/draft_segment.dart` | `DraftSegment` sealed class + `SnappedSegment` / `FreehandSegment` |
| Modify | `movile_app/lib/src/features/editor/route_editor_controller.dart` | Refactor to segment model; add freehand handlers |
| Modify | `movile_app/test/features/editor/route_editor_controller_test.dart` | Tests for segments, freehand, undo, save |
| Modify | `movile_app/lib/src/shared/widgets/splitway_map.dart` | Freehand gesture overlay + per-segment color rendering |
| Modify | `movile_app/lib/src/features/editor/route_editor_screen.dart` | Freehand chip in mode bar; pass new props to SplitwayMap |
| Modify | `movile_app/lib/l10n/app_en.arb` | New English strings |
| Modify | `movile_app/lib/l10n/app_es.arb` | New Spanish strings |

---

### Task 1: `simplifyPath` helper (splitway_core, TDD)

**Files:**
- Create: `packages/splitway_core/lib/src/path_simplifier.dart`
- Create: `packages/splitway_core/test/path_simplifier_test.dart`
- Modify: `packages/splitway_core/lib/splitway_core.dart`

- [ ] **Step 1.1: Write failing tests for `simplifyPath`**

Create `packages/splitway_core/test/path_simplifier_test.dart`:

```dart
import 'package:splitway_core/splitway_core.dart';
import 'package:test/test.dart';

void main() {
  group('simplifyPath', () {
    test('returns input unchanged when fewer than 3 points', () {
      final two = [
        const GeoPoint(latitude: 40.0, longitude: -3.0),
        const GeoPoint(latitude: 40.1, longitude: -3.0),
      ];
      expect(simplifyPath(two, 10.0), equals(two));
    });

    test('returns input unchanged for empty list', () {
      expect(simplifyPath([], 10.0), isEmpty);
    });

    test('collinear points within tolerance collapse to endpoints', () {
      // Three points along the same latitude — the middle one is on the line.
      final points = [
        const GeoPoint(latitude: 40.0, longitude: -3.0),
        const GeoPoint(latitude: 40.0, longitude: -2.95),
        const GeoPoint(latitude: 40.0, longitude: -2.9),
      ];
      final result = simplifyPath(points, 10.0);
      expect(result, hasLength(2));
      expect(result.first, equals(points.first));
      expect(result.last, equals(points.last));
    });

    test('preserves point that deviates beyond tolerance', () {
      // Middle point ~111 m north of the line between endpoints.
      final points = [
        const GeoPoint(latitude: 40.0, longitude: -3.0),
        const GeoPoint(latitude: 40.001, longitude: -2.95),
        const GeoPoint(latitude: 40.0, longitude: -2.9),
      ];
      final result = simplifyPath(points, 50.0);
      expect(result, hasLength(3));
    });

    test('always preserves first and last points', () {
      final points = [
        const GeoPoint(latitude: 40.0, longitude: -3.0),
        const GeoPoint(latitude: 40.0, longitude: -2.99),
        const GeoPoint(latitude: 40.0, longitude: -2.98),
        const GeoPoint(latitude: 40.0, longitude: -2.97),
        const GeoPoint(latitude: 40.0, longitude: -2.9),
      ];
      final result = simplifyPath(points, 100.0);
      expect(result.first, equals(points.first));
      expect(result.last, equals(points.last));
    });
  });
}
```

- [ ] **Step 1.2: Run tests — verify they fail**

Run: `cd packages/splitway_core && dart test test/path_simplifier_test.dart`
Expected: compilation error — `simplifyPath` not defined.

- [ ] **Step 1.3: Implement `simplifyPath`**

Create `packages/splitway_core/lib/src/path_simplifier.dart`:

```dart
import 'dart:math' as math;

import '../models/geo_point.dart';

/// Simplifies a polyline using the Douglas-Peucker algorithm.
/// [toleranceMeters] is the maximum perpendicular distance (in meters) a point
/// can deviate from the simplified line before it's kept.
List<GeoPoint> simplifyPath(List<GeoPoint> points, double toleranceMeters) {
  if (points.length < 3) return List.of(points);

  final keep = List.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;

  _dpRecurse(points, 0, points.length - 1, toleranceMeters, keep);

  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}

void _dpRecurse(
  List<GeoPoint> points,
  int start,
  int end,
  double tolerance,
  List<bool> keep,
) {
  if (end - start < 2) return;

  double maxDist = 0;
  int maxIdx = start;

  final a = points[start];
  final b = points[end];

  for (var i = start + 1; i < end; i++) {
    final d = _perpendicularDistance(points[i], a, b);
    if (d > maxDist) {
      maxDist = d;
      maxIdx = i;
    }
  }

  if (maxDist > tolerance) {
    keep[maxIdx] = true;
    _dpRecurse(points, start, maxIdx, tolerance, keep);
    _dpRecurse(points, maxIdx, end, tolerance, keep);
  }
}

/// Perpendicular distance from [p] to the great-circle line segment [a]→[b],
/// approximated as planar since segments are short (sub-km).
double _perpendicularDistance(GeoPoint p, GeoPoint a, GeoPoint b) {
  final dx = b.longitude - a.longitude;
  final dy = b.latitude - a.latitude;
  final lenSq = dx * dx + dy * dy;
  if (lenSq < 1e-20) return a.distanceTo(p);

  var t = ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy) /
      lenSq;
  t = t.clamp(0.0, 1.0);

  final proj = GeoPoint(
    latitude: a.latitude + t * dy,
    longitude: a.longitude + t * dx,
  );
  return proj.distanceTo(p);
}
```

- [ ] **Step 1.4: Export from barrel file**

Add to `packages/splitway_core/lib/splitway_core.dart`:

```dart
export 'src/path_simplifier.dart';
```

- [ ] **Step 1.5: Run tests — verify they pass**

Run: `cd packages/splitway_core && dart test test/path_simplifier_test.dart -r expanded`
Expected: all 5 tests PASS.

- [ ] **Step 1.6: Commit**

```bash
git add packages/splitway_core/lib/src/path_simplifier.dart packages/splitway_core/test/path_simplifier_test.dart packages/splitway_core/lib/splitway_core.dart
git commit -m "feat(core): add simplifyPath Douglas-Peucker helper"
```

---

### Task 2: `DraftSegment` sealed class

**Files:**
- Create: `movile_app/lib/src/features/editor/draft_segment.dart`

- [ ] **Step 2.1: Create the sealed class file**

Create `movile_app/lib/src/features/editor/draft_segment.dart`:

```dart
import 'package:splitway_core/splitway_core.dart';

sealed class DraftSegment {
  const DraftSegment();

  /// The points this segment contributes to the display path.
  List<GeoPoint> get renderedPath;
}

class SnappedSegment extends DraftSegment {
  SnappedSegment()
      : waypoints = [],
        snappedPath = [];

  final List<GeoPoint> waypoints;

  /// Road-snapped path, or copy of [waypoints] when snap is unavailable.
  final List<GeoPoint> snappedPath;

  @override
  List<GeoPoint> get renderedPath =>
      snappedPath.isNotEmpty ? snappedPath : waypoints;
}

class FreehandSegment extends DraftSegment {
  FreehandSegment() : rawPoints = [], simplifiedPoints = [];

  /// Accumulated during pan gesture (distance-sampled, pre-simplification).
  final List<GeoPoint> rawPoints;

  /// Set after pan ends, via Douglas-Peucker. This is what gets stored.
  final List<GeoPoint> simplifiedPoints;

  @override
  List<GeoPoint> get renderedPath =>
      simplifiedPoints.isNotEmpty ? simplifiedPoints : rawPoints;
}
```

- [ ] **Step 2.2: Commit**

```bash
git add movile_app/lib/src/features/editor/draft_segment.dart
git commit -m "feat(editor): add DraftSegment sealed class model"
```

---

### Task 3: Add localization strings

**Files:**
- Modify: `movile_app/lib/l10n/app_en.arb`
- Modify: `movile_app/lib/l10n/app_es.arb`

- [ ] **Step 3.1: Add English strings**

Add the following entries to `movile_app/lib/l10n/app_en.arb` after the `"editorSegmentAddSector"` entry:

```json
"editorSegmentFreehand": "Freehand",
"editorModeFreehand": "Draw freehand",
"editorUndoFreehand": "Undo stroke",
```

- [ ] **Step 3.2: Add Spanish strings**

Add the following entries to `movile_app/lib/l10n/app_es.arb` after the `"editorSegmentAddSector"` entry:

```json
"editorSegmentFreehand": "A mano",
"editorModeFreehand": "Dibujo a mano alzada",
"editorUndoFreehand": "Deshacer trazo",
```

- [ ] **Step 3.3: Run l10n generation**

Run: `cd movile_app && flutter gen-l10n`
Expected: no errors; `app_localizations.dart` regenerated with new getters.

- [ ] **Step 3.4: Commit**

```bash
git add movile_app/lib/l10n/app_en.arb movile_app/lib/l10n/app_es.arb
git commit -m "feat(l10n): add freehand drawing strings"
```

---

### Task 4: Refactor controller to segment model (TDD)

**Files:**
- Modify: `movile_app/lib/src/features/editor/route_editor_controller.dart`
- Modify: `movile_app/test/features/editor/route_editor_controller_test.dart`

This is the largest task. It refactors the controller internals while keeping the public API compatible (getters return the same types, `handleMapTap` still works).

- [ ] **Step 4.1: Write failing tests for the new segment model**

Add to the **top** of `main()` in `route_editor_controller_test.dart`, before the existing `sectorPoint mode` group:

```dart
  group('segment-based drawing', () {
    test('taps in appendPath mode create a SnappedSegment', () {
      expect(ctrl.segments, hasLength(1));
      expect(ctrl.segments.first, isA<SnappedSegment>());
      expect((ctrl.segments.first as SnappedSegment).waypoints, hasLength(3));
    });

    test('draftPath concatenates all segment rendered paths', () {
      expect(ctrl.draftPath, hasLength(3));
    });

    test('switching to freehand and adding points creates FreehandSegment', () {
      ctrl.setInputMode(DrawInputMode.freehand);
      ctrl.startFreehandStroke();
      ctrl.addFreehandPoint(const GeoPoint(latitude: 40.0, longitude: -2.75));
      ctrl.addFreehandPoint(const GeoPoint(latitude: 40.0, longitude: -2.70));
      ctrl.endFreehandStroke();

      expect(ctrl.segments, hasLength(2));
      expect(ctrl.segments.last, isA<FreehandSegment>());
    });

    test('continuing appendPath after freehand creates new SnappedSegment', () {
      ctrl.setInputMode(DrawInputMode.freehand);
      ctrl.startFreehandStroke();
      ctrl.addFreehandPoint(const GeoPoint(latitude: 40.0, longitude: -2.75));
      ctrl.addFreehandPoint(const GeoPoint(latitude: 40.0, longitude: -2.70));
      ctrl.endFreehandStroke();

      ctrl.setInputMode(DrawInputMode.appendPath);
      ctrl.handleMapTap(const GeoPoint(latitude: 40.0, longitude: -2.65));

      expect(ctrl.segments, hasLength(3));
      expect(ctrl.segments[0], isA<SnappedSegment>());
      expect(ctrl.segments[1], isA<FreehandSegment>());
      expect(ctrl.segments[2], isA<SnappedSegment>());
    });
  });

  group('undo', () {
    test('undoLastAction removes last waypoint from SnappedSegment', () {
      ctrl.undoLastAction();
      expect(ctrl.draftPath, hasLength(2));
    });

    test('undoLastAction removes empty SnappedSegment', () {
      ctrl.undoLastAction(); // 2 waypoints
      ctrl.undoLastAction(); // 1 waypoint
      ctrl.undoLastAction(); // 0 → segment removed
      expect(ctrl.segments, isEmpty);
    });

    test('undoLastAction removes entire FreehandSegment', () {
      ctrl.setInputMode(DrawInputMode.freehand);
      ctrl.startFreehandStroke();
      ctrl.addFreehandPoint(const GeoPoint(latitude: 40.0, longitude: -2.75));
      ctrl.addFreehandPoint(const GeoPoint(latitude: 40.0, longitude: -2.70));
      ctrl.endFreehandStroke();

      ctrl.undoLastAction();
      expect(ctrl.segments, hasLength(1));
      expect(ctrl.segments.first, isA<SnappedSegment>());
    });
  });

  group('draftCanSave', () {
    test('true when total path has >= 2 points and name is set', () {
      expect(ctrl.draftCanSave, isTrue);
    });

    test('false with fewer than 2 total path points', () {
      ctrl.undoLastAction();
      ctrl.undoLastAction();
      expect(ctrl.draftCanSave, isFalse);
    });
  });
```

- [ ] **Step 4.2: Run tests — verify they fail**

Run: `cd movile_app && flutter test test/features/editor/route_editor_controller_test.dart`
Expected: compilation errors — `segments`, `startFreehandStroke`, `addFreehandPoint`, `endFreehandStroke`, `undoLastAction`, `DrawInputMode.freehand` not found.

- [ ] **Step 4.3: Add `freehand` to `DrawInputMode`**

In `movile_app/lib/src/features/editor/route_editor_controller.dart`, add to the enum:

```dart
enum DrawInputMode {
  appendPath,
  sectorPoint,
  freehand,
}
```

- [ ] **Step 4.4: Import `DraftSegment` and refactor controller state**

At the top of `route_editor_controller.dart`, add import:

```dart
import 'draft_segment.dart';
```

Replace the `_rawWaypoints` and `_draftPath` field declarations (and their getters) with:

```dart
  final List<DraftSegment> _segments = [];
  List<DraftSegment> get segments => List.unmodifiable(_segments);

  /// Road-following display path — concatenation of all segments.
  List<GeoPoint> get draftPath {
    final path = <GeoPoint>[];
    for (final seg in _segments) {
      final rendered = seg.renderedPath;
      if (rendered.isEmpty) continue;
      if (path.isNotEmpty && rendered.isNotEmpty && path.last == rendered.first) {
        path.addAll(rendered.skip(1));
      } else {
        path.addAll(rendered);
      }
    }
    return path;
  }

  /// Raw waypoints from snapped segments only (shown as circles on map).
  List<GeoPoint> get rawWaypoints {
    return [
      for (final seg in _segments)
        if (seg is SnappedSegment) ...seg.waypoints,
    ];
  }

  int get draftWaypointCount => rawWaypoints.length;
```

- [ ] **Step 4.5: Refactor `startDrawing` and `cancelDrawing` to use `_segments`**

Replace `_rawWaypoints.clear(); _draftPath.clear();` in both methods with:

```dart
    _segments.clear();
```

- [ ] **Step 4.6: Refactor `handleMapTap` for appendPath using segments**

Replace the `case DrawInputMode.appendPath:` body:

```dart
      case DrawInputMode.freehand:
        return; // Freehand input comes via startFreehandStroke/addFreehandPoint.
      case DrawInputMode.appendPath:
        final lastSeg = _segments.lastOrNull;
        final SnappedSegment seg;
        if (lastSeg is SnappedSegment) {
          seg = lastSeg;
        } else {
          seg = SnappedSegment();
          _segments.add(seg);
        }
        seg.waypoints.add(p);
        seg.snappedPath
          ..clear()
          ..addAll(seg.waypoints);
        notifyListeners();
        _scheduleSnap();
```

- [ ] **Step 4.7: Add freehand handler methods**

Add these methods to the controller class:

```dart
  FreehandSegment? _activeFreehand;

  void startFreehandStroke() {
    if (!_drawing) return;
    final seg = FreehandSegment();
    _segments.add(seg);
    _activeFreehand = seg;
    notifyListeners();
  }

  void addFreehandPoint(GeoPoint p) {
    final seg = _activeFreehand;
    if (seg == null) return;
    if (seg.rawPoints.isNotEmpty && seg.rawPoints.last.distanceTo(p) < 5.0) {
      return;
    }
    seg.rawPoints.add(p);
    notifyListeners();
  }

  void endFreehandStroke() {
    final seg = _activeFreehand;
    if (seg == null) return;
    _activeFreehand = null;
    if (seg.rawPoints.length < 2) {
      _segments.remove(seg);
      notifyListeners();
      return;
    }
    seg.simplifiedPoints
      ..clear()
      ..addAll(simplifyPath(seg.rawPoints, 4.0));
    notifyListeners();
  }
```

Also add the import at the top:

```dart
import 'package:splitway_core/splitway_core.dart' show GeoPoint, GateDefinition, RouteTemplate, SectorDefinition, RouteDifficulty, SessionRun, simplifyPath;
```

(Or just ensure `simplifyPath` is available through the existing `splitway_core` import.)

- [ ] **Step 4.8: Replace `undoLastPathPoint` with `undoLastAction`**

Remove the old `undoLastPathPoint()` method and add:

```dart
  void undoLastAction() {
    if (_segments.isEmpty) return;
    _cancelSnap();
    final last = _segments.last;
    switch (last) {
      case FreehandSegment():
        _segments.removeLast();
      case SnappedSegment():
        if (last.waypoints.isNotEmpty) {
          last.waypoints.removeLast();
          last.snappedPath
            ..clear()
            ..addAll(last.waypoints);
        }
        if (last.waypoints.isEmpty) {
          _segments.removeLast();
        } else if (last.waypoints.length >= 2 && routingService != null) {
          _scheduleSnap();
        }
    }
    notifyListeners();
  }
```

- [ ] **Step 4.9: Refactor `_scheduleSnap` / `_snapPath` to work on last SnappedSegment**

Replace `_snapPath()`:

```dart
  Future<void> _snapPath() async {
    if (routingService == null) return;
    final seg = _segments.lastOrNull;
    if (seg is! SnappedSegment || seg.waypoints.length < 2) return;

    final waypoints = List<GeoPoint>.of(seg.waypoints);
    final generation = ++_snapGeneration;

    _snapping = true;
    notifyListeners();

    final snapped = await routingService!.snapToRoads(waypoints);

    if (_snapGeneration != generation) return;

    _snapping = false;
    if (snapped != null && snapped.length >= 2) {
      _snapFailed = false;
      seg.snappedPath
        ..clear()
        ..addAll(snapped);
    } else {
      _snapFailed = true;
      seg.snappedPath
        ..clear()
        ..addAll(waypoints);
    }
    notifyListeners();
  }
```

Update `_scheduleSnap` condition:

```dart
  void _scheduleSnap() {
    final seg = _segments.lastOrNull;
    if (routingService == null || seg is! SnappedSegment || seg.waypoints.length < 2) return;
    _snapDebouncer?.cancel();
    _snapDebouncer = Timer(const Duration(milliseconds: 600), _snapPath);
  }
```

- [ ] **Step 4.10: Refactor `draftCanSave`**

Replace:

```dart
  bool get draftCanSave =>
      draftPath.length >= 2 && _draftName.trim().isNotEmpty;
```

- [ ] **Step 4.11: Refactor `saveDraft` to snap per segment**

Replace the body of `saveDraft()` with:

```dart
  Future<RouteTemplate?> saveDraft() async {
    if (!draftCanSave) return null;
    _cancelSnap();

    final pathParts = <List<GeoPoint>>[];

    for (final seg in _segments) {
      switch (seg) {
        case SnappedSegment():
          if (seg.waypoints.isEmpty) continue;
          if (routingService != null && seg.waypoints.length >= 2) {
            _snapping = true;
            notifyListeners();
            final snapped = await routingService!.snapToRoads(seg.waypoints);
            _snapping = false;
            notifyListeners();
            pathParts.add(snapped ?? List.of(seg.waypoints));
          } else {
            pathParts.add(List.of(seg.waypoints));
          }
        case FreehandSegment():
          if (seg.simplifiedPoints.isNotEmpty) {
            pathParts.add(List.of(seg.simplifiedPoints));
          } else if (seg.rawPoints.isNotEmpty) {
            pathParts.add(List.of(seg.rawPoints));
          }
      }
    }

    // Concatenate parts, deduplicating junction points.
    final finalPath = <GeoPoint>[];
    for (final part in pathParts) {
      if (part.isEmpty) continue;
      if (finalPath.isNotEmpty && part.isNotEmpty &&
          finalPath.last.distanceTo(part.first) < 1.0) {
        finalPath.addAll(part.skip(1));
      } else {
        finalPath.addAll(part);
      }
    }

    if (finalPath.length < 2) return null;

    final distFirstLast = finalPath.first.distanceTo(finalPath.last);
    final isClosed = distFirstLast <= 20.0;

    if (isClosed && finalPath.first != finalPath.last) {
      finalPath.add(finalPath.first);
    }

    debugPrint(
        'Route: ${isClosed ? "closed" : "open"} circuit, '
        'distance first<>last = ${distFirstLast.toStringAsFixed(1)} m');

    String? locationLabel;
    if (geocodingService != null && finalPath.isNotEmpty) {
      locationLabel = await geocodingService!.reverseGeocode(finalPath.first);
    }

    final startFinishGate = _perpendicularGate(finalPath[0], finalPath[1]);

    final id = 'route-${DateTime.now().microsecondsSinceEpoch}';
    final route = RouteTemplate(
      id: id,
      name: _draftName.trim(),
      description: _draftDescription?.trim().isEmpty ?? true
          ? null
          : _draftDescription!.trim(),
      locationLabel: locationLabel,
      path: List.unmodifiable(finalPath),
      startFinishGate: startFinishGate,
      sectors: [
        for (var i = 0; i < _draftSectorGates.length; i++)
          SectorDefinition(
            id: '$id-sec-${i + 1}',
            order: i,
            label: 'Sector ${i + 1}',
            gate: _draftSectorGates[i],
          ),
      ],
      difficulty: _draftDifficulty,
      createdAt: DateTime.now(),
    );

    await _repo.saveRouteTemplate(route);

    _drawing = false;
    _draftName = '';
    _draftDescription = null;
    _draftDifficulty = RouteDifficulty.medium;
    _segments.clear();
    _draftSectorGates.clear();
    _draftSectorPoints.clear();
    _inputMode = DrawInputMode.appendPath;
    _activeFreehand = null;

    await load();
    _selected = route;
    notifyListeners();
    return route;
  }
```

- [ ] **Step 4.12: Run tests — verify they pass**

Run: `cd movile_app && flutter test test/features/editor/route_editor_controller_test.dart -r expanded`
Expected: ALL tests PASS (both new segment tests and existing sectorPoint tests).

- [ ] **Step 4.13: Commit**

```bash
git add movile_app/lib/src/features/editor/route_editor_controller.dart movile_app/lib/src/features/editor/draft_segment.dart movile_app/test/features/editor/route_editor_controller_test.dart
git commit -m "feat(editor): refactor controller to segment-based draft model with freehand support"
```

---

### Task 5: Freehand gesture overlay in SplitwayMap

**Files:**
- Modify: `movile_app/lib/src/shared/widgets/splitway_map.dart`

- [ ] **Step 5.1: Add new widget properties**

Add these properties to `SplitwayMap`:

```dart
  /// When true, single-finger drag draws freehand instead of panning.
  final bool freehandMode;
  /// Segment types for per-segment color rendering. Parallel to [draftSegments].
  final List<DraftSegment> draftSegments;
  final VoidCallback? onFreehandStart;
  final ValueChanged<GeoPoint>? onFreehandPoint;
  final VoidCallback? onFreehandEnd;
```

Update the constructor to accept these (with defaults: `freehandMode = false`, `draftSegments = const []`, callbacks null).

- [ ] **Step 5.2: Update gesture settings when `freehandMode` changes**

In `didUpdateWidget`, add after the existing `if (!widget.useMapbox) return;`:

```dart
    if (oldWidget.freehandMode != widget.freehandMode) {
      _updateGesturesForFreehand();
    }
```

Add the helper:

```dart
  Future<void> _updateGesturesForFreehand() async {
    final map = _map;
    if (map == null) return;
    if (widget.freehandMode) {
      await map.gestures.updateSettings(mbx.GesturesSettings(
        scrollEnabled: false,
        pinchToZoomEnabled: true,
        doubleTapToZoomInEnabled: true,
        doubleTouchToZoomOutEnabled: true,
        rotateEnabled: false,
        quickZoomEnabled: false,
        pitchEnabled: false,
        pinchPanEnabled: false,
      ));
    } else if (widget.interactive) {
      await map.gestures.updateSettings(mbx.GesturesSettings(
        scrollEnabled: true,
        pinchToZoomEnabled: true,
        doubleTapToZoomInEnabled: true,
        doubleTouchToZoomOutEnabled: true,
        rotateEnabled: true,
        quickZoomEnabled: true,
        pitchEnabled: true,
        pinchPanEnabled: true,
      ));
    }
  }
```

- [ ] **Step 5.3: Add freehand gesture overlay in `build`**

Wrap the `MapWidget` in a `Stack` with a `GestureDetector` when `freehandMode` is true. Replace the current Mapbox return in `build`:

```dart
    final mapWidget = mbx.MapWidget(
      key: const ValueKey('splitway-mapbox'),
      styleUri: widget.styleUri ?? mbx.MapboxStyles.OUTDOORS,
      onMapCreated: _onMapCreated,
    );

    if (!widget.freehandMode) return mapWidget;

    return Stack(
      children: [
        mapWidget,
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: _onFreehandPanStart,
            onPanUpdate: _onFreehandPanUpdate,
            onPanEnd: _onFreehandPanEnd,
          ),
        ),
      ],
    );
```

- [ ] **Step 5.4: Implement freehand pan handlers**

Add these methods to `_SplitwayMapState`:

```dart
  void _onFreehandPanStart(DragStartDetails details) {
    widget.onFreehandStart?.call();
    _convertAndSendFreehandPoint(details.localPosition);
  }

  void _onFreehandPanUpdate(DragUpdateDetails details) {
    _convertAndSendFreehandPoint(details.localPosition);
  }

  void _onFreehandPanEnd(DragEndDetails details) {
    widget.onFreehandEnd?.call();
  }

  Future<void> _convertAndSendFreehandPoint(Offset screenPos) async {
    final map = _map;
    if (map == null) return;
    try {
      final point = await map.coordinateForPixel(mbx.ScreenCoordinate(
        x: screenPos.dx,
        y: screenPos.dy,
      ));
      final coords = point.coordinates;
      widget.onFreehandPoint?.call(GeoPoint(
        latitude: coords.lat.toDouble(),
        longitude: coords.lng.toDouble(),
      ));
    } catch (_) {
      // Conversion failed — skip this point.
    }
  }
```

- [ ] **Step 5.5: Update `_renderAnnotations` for per-segment colors**

Replace the `draftPath` rendering block (the one that draws the purple line at `0xFF6A1B9A`) with segment-aware rendering:

```dart
    // Draft segments: snapped = purple, freehand = orange.
    if (widget.draftSegments.isNotEmpty) {
      for (final seg in widget.draftSegments) {
        final rendered = seg.renderedPath;
        if (rendered.length < 2) continue;
        final color = seg is FreehandSegment ? 0xFFEF6C00 : 0xFF6A1B9A;
        await lineMgr.create(mbx.PolylineAnnotationOptions(
          geometry: _toLineString(rendered),
          lineColor: color,
          lineWidth: 3,
        ));
      }
    } else if (widget.draftPath.length >= 2) {
      // Backward compat: fall back to flat draftPath.
      await lineMgr.create(mbx.PolylineAnnotationOptions(
        geometry: _toLineString(widget.draftPath),
        lineColor: 0xFF6A1B9A,
        lineWidth: 3,
      ));
    }
```

- [ ] **Step 5.6: Update `didUpdateWidget` to detect segment changes**

In the `annotationsChanged` condition, add:

```dart
        oldWidget.draftSegments.length != widget.draftSegments.length ||
        oldWidget.freehandMode != widget.freehandMode ||
```

- [ ] **Step 5.7: Commit**

```bash
git add movile_app/lib/src/shared/widgets/splitway_map.dart
git commit -m "feat(map): add freehand gesture overlay and per-segment color rendering"
```

---

### Task 6: Wire freehand mode into DrawingView UI

**Files:**
- Modify: `movile_app/lib/src/features/editor/route_editor_screen.dart`

- [ ] **Step 6.1: Import `draft_segment.dart`**

Add at the top of `route_editor_screen.dart`:

```dart
import 'draft_segment.dart';
```

- [ ] **Step 6.2: Add freehand ChoiceChip to the mode bar**

In `_DrawingViewState.build`, inside the `Wrap` that contains the mode chips, add after the `sectorPoint` chip:

```dart
                    ChoiceChip(
                      label: Text(l.editorSegmentFreehand),
                      selected: controller.inputMode == DrawInputMode.freehand,
                      onSelected: (_) =>
                          controller.setInputMode(DrawInputMode.freehand),
                    ),
```

- [ ] **Step 6.3: Update the mode label helper**

In `_DrawingViewState._modeLabel`, add the freehand case:

```dart
  String _modeLabel(AppLocalizations l, DrawInputMode mode) => switch (mode) {
        DrawInputMode.appendPath => l.editorModeAppendPath,
        DrawInputMode.sectorPoint => l.editorModeSectorGate,
        DrawInputMode.freehand => l.editorModeFreehand,
      };
```

- [ ] **Step 6.4: Pass freehand props to SplitwayMap**

In the `SplitwayMap(...)` call inside `_DrawingViewState.build`, add:

```dart
                  freehandMode: controller.inputMode == DrawInputMode.freehand,
                  draftSegments: controller.segments,
                  onFreehandStart: controller.startFreehandStroke,
                  onFreehandPoint: controller.addFreehandPoint,
                  onFreehandEnd: controller.endFreehandStroke,
```

- [ ] **Step 6.5: Update undo button to call `undoLastAction`**

Replace `controller.undoLastPathPoint` with `controller.undoLastAction` in the `OutlinedButton.icon` for undo:

```dart
                    OutlinedButton.icon(
                      onPressed: controller.draftPath.isEmpty
                          ? null
                          : controller.undoLastAction,
                      icon: const Icon(Icons.undo, size: 18),
                      label: Text(l.editorUndoPoint),
                    ),
```

- [ ] **Step 6.6: Update `_DraftStatus` to count total path points**

In `_DraftStatus.build`, the path-points chip should use total draftPath length:

```dart
        _StatusChip(
          icon: Icons.timeline,
          label: l.editorPathPoints(controller.draftPath.length),
          ok: controller.draftPath.length >= 2,
        ),
```

(This replaces `controller.draftWaypointCount` with `controller.draftPath.length` so it includes freehand points in the count.)

- [ ] **Step 6.7: Run the app and test manually**

Run: `cd movile_app && flutter run`

Manual test checklist:
1. Create a new route → enter drawing mode
2. Tap 2+ waypoints in "Path" mode → see purple snapped line
3. Switch to "Freehand" → drag finger → see orange freehand line
4. Switch back to "Path" → tap more waypoints → see new purple segment appended
5. Pinch-zoom works while in freehand mode
6. Undo removes the freehand stroke entirely
7. Undo in path mode removes last waypoint
8. Save the route → route appears in the list with the full mixed path

- [ ] **Step 6.8: Commit**

```bash
git add movile_app/lib/src/features/editor/route_editor_screen.dart
git commit -m "feat(editor): wire freehand drawing mode into DrawingView UI"
```

---

### Task 7: Write save integration test with mixed segments

**Files:**
- Modify: `movile_app/test/features/editor/route_editor_controller_test.dart`

- [ ] **Step 7.1: Add save test with mixed segments**

Add a new group at the bottom of `main()`:

```dart
  group('saveDraft with mixed segments', () {
    test('produces concatenated path with freehand points intact', () async {
      // ctrl already has 3 tapped waypoints from setUp (SnappedSegment).
      // Add a freehand stroke.
      ctrl.setInputMode(DrawInputMode.freehand);
      ctrl.startFreehandStroke();
      ctrl.addFreehandPoint(const GeoPoint(latitude: 40.0, longitude: -2.75));
      ctrl.addFreehandPoint(const GeoPoint(latitude: 40.001, longitude: -2.70));
      ctrl.addFreehandPoint(const GeoPoint(latitude: 40.0, longitude: -2.65));
      ctrl.endFreehandStroke();

      // Add more tapped waypoints.
      ctrl.setInputMode(DrawInputMode.appendPath);
      ctrl.handleMapTap(const GeoPoint(latitude: 40.0, longitude: -2.60));
      ctrl.handleMapTap(const GeoPoint(latitude: 40.0, longitude: -2.55));

      final saved = await ctrl.saveDraft();
      expect(saved, isNotNull);
      // Path should contain all points: 3 snapped + freehand simplified + 2 snapped.
      expect(saved!.path.length, greaterThanOrEqualTo(5));
      // Freehand points should be present (not snapped away).
      expect(
        saved.path.any((p) =>
            (p.latitude - 40.001).abs() < 0.01 &&
            (p.longitude - (-2.70)).abs() < 0.01),
        isTrue,
      );
    });

    test('closed circuit detection works with mixed path', () async {
      // Clear and create a closed route: tap → freehand → tap back near start.
      final freshRepo = await _makeRepo();
      final freshCtrl = RouteEditorController(freshRepo);
      freshCtrl.startDrawing(name: 'Loop', difficulty: RouteDifficulty.easy);

      freshCtrl.handleMapTap(const GeoPoint(latitude: 40.0, longitude: -3.0));
      freshCtrl.handleMapTap(const GeoPoint(latitude: 40.0, longitude: -2.99));

      freshCtrl.setInputMode(DrawInputMode.freehand);
      freshCtrl.startFreehandStroke();
      freshCtrl.addFreehandPoint(const GeoPoint(latitude: 40.001, longitude: -2.98));
      freshCtrl.addFreehandPoint(const GeoPoint(latitude: 40.001, longitude: -3.01));
      freshCtrl.endFreehandStroke();

      freshCtrl.setInputMode(DrawInputMode.appendPath);
      // Tap very close to start (within 20 m).
      freshCtrl.handleMapTap(const GeoPoint(latitude: 40.0, longitude: -3.0001));

      final saved = await freshCtrl.saveDraft();
      expect(saved, isNotNull);
      expect(saved!.isClosed, isTrue);
    });
  });
```

- [ ] **Step 7.2: Run full test suite**

Run: `cd movile_app && flutter test test/features/editor/route_editor_controller_test.dart -r expanded`
Expected: ALL tests PASS.

- [ ] **Step 7.3: Run core tests too**

Run: `cd packages/splitway_core && dart test -r expanded`
Expected: ALL tests PASS.

- [ ] **Step 7.4: Commit**

```bash
git add movile_app/test/features/editor/route_editor_controller_test.dart
git commit -m "test(editor): add integration tests for mixed segment save and closed circuit"
```
