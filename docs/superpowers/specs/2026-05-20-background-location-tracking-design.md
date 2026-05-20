# Background Location Tracking

**Date:** 2026-05-20  
**Status:** Approved  
**Approach:** `flutter_foreground_task` + `geolocator` (Approach 2)

## Goal

Allow the app to continue recording GPS data when the screen turns off or the user switches to another app. Both free ride and normal route session recording benefit from this. Background tracking activates automatically whenever the OS has granted `always` location permission.

## Architecture overview

```
┌──────────────────────────────────────────────────────────┐
│                    Flutter main isolate                   │
│                                                          │
│  FreeRideController / SessionController                  │
│    ├─ startRecording()                                   │
│    │    ├─ LocationService.ensurePermission()             │
│    │    ├─ LocationService.ensureBackgroundPermission()   │
│    │    ├─ BackgroundTrackingService.startTracking()      │
│    │    └─ LocationService.positionStream(bg: true)       │
│    ├─ _ticker (500 ms)                                   │
│    │    └─ BackgroundTrackingService.updateNotification() │
│    └─ finishRecording()                                  │
│         └─ BackgroundTrackingService.stopTracking()       │
│                                                          │
│  LocationService (static)                                │
│    ├─ ensurePermission()          (existing)             │
│    ├─ ensureBackgroundPermission() (new)                 │
│    └─ positionStream(backgroundMode) (modified)          │
│                                                          │
│  BackgroundTrackingService (new, static)                 │
│    ├─ init()               called in main()              │
│    ├─ startTracking()      starts foreground service     │
│    ├─ updateNotification() throttled to ~2 s             │
│    ├─ stopTracking()       stops foreground service      │
│    └─ isRunning            getter                        │
└──────────────────────────────────────────────────────────┘
         │                            │
    Android: foreground service   iOS: background mode
    via flutter_foreground_task   via geolocator AppleSettings
```

## 1. Permissions and authorization flow

### New method: `LocationService.ensureBackgroundPermission()`

Called after `ensurePermission()` succeeds. Requests `LocationPermission.always`.

- **Android 10+:** OS shows a separate dialog asking for "Allow all the time". If `whileInUse` was already granted, `requestPermission()` triggers the upgrade prompt.
- **iOS:** A second `requestPermission()` call upgrades `whenInUse` to `always`. On iOS 13+ the OS may defer the `always` grant to a system prompt that appears later.
- **Fallback:** If denied, the app still records in foreground-only mode (current behavior). No crash, no blocking.

### Return states

| Result | Background behavior |
|---|---|
| `granted` (always) | `BackgroundTrackingService` starts, GPS continues in background |
| `denied` | Foreground-only, info banner shown |
| `permanentlyDenied` | Foreground-only, banner with "Open settings" button |

### Permission request order

```
1. ensurePermission()           → whileInUse
2. ensureBackgroundPermission() → always (only if step 1 succeeded)
```

## 2. `BackgroundTrackingService` — new component

**File:** `lib/src/services/tracking/background_tracking_service.dart`

Static class wrapping `flutter_foreground_task`. Responsible only for the Android foreground service lifecycle and notification updates. Does not touch GPS streams.

### API

```dart
class BackgroundTrackingService {
  static void init();
  static Future<bool> startTracking({
    required String title,
    required String body,
  });
  static void updateNotification({
    required String distance,
    required String time,
  });
  static Future<void> stopTracking();
  static bool get isRunning;
}
```

### `init()`

Called in `main()` before `runApp()`. Configures:
- `FlutterForegroundTask.initCommunicationPort()`
- Android notification channel: name "Splitway Tracking", importance low (no sound), foreground service type `location`.

### `startTracking()`

Calls `FlutterForegroundTask.startService()`. Returns `false` if the service fails to start (e.g., permission issue on a specific Android OEM).

### `updateNotification()`

Calls `FlutterForegroundTask.updateService(notificationTitle:, notificationText:)`. Internally throttled: ignores calls within 2 seconds of the last effective update using a `DateTime _lastUpdate` field. The notification body format is `"{distance} · {time}"` (e.g., "2.3 km · 00:14:32").

### `stopTracking()`

Calls `FlutterForegroundTask.stopService()`. Resets `_lastUpdate`.

## 3. Changes to `LocationService`

### New method: `ensureBackgroundPermission()`

As described in section 1. Added as a new static method alongside the existing `ensurePermission()`.

### Modified: `positionStream()`

New parameter `bool backgroundMode = false`.

When `backgroundMode` is `true`:
- **Android:** No change to `LocationSettings` — the foreground service is managed externally by `BackgroundTrackingService`. Geolocator just emits positions.
- **iOS:** Uses `AppleSettings(accuracy: accuracy, distanceFilter: distanceFilterMeters, allowBackgroundLocationUpdates: true, pauseLocationUpdatesAutomatically: false, showBackgroundLocationIndicator: true)`.

When `backgroundMode` is `false`: current behavior unchanged (`LocationSettings`).

Platform detection (`Platform.isIOS`) is encapsulated inside the method. Controllers just pass `backgroundMode: true/false`.

## 4. Controller changes

Both `FreeRideController` and `SessionController` follow the same pattern.

### New field

```dart
bool _backgroundActive = false;
```

Not persisted. Re-evaluated at each recording start.

### `startRecording()` additions

After the existing `ensurePermission()` call:

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

The `positionStream()` call passes `backgroundMode: _backgroundActive`.

### Ticker (500 ms) addition

```dart
if (_backgroundActive) {
  BackgroundTrackingService.updateNotification(
    distance: _formattedDistance(),
    time: _formattedTime(),
  );
}
```

### `finishRecording()` addition

```dart
if (_backgroundActive) {
  await BackgroundTrackingService.stopTracking();
  _backgroundActive = false;
}
```

### Exposing `_backgroundActive` to the UI

The controllers expose a getter `bool get backgroundActive => _backgroundActive;` so the screen can show the appropriate banner.

## 5. Native platform changes

### Android — `AndroidManifest.xml`

New permissions:

```xml
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
```

New service inside `<application>` (exact class name from `flutter_foreground_task` docs):

```xml
<service
    android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
    android:foregroundServiceType="location"
    android:exported="false"/>
```

### iOS — `Info.plist`

New entries:

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

## 6. UX — states and user feedback

### During recording

| Permission state | Behavior | UI |
|---|---|---|
| `always` granted | Background active, persistent notification | Green chip "Grabación en segundo plano activa" visible ~3 s then fades |
| `whileInUse` only | Foreground-only | Persistent orange banner: "La grabación se detendrá si sales de la app" + "Abrir ajustes" button |
| Denied / services off | Recording does not start | Red banner (existing `_PermissionBanner` pattern) |

### Android notification

- **Title (fixed):** "Splitway · Grabando ruta"
- **Body (dynamic, ~2 s refresh):** "2.3 km · 00:14:32"
- **Tap action:** Returns to the app's active recording screen
- **Channel:** Low importance (no sound, no vibration)

### Wakelock interaction

`wakelock_plus` behavior is unchanged. If the user has "Keep screen awake" enabled in settings, the screen stays on during recording as before. Background tracking is an independent, additive capability — it ensures GPS continues even if the screen turns off, regardless of the wakelock setting.

## 7. New dependency

**Package:** `flutter_foreground_task`  
**Purpose:** Android foreground service lifecycle and persistent notification  
**License:** MIT  
**Why this package:** Clean API for starting/stopping a foreground service from Dart, direct notification update support without a separate isolate, well-maintained, no commercial license.

## 8. Localization strings (new)

| Key | EN | ES |
|---|---|---|
| `backgroundNotificationTitle` | Splitway · Recording route | Splitway · Grabando ruta |
| `backgroundNotificationBody` | {distance} · {time} | {distance} · {time} |
| `backgroundActiveChip` | Background recording active | Grabación en segundo plano activa |
| `backgroundDeniedBanner` | Recording will stop if you leave the app. Grant "Always" location permission for background recording. | La grabación se detendrá si sales de la app. Concede permiso "Siempre" para grabar en segundo plano. |
| `backgroundOpenSettings` | Open settings | Abrir ajustes |
