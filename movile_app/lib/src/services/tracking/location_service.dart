import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:splitway_core/splitway_core.dart';

enum LocationPermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  servicesDisabled,
}

class LocationService {
  LocationService._();

  /// Walks the user through enabling location services + granting fine
  /// permission. Returns the resolved [LocationPermissionStatus] so the UI
  /// can show the right hint.
  static Future<LocationPermissionStatus> ensurePermission() async {
    final servicesOn = await Geolocator.isLocationServiceEnabled();
    if (!servicesOn) return LocationPermissionStatus.servicesDisabled;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse =>
        LocationPermissionStatus.granted,
      LocationPermission.deniedForever =>
        LocationPermissionStatus.permanentlyDenied,
      _ => LocationPermissionStatus.denied,
    };
  }

  /// Stream of GPS samples mapped to [TelemetryPoint]. Caller must hold
  /// the subscription and cancel it on dispose.
  static Stream<TelemetryPoint> positionStream({
    int distanceFilterMeters = 0,
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
  }) {
    final settings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilterMeters,
    );
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (p) => TelemetryPoint(
        timestamp: p.timestamp,
        location: GeoPoint(
          latitude: p.latitude,
          longitude: p.longitude,
          altitudeMeters: p.altitude,
        ),
        speedMps: p.speed,
        accuracyMeters: p.accuracy,
        bearingDeg: p.heading,
        altitudeMeters: p.altitude,
      ),
    );
  }
}
