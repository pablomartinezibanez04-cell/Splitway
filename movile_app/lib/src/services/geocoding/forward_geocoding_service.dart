import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:splitway_core/splitway_core.dart';

class ForwardGeocodingService {
  const ForwardGeocodingService({required this.accessToken, http.Client? client})
      : _client = client;

  final String accessToken;
  final http.Client? _client;

  Future<List<GeocodingResult>> search(String query) async {
    if (query.trim().isEmpty) return const [];

    final url = Uri.parse(
      'https://api.mapbox.com/search/geocode/v6/forward'
      '?q=${Uri.encodeComponent(query.trim())}'
      '&limit=5'
      '&access_token=$accessToken',
    );

    try {
      final client = _client ?? http.Client();
      final response = await client.get(url).timeout(const Duration(seconds: 5));
      if (_client == null) client.close();

      if (response.statusCode != 200) return const [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final features = json['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) return const [];

      final results = <GeocodingResult>[];
      for (final feature in features) {
        final map = feature as Map<String, dynamic>;
        final properties = map['properties'] as Map<String, dynamic>?;
        final geometry = map['geometry'] as Map<String, dynamic>?;
        if (properties == null || geometry == null) continue;

        final name = properties['full_address'] as String? ??
            properties['name'] as String?;
        final coords = geometry['coordinates'] as List<dynamic>?;
        if (name == null || coords == null || coords.length < 2) continue;

        results.add(GeocodingResult(
          name: name,
          coordinates: GeoPoint(
            latitude: (coords[1] as num).toDouble(),
            longitude: (coords[0] as num).toDouble(),
          ),
        ));
      }
      return results;
    } catch (_) {
      return const [];
    }
  }
}
