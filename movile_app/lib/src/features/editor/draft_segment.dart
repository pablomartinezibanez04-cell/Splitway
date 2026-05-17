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
