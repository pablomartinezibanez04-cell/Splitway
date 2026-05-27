import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:splitway_core/splitway_core.dart';

import '../logging/app_logger.dart';
import '../logging/http_logging.dart';

class ElevationService {
  ElevationService({
    String baseUrl = 'https://api.open-meteo.com/v1/elevation',
  }) : _base = baseUrl;

  final String _base;

  static const _maxPerRequest = 100;

  /// Fetches elevation for [points] and returns a new list with
  /// [GeoPoint.altitudeMeters] populated. Points that already have altitude
  /// are kept as-is. Returns the original list unchanged on failure.
  Future<List<GeoPoint>> enrich(List<GeoPoint> points) async {
    if (points.isEmpty) return points;

    final sampled = _sampleIndices(points.length, _maxPerRequest);
    final queryPoints = sampled.map((i) => points[i]).toList();

    final elevations = await _fetchElevations(queryPoints);
    if (elevations == null) return points;

    final elevationByIndex = <int, double>{};
    for (var i = 0; i < sampled.length; i++) {
      elevationByIndex[sampled[i]] = elevations[i];
    }

    final result = <GeoPoint>[];
    for (var i = 0; i < points.length; i++) {
      final known = elevationByIndex[i];
      if (known != null) {
        result.add(GeoPoint(
          latitude: points[i].latitude,
          longitude: points[i].longitude,
          altitudeMeters: known,
        ));
      } else {
        final alt = _interpolate(i, elevationByIndex);
        result.add(GeoPoint(
          latitude: points[i].latitude,
          longitude: points[i].longitude,
          altitudeMeters: alt,
        ));
      }
    }
    return result;
  }

  Future<List<double>?> _fetchElevations(List<GeoPoint> points) async {
    final lats = points.map((p) => p.latitude.toStringAsFixed(5)).join(',');
    final lngs = points.map((p) => p.longitude.toStringAsFixed(5)).join(',');
    final uri = Uri.parse('$_base?latitude=$lats&longitude=$lngs');

    try {
      final response = await logHttp(
        'elevation',
        uri,
        () => http.get(uri).timeout(const Duration(seconds: 10)),
      );
      if (response.statusCode != 200) {
        debugPrint('ElevationService: error ${response.statusCode}');
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = data['elevation'] as List<dynamic>;
      return raw.map((e) => (e as num).toDouble()).toList();
    } catch (e, st) {
      debugPrint('ElevationService error: $e');
      AppLogger.maybeInstance?.warning(
        'elevation',
        'ElevationService.fetch failed',
        error: e,
        stackTrace: st,
        context: {'url': uri.toString()},
      );
      return null;
    }
  }

  /// Evenly samples up to [max] indices from [0, length).
  static List<int> _sampleIndices(int length, int max) {
    if (length <= max) return List.generate(length, (i) => i);
    final step = (length - 1) / (max - 1);
    return List.generate(max, (i) => min((i * step).round(), length - 1));
  }

  /// Linearly interpolates elevation for index [i] from the two nearest
  /// sampled neighbours in [known].
  static double? _interpolate(int i, Map<int, double> known) {
    int? lower;
    int? upper;
    for (final k in known.keys) {
      if (k <= i && (lower == null || k > lower)) lower = k;
      if (k >= i && (upper == null || k < upper)) upper = k;
    }
    if (lower == null && upper == null) return null;
    if (lower == null) return known[upper];
    if (upper == null) return known[lower];
    if (lower == upper) return known[lower];
    final t = (i - lower) / (upper - lower);
    return known[lower]! + t * (known[upper]! - known[lower]!);
  }
}
