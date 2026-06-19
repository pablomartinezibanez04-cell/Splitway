import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:splitway_core/splitway_core.dart';

import '../logging/app_logger.dart';
import '../logging/http_logging.dart';

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
    http.Client? client,
  })  : _token = mapboxToken,
        _base = baseUrl,
        _client = client;

  final String _token;
  final String _base;
  final http.Client? _client;

  static const _maxWaypoints = 25;

  /// Half-angle (degrees) used for each waypoint's [bearings] filter. The two
  /// carriageways of a divided road run ~180° apart, so a 45° window keeps the
  /// snap on the carriage going the user's way while tolerating tap jitter.
  static const _bearingToleranceDeg = 45;

  /// Below this spacing (m) the direction between two consecutive taps is just
  /// jitter, so no bearing is constrained for that waypoint.
  static const _minBearingSpacingMeters = 10.0;

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

    // Constrain each waypoint to road segments running in the user's intended
    // direction of travel, so a tap near a divided road snaps to the correct
    // carriageway instead of the oncoming one (which forces a long detour to
    // turn around). The travel direction is taken from the outgoing segment
    // (incoming for the final waypoint).
    final bearings = _bearingsParam(sampled);

    final uri = Uri.parse(
      '$_base/directions/v5/mapbox/$profile/$coords'
      '?geometries=geojson&overview=full'
      '${bearings != null ? '&bearings=$bearings' : ''}'
      '&access_token=$_token',
    );

    try {
      final client = _client ?? http.Client();
      final response = await logHttp(
        'mapbox',
        uri,
        () => client.get(uri).timeout(const Duration(seconds: 10)),
      );
      if (_client == null) client.close();

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
    } catch (e, st) {
      debugPrint('RoutingService error: $e');
      AppLogger.maybeInstance?.warning(
        'mapbox',
        'RoutingService.snapToRoads failed',
        error: e,
        stackTrace: st,
        context: {'url': uri.toString()},
      );
      return null;
    }
  }

  /// Builds the Directions API `bearings` value: one `{angle},{tolerance}`
  /// pair per waypoint, empty where the local direction is unreliable. Returns
  /// `null` when no waypoint has a usable bearing (so the param is omitted).
  static String? _bearingsParam(List<GeoPoint> points) {
    final entries = <String>[];
    var anyConstrained = false;
    for (var i = 0; i < points.length; i++) {
      // Outgoing direction, or the incoming one for the last point.
      final from = i < points.length - 1 ? points[i] : points[i - 1];
      final to = i < points.length - 1 ? points[i + 1] : points[i];
      if (from.distanceTo(to) < _minBearingSpacingMeters) {
        entries.add('');
        continue;
      }
      anyConstrained = true;
      entries.add('${from.bearingTo(to).round()},$_bearingToleranceDeg');
    }
    return anyConstrained ? entries.join(';') : null;
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
