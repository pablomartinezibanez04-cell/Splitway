import 'geo_point.dart';

class GeocodingResult {
  const GeocodingResult({required this.name, required this.coordinates});

  final String name;
  final GeoPoint coordinates;
}
