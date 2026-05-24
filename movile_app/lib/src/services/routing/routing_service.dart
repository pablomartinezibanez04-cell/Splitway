import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:splitway_core/splitway_core.dart';

/// Calls the Mapbox Directions API to convert a list of user-tapped
/// waypoints into a road-following path.
///
/// Uses the **public** Mapbox access token (same one used for the map tiles)
/// with the `mapbox/driving` profile by default.
///
/// The Directions API supports up to 25 waypoints per request. If the user
/// tapped more points, [snapToRoads] samples them evenly down to 25 and the
/// returned geometry is the full road-following polyline between those
/// sampled waypoints.
class RoutingService {
  RoutingService({
    required String mapboxToken,
    String baseUrl = 'https://api.mapbox.com',
  })  : _token = mapboxToken,
        _base = baseUrl;

  final String _token;
  final String _base;

  static const _maxWaypoints = 25;

  /// Returns the road-following geometry for [waypoints], or `null` if the
  /// API call fails (no internet, invalid token, etc.).
  ///
  /// [profile] defaults to `'driving'` but can be `'cycling'` or `'walking'`.
  Future<List<GeoPoint>?> snapToRoads(
    List<GeoPoint> waypoints, {
    String profile = 'driving',
  }) async {
    if (waypoints.length < 2) return null;

    // Sample evenly if more than 25 waypoints.
    final sampled = _sample(waypoints, _maxWaypoints);

    final coords =
        sampled.map((p) => '${p.longitude},${p.latitude}').join(';');

    final uri = Uri.parse(
      '$_base/directions/v5/mapbox/$profile/$coords'
      '?geometries=geojson&overview=full&access_token=$_token',
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint(
            'RoutingService: Directions API error ${response.statusCode}: ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        debugPrint('RoutingService: no routes returned');
        return null;
      }

      final geometry = routes[0]['geometry']['coordinates'] as List;
      return geometry
          .map((c) => GeoPoint(
                latitude: (c[1] as num).toDouble(),
                longitude: (c[0] as num).toDouble(),
              ))
          .toList();
    } catch (e) {
      debugPrint('RoutingService error: $e');
      return null;
    }
  }

  /// Sample [points] evenly to at most [max] entries, always keeping the
  /// first and last point.
  static List<GeoPoint> _sample(List<GeoPoint> points, int max) {
    if (points.length <= max) return points;
    final result = <GeoPoint>[];
    final step = (points.length - 1) / (max - 1);
    for (var i = 0; i < max; i++) {
      result.add(points[(i * step).round()]);
    }
    return result;
  }
}
