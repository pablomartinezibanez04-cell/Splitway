import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:splitway_core/splitway_core.dart';

import '../logging/app_logger.dart';

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
    if (!servicesOn) {
      AppLogger.maybeInstance?.warning(
        'location',
        'Location services disabled',
      );
      return LocationPermissionStatus.servicesDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      AppLogger.maybeInstance?.warning(
        'location',
        'GPS permission denied',
        context: {'permission': permission.name},
      );
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

  /// Requests the 'always' location permission needed for background tracking.
  /// Must be called after [ensurePermission] has already obtained 'whileInUse'.
  static Future<LocationPermissionStatus> ensureBackgroundPermission() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always) {
      return LocationPermissionStatus.granted;
    }
    final upgraded = await Geolocator.requestPermission();
    return switch (upgraded) {
      LocationPermission.always => LocationPermissionStatus.granted,
      LocationPermission.deniedForever =>
        LocationPermissionStatus.permanentlyDenied,
      _ => LocationPermissionStatus.denied,
    };
  }

  /// Stream of GPS samples mapped to [TelemetryPoint]. Caller must hold
  /// the subscription and cancel it on dispose.
  ///
  /// Set [backgroundMode] to true when tracking while the app is backgrounded.
  /// On iOS this switches to [AppleSettings] with background location updates
  /// enabled; on other platforms it falls back to generic [LocationSettings].
  static Stream<TelemetryPoint> positionStream({
    int distanceFilterMeters = 0,
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
    bool backgroundMode = false,
    Duration updateInterval = const Duration(milliseconds: 500),
  }) {
    final LocationSettings settings;
    if (Platform.isIOS) {
      settings = AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
        allowBackgroundLocationUpdates: backgroundMode,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: backgroundMode,
        activityType: ActivityType.otherNavigation,
      );
    } else if (Platform.isAndroid) {
      // Request sub-second updates from the fused location provider so the
      // map and metrics tick faster than the default 1 Hz cadence.
      settings = AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
        intervalDuration: updateInterval,
        forceLocationManager: false,
      );
    } else {
      settings = LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
      );
    }
    return Geolocator.getPositionStream(locationSettings: settings)
        .handleError((Object e, StackTrace st) {
      AppLogger.maybeInstance?.warning(
        'location',
        'Position stream error',
        error: e,
        stackTrace: st,
      );
    }).map(
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
