import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/features/editor/draft_segment.dart';
import 'package:splitway_mobile/src/features/editor/route_editor_controller.dart';

Future<LocalDraftRepository> _makeRepo() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await SplitwayLocalDatabase.open(overridePath: inMemoryDatabasePath);
  return LocalDraftRepository(db);
}

void main() {
  late LocalDraftRepository repo;
  late RouteEditorController ctrl;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    repo = await _makeRepo();
    ctrl = RouteEditorController(repo);
    ctrl.startDrawing(name: 'Test', difficulty: RouteDifficulty.medium);
    // Build a minimal draft path (3 collinear-ish points going east).
    ctrl.handleMapTap(const GeoPoint(latitude: 40.0, longitude: -3.0));
    ctrl.handleMapTap(const GeoPoint(latitude: 40.0, longitude: -2.9));
    ctrl.handleMapTap(const GeoPoint(latitude: 40.0, longitude: -2.8));
  });

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
      ctrl.undoLastAction(); // 0 -> segment removed
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

  group('sectorPoint mode', () {
    test('enum contains sectorPoint (not sectorGate)', () {
      expect(DrawInputMode.values.map((e) => e.name), contains('sectorPoint'));
      expect(DrawInputMode.values.map((e) => e.name),
          isNot(contains('sectorGate')));
    });

    test(
        'tap in sectorPoint mode snaps to nearest path vertex and adds a sector gate',
        () {
      ctrl.setInputMode(DrawInputMode.sectorPoint);
      // Tap near the middle vertex (-2.9 lng).
      ctrl.handleMapTap(const GeoPoint(latitude: 40.0002, longitude: -2.9));

      expect(ctrl.draftSectorGates, hasLength(1));
      // Gate center should be very close to the snapped path vertex.
      final center = ctrl.draftSectorGates.first.center;
      expect(
          center.distanceTo(const GeoPoint(latitude: 40.0, longitude: -2.9)),
          lessThan(50)); // within 50 m of the snapped vertex
    });

    test('two taps add two sector points', () {
      ctrl.setInputMode(DrawInputMode.sectorPoint);
      ctrl.handleMapTap(const GeoPoint(latitude: 40.0002, longitude: -2.9));
      ctrl.handleMapTap(const GeoPoint(latitude: 40.0002, longitude: -2.8));

      expect(ctrl.draftSectorGates, hasLength(2));
    });

    test('pendingGateLeft is always null in sectorPoint mode', () {
      ctrl.setInputMode(DrawInputMode.sectorPoint);
      ctrl.handleMapTap(const GeoPoint(latitude: 40.0002, longitude: -2.9));
      expect(ctrl.pendingGateLeft, isNull);
    });

    test('draftSectorPoints has same length as draftSectorGates', () {
      ctrl.setInputMode(DrawInputMode.sectorPoint);
      ctrl.handleMapTap(const GeoPoint(latitude: 40.0002, longitude: -2.9));
      expect(ctrl.draftSectorPoints, hasLength(1));
      ctrl.handleMapTap(const GeoPoint(latitude: 40.0002, longitude: -2.8));
      expect(ctrl.draftSectorPoints, hasLength(2));
    });

    test('tap far from the path in sectorPoint mode does nothing', () {
      ctrl.setInputMode(DrawInputMode.sectorPoint);
      // ~5.5 km north of the path — clearly outside the snap threshold.
      ctrl.handleMapTap(const GeoPoint(latitude: 40.05, longitude: -2.9));

      expect(ctrl.draftSectorGates, isEmpty);
      expect(ctrl.draftSectorPoints, isEmpty);
      expect(ctrl.canUndo, isTrue); // only the 3 path taps remain undoable
      ctrl.undoLastAction();
      expect(ctrl.draftPath, hasLength(2));
    });

    test('tap in sectorPoint mode with no draftPath does nothing', () async {
      // Fresh controller with no path.
      final emptyRepo = await _makeRepo();
      final emptyCtrl = RouteEditorController(emptyRepo);
      emptyCtrl.startDrawing(name: 'Empty', difficulty: RouteDifficulty.easy);
      emptyCtrl.setInputMode(DrawInputMode.sectorPoint);
      emptyCtrl.handleMapTap(const GeoPoint(latitude: 40.0, longitude: -3.0));

      expect(emptyCtrl.draftSectorGates, isEmpty);
    });
  });

  group('cancelDrawing resets sector points', () {
    test('draftSectorPoints cleared on cancel', () {
      ctrl.setInputMode(DrawInputMode.sectorPoint);
      ctrl.handleMapTap(const GeoPoint(latitude: 40.0002, longitude: -2.9));
      expect(ctrl.draftSectorPoints, hasLength(1));

      ctrl.cancelDrawing();
      expect(ctrl.draftSectorPoints, isEmpty);
    });
  });

  group('LIFO undo across path points and sectors', () {
    test('undoLastAction removes the most recently added sector first', () {
      ctrl.setInputMode(DrawInputMode.sectorPoint);
      ctrl.handleMapTap(const GeoPoint(latitude: 40.0002, longitude: -2.9));
      expect(ctrl.draftSectorPoints, hasLength(1));
      expect(ctrl.draftPath, hasLength(3));

      ctrl.undoLastAction();

      expect(ctrl.draftSectorPoints, isEmpty);
      expect(ctrl.draftSectorGates, isEmpty);
      // Path is untouched — the sector was the last action.
      expect(ctrl.draftPath, hasLength(3));
    });

    test('undo unwinds interleaved path and sector actions as a stack', () {
      // setUp added 3 path points. Add a sector, then another path point.
      ctrl.setInputMode(DrawInputMode.sectorPoint);
      ctrl.handleMapTap(const GeoPoint(latitude: 40.0002, longitude: -2.9));
      ctrl.setInputMode(DrawInputMode.appendPath);
      ctrl.handleMapTap(const GeoPoint(latitude: 40.0, longitude: -2.7));
      expect(ctrl.draftPath, hasLength(4));
      expect(ctrl.draftSectorPoints, hasLength(1));

      ctrl.undoLastAction(); // pops the last path point
      expect(ctrl.draftPath, hasLength(3));
      expect(ctrl.draftSectorPoints, hasLength(1));

      ctrl.undoLastAction(); // pops the sector
      expect(ctrl.draftPath, hasLength(3));
      expect(ctrl.draftSectorPoints, isEmpty);

      ctrl.undoLastAction(); // back to popping path points
      expect(ctrl.draftPath, hasLength(2));
    });

    test('canUndo is false once every action is undone', () {
      ctrl.setInputMode(DrawInputMode.sectorPoint);
      ctrl.handleMapTap(const GeoPoint(latitude: 40.0002, longitude: -2.9));
      ctrl.undoLastAction(); // sector
      ctrl.undoLastAction(); // path 3 -> 2
      ctrl.undoLastAction(); // path 2 -> 1
      ctrl.undoLastAction(); // path 1 -> 0, segment removed
      expect(ctrl.canUndo, isFalse);
      // Extra undo is a no-op.
      ctrl.undoLastAction();
      expect(ctrl.canUndo, isFalse);
    });
  });

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
}
