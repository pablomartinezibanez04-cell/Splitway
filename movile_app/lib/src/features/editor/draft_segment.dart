import 'package:splitway_core/splitway_core.dart';

sealed class DraftSegment {
  const DraftSegment();

  /// The points this segment contributes to the display path.
  List<GeoPoint> get renderedPath;
}

class SnappedSegment extends DraftSegment {
  SnappedSegment({this.seedPoint})
      : waypoints = [],
        snappedPath = [];

  /// Inherited from the end of the previous segment; not user-tapped.
  /// Used as the starting waypoint for Mapbox snap but ignored by undo.
  final GeoPoint? seedPoint;

  final List<GeoPoint> waypoints;

  /// Road-snapped path, or copy of effective waypoints when snap is unavailable.
  final List<GeoPoint> snappedPath;

  List<GeoPoint> get effectiveWaypoints => [
        if (seedPoint != null) seedPoint!,
        ...waypoints,
      ];

  @override
  List<GeoPoint> get renderedPath =>
      snappedPath.isNotEmpty ? snappedPath : effectiveWaypoints;
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
