import 'package:splitway_core/splitway_core.dart';
import 'package:test/test.dart';

void main() {
  group('encodePolyline', () {
    test('encodes single point', () {
      final result = encodePolyline([
        const GeoPoint(latitude: -17.0, longitude: 145.0),
      ]);
      expect(result, isNotEmpty);
    });

    test('encodes known polyline correctly', () {
      // Google's example: (38.5, -120.2), (40.7, -120.95), (43.252, -126.453)
      final result = encodePolyline([
        const GeoPoint(latitude: 38.5, longitude: -120.2),
        const GeoPoint(latitude: 40.7, longitude: -120.95),
        const GeoPoint(latitude: 43.252, longitude: -126.453),
      ]);
      expect(result, '_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    });

    test('returns empty string for empty list', () {
      expect(encodePolyline([]), '');
    });
  });

  group('downsamplePath', () {
    test('returns same list when under maxPoints', () {
      final path = [
        const GeoPoint(latitude: 0, longitude: 0),
        const GeoPoint(latitude: 1, longitude: 1),
      ];
      expect(downsamplePath(path, maxPoints: 80), path);
    });

    test('downsamples to maxPoints keeping first and last', () {
      final path = List.generate(
        200,
        (i) => GeoPoint(latitude: i * 0.01, longitude: i * 0.01),
      );
      final result = downsamplePath(path, maxPoints: 10);
      expect(result.length, 10);
      expect(result.first, path.first);
      expect(result.last, path.last);
    });

    test('returns same list when exactly maxPoints', () {
      final path = List.generate(
        80,
        (i) => GeoPoint(latitude: i * 0.01, longitude: i * 0.01),
      );
      expect(downsamplePath(path, maxPoints: 80), path);
    });
  });
}
