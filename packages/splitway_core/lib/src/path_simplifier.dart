import 'models/geo_point.dart';

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
