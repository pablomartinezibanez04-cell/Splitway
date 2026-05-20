# Background Location Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow route recording (free ride and normal sessions) to continue capturing GPS data when the screen turns off or the app goes to the background.

**Architecture:** `flutter_foreground_task` manages the Android foreground service lifecycle and persistent notification. `geolocator` continues to power the GPS stream in the main isolate, using `AppleSettings` on iOS to enable background updates. Controllers coordinate service start/stop and notification updates.

**Tech Stack:** Flutter, geolocator ^14.0.0 (existing), flutter_foreground_task (new), dart:io (Platform detection)

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `lib/src/services/tracking/background_tracking_service.dart` | Wraps `flutter_foreground_task`: init, start, stop, updateNotification, isRunning |
| Modify | `lib/src/services/tracking/location_service.dart` | Add `ensureBackgroundPermission()`, add `backgroundMode` param to `positionStream()` |
| Modify | `lib/src/features/free_ride/free_ride_controller.dart` | Integrate background service start/stop/update into recording lifecycle |
| Modify | `lib/src/features/session/live_session_controller.dart` | Same integration for normal route sessions |
| Modify | `lib/src/features/free_ride/free_ride_screen.dart` | Show background status banner/chip |
| Modify | `lib/src/features/session/live_session_screen.dart` | Same background banner/chip |
| Modify | `lib/main.dart` | Call `BackgroundTrackingService.init()` before `runApp()` |
| Modify | `android/app/src/main/AndroidManifest.xml` | Add background location, foreground service permissions and service declaration |
| Modify | `ios/Runner/Info.plist` | Add always-location description and UIBackgroundModes |
| Modify | `lib/l10n/app_en.arb` | New l10n strings (EN) |
| Modify | `lib/l10n/app_es.arb` | New l10n strings (ES) |
| Modify | `pubspec.yaml` | Add `flutter_foreground_task` dependency |
| Create | `test/services/tracking/background_tracking_service_test.dart` | Unit tests for throttling logic and state management |
| Create | `test/services/tracking/location_service_test.dart` | Unit tests for `ensureBackgroundPermission()` and platform-aware settings |

---

### Task 1: Add `flutter_foreground_task` dependency and native config

**Files:**
- Modify: `movile_app/pubspec.yaml`
- Modify: `movile_app/android/app/src/main/AndroidManifest.xml`
- Modify: `movile_app/ios/Runner/Info.plist`

- [ ] **Step 1: Add package to pubspec.yaml**

In `movile_app/pubspec.yaml`, add `flutter_foreground_task` under `dependencies` (after `wakelock_plus`):

```yaml
  wakelock_plus: ^1.3.0
  flutter_foreground_task: ^8.17.0
  share_plus: ^10.0.0
```

- [ ] **Step 2: Add Android permissions and service declaration**

In `movile_app/android/app/src/main/AndroidManifest.xml`, add three permissions after the existing `ACCESS_COARSE_LOCATION` line (before `<application>`):

```xml
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
```

Inside the `<application>` tag, after the `</activity>` closing tag but before the flutterEmbedding `<meta-data>`, add:

```xml
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="location"
            android:exported="false"/>
```

- [ ] **Step 3: Add iOS Info.plist entries**

In `movile_app/ios/Runner/Info.plist`, add before the closing `</dict>`:

```xml
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Splitway needs your location to record routes and show your position on the map.</string>
	<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
	<string>Splitway needs background location access to keep recording your route when the screen is off or you switch apps.</string>
	<key>UIBackgroundModes</key>
	<array>
		<string>location</string>
	</array>
```

- [ ] **Step 4: Run `flutter pub get`**

Run: `cd movile_app && flutter pub get`
Expected: "Got dependencies!" with no errors.

- [ ] **Step 5: Commit**

```bash
git add movile_app/pubspec.yaml movile_app/android/app/src/main/AndroidManifest.xml movile_app/ios/Runner/Info.plist
git commit -m "chore: add flutter_foreground_task and native background location config"
```

---

### Task 2: Create `BackgroundTrackingService`

**Files:**
- Create: `movile_app/lib/src/services/tracking/background_tracking_service.dart`
- Create: `movile_app/test/services/tracking/background_tracking_service_test.dart`

- [ ] **Step 1: Write the unit test**

Create `movile_app/test/services/tracking/background_tracking_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/tracking/background_tracking_service.dart';

void main() {
  group('BackgroundTrackingService', () {
    setUp(() {
      BackgroundTrackingService.resetForTest();
    });

    test('isRunning is false initially', () {
      expect(BackgroundTrackingService.isRunning, isFalse);
    });

    test('updateNotification throttles calls within 2 seconds', () {
      // Simulate running state
      BackgroundTrackingService.setRunningForTest(true);

      var callCount = 0;
      BackgroundTrackingService.onUpdateForTest = () => callCount++;

      BackgroundTrackingService.updateNotification(
        distance: '0.0 km',
        time: '00:00:00',
      );
      expect(callCount, 1);

      // Second call within 2s should be throttled
      BackgroundTrackingService.updateNotification(
        distance: '0.1 km',
        time: '00:00:01',
      );
      expect(callCount, 1);
    });

    test('updateNotification does nothing when not running', () {
      var callCount = 0;
      BackgroundTrackingService.onUpdateForTest = () => callCount++;

      BackgroundTrackingService.updateNotification(
        distance: '0.0 km',
        time: '00:00:00',
      );
      expect(callCount, 0);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd movile_app && flutter test test/services/tracking/background_tracking_service_test.dart`
Expected: FAIL — file does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `movile_app/lib/src/services/tracking/background_tracking_service.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class BackgroundTrackingService {
  BackgroundTrackingService._();

  static bool _running = false;
  static bool get isRunning => _running;

  static DateTime? _lastUpdate;
  static const _throttleDuration = Duration(seconds: 2);

  @visibleForTesting
  static VoidCallback? onUpdateForTest;

  static void init() {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'splitway_tracking',
        channelName: 'Splitway Tracking',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  static Future<bool> startTracking({
    required String title,
    required String body,
  }) async {
    if (_running) return true;
    if (!Platform.isAndroid) {
      _running = true;
      return true;
    }
    try {
      final result = await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: title,
        notificationText: body,
        callback: _taskCallback,
      );
      _running = result is int || result == true;
      return _running;
    } catch (e) {
      debugPrint('BackgroundTrackingService.startTracking failed: $e');
      return false;
    }
  }

  static void updateNotification({
    required String distance,
    required String time,
  }) {
    if (!_running) return;

    final now = DateTime.now();
    if (_lastUpdate != null &&
        now.difference(_lastUpdate!) < _throttleDuration) {
      return;
    }
    _lastUpdate = now;

    if (onUpdateForTest != null) {
      onUpdateForTest!();
      return;
    }

    if (!Platform.isAndroid) return;
    FlutterForegroundTask.updateService(
      notificationText: '$distance · $time',
    );
  }

  static Future<void> stopTracking() async {
    if (!_running) return;
    _running = false;
    _lastUpdate = null;
    if (!Platform.isAndroid) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('BackgroundTrackingService.stopTracking failed: $e');
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _running = false;
    _lastUpdate = null;
    onUpdateForTest = null;
  }

  @visibleForTesting
  static void setRunningForTest(bool value) {
    _running = value;
    _lastUpdate = null;
  }
}

@pragma('vm:entry-point')
void _taskCallback() {
  // The foreground service keeps the Flutter engine alive.
  // GPS streaming and notification updates happen in the main isolate
  // via the controllers, so this callback is intentionally empty.
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd movile_app && flutter test test/services/tracking/background_tracking_service_test.dart`
Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/services/tracking/background_tracking_service.dart movile_app/test/services/tracking/background_tracking_service_test.dart
git commit -m "feat: add BackgroundTrackingService wrapping flutter_foreground_task"
```

---

### Task 3: Add `ensureBackgroundPermission()` and `backgroundMode` to `LocationService`

**Files:**
- Modify: `movile_app/lib/src/services/tracking/location_service.dart`
- Create: `movile_app/test/services/tracking/location_service_test.dart`

- [ ] **Step 1: Write the unit test**

Create `movile_app/test/services/tracking/location_service_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd movile_app && flutter test test/services/tracking/location_service_test.dart`
Expected: FAIL — `backgroundMode` parameter does not exist yet.

- [ ] **Step 3: Add the `dart:io` import and `ensureBackgroundPermission()` method**

In `movile_app/lib/src/services/tracking/location_service.dart`, add after the existing imports:

```dart
import 'dart:io';
```

Add after the closing `}` of `ensurePermission()` (after line 35), before `positionStream()`:

```dart
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
```

- [ ] **Step 4: Add `backgroundMode` parameter to `positionStream()`**

Replace the current `positionStream()` method (lines 39–61) with:

```dart
  static Stream<TelemetryPoint> positionStream({
    int distanceFilterMeters = 0,
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
    bool backgroundMode = false,
  }) {
    final LocationSettings settings;
    if (backgroundMode && Platform.isIOS) {
      settings = AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
        allowBackgroundLocationUpdates: true,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilterMeters,
      );
    }
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd movile_app && flutter test test/services/tracking/location_service_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add movile_app/lib/src/services/tracking/location_service.dart movile_app/test/services/tracking/location_service_test.dart
git commit -m "feat: add background permission and iOS background mode to LocationService"
```

---

### Task 4: Add localization strings

**Files:**
- Modify: `movile_app/lib/l10n/app_en.arb`
- Modify: `movile_app/lib/l10n/app_es.arb`

- [ ] **Step 1: Add EN strings**

In `movile_app/lib/l10n/app_en.arb`, add before the closing `}`:

```json
  "backgroundNotificationTitle": "Splitway · Recording route",
  "backgroundActiveChip": "Background recording active",
  "backgroundDeniedBanner": "Recording will stop if you leave the app. Grant \"Always\" location permission for background recording.",
  "backgroundOpenSettings": "Open settings"
```

- [ ] **Step 2: Add ES strings**

In `movile_app/lib/l10n/app_es.arb`, add before the closing `}`:

```json
  "backgroundNotificationTitle": "Splitway · Grabando ruta",
  "backgroundActiveChip": "Grabación en segundo plano activa",
  "backgroundDeniedBanner": "La grabación se detendrá si sales de la app. Concede permiso \"Siempre\" para grabar en segundo plano.",
  "backgroundOpenSettings": "Abrir ajustes"
```

- [ ] **Step 3: Regenerate localizations**

Run: `cd movile_app && flutter gen-l10n`
Expected: No errors. Files `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_es.dart` are regenerated.

- [ ] **Step 4: Verify the project compiles**

Run: `cd movile_app && flutter analyze --no-pub`
Expected: No analysis errors related to the new keys.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/l10n/
git commit -m "feat(l10n): add background tracking localization strings (en/es)"
```

---

### Task 5: Initialize `BackgroundTrackingService` in `main()`

**Files:**
- Modify: `movile_app/lib/main.dart`

- [ ] **Step 1: Add the import**

In `movile_app/lib/main.dart`, add after the existing imports (after line 13):

```dart
import 'src/services/tracking/background_tracking_service.dart';
```

- [ ] **Step 2: Call `init()` before `runApp()`**

In `movile_app/lib/main.dart`, add a line after `await initializeDateFormatting('en_US');` (after line 20) and before `final config = await AppConfig.load();`:

```dart
  BackgroundTrackingService.init();
```

- [ ] **Step 3: Verify the project compiles**

Run: `cd movile_app && flutter analyze --no-pub`
Expected: No analysis errors.

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/main.dart
git commit -m "feat: initialize BackgroundTrackingService in main()"
```

---

### Task 6: Integrate background tracking into `FreeRideController`

**Files:**
- Modify: `movile_app/lib/src/features/free_ride/free_ride_controller.dart`

- [ ] **Step 1: Add the import**

In `movile_app/lib/src/features/free_ride/free_ride_controller.dart`, add after the existing imports (after line 6):

```dart
import '../../services/tracking/background_tracking_service.dart';
```

- [ ] **Step 2: Add `_backgroundActive` field and getter**

After the `String? _selectedVehicleId;` field (after line 29), add:

```dart
  bool _backgroundActive = false;
  bool get backgroundActive => _backgroundActive;
```

- [ ] **Step 3: Modify `startRecording()` to request background permission and start the service**

In the `startRecording()` method, after the permission check block (after line 51 — the `return;` inside the `if` block), and before the `final id = ...` line, add:

```dart
    final bgStatus = await LocationService.ensureBackgroundPermission();
    _backgroundActive = bgStatus == LocationPermissionStatus.granted;

    if (_backgroundActive) {
      await BackgroundTrackingService.startTracking(
        title: 'Splitway · Grabando ruta',
        body: '0.0 km · 00:00:00',
      );
    }
```

Then modify the existing `LocationService.positionStream()` call (around line 60) to pass `backgroundMode`:

```dart
    _gpsSub = LocationService.positionStream(
      distanceFilterMeters: distanceFilterMeters,
      backgroundMode: _backgroundActive,
    ).listen((point) {
```

- [ ] **Step 4: Add notification update to the ticker**

Replace the existing `_ticker` assignment (around line 68) with:

```dart
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_backgroundActive) {
        final snap = snapshot;
        final distKm = (snap.totalDistanceMeters / 1000).toStringAsFixed(1);
        BackgroundTrackingService.updateNotification(
          distance: '$distKm km',
          time: _formatElapsed(snap.elapsed),
        );
      }
      notifyListeners();
    });
```

- [ ] **Step 5: Add the `_formatElapsed` helper**

Add this private method at the bottom of the class (before `dispose()`):

```dart
  static String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
```

- [ ] **Step 6: Stop the service in `finishRecording()`**

In `finishRecording()`, after `_ticker = null;` (around line 85), add:

```dart
    if (_backgroundActive) {
      await BackgroundTrackingService.stopTracking();
      _backgroundActive = false;
    }
```

- [ ] **Step 7: Reset background state in `resetForNewRide()`**

In `resetForNewRide()`, add `_backgroundActive = false;` after `_permissionStatus = null;`.

- [ ] **Step 8: Stop service on dispose**

In `dispose()`, before `super.dispose();`, add:

```dart
    if (_backgroundActive) {
      BackgroundTrackingService.stopTracking();
    }
```

- [ ] **Step 9: Verify the project compiles**

Run: `cd movile_app && flutter analyze --no-pub`
Expected: No analysis errors.

- [ ] **Step 10: Commit**

```bash
git add movile_app/lib/src/features/free_ride/free_ride_controller.dart
git commit -m "feat: integrate background tracking into FreeRideController"
```

---

### Task 7: Integrate background tracking into `LiveSessionController`

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_controller.dart`

- [ ] **Step 1: Add the import**

In `movile_app/lib/src/features/session/live_session_controller.dart`, add after the existing imports (after line 7):

```dart
import '../../services/tracking/background_tracking_service.dart';
```

- [ ] **Step 2: Add `_backgroundActive` field and getter**

After the `String? _selectedVehicleId;` field (after line 42), add:

```dart
  bool _backgroundActive = false;
  bool get backgroundActive => _backgroundActive;
```

- [ ] **Step 3: Add a notification ticker field**

After the `StreamSubscription<TelemetryPoint>? _gpsSub;` field (after line 62), add:

```dart
  Timer? _bgNotificationTicker;
```

- [ ] **Step 4: Modify `startSession()` to request background permission and start the service**

In `startSession()`, inside the `if (_source == TrackingSource.realGps)` block (line 119), before the `_gpsSub = ...` call, add:

```dart
      final bgStatus = await LocationService.ensureBackgroundPermission();
      _backgroundActive = bgStatus == LocationPermissionStatus.granted;

      if (_backgroundActive) {
        await BackgroundTrackingService.startTracking(
          title: 'Splitway · Grabando ruta',
          body: '0.0 km · 00:00:00',
        );
        _bgNotificationTicker = Timer.periodic(
          const Duration(milliseconds: 500),
          (_) {
            final snap = _tracker?.snapshot;
            if (snap == null) return;
            final distKm =
                (snap.totalDistanceMeters / 1000).toStringAsFixed(1);
            BackgroundTrackingService.updateNotification(
              distance: '$distKm km',
              time: _formatElapsed(snap.elapsed),
            );
          },
        );
      }
```

Then modify the existing `_gpsSub = LocationService.positionStream(` call to pass `backgroundMode`:

```dart
      _gpsSub = LocationService.positionStream(
        distanceFilterMeters: distanceFilterMeters,
        backgroundMode: _backgroundActive,
      ).listen((p) {
```

- [ ] **Step 5: Add the `_formatElapsed` helper**

Add at the bottom of the class (before `dispose()`):

```dart
  static String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
```

- [ ] **Step 6: Stop the service in `finishSession()`**

In `finishSession()`, after `_gpsSub = null;` (line 217), add:

```dart
    _bgNotificationTicker?.cancel();
    _bgNotificationTicker = null;
    if (_backgroundActive) {
      await BackgroundTrackingService.stopTracking();
      _backgroundActive = false;
    }
```

- [ ] **Step 7: Reset background state in `resetForNewSession()`**

In `resetForNewSession()`, add `_backgroundActive = false;` after `_result = null;`.

- [ ] **Step 8: Clean up on dispose**

In `dispose()`, add before `super.dispose();`:

```dart
    _bgNotificationTicker?.cancel();
    if (_backgroundActive) {
      BackgroundTrackingService.stopTracking();
    }
```

- [ ] **Step 9: Verify the project compiles**

Run: `cd movile_app && flutter analyze --no-pub`
Expected: No analysis errors.

- [ ] **Step 10: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_controller.dart
git commit -m "feat: integrate background tracking into LiveSessionController"
```

---

### Task 8: Add background status UI to `FreeRideScreen`

**Files:**
- Modify: `movile_app/lib/src/features/free_ride/free_ride_screen.dart`

- [ ] **Step 1: Add geolocator import for `openAppSettings`**

At the top of `movile_app/lib/src/features/free_ride/free_ride_screen.dart`, the `geolocator` import already exists (line 3). No new import needed.

- [ ] **Step 2: Add a green chip when background is active**

In `_buildRecording()`, after the `_GpsStatusTile` widget (around line 301), add:

```dart
          if (ctrl.backgroundActive) ...[
            const SizedBox(height: 4),
            Chip(
              avatar: Icon(Icons.gps_fixed, color: Colors.green, size: 18),
              label: Text(l.backgroundActiveChip),
              backgroundColor: Colors.green.withValues(alpha: 0.12),
              side: BorderSide(color: Colors.green.withValues(alpha: 0.4)),
            ),
          ],
```

- [ ] **Step 3: Add an orange banner when background is denied**

Immediately after the green chip block, add:

```dart
          if (!ctrl.backgroundActive &&
              ctrl.stage == FreeRideStage.recording) ...[
            const SizedBox(height: 4),
            Container(
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l.backgroundDeniedBanner,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  TextButton(
                    onPressed: () => Geolocator.openAppSettings(),
                    child: Text(l.backgroundOpenSettings),
                  ),
                ],
              ),
            ),
          ],
```

- [ ] **Step 4: Verify the project compiles**

Run: `cd movile_app && flutter analyze --no-pub`
Expected: No analysis errors.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/free_ride/free_ride_screen.dart
git commit -m "feat(ui): add background tracking status banners to FreeRideScreen"
```

---

### Task 9: Add background status UI to `LiveSessionScreen`

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_screen.dart`

- [ ] **Step 1: Find the recording UI section**

The `LiveSessionScreen` already imports `geolocator` (via `location_service.dart`). We need to add the same banner pattern from Task 8 into the running-state UI of this screen.

Look for the section that renders the recording metrics (when `ctrl.stage == LiveSessionStage.running`). Add the background status widgets there.

- [ ] **Step 2: Add the green chip and orange banner**

In the running-state build section, after the GPS status / metrics area and before the stop button, add:

```dart
            if (ctrl.backgroundActive) ...[
              const SizedBox(height: 4),
              Chip(
                avatar: Icon(Icons.gps_fixed, color: Colors.green, size: 18),
                label: Text(l.backgroundActiveChip),
                backgroundColor: Colors.green.withValues(alpha: 0.12),
                side: BorderSide(color: Colors.green.withValues(alpha: 0.4)),
              ),
            ],
            if (!ctrl.backgroundActive &&
                ctrl.source == TrackingSource.realGps) ...[
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l.backgroundDeniedBanner,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                    TextButton(
                      onPressed: () => Geolocator.openAppSettings(),
                      child: Text(l.backgroundOpenSettings),
                    ),
                  ],
                ),
              ),
            ],
```

Note: The orange banner only shows when `source == TrackingSource.realGps` — it would be confusing during simulation mode.

- [ ] **Step 3: Add geolocator import if not already present**

Ensure `package:geolocator/geolocator.dart` is imported at the top of the file. Check if it's already imported via `location_service.dart` — if `Geolocator.openAppSettings()` compiles, no import needed. Otherwise add:

```dart
import 'package:geolocator/geolocator.dart';
```

- [ ] **Step 4: Verify the project compiles**

Run: `cd movile_app && flutter analyze --no-pub`
Expected: No analysis errors.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_screen.dart
git commit -m "feat(ui): add background tracking status banners to LiveSessionScreen"
```

---

### Task 10: Run full test suite and verify

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `cd movile_app && flutter test`
Expected: All tests pass including the new ones.

- [ ] **Step 2: Run flutter analyze**

Run: `cd movile_app && flutter analyze`
Expected: No errors, no warnings related to new code.

- [ ] **Step 3: Manual verification checklist**

On a real device or emulator, verify:

1. **Free Ride — background granted:** Start free ride → app should request "Always" permission → grant → green chip appears → minimize app → GPS points still recorded → re-open → metrics updated → stop → run saved correctly
2. **Free Ride — background denied:** Start free ride → deny "Always" → orange banner appears with "Open settings" button → recording works normally with screen on → minimize → GPS stops (expected)
3. **Session — background granted:** Same flow as free ride but via session start with real GPS source
4. **Android notification:** While recording in background, notification shows "Splitway · Grabando ruta" with updating distance/time metrics
5. **Notification tap:** Tapping the notification returns to the active recording screen

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: address issues found during background tracking verification"
```
