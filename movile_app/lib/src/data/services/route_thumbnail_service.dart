import 'package:http/http.dart' as http;
import 'package:splitway_core/splitway_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/logging/http_logging.dart';

/// Downloads a Mapbox Static API image of a route and uploads it to
/// Supabase Storage, returning a signed URL valid for 1 year.
class RouteThumbnailService {
  RouteThumbnailService({
    required SupabaseClient supabase,
    required String mapboxToken,
    http.Client? httpClient,
  })  : _supabase = supabase,
        _mapboxToken = mapboxToken,
        _http = httpClient ?? http.Client();

  final SupabaseClient _supabase;
  final String _mapboxToken;
  final http.Client _http;

  static const _bucket = 'route-thumbnails';
  static const _width = 200;
  static const _height = 120;
  static const _strokeWidth = 3;
  static const _strokeColor = 'e74c3c';
  static const _maxPoints = 80;
  static const _signedUrlExpiry = 365 * 24 * 3600; // 1 year

  /// Generates a thumbnail for [route], uploads it to Supabase Storage,
  /// and returns a 1-year signed URL.
  Future<String> generate(RouteTemplate route, String userId) async {
    // 1. Downsample + encode
    final sampled = downsamplePath(route.path, maxPoints: _maxPoints);
    final polyline = encodePolyline(sampled);
    final encodedPolyline = Uri.encodeComponent(polyline);

    // 2. Build Mapbox Static API URL
    final url = Uri.parse(
      'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/static'
      '/path-$_strokeWidth+$_strokeColor-1($encodedPolyline)'
      '/auto/${_width}x$_height'
      '?access_token=$_mapboxToken&padding=20',
    );

    // 3. Download PNG
    final response = await logHttp('mapbox', url, () => _http.get(url));
    if (response.statusCode != 200) {
      throw Exception(
        'Mapbox Static API error ${response.statusCode}: ${response.body}',
      );
    }

    // 4. Upload to Supabase Storage (upsert)
    final storagePath = '$userId/${route.id}.png';
    await logSupabase(
      'thumbnail.upload',
      () => _supabase.storage.from(_bucket).uploadBinary(
            storagePath,
            response.bodyBytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/png',
            ),
          ),
    );

    // 5. Create signed URL (1 year)
    return logSupabase(
      'thumbnail.signedUrl',
      () => _supabase.storage
          .from(_bucket)
          .createSignedUrl(storagePath, _signedUrlExpiry),
    );
  }
}
