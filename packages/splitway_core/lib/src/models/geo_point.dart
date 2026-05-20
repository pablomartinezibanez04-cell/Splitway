import 'dart:math' as math;

class GeoPoint {
  const GeoPoint({
    required this.latitude,
    required this.longitude,
    this.altitudeMeters,
  });

  final double latitude;
  final double longitude;
  final double? altitudeMeters;

  static const double _earthRadiusMeters = 6371000.0;

  double distanceTo(GeoPoint other) {
    final lat1 = _toRadians(latitude);
    final lat2 = _toRadians(other.latitude);
    final dLat = _toRadians(other.latitude - latitude);
    final dLon = _toRadians(other.longitude - longitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  double bearingTo(GeoPoint other) {
    final lat1 = _toRadians(latitude);
    final lat2 = _toRadians(other.latitude);
    final dLon = _toRadians(other.longitude - longitude);
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final bearing = math.atan2(y, x);
    return (_toDegrees(bearing) + 360) % 360;
  }

  /// Returns the point located [distanceMeters] away from this point
  /// in the direction of [bearingDeg] (0° = north, clockwise).
  GeoPoint destinationPoint(double bearingDeg, double distanceMeters) {
    const R = _earthRadiusMeters;
    final angDist = distanceMeters / R; // angular distance in radians
    final theta = _toRadians(bearingDeg);
    final lat1 = _toRadians(latitude);
    final lon1 = _toRadians(longitude);

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angDist) +
          math.cos(lat1) * math.sin(angDist) * math.cos(theta),
    );
    final lon2 = lon1 +
        math.atan2(
          math.sin(theta) * math.sin(angDist) * math.cos(lat1),
          math.cos(angDist) - math.sin(lat1) * math.sin(lat2),
        );

    return GeoPoint(
      latitude: _toDegrees(lat2),
      longitude: (_toDegrees(lon2) + 540) % 360 - 180, // normalise to [-180, 180]
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'altitudeMeters': altitudeMeters,
      };

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        altitudeMeters: (json['altitudeMeters'] as num?)?.toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoPoint &&
          other.latitude == latitude &&
          other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;
  static double _toDegrees(double radians) => radians * 180.0 / math.pi;
}
