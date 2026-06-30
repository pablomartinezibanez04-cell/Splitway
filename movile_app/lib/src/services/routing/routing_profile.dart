import '../garage/vehicle.dart';

/// Maps the recording vehicle to the Mapbox routing profile used to estimate a
/// free ride's "normal time": bicycles route over bike paths, on-foot rides use
/// walking, and everything motorized (car/motorcycle/kart) — plus the catch-all
/// `other` — uses driving.
String routingProfileForVehicle(VehicleType? type) => switch (type) {
      null => 'walking',
      VehicleType.bicycle => 'cycling',
      VehicleType.car ||
      VehicleType.motorcycle ||
      VehicleType.goKart ||
      VehicleType.other =>
        'driving',
    };
