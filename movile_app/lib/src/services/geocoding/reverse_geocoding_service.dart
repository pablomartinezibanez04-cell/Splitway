import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:splitway_core/splitway_core.dart';

import '../logging/app_logger.dart';
import '../logging/http_logging.dart';

/// Calls the Mapbox Reverse Geocoding API v6 to convert a [GeoPoint] into a
/// human-readable place name (e.g. "Madrid, Spain").
class ReverseGeocodingService {
  const ReverseGeocodingService({required this.accessToken, http.Client? client})
      : _client = client;

  final String accessToken;
  final http.Client? _client;

  /// Returns a location label like "City, Country" or null if the lookup fails.
  Future<String?> reverseGeocode(GeoPoint point) async {
    final url = Uri.parse(
      'https://api.mapbox.com/search/geocode/v6/reverse'
      '?longitude=${point.longitude}'
      '&latitude=${point.latitude}'
      '&types=place'
      '&limit=1'
      '&access_token=$accessToken',
    );

    try {
      final client = _client ?? http.Client();
      final response = await logHttp(
        'mapbox',
        url,
        () => client.get(url).timeout(const Duration(seconds: 5)),
      );
      if (_client == null) client.close();

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) return null;

      final properties =
          (features.first as Map<String, dynamic>)['properties'] as Map<String, dynamic>?;
      if (properties == null) return null;

      final placeName = properties['full_address'] as String? ??
          properties['name'] as String?;
      return placeName;
    } catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'mapbox',
        'reverseGeocode failed',
        error: e,
        stackTrace: st,
        context: {'url': url.toString()},
      );
      return null;
    }
  }
}
