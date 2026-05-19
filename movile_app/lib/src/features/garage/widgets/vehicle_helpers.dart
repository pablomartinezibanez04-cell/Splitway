import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import '../../../services/garage/vehicle.dart';

IconData vehicleTypeIcon(VehicleType type) => switch (type) {
  VehicleType.car => Icons.directions_car,
  VehicleType.motorcycle => Icons.two_wheeler,
  VehicleType.bicycle => Icons.pedal_bike,
  VehicleType.goKart => Icons.sports_motorsports,
  VehicleType.other => Icons.commute,
};

String vehicleTypeLabel(AppLocalizations l, VehicleType type) => switch (type) {
  VehicleType.car => l.vehicleTypeCar,
  VehicleType.motorcycle => l.vehicleTypeMotorcycle,
  VehicleType.bicycle => l.vehicleTypeBicycle,
  VehicleType.goKart => l.vehicleTypeGoKart,
  VehicleType.other => l.vehicleTypeOther,
};
