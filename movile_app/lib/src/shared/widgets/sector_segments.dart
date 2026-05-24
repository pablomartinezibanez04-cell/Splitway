import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';

/// ARGB color palette for sector segments, used by both map renderers.
const kSectorColors = [
  Color(0xFFD32F2F),
  Color(0xFF6A1B9A),
  Color(0xFF00838F),
  Color(0xFFF57F17),
  Color(0xFF558B2F),
  Color(0xFF4527A0),
  Color(0xFFAD1457),
  Color(0xFF00695C),
];

/// Splits [path] at the path indices nearest to each sector gate centre.
/// Returns one sub-list per colored segment (always at least 1 element).
List<List<GeoPoint>> computeSectorSegments(
    List<GeoPoint> path, List<SectorDefinition> sectors) {
  if (sectors.isEmpty || path.length < 2) return [path];

  final breakIndices = sectors.map((s) {
    int bestIdx = 0;
    double bestDist = path[0].distanceTo(s.gate.center);
    for (var i = 1; i < path.length; i++) {
      final d = path[i].distanceTo(s.gate.center);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }).toSet().toList()
    ..sort();

  final segments = <List<GeoPoint>>[];
  int start = 0;
  for (final bp in breakIndices) {
    if (bp > start) segments.add(path.sublist(start, bp + 1));
    start = bp;
  }
  if (start < path.length) segments.add(path.sublist(start));
  return segments;
}
