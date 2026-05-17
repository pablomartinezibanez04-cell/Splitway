import 'package:splitway_core/splitway_core.dart';
import 'package:test/test.dart';

void main() {
  group('simplifyPath', () {
    test('returns input unchanged when fewer than 3 points', () {
      final two = [
        const GeoPoint(latitude: 40.0, longitude: -3.0),
        const GeoPoint(latitude: 40.1, longitude: -3.0),
      ];
      expect(simplifyPath(two, 10.0), equals(two));
    });

    test('returns input unchanged for empty list', () {
      expect(simplifyPath([], 10.0), isEmpty);
    });

    test('collinear points within tolerance collapse to endpoints', () {
      final points = [
        const GeoPoint(latitude: 40.0, longitude: -3.0),
        const GeoPoint(latitude: 40.0, longitude: -2.95),
        const GeoPoint(latitude: 40.0, longitude: -2.9),
      ];
      final result = simplifyPath(points, 10.0);
      expect(result, hasLength(2));
      expect(result.first, equals(points.first));
      expect(result.last, equals(points.last));
    });

    test('preserves point that deviates beyond tolerance', () {
      final points = [
        const GeoPoint(latitude: 40.0, longitude: -3.0),
        const GeoPoint(latitude: 40.001, longitude: -2.95),
        const GeoPoint(latitude: 40.0, longitude: -2.9),
      ];
      final result = simplifyPath(points, 50.0);
      expect(result, hasLength(3));
    });

    test('always preserves first and last points', () {
      final points = [
        const GeoPoint(latitude: 40.0, longitude: -3.0),
        const GeoPoint(latitude: 40.0, longitude: -2.99),
        const GeoPoint(latitude: 40.0, longitude: -2.98),
        const GeoPoint(latitude: 40.0, longitude: -2.97),
        const GeoPoint(latitude: 40.0, longitude: -2.9),
      ];
      final result = simplifyPath(points, 100.0);
      expect(result.first, equals(points.first));
      expect(result.last, equals(points.last));
    });
  });
}
