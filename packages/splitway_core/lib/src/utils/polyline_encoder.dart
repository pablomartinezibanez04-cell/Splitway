import '../models/geo_point.dart';

/// Encodes a list of [GeoPoint]s into a Google Encoded Polyline string.
///
/// See: https://developers.google.com/maps/documentation/utilities/polylinealgorithm
String encodePolyline(List<GeoPoint> points) {
  if (points.isEmpty) return '';
  final buf = StringBuffer();
  int prevLat = 0;
  int prevLng = 0;

  for (final point in points) {
    final lat = (point.latitude * 1e5).round();
    final lng = (point.longitude * 1e5).round();
    _encode(lat - prevLat, buf);
    _encode(lng - prevLng, buf);
    prevLat = lat;
    prevLng = lng;
  }
  return buf.toString();
}

void _encode(int value, StringBuffer buf) {
  var v = value < 0 ? ~(value << 1) : (value << 1);
  while (v >= 0x20) {
    buf.writeCharCode((0x20 | (v & 0x1f)) + 63);
    v >>= 5;
  }
  buf.writeCharCode(v + 63);
}

/// Reduces [path] to at most [maxPoints] points using even-interval sampling.
/// Always keeps the first and last point.
List<GeoPoint> downsamplePath(List<GeoPoint> path, {int maxPoints = 80}) {
  if (path.length <= maxPoints) return path;

  final result = <GeoPoint>[path.first];
  final step = (path.length - 1) / (maxPoints - 1);
  for (var i = 1; i < maxPoints - 1; i++) {
    result.add(path[(i * step).round()]);
  }
  result.add(path.last);
  return result;
}
