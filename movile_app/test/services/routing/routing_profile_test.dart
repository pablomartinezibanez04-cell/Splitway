import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/garage/vehicle.dart';
import 'package:splitway_mobile/src/services/routing/routing_profile.dart';

void main() {
  test('null vehicle (on foot) → walking', () {
    expect(routingProfileForVehicle(null), 'walking');
  });

  test('bicycle → cycling', () {
    expect(routingProfileForVehicle(VehicleType.bicycle), 'cycling');
  });

  test('motorized and other → driving', () {
    expect(routingProfileForVehicle(VehicleType.car), 'driving');
    expect(routingProfileForVehicle(VehicleType.motorcycle), 'driving');
    expect(routingProfileForVehicle(VehicleType.goKart), 'driving');
    expect(routingProfileForVehicle(VehicleType.other), 'driving');
  });
}
