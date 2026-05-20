import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/tracking/location_service.dart';

void main() {
  group('LocationPermissionStatus', () {
    test('enum has all expected values', () {
      expect(LocationPermissionStatus.values, hasLength(4));
      expect(LocationPermissionStatus.values, contains(LocationPermissionStatus.granted));
      expect(LocationPermissionStatus.values, contains(LocationPermissionStatus.denied));
      expect(LocationPermissionStatus.values, contains(LocationPermissionStatus.permanentlyDenied));
      expect(LocationPermissionStatus.values, contains(LocationPermissionStatus.servicesDisabled));
    });
  });

  // Note: ensureBackgroundPermission() and positionStream() depend on
  // Geolocator platform channels which cannot be unit-tested without mocking
  // the plugin. Their behavior is validated through manual/integration testing
  // on real devices. The tests here verify the public API surface exists.
  group('LocationService API surface', () {
    test('positionStream accepts backgroundMode parameter', () {
      // Verify the method signature accepts the parameter without error.
      // The stream itself requires platform channels so we don't subscribe.
      expect(
        () => LocationService.positionStream(backgroundMode: true),
        returnsNormally,
      );
    });
  });
}
