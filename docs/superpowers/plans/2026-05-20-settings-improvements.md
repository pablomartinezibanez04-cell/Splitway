# Settings Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 13 new settings to Splitway: theme mode, unit system (metric/imperial), time format separator, keep screen awake, haptic feedback, audio alerts, GPS sampling rate, default routing profile, default vehicle, change password, delete account, export history as CSV, and clear local cache.

**Architecture:** A new `AppSettingsController` (ChangeNotifier + SharedPreferences) is the single source of truth for all user preferences, following the same pattern as `LocaleController`. It is loaded in `main()`, passed to `SplitwayApp` → `AppRouter` → screens via constructor injection. Screens own the wakelock/haptic/audio side-effects; controllers only receive what they strictly need (GPS distance filter via method param). `Formatters` gains optional `unit` and `dotSeparator` params with backward-compatible defaults.

**Tech Stack:** Flutter + Material 3, `shared_preferences` (already in deps), `wakelock_plus` (new), `share_plus` (new), `audioplayers` (new), Supabase Auth (`updateUser` for password change, Edge Function for account deletion).

---

## File Map

**New files:**
- `movile_app/lib/src/services/settings/app_settings_controller.dart`
- `movile_app/test/services/settings/app_settings_controller_test.dart`
- `movile_app/test/shared/formatters_test.dart`
- `movile_app/assets/sounds/beep.mp3` (short ~0.3s beep — see Task 11)
- `supabase/functions/delete-user/index.ts`

**Modified files:**
- `movile_app/pubspec.yaml` — add packages + declare sounds asset
- `movile_app/lib/main.dart` — load `AppSettingsController`
- `movile_app/lib/src/app.dart` — accept + apply `settingsController`
- `movile_app/lib/src/routing/app_router.dart` — receive + thread settings to screens
- `movile_app/lib/src/shared/formatters.dart` — unit-aware speed/distance/duration
- `movile_app/lib/src/features/settings/settings_screen.dart` — full expansion
- `movile_app/lib/src/features/session/live_session_controller.dart` — GPS distance filter param
- `movile_app/lib/src/features/session/live_session_screen.dart` — wakelock, haptic, audio, units
- `movile_app/lib/src/features/free_ride/free_ride_controller.dart` — GPS distance filter param
- `movile_app/lib/src/features/free_ride/free_ride_screen.dart` — wakelock, units
- `movile_app/lib/src/features/history/history_screen.dart` — units
- `movile_app/lib/src/features/editor/route_editor_controller.dart` — default profile param
- `movile_app/lib/l10n/app_en.arb` — new strings
- `movile_app/lib/l10n/app_es.arb` — new strings

---

### Task 1: Add packages and assets declaration

**Files:**
- Modify: `movile_app/pubspec.yaml`

- [ ] **Step 1: Add dependencies and asset folder**

In `movile_app/pubspec.yaml`, add the three new packages under `dependencies` and declare the sounds asset folder:

```yaml
dependencies:
  # ... existing deps ...
  wakelock_plus: ^1.3.0
  share_plus: ^10.0.0
  audioplayers: ^6.1.0

flutter:
  uses-material-design: true
  generate: true
  assets:
    - env/local.json
    - assets/sounds/   # NEW
```

- [ ] **Step 2: Create the sounds asset folder**

```bash
mkdir movile_app/assets/sounds
```

- [ ] **Step 3: Obtain a short beep sound**

Download any CC0-licensed short beep (880 Hz, ~0.3 s) and save it as `movile_app/assets/sounds/beep.mp3`. A suitable source: [freesound.org search "beep short"](https://freesound.org) — filter by CC0. Alternatively generate one with ffmpeg:

```bash
ffmpeg -f lavfi -i "sine=frequency=880:duration=0.3" movile_app/assets/sounds/beep.mp3
```

- [ ] **Step 4: Run flutter pub get**

```bash
cd movile_app && flutter pub get
```

Expected: resolves `wakelock_plus`, `share_plus`, `audioplayers` with no conflicts.

- [ ] **Step 5: Commit**

```bash
git add movile_app/pubspec.yaml movile_app/pubspec.lock movile_app/assets/sounds/beep.mp3
git commit -m "chore: add wakelock_plus, share_plus, audioplayers packages"
```

---

### Task 2: Create AppSettingsController

**Files:**
- Create: `movile_app/lib/src/services/settings/app_settings_controller.dart`
- Create: `movile_app/test/services/settings/app_settings_controller_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `movile_app/test/services/settings/app_settings_controller_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('loads default values on first launch', () async {
    final ctrl = await AppSettingsController.load();
    expect(ctrl.unitSystem, UnitSystem.metric);
    expect(ctrl.themeMode, AppThemeMode.system);
    expect(ctrl.timeFormatDot, isTrue);
    expect(ctrl.keepScreenAwake, isTrue);
    expect(ctrl.hapticFeedback, isTrue);
    expect(ctrl.audioAlerts, isFalse);
    expect(ctrl.gpsSamplingDistanceFilter, 0);
    expect(ctrl.defaultVehicleId, isNull);
    expect(ctrl.defaultRoutingProfile, 'driving');
  });

  test('persists and reloads unit system', () async {
    final ctrl = await AppSettingsController.load();
    await ctrl.setUnitSystem(UnitSystem.imperial);

    final ctrl2 = await AppSettingsController.load();
    expect(ctrl2.unitSystem, UnitSystem.imperial);
  });

  test('persists and reloads theme mode', () async {
    final ctrl = await AppSettingsController.load();
    await ctrl.setThemeMode(AppThemeMode.dark);

    final ctrl2 = await AppSettingsController.load();
    expect(ctrl2.themeMode, AppThemeMode.dark);
  });

  test('flutterThemeMode maps all variants correctly', () async {
    final ctrl = await AppSettingsController.load();

    await ctrl.setThemeMode(AppThemeMode.dark);
    expect(ctrl.flutterThemeMode, ThemeMode.dark);

    await ctrl.setThemeMode(AppThemeMode.light);
    expect(ctrl.flutterThemeMode, ThemeMode.light);

    await ctrl.setThemeMode(AppThemeMode.system);
    expect(ctrl.flutterThemeMode, ThemeMode.system);
  });

  test('gpsSamplingDistanceFilter returns correct meters', () async {
    final ctrl = await AppSettingsController.load();

    await ctrl.setGpsSamplingInterval(GpsSamplingInterval.oneSecond);
    expect(ctrl.gpsSamplingDistanceFilter, 0);

    await ctrl.setGpsSamplingInterval(GpsSamplingInterval.twoSeconds);
    expect(ctrl.gpsSamplingDistanceFilter, 5);

    await ctrl.setGpsSamplingInterval(GpsSamplingInterval.fiveSeconds);
    expect(ctrl.gpsSamplingDistanceFilter, 15);
  });

  test('notifies listeners on value change', () async {
    final ctrl = await AppSettingsController.load();
    var notified = false;
    ctrl.addListener(() => notified = true);
    await ctrl.setUnitSystem(UnitSystem.imperial);
    expect(notified, isTrue);
  });

  test('does not notify when value unchanged', () async {
    final ctrl = await AppSettingsController.load();
    var count = 0;
    ctrl.addListener(() => count++);
    await ctrl.setUnitSystem(UnitSystem.metric); // already metric
    expect(count, 0);
  });

  test('persists defaultVehicleId and clearable', () async {
    final ctrl = await AppSettingsController.load();
    await ctrl.setDefaultVehicleId('vehicle-123');
    expect(ctrl.defaultVehicleId, 'vehicle-123');
    await ctrl.setDefaultVehicleId(null);
    expect(ctrl.defaultVehicleId, isNull);
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd movile_app && flutter test test/services/settings/app_settings_controller_test.dart
```

Expected: `Error: Could not resolve ... app_settings_controller.dart`

- [ ] **Step 3: Implement AppSettingsController**

Create `movile_app/lib/src/services/settings/app_settings_controller.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UnitSystem { metric, imperial }

enum AppThemeMode { system, light, dark }

enum GpsSamplingInterval { oneSecond, twoSeconds, fiveSeconds }

class AppSettingsController extends ChangeNotifier {
  AppSettingsController._(this._prefs) {
    _unitSystem = UnitSystem.values.byName(
      _prefs.getString(_kUnitSystem) ?? UnitSystem.metric.name,
    );
    _themeMode = AppThemeMode.values.byName(
      _prefs.getString(_kThemeMode) ?? AppThemeMode.system.name,
    );
    _timeFormatDot = _prefs.getBool(_kTimeFormatDot) ?? true;
    _keepScreenAwake = _prefs.getBool(_kKeepScreenAwake) ?? true;
    _hapticFeedback = _prefs.getBool(_kHapticFeedback) ?? true;
    _audioAlerts = _prefs.getBool(_kAudioAlerts) ?? false;
    _gpsSamplingInterval = GpsSamplingInterval.values.byName(
      _prefs.getString(_kGpsSamplingInterval) ??
          GpsSamplingInterval.oneSecond.name,
    );
    _defaultVehicleId = _prefs.getString(_kDefaultVehicleId);
    _defaultRoutingProfile =
        _prefs.getString(_kDefaultRoutingProfile) ?? 'driving';
  }

  static const _kUnitSystem = 'unit_system';
  static const _kThemeMode = 'app_theme_mode';
  static const _kTimeFormatDot = 'time_format_dot';
  static const _kKeepScreenAwake = 'keep_screen_awake';
  static const _kHapticFeedback = 'haptic_feedback';
  static const _kAudioAlerts = 'audio_alerts';
  static const _kGpsSamplingInterval = 'gps_sampling_interval';
  static const _kDefaultVehicleId = 'default_vehicle_id';
  static const _kDefaultRoutingProfile = 'default_routing_profile';

  final SharedPreferences _prefs;

  late UnitSystem _unitSystem;
  late AppThemeMode _themeMode;
  late bool _timeFormatDot;
  late bool _keepScreenAwake;
  late bool _hapticFeedback;
  late bool _audioAlerts;
  late GpsSamplingInterval _gpsSamplingInterval;
  String? _defaultVehicleId;
  late String _defaultRoutingProfile;

  UnitSystem get unitSystem => _unitSystem;
  AppThemeMode get themeMode => _themeMode;
  bool get timeFormatDot => _timeFormatDot;
  bool get keepScreenAwake => _keepScreenAwake;
  bool get hapticFeedback => _hapticFeedback;
  bool get audioAlerts => _audioAlerts;
  GpsSamplingInterval get gpsSamplingInterval => _gpsSamplingInterval;
  String? get defaultVehicleId => _defaultVehicleId;
  String get defaultRoutingProfile => _defaultRoutingProfile;

  ThemeMode get flutterThemeMode => switch (_themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  /// Distance filter in meters passed to geolocator's position stream.
  int get gpsSamplingDistanceFilter => switch (_gpsSamplingInterval) {
        GpsSamplingInterval.oneSecond => 0,
        GpsSamplingInterval.twoSeconds => 5,
        GpsSamplingInterval.fiveSeconds => 15,
      };

  static Future<AppSettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettingsController._(prefs);
  }

  Future<void> setUnitSystem(UnitSystem v) async {
    if (_unitSystem == v) return;
    _unitSystem = v;
    await _prefs.setString(_kUnitSystem, v.name);
    notifyListeners();
  }

  Future<void> setThemeMode(AppThemeMode v) async {
    if (_themeMode == v) return;
    _themeMode = v;
    await _prefs.setString(_kThemeMode, v.name);
    notifyListeners();
  }

  Future<void> setTimeFormatDot(bool v) async {
    if (_timeFormatDot == v) return;
    _timeFormatDot = v;
    await _prefs.setBool(_kTimeFormatDot, v);
    notifyListeners();
  }

  Future<void> setKeepScreenAwake(bool v) async {
    if (_keepScreenAwake == v) return;
    _keepScreenAwake = v;
    await _prefs.setBool(_kKeepScreenAwake, v);
    notifyListeners();
  }

  Future<void> setHapticFeedback(bool v) async {
    if (_hapticFeedback == v) return;
    _hapticFeedback = v;
    await _prefs.setBool(_kHapticFeedback, v);
    notifyListeners();
  }

  Future<void> setAudioAlerts(bool v) async {
    if (_audioAlerts == v) return;
    _audioAlerts = v;
    await _prefs.setBool(_kAudioAlerts, v);
    notifyListeners();
  }

  Future<void> setGpsSamplingInterval(GpsSamplingInterval v) async {
    if (_gpsSamplingInterval == v) return;
    _gpsSamplingInterval = v;
    await _prefs.setString(_kGpsSamplingInterval, v.name);
    notifyListeners();
  }

  Future<void> setDefaultVehicleId(String? v) async {
    if (_defaultVehicleId == v) return;
    _defaultVehicleId = v;
    if (v == null) {
      await _prefs.remove(_kDefaultVehicleId);
    } else {
      await _prefs.setString(_kDefaultVehicleId, v);
    }
    notifyListeners();
  }

  Future<void> setDefaultRoutingProfile(String v) async {
    if (_defaultRoutingProfile == v) return;
    _defaultRoutingProfile = v;
    await _prefs.setString(_kDefaultRoutingProfile, v);
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd movile_app && flutter test test/services/settings/app_settings_controller_test.dart
```

Expected: All 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/services/settings/ movile_app/test/services/settings/
git commit -m "feat(settings): add AppSettingsController with SharedPreferences persistence"
```

---

### Task 3: Wire AppSettingsController into app startup and routing

**Files:**
- Modify: `movile_app/lib/main.dart`
- Modify: `movile_app/lib/src/app.dart`
- Modify: `movile_app/lib/src/routing/app_router.dart`

- [ ] **Step 1: Load settings in main()**

In `movile_app/lib/main.dart`, add the import and load call after `localeController`:

```dart
import 'src/services/settings/app_settings_controller.dart';

// Inside main(), after localeController line:
final settingsController = await AppSettingsController.load();

runApp(SplitwayApp(
  config: config,
  database: database,
  localeController: localeController,
  settingsController: settingsController,  // NEW
));
```

- [ ] **Step 2: Add settingsController to SplitwayApp**

In `movile_app/lib/src/app.dart`:

Add import:
```dart
import 'services/settings/app_settings_controller.dart';
```

Add field to `SplitwayApp`:
```dart
class SplitwayApp extends StatefulWidget {
  const SplitwayApp({
    super.key,
    required this.config,
    required this.database,
    required this.localeController,
    required this.settingsController,  // NEW
  });

  final AppConfig config;
  final SplitwayLocalDatabase database;
  final LocaleController localeController;
  final AppSettingsController settingsController;  // NEW
```

In `_SplitwayAppState.initState()`, pass settings to `AppRouter`:
```dart
_router = AppRouter(
  repository: _repository,
  config: widget.config,
  authService: _authService,
  syncService: _syncService,
  profileService: _profileService,
  garageService: _garageService,
  localeController: widget.localeController,
  settingsController: widget.settingsController,  // NEW
);
```

In `build()`, wrap with `ListenableBuilder` for both controllers and add `themeMode`:
```dart
@override
Widget build(BuildContext context) {
  return ListenableBuilder(
    listenable: Listenable.merge([
      widget.localeController,
      widget.settingsController,  // NEW
    ]),
    builder: (context, _) => MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: widget.localeController.locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: widget.settingsController.flutterThemeMode,  // NEW
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
      ),
      routerConfig: _router.router,
    ),
  );
}
```

- [ ] **Step 3: Add settingsController to AppRouter**

In `movile_app/lib/src/routing/app_router.dart`:

Add import:
```dart
import '../services/settings/app_settings_controller.dart';
```

Add field to `AppRouter`:
```dart
class AppRouter {
  AppRouter({
    required this.repository,
    required this.config,
    required this.localeController,
    required this.settingsController,  // NEW
    this.authService,
    SyncService? syncService,
    ProfileService? profileService,
    GarageService? garageService,
  }) : /* existing initializers */ {
    // after existing setup:
    _editorController.routingProfile = settingsController.defaultRoutingProfile;  // NEW
    /* rest of body */
  }

  // ...existing fields...
  final AppSettingsController settingsController;  // NEW
```

Pass settings to the screens that need them in the `routes` list:

```dart
// /settings route:
GoRoute(
  path: '/settings',
  builder: (_, __) => SettingsScreen(
    localeController: localeController,
    settingsController: settingsController,  // NEW
    authService: authService,                // NEW
    repository: repository,                  // NEW
  ),
),

// /session route:
builder: (_, __) => LiveSessionScreen(
  controller: _sessionController,
  config: config,
  authService: authService,
  profileService: profileService,
  garageService: garageService,
  settingsController: settingsController,  // NEW
),

// /free-ride route:
builder: (_, __) => FreeRideScreen(
  controller: _freeRideController,
  config: config,
  authService: authService,
  profileService: profileService,
  garageService: garageService,
  settingsController: settingsController,  // NEW
),

// /history route:
builder: (_, __) => HistoryScreen(
  repository: repository,
  config: config,
  authService: authService,
  profileService: profileService,
  garageService: garageService,
  settingsController: settingsController,  // NEW
),
```

- [ ] **Step 4: Hot-reload and verify app compiles**

```bash
cd movile_app && flutter analyze
```

Expected: No errors. Fix any constructor mismatch warnings before continuing.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/main.dart movile_app/lib/src/app.dart movile_app/lib/src/routing/app_router.dart
git commit -m "feat(settings): wire AppSettingsController through app startup and router"
```

---

### Task 4: Unit-aware Formatters

**Files:**
- Modify: `movile_app/lib/src/shared/formatters.dart`
- Create: `movile_app/test/shared/formatters_test.dart`

- [ ] **Step 1: Write failing tests**

Create `movile_app/test/shared/formatters_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';
import 'package:splitway_mobile/src/shared/formatters.dart';

void main() {
  group('Formatters.duration', () {
    test('formats with dot separator', () {
      expect(
        Formatters.duration(
          const Duration(minutes: 1, seconds: 23, milliseconds: 456),
        ),
        '01:23.456',
      );
    });

    test('formats with comma separator', () {
      expect(
        Formatters.duration(
          const Duration(minutes: 1, seconds: 23, milliseconds: 456),
          dotSeparator: false,
        ),
        '01:23,456',
      );
    });

    test('handles zero duration', () {
      expect(Formatters.duration(Duration.zero), '00:00.000');
    });

    test('returns placeholder for negative duration', () {
      expect(
        Formatters.duration(const Duration(milliseconds: -1)),
        '--:--.---',
      );
    });
  });

  group('Formatters.speedMps - metric', () {
    test('converts m/s to km/h', () {
      // 10 m/s = 36 km/h
      expect(Formatters.speedMps(10.0), '36.0');
    });
  });

  group('Formatters.speedMps - imperial', () {
    test('converts m/s to mph', () {
      // 10 m/s = 36 km/h = 22.4 mph
      final result = double.parse(Formatters.speedMps(10.0, unit: UnitSystem.imperial));
      expect(result, closeTo(22.4, 0.1));
    });
  });

  group('Formatters.distanceMeters - metric', () {
    test('returns meters when below 1000', () {
      final (value, isKm) = Formatters.distanceMeters(500);
      expect(isKm, isFalse);
      expect(value, 500);
    });

    test('returns km when at or above 1000', () {
      final (value, isKm) = Formatters.distanceMeters(1500);
      expect(isKm, isTrue);
      expect(value, 1.5);
    });
  });

  group('Formatters.distanceMeters - imperial', () {
    test('returns feet when below 1 mile', () {
      final (value, isMiles) = Formatters.distanceMeters(100, unit: UnitSystem.imperial);
      expect(isMiles, isFalse);
      expect(value, closeTo(328.1, 0.1));
    });

    test('returns miles when at or above 1 mile (1609m)', () {
      final (value, isMiles) = Formatters.distanceMeters(1609.34, unit: UnitSystem.imperial);
      expect(isMiles, isTrue);
      expect(value, closeTo(1.0, 0.01));
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd movile_app && flutter test test/shared/formatters_test.dart
```

Expected: Failures on comma separator, imperial conversions (not yet implemented).

- [ ] **Step 3: Update Formatters**

Replace the contents of `movile_app/lib/src/shared/formatters.dart`:

```dart
import 'package:intl/intl.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

class Formatters {
  Formatters._();

  /// Formats [d] as `MM:SS.mmm`. Pass `dotSeparator: false` for comma.
  static String duration(Duration d, {bool dotSeparator = true}) {
    final ms = d.inMilliseconds;
    if (ms < 0) return '--:--.---';
    final totalSeconds = d.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final millis = ms % 1000;
    final sep = dotSeparator ? '.' : ',';
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}$sep'
        '${millis.toString().padLeft(3, '0')}';
  }

  /// Speed in m/s → formatted numeric string in km/h (metric) or mph (imperial).
  /// Caller wraps the result with the appropriate unit label.
  static String speedMps(double mps, {UnitSystem unit = UnitSystem.metric}) {
    final kmh = mps * 3.6;
    if (unit == UnitSystem.imperial) {
      return (kmh * 0.621371).toStringAsFixed(1);
    }
    return kmh.toStringAsFixed(1);
  }

  /// Distance in metres → `(value, isLargeUnit)`.
  ///
  /// Metric: metres / kilometres. Imperial: feet / miles.
  /// `isLargeUnit` is true for km or miles, false for m or feet.
  static (double value, bool isLargeUnit) distanceMeters(
    double meters, {
    UnitSystem unit = UnitSystem.metric,
  }) {
    if (unit == UnitSystem.imperial) {
      final feet = meters * 3.28084;
      if (feet >= 5280) return (feet / 5280, true); // miles
      return (feet, false); // feet
    }
    if (meters >= 1000) return (meters / 1000, true); // km
    return (meters, false); // m
  }

  static String dateTime(DateTime dt) {
    return DateFormat('dd MMM yyyy · HH:mm').format(dt);
  }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd movile_app && flutter test test/shared/formatters_test.dart
```

Expected: All 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/shared/formatters.dart movile_app/test/shared/
git commit -m "feat(formatters): add unit system and time separator support"
```

---

### Task 5: Add new ARB strings for units and settings

**Files:**
- Modify: `movile_app/lib/l10n/app_en.arb`
- Modify: `movile_app/lib/l10n/app_es.arb`

- [ ] **Step 1: Add English strings**

In `app_en.arb`, add after the existing `unitKmh` entry:

```json
  "unitMph": "{value} mph",
  "@unitMph": { "placeholders": { "value": { "type": "String" } } },
  "unitFeet": "{value} ft",
  "@unitFeet": { "placeholders": { "value": { "type": "String" } } },
  "unitMiles": "{value} mi",
  "@unitMiles": { "placeholders": { "value": { "type": "String" } } },

  "settingsAppearanceSection": "Appearance",
  "settingsThemeLabel": "Theme",
  "settingsThemeSystem": "System default",
  "settingsThemeLight": "Light",
  "settingsThemeDark": "Dark",

  "settingsMeasurementSection": "Measurement",
  "settingsUnitSystemLabel": "Unit system",
  "settingsUnitMetric": "Metric (km, m/s → km/h)",
  "settingsUnitImperial": "Imperial (mi, m/s → mph)",
  "settingsTimeFormatLabel": "Lap time separator",
  "settingsTimeFormatDot": "Dot  —  01:23.456",
  "settingsTimeFormatComma": "Comma  —  01:23,456",

  "settingsSessionSection": "Session behaviour",
  "settingsKeepScreenAwakeLabel": "Keep screen awake",
  "settingsKeepScreenAwakeDesc": "Prevents the display from sleeping during an active session or free ride.",
  "settingsHapticFeedbackLabel": "Haptic feedback",
  "settingsHapticFeedbackDesc": "Vibrate when crossing a sector gate or the finish line.",
  "settingsAudioAlertsLabel": "Audio alerts",
  "settingsAudioAlertsDesc": "Play a short beep on each sector and lap crossing.",
  "settingsGpsSamplingLabel": "GPS update rate",
  "settingsGpsSampling1s": "Every 1 s — high accuracy, more battery",
  "settingsGpsSampling2s": "Every ~2 s — balanced",
  "settingsGpsSampling5s": "Every ~5 s — low battery",

  "settingsRoutesSection": "Routes",
  "settingsDefaultRoutingProfileLabel": "Default routing mode",

  "settingsGarageSection": "Garage",
  "settingsDefaultVehicleLabel": "Default vehicle",
  "settingsDefaultVehicleNone": "None (always ask)",

  "settingsAccountSection": "Account",
  "settingsChangePasswordLabel": "Change password",
  "settingsDeleteAccountLabel": "Delete account",
  "settingsDeleteAccountConfirmTitle": "Delete account?",
  "settingsDeleteAccountConfirmBody": "All your data will be permanently deleted. This cannot be undone.",
  "settingsDeleteAccountConfirmButton": "Delete my account",
  "settingsDeleteAccountSuccess": "Account deleted. Goodbye!",
  "settingsDeleteAccountError": "Could not delete account. Try again.",

  "settingsChangePasswordCurrentLabel": "Current password",
  "settingsChangePasswordNewLabel": "New password",
  "settingsChangePasswordConfirmLabel": "Confirm new password",
  "settingsChangePasswordButton": "Update password",
  "settingsChangePasswordSuccess": "Password updated",
  "settingsChangePasswordError": "Could not update password. Try again.",
  "settingsChangePasswordMismatch": "Passwords do not match",
  "settingsChangePasswordTooShort": "Minimum 6 characters",

  "settingsDataSection": "Data",
  "settingsExportHistoryLabel": "Export history",
  "settingsExportHistoryDesc": "Download all sessions and free rides as a CSV file.",
  "settingsClearCacheLabel": "Clear local data",
  "settingsClearCacheDesc": "Deletes all locally saved routes and sessions. Cloud data is not affected.",
  "settingsClearCacheConfirmTitle": "Clear all local data?",
  "settingsClearCacheConfirmBody": "Your routes and sessions will be deleted from this device. If sync is enabled they will remain in the cloud.",
  "settingsClearCacheConfirmButton": "Clear data",
  "settingsClearCacheDone": "Local data cleared",
  "settingsExportSharing": "Exporting…"
```

- [ ] **Step 2: Add Spanish strings**

In `app_es.arb`, add the same keys with Spanish translations:

```json
  "unitMph": "{value} mph",
  "@unitMph": { "placeholders": { "value": { "type": "String" } } },
  "unitFeet": "{value} ft",
  "@unitFeet": { "placeholders": { "value": { "type": "String" } } },
  "unitMiles": "{value} mi",
  "@unitMiles": { "placeholders": { "value": { "type": "String" } } },

  "settingsAppearanceSection": "Apariencia",
  "settingsThemeLabel": "Tema",
  "settingsThemeSystem": "Seguir sistema",
  "settingsThemeLight": "Claro",
  "settingsThemeDark": "Oscuro",

  "settingsMeasurementSection": "Medición",
  "settingsUnitSystemLabel": "Sistema de unidades",
  "settingsUnitMetric": "Métrico (km, m/s → km/h)",
  "settingsUnitImperial": "Imperial (mi, m/s → mph)",
  "settingsTimeFormatLabel": "Separador de tiempo de vuelta",
  "settingsTimeFormatDot": "Punto  —  01:23.456",
  "settingsTimeFormatComma": "Coma  —  01:23,456",

  "settingsSessionSection": "Comportamiento de sesión",
  "settingsKeepScreenAwakeLabel": "Mantener pantalla encendida",
  "settingsKeepScreenAwakeDesc": "Evita que la pantalla se apague durante una sesión activa o free ride.",
  "settingsHapticFeedbackLabel": "Vibración háptica",
  "settingsHapticFeedbackDesc": "Vibra al cruzar una puerta de sector o la línea de meta.",
  "settingsAudioAlertsLabel": "Alertas de audio",
  "settingsAudioAlertsDesc": "Reproduce un pitido corto en cada cruce de sector y vuelta.",
  "settingsGpsSamplingLabel": "Frecuencia GPS",
  "settingsGpsSampling1s": "Cada 1 s — alta precisión, más batería",
  "settingsGpsSampling2s": "Cada ~2 s — equilibrado",
  "settingsGpsSampling5s": "Cada ~5 s — menos batería",

  "settingsRoutesSection": "Rutas",
  "settingsDefaultRoutingProfileLabel": "Modo de ruta por defecto",

  "settingsGarageSection": "Garaje",
  "settingsDefaultVehicleLabel": "Vehículo por defecto",
  "settingsDefaultVehicleNone": "Ninguno (preguntar siempre)",

  "settingsAccountSection": "Cuenta",
  "settingsChangePasswordLabel": "Cambiar contraseña",
  "settingsDeleteAccountLabel": "Eliminar cuenta",
  "settingsDeleteAccountConfirmTitle": "¿Eliminar cuenta?",
  "settingsDeleteAccountConfirmBody": "Todos tus datos serán eliminados permanentemente. Esta acción no se puede deshacer.",
  "settingsDeleteAccountConfirmButton": "Eliminar mi cuenta",
  "settingsDeleteAccountSuccess": "Cuenta eliminada. ¡Hasta pronto!",
  "settingsDeleteAccountError": "No se pudo eliminar la cuenta. Inténtalo de nuevo.",

  "settingsChangePasswordCurrentLabel": "Contraseña actual",
  "settingsChangePasswordNewLabel": "Nueva contraseña",
  "settingsChangePasswordConfirmLabel": "Confirmar nueva contraseña",
  "settingsChangePasswordButton": "Actualizar contraseña",
  "settingsChangePasswordSuccess": "Contraseña actualizada",
  "settingsChangePasswordError": "No se pudo actualizar la contraseña. Inténtalo de nuevo.",
  "settingsChangePasswordMismatch": "Las contraseñas no coinciden",
  "settingsChangePasswordTooShort": "Mínimo 6 caracteres",

  "settingsDataSection": "Datos",
  "settingsExportHistoryLabel": "Exportar historial",
  "settingsExportHistoryDesc": "Descarga todas las sesiones y free rides como archivo CSV.",
  "settingsClearCacheLabel": "Borrar datos locales",
  "settingsClearCacheDesc": "Elimina todas las rutas y sesiones guardadas localmente. Los datos en la nube no se ven afectados.",
  "settingsClearCacheConfirmTitle": "¿Borrar todos los datos locales?",
  "settingsClearCacheConfirmBody": "Tus rutas y sesiones se eliminarán de este dispositivo. Si tienes sync activado, permanecerán en la nube.",
  "settingsClearCacheConfirmButton": "Borrar datos",
  "settingsClearCacheDone": "Datos locales borrados",
  "settingsExportSharing": "Exportando…"
```

- [ ] **Step 3: Regenerate localizations**

```bash
cd movile_app && flutter gen-l10n
```

Expected: `app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_es.dart` updated. No errors.

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/l10n/
git commit -m "feat(settings): add ARB strings for all new settings sections"
```

---

### Task 6: Expand SettingsScreen with all sections

**Files:**
- Modify: `movile_app/lib/src/features/settings/settings_screen.dart`

- [ ] **Step 1: Replace SettingsScreen with the full multi-section version**

Replace the entire file `movile_app/lib/src/features/settings/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../data/repositories/local_draft_repository.dart';
import '../../services/auth/auth_service.dart';
import '../../services/locale/locale_controller.dart';
import '../../services/settings/app_settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.localeController,
    required this.settingsController,
    this.authService,
    required this.repository,
  });

  final LocaleController localeController;
  final AppSettingsController settingsController;
  final AuthService? authService;
  final LocalDraftRepository repository;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.settingsTitle),
        leading: IconButton(
          icon: const BackButtonIcon(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/routes');
            }
          },
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([localeController, settingsController]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            // ── Language ────────────────────────────────────────────────
            _SectionHeader(l.settingsLanguageSection),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l.settingsLanguageDescription,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            RadioListTile<Locale>(
              title: Text(l.languageSpanish),
              value: const Locale('es'),
              groupValue: localeController.locale,
              onChanged: (v) {
                if (v != null) localeController.setLocale(v);
              },
            ),
            RadioListTile<Locale>(
              title: Text(l.languageEnglish),
              value: const Locale('en'),
              groupValue: localeController.locale,
              onChanged: (v) {
                if (v != null) localeController.setLocale(v);
              },
            ),

            // ── Appearance ───────────────────────────────────────────────
            _SectionHeader(l.settingsAppearanceSection),
            RadioListTile<AppThemeMode>(
              title: Text(l.settingsThemeSystem),
              value: AppThemeMode.system,
              groupValue: settingsController.themeMode,
              onChanged: (v) {
                if (v != null) settingsController.setThemeMode(v);
              },
            ),
            RadioListTile<AppThemeMode>(
              title: Text(l.settingsThemeLight),
              value: AppThemeMode.light,
              groupValue: settingsController.themeMode,
              onChanged: (v) {
                if (v != null) settingsController.setThemeMode(v);
              },
            ),
            RadioListTile<AppThemeMode>(
              title: Text(l.settingsThemeDark),
              value: AppThemeMode.dark,
              groupValue: settingsController.themeMode,
              onChanged: (v) {
                if (v != null) settingsController.setThemeMode(v);
              },
            ),

            // ── Measurement ──────────────────────────────────────────────
            _SectionHeader(l.settingsMeasurementSection),
            RadioListTile<UnitSystem>(
              title: Text(l.settingsUnitMetric),
              value: UnitSystem.metric,
              groupValue: settingsController.unitSystem,
              onChanged: (v) {
                if (v != null) settingsController.setUnitSystem(v);
              },
            ),
            RadioListTile<UnitSystem>(
              title: Text(l.settingsUnitImperial),
              value: UnitSystem.imperial,
              groupValue: settingsController.unitSystem,
              onChanged: (v) {
                if (v != null) settingsController.setUnitSystem(v);
              },
            ),
            const Divider(indent: 16, endIndent: 16, height: 8),
            RadioListTile<bool>(
              title: Text(l.settingsTimeFormatDot),
              value: true,
              groupValue: settingsController.timeFormatDot,
              onChanged: (v) {
                if (v != null) settingsController.setTimeFormatDot(v);
              },
            ),
            RadioListTile<bool>(
              title: Text(l.settingsTimeFormatComma),
              value: false,
              groupValue: settingsController.timeFormatDot,
              onChanged: (v) {
                if (v != null) settingsController.setTimeFormatDot(v);
              },
            ),

            // ── Session behaviour ────────────────────────────────────────
            _SectionHeader(l.settingsSessionSection),
            SwitchListTile(
              title: Text(l.settingsKeepScreenAwakeLabel),
              subtitle: Text(l.settingsKeepScreenAwakeDesc),
              value: settingsController.keepScreenAwake,
              onChanged: settingsController.setKeepScreenAwake,
            ),
            SwitchListTile(
              title: Text(l.settingsHapticFeedbackLabel),
              subtitle: Text(l.settingsHapticFeedbackDesc),
              value: settingsController.hapticFeedback,
              onChanged: settingsController.setHapticFeedback,
            ),
            SwitchListTile(
              title: Text(l.settingsAudioAlertsLabel),
              subtitle: Text(l.settingsAudioAlertsDesc),
              value: settingsController.audioAlerts,
              onChanged: settingsController.setAudioAlerts,
            ),
            ListTile(
              title: Text(l.settingsGpsSamplingLabel),
              trailing: DropdownButton<GpsSamplingInterval>(
                value: settingsController.gpsSamplingInterval,
                underline: const SizedBox(),
                onChanged: (v) {
                  if (v != null) settingsController.setGpsSamplingInterval(v);
                },
                items: [
                  DropdownMenuItem(
                    value: GpsSamplingInterval.oneSecond,
                    child: Text(l.settingsGpsSampling1s),
                  ),
                  DropdownMenuItem(
                    value: GpsSamplingInterval.twoSeconds,
                    child: Text(l.settingsGpsSampling2s),
                  ),
                  DropdownMenuItem(
                    value: GpsSamplingInterval.fiveSeconds,
                    child: Text(l.settingsGpsSampling5s),
                  ),
                ],
              ),
            ),

            // ── Routes ──────────────────────────────────────────────────
            _SectionHeader(l.settingsRoutesSection),
            ListTile(
              title: Text(l.settingsDefaultRoutingProfileLabel),
              trailing: DropdownButton<String>(
                value: settingsController.defaultRoutingProfile,
                underline: const SizedBox(),
                onChanged: (v) {
                  if (v != null) settingsController.setDefaultRoutingProfile(v);
                },
                items: const [
                  DropdownMenuItem(value: 'driving', child: Text('Road')),
                  DropdownMenuItem(value: 'walking', child: Text('Trail')),
                  DropdownMenuItem(value: 'cycling', child: Text('Cycling')),
                ],
              ),
            ),

            // ── Account ──────────────────────────────────────────────────
            if (authService?.isLoggedIn == true) ...[
              _SectionHeader(l.settingsAccountSection),
              ListTile(
                title: Text(l.settingsChangePasswordLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showChangePasswordDialog(context, l),
              ),
              ListTile(
                title: Text(
                  l.settingsDeleteAccountLabel,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).colorScheme.error,
                ),
                onTap: () => _confirmDeleteAccount(context, l),
              ),
            ],

            // ── Data ─────────────────────────────────────────────────────
            _SectionHeader(l.settingsDataSection),
            ListTile(
              title: Text(l.settingsExportHistoryLabel),
              subtitle: Text(l.settingsExportHistoryDesc),
              trailing: const Icon(Icons.download_outlined),
              onTap: () => _exportHistory(context, l),
            ),
            ListTile(
              title: Text(l.settingsClearCacheLabel),
              subtitle: Text(l.settingsClearCacheDesc),
              trailing: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              onTap: () => _confirmClearCache(context, l),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, AppLocalizations l) {
    showDialog<void>(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        authService: authService!,
        l: l,
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context, AppLocalizations l) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.settingsDeleteAccountConfirmTitle),
        content: Text(l.settingsDeleteAccountConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteAccount(context, l);
            },
            child: Text(l.settingsDeleteAccountConfirmButton),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context, AppLocalizations l) async {
    // Implemented in Task 16
  }

  Future<void> _exportHistory(BuildContext context, AppLocalizations l) async {
    // Implemented in Task 17
  }

  void _confirmClearCache(BuildContext context, AppLocalizations l) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.settingsClearCacheConfirmTitle),
        content: Text(l.settingsClearCacheConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _clearCache(context, l);
            },
            child: Text(l.settingsClearCacheConfirmButton),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCache(BuildContext context, AppLocalizations l) async {
    // Implemented in Task 18
  }
}

// ── Section header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

// ── Change password dialog ──────────────────────────────────────────────────

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.authService, required this.l});

  final AuthService authService;
  final AppLocalizations l;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    // Actual Supabase call added in Task 15
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    return AlertDialog(
      title: Text(l.settingsChangePasswordLabel),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextFormField(
              controller: _newCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l.settingsChangePasswordNewLabel,
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return l.settingsChangePasswordTooShort;
                if (v.length < 6) return l.settingsChangePasswordTooShort;
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l.settingsChangePasswordConfirmLabel,
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (v != _newCtrl.text) return l.settingsChangePasswordMismatch;
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.settingsChangePasswordButton),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze**

```bash
cd movile_app && flutter analyze lib/src/features/settings/
```

Expected: No errors. (The `_deleteAccount` and `_exportHistory` stubs are intentional — filled in Tasks 15–17.)

- [ ] **Step 3: Smoke-test on emulator**

Run the app and navigate to Settings via the drawer. Verify all sections appear and toggles/radio buttons respond visually.

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/features/settings/settings_screen.dart
git commit -m "feat(settings): expand settings screen with all new sections"
```

---

### Task 7: Apply unit-aware formatters in Session, FreeRide, History screens

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_screen.dart`
- Modify: `movile_app/lib/src/features/free_ride/free_ride_screen.dart`
- Modify: `movile_app/lib/src/features/history/history_screen.dart`

> **Note on approach:** Each screen already receives `settingsController` (wired in Task 3). Pass `settingsController.unitSystem` and `settingsController.timeFormatDot` to every `Formatters.duration()`, `Formatters.speedMps()`, and `Formatters.distanceMeters()` call. Wrap the screen body in a `ListenableBuilder` on `settingsController` so it rebuilds when units change.

- [ ] **Step 1: Update LiveSessionScreen**

In `movile_app/lib/src/features/session/live_session_screen.dart`:

1. Add field and import:
```dart
import '../../services/settings/app_settings_controller.dart';

// In LiveSessionScreen StatefulWidget:
final AppSettingsController settingsController;
```

2. Wrap `build()` body in `ListenableBuilder`:
```dart
@override
Widget build(BuildContext context) {
  final l = AppLocalizations.of(context);
  final ctrl = widget.controller;
  return ListenableBuilder(
    listenable: widget.settingsController,
    builder: (context, _) => Scaffold(
      // ... existing Scaffold content ...
    ),
  );
}
```

3. Find every call to `Formatters.duration(...)` and add the `dotSeparator` param:
```dart
Formatters.duration(d, dotSeparator: widget.settingsController.timeFormatDot)
```

4. Find every call to `Formatters.speedMps(...)` and add the `unit` param:
```dart
Formatters.speedMps(mps, unit: widget.settingsController.unitSystem)
```

5. Find every call to `Formatters.distanceMeters(...)` and add the `unit` param:
```dart
Formatters.distanceMeters(meters, unit: widget.settingsController.unitSystem)
```

6. Update the unit label helper to return the correct string for each unit:
```dart
// Replace hard-coded unitKmh / unitMeters / unitKilometers calls:
String _speedLabel(AppLocalizations l, double mps) {
  final v = Formatters.speedMps(mps, unit: widget.settingsController.unitSystem);
  return widget.settingsController.unitSystem == UnitSystem.imperial
      ? l.unitMph(v)
      : l.unitKmh(v);
}

String _distanceLabel(AppLocalizations l, double meters) {
  final (value, isLarge) = Formatters.distanceMeters(
    meters,
    unit: widget.settingsController.unitSystem,
  );
  final formatted = value.toStringAsFixed(value >= 10 ? 1 : 2);
  if (widget.settingsController.unitSystem == UnitSystem.imperial) {
    return isLarge ? l.unitMiles(formatted) : l.unitFeet(formatted);
  }
  return isLarge ? l.unitKilometers(formatted) : l.unitMeters(formatted);
}
```

Use `_speedLabel` and `_distanceLabel` everywhere those units appear in the screen widgets.

- [ ] **Step 2: Update FreeRideScreen the same way**

Apply identical changes to `movile_app/lib/src/features/free_ride/free_ride_screen.dart` — add `settingsController` field, wrap in `ListenableBuilder`, update all `Formatters` calls using the same helper pattern.

- [ ] **Step 3: Update HistoryScreen the same way**

Apply identical changes to `movile_app/lib/src/features/history/history_screen.dart`.

- [ ] **Step 4: Run flutter analyze**

```bash
cd movile_app && flutter analyze
```

Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/session/ movile_app/lib/src/features/free_ride/ movile_app/lib/src/features/history/
git commit -m "feat(settings): apply unit system and time format to session, free ride, history"
```

---

### Task 8: Keep screen awake during active sessions

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_screen.dart`
- Modify: `movile_app/lib/src/features/free_ride/free_ride_screen.dart`

- [ ] **Step 1: Add wakelock to LiveSessionScreen**

In `movile_app/lib/src/features/session/live_session_screen.dart`:

Add import:
```dart
import 'package:wakelock_plus/wakelock_plus.dart';
```

In `_LiveSessionScreenState.initState()`, add a listener that reacts to stage changes:
```dart
@override
void initState() {
  super.initState();
  widget.controller.addListener(_onChange);
  widget.authService?.addListener(_onChange);
  widget.controller.load();
}

void _onChange() {
  _updateWakelock();
  setState(() {});
}

void _updateWakelock() {
  final shouldKeep = widget.settingsController.keepScreenAwake &&
      widget.controller.stage == LiveSessionStage.running;
  WakelockPlus.toggle(enable: shouldKeep);
}

@override
void dispose() {
  widget.controller.removeListener(_onChange);
  widget.authService?.removeListener(_onChange);
  WakelockPlus.disable();  // always release on leaving screen
  super.dispose();
}
```

- [ ] **Step 2: Add wakelock to FreeRideScreen**

Apply the same pattern in `movile_app/lib/src/features/free_ride/free_ride_screen.dart`:

```dart
import 'package:wakelock_plus/wakelock_plus.dart';

// In _FreeRideScreenState:
void _onChange() {
  _updateWakelock();
  setState(() {});
}

void _updateWakelock() {
  final shouldKeep = widget.settingsController.keepScreenAwake &&
      widget.controller.stage == FreeRideStage.recording;
  WakelockPlus.toggle(enable: shouldKeep);
}

@override
void dispose() {
  widget.controller.removeListener(_onChange);
  WakelockPlus.disable();
  super.dispose();
}
```

- [ ] **Step 3: Verify on device**

Run the app on a real device or emulator:
1. Set "Keep screen awake" ON in Settings.
2. Start a session. The screen should not auto-lock.
3. Toggle the setting OFF. Restart the session — screen should auto-lock normally.

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_screen.dart movile_app/lib/src/features/free_ride/free_ride_screen.dart
git commit -m "feat(settings): keep screen awake during active session and free ride"
```

---

### Task 9: Haptic feedback on sector/lap crossing

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_screen.dart`

- [ ] **Step 1: Trigger haptic on TrackingEvents**

In `movile_app/lib/src/features/session/live_session_screen.dart`:

Add import:
```dart
import 'package:flutter/services.dart';
import 'package:splitway_core/splitway_core.dart'; // for SectorCrossed, LapClosed
```

In `_LiveSessionScreenState`, track the last event count to detect new events:
```dart
int _lastEventCount = 0;

void _onChange() {
  _updateWakelock();
  _checkHaptic();
  setState(() {});
}

void _checkHaptic() {
  if (!widget.settingsController.hapticFeedback) return;
  final tracker = widget.controller.tracker;
  if (tracker == null) return;
  final events = tracker.events;
  if (events.length > _lastEventCount) {
    final newEvents = events.sublist(_lastEventCount);
    for (final evt in newEvents) {
      if (evt is SectorCrossed || evt is LapClosed) {
        HapticFeedback.mediumImpact();
        break; // one haptic pulse per notification cycle is enough
      }
    }
  }
  _lastEventCount = events.length;
}
```

Reset `_lastEventCount` when a new session starts. In the button handler that calls `controller.startSession()`:
```dart
_lastEventCount = 0;
await widget.controller.startSession(...);
```

- [ ] **Step 2: Test on device**

Start a simulated session, trigger Auto Lap, and confirm the device vibrates on lap completion. Turn "Haptic feedback" OFF in Settings and verify no vibration occurs.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_screen.dart
git commit -m "feat(settings): haptic feedback on sector and lap crossing"
```

---

### Task 10: Audio alerts on sector/lap crossing

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_screen.dart`

- [ ] **Step 1: Add AudioPlayer to LiveSessionScreen**

In `movile_app/lib/src/features/session/live_session_screen.dart`:

Add import:
```dart
import 'package:audioplayers/audioplayers.dart';
```

Add the player to the state, initialised once:
```dart
final _audioPlayer = AudioPlayer();

@override
void dispose() {
  // ... existing dispose ...
  _audioPlayer.dispose();
  super.dispose();
}
```

- [ ] **Step 2: Play beep on event**

Update `_checkHaptic()` to also play the beep (rename to `_onNewEvents()` for clarity):

```dart
void _onNewEvents() {
  final tracker = widget.controller.tracker;
  if (tracker == null) return;
  final events = tracker.events;
  if (events.length <= _lastEventCount) return;

  final newEvents = events.sublist(_lastEventCount);
  bool hasCrossing = false;
  for (final evt in newEvents) {
    if (evt is SectorCrossed || evt is LapClosed) {
      hasCrossing = true;
      break;
    }
  }
  _lastEventCount = events.length;

  if (hasCrossing) {
    if (widget.settingsController.hapticFeedback) {
      HapticFeedback.mediumImpact();
    }
    if (widget.settingsController.audioAlerts) {
      _audioPlayer.play(AssetSource('sounds/beep.mp3'));
    }
  }
}
```

Replace the call to `_checkHaptic()` in `_onChange()` with `_onNewEvents()`.

- [ ] **Step 3: Test on device**

Enable "Audio alerts" in Settings. Start a simulated session, trigger Auto Lap, and confirm you hear a beep. Disable the setting and confirm silence.

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_screen.dart
git commit -m "feat(settings): audio beep alert on sector and lap crossing"
```

---

### Task 11: GPS sampling rate in session and free ride

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_controller.dart`
- Modify: `movile_app/lib/src/features/session/live_session_screen.dart`
- Modify: `movile_app/lib/src/features/free_ride/free_ride_controller.dart`
- Modify: `movile_app/lib/src/features/free_ride/free_ride_screen.dart`

- [ ] **Step 1: Add distanceFilterMeters param to LiveSessionController.startSession()**

In `movile_app/lib/src/features/session/live_session_controller.dart`, find `startSession()` and add the param:

```dart
Future<void> startSession({int distanceFilterMeters = 0}) async {
  final route = _selected;
  if (route == null) return;
  _tracker?.dispose();
  _tracker = LiveTrackingController(route: route)
    ..addListener(_onTrackerChange)
    ..startSession();
  _stage = LiveSessionStage.running;
  notifyListeners();

  if (_source == TrackingSource.realGps) {
    _gpsSub = LocationService.positionStream(
      distanceFilterMeters: distanceFilterMeters,  // NEW
    ).listen((p) {
      _tracker?.ingestPoint(p);
    });
  }
}
```

- [ ] **Step 2: Call startSession with the setting from LiveSessionScreen**

In `movile_app/lib/src/features/session/live_session_screen.dart`, find the button that calls `controller.startSession()` and pass the filter:

```dart
onPressed: () {
  _lastEventCount = 0;
  widget.controller.startSession(
    distanceFilterMeters: widget.settingsController.gpsSamplingDistanceFilter,
  );
},
```

- [ ] **Step 3: Add distanceFilterMeters param to FreeRideController.startRecording()**

In `movile_app/lib/src/features/free_ride/free_ride_controller.dart`:

```dart
Future<void> startRecording({int distanceFilterMeters = 0}) async {
  _permissionStatus = await LocationService.ensurePermission();
  if (_permissionStatus != LocationPermissionStatus.granted) {
    notifyListeners();
    return;
  }
  // ... existing setup ...
  _gpsSub = LocationService.positionStream(
    distanceFilterMeters: distanceFilterMeters,  // NEW
  ).listen((point) {
    // ... existing listener ...
  });
}
```

- [ ] **Step 4: Call startRecording with the setting from FreeRideScreen**

In `movile_app/lib/src/features/free_ride/free_ride_screen.dart`, find the start button:

```dart
onPressed: () => widget.controller.startRecording(
  distanceFilterMeters: widget.settingsController.gpsSamplingDistanceFilter,
),
```

- [ ] **Step 5: Run flutter analyze**

```bash
cd movile_app && flutter analyze
```

Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add movile_app/lib/src/features/session/ movile_app/lib/src/features/free_ride/
git commit -m "feat(settings): apply GPS sampling rate to session and free ride"
```

---

### Task 12: Default routing profile

**Files:**
- Modify: `movile_app/lib/src/features/editor/route_editor_controller.dart`
- Modify: `movile_app/lib/src/routing/app_router.dart`

- [ ] **Step 1: Add defaultProfile param to RouteEditorController constructor**

In `movile_app/lib/src/features/editor/route_editor_controller.dart`, find the constructor and the field at line 144:

```dart
String _routingProfile = 'driving';

// Add param:
RouteEditorController(
  LocalDraftRepository repository, {
  RoutingService? routingService,
  ReverseGeocodingService? geocodingService,
  String defaultRoutingProfile = 'driving',  // NEW
}) : // existing initializers
{
  _routingProfile = defaultRoutingProfile;  // NEW — set before first use
}
```

- [ ] **Step 2: Pass defaultRoutingProfile from AppRouter**

In `movile_app/lib/src/routing/app_router.dart`, update the `_editorController` instantiation:

```dart
_editorController = RouteEditorController(
  repository,
  routingService: config.hasMapbox
      ? RoutingService(mapboxToken: config.mapboxToken!)
      : null,
  geocodingService: config.hasMapbox
      ? ReverseGeocodingService(accessToken: config.mapboxToken!)
      : null,
  defaultRoutingProfile: settingsController.defaultRoutingProfile,  // NEW
),
```

> **Note:** The default profile only applies when the controller is first created. If the user changes it in Settings, the new default takes effect the next app launch (the editor's in-session profile can still be changed via the FAB). This is intentional — changing the default mid-session would be confusing.

- [ ] **Step 3: Run flutter analyze**

```bash
cd movile_app && flutter analyze
```

- [ ] **Step 4: Commit**

```bash
git add movile_app/lib/src/features/editor/route_editor_controller.dart movile_app/lib/src/routing/app_router.dart
git commit -m "feat(settings): apply default routing profile to route editor"
```

---

### Task 13: Default vehicle pre-selection

**Files:**
- Modify: `movile_app/lib/src/features/session/live_session_screen.dart`
- Modify: `movile_app/lib/src/features/free_ride/free_ride_screen.dart`

> The `LiveSessionController` already has `selectVehicle(String? vehicleId)`. The screen should call it with the default from settings when the session loads and no vehicle is already selected.

- [ ] **Step 1: Pre-select default vehicle in LiveSessionScreen**

In `movile_app/lib/src/features/session/live_session_screen.dart`, in `initState()`:

```dart
@override
void initState() {
  super.initState();
  widget.controller.addListener(_onChange);
  widget.authService?.addListener(_onChange);
  widget.controller.load().then((_) {
    // Pre-select default vehicle if none is already chosen
    if (widget.controller.selectedVehicleId == null) {
      final defaultId = widget.settingsController.defaultVehicleId;
      if (defaultId != null) {
        widget.controller.selectVehicle(defaultId);
      }
    }
  });
}
```

- [ ] **Step 2: Pre-select default vehicle in FreeRideScreen**

Apply the same pattern in `movile_app/lib/src/features/free_ride/free_ride_screen.dart`:

```dart
@override
void initState() {
  super.initState();
  widget.controller.addListener(_onChange);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (widget.controller.selectedVehicleId == null) {
      final defaultId = widget.settingsController.defaultVehicleId;
      if (defaultId != null) {
        widget.controller.selectVehicle(defaultId);
      }
    }
  });
}
```

- [ ] **Step 3: Wire default vehicle picker in SettingsScreen**

The Settings screen shows a dropdown for "Default vehicle". To populate it with actual vehicles we need the `GarageService`. Update `SettingsScreen` to accept an optional `garageService`:

In `settings_screen.dart`, add:
```dart
import '../../services/garage/garage_service.dart';

// In SettingsScreen:
final GarageService? garageService;

// In constructor:
const SettingsScreen({
  // ... existing params ...
  this.garageService,
});
```

Replace the static garage section with a dynamic one:
```dart
// ── Garage ──────────────────────────────────────────────────────────────────
if (garageService != null)
  ListenableBuilder(
    listenable: garageService!,
    builder: (context, _) {
      final vehicles = garageService!.vehicles;
      return ListTile(
        title: Text(l.settingsDefaultVehicleLabel),
        trailing: DropdownButton<String?>(
          value: settingsController.defaultVehicleId,
          underline: const SizedBox(),
          onChanged: (v) => settingsController.setDefaultVehicleId(v),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(l.settingsDefaultVehicleNone),
            ),
            for (final v in vehicles)
              DropdownMenuItem<String?>(
                value: v.id,
                child: Text(v.name),
              ),
          ],
        ),
      );
    },
  ),
```

In `app_router.dart`, pass `garageService` to `SettingsScreen`:
```dart
builder: (_, __) => SettingsScreen(
  localeController: localeController,
  settingsController: settingsController,
  authService: authService,
  repository: repository,
  garageService: garageService,  // NEW
),
```

- [ ] **Step 4: Run flutter analyze**

```bash
cd movile_app && flutter analyze
```

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/session/live_session_screen.dart movile_app/lib/src/features/free_ride/free_ride_screen.dart movile_app/lib/src/features/settings/settings_screen.dart movile_app/lib/src/routing/app_router.dart
git commit -m "feat(settings): pre-select default vehicle in session and free ride"
```

---

### Task 14: Change password

**Files:**
- Modify: `movile_app/lib/src/features/settings/settings_screen.dart`

> The `_ChangePasswordDialog` widget was stubbed in Task 6. This task wires the actual Supabase call.

- [ ] **Step 1: Complete _ChangePasswordDialogState._submit()**

In `settings_screen.dart`, replace the stub `_submit()` method:

```dart
Future<void> _submit() async {
  if (!_formKey.currentState!.validate()) return;
  setState(() {
    _loading = true;
    _error = null;
  });

  try {
    await supabase.auth.updateUser(
      UserAttributes(password: _newCtrl.text),
    );
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.l.settingsChangePasswordSuccess)),
    );
  } catch (_) {
    if (!mounted) return;
    setState(() {
      _error = widget.l.settingsChangePasswordError;
      _loading = false;
    });
  }
}
```

Add the import at the top of `settings_screen.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';
```

> **Important:** This approach uses the Supabase client-side `updateUser()` which works for email/password users only. Google OAuth users do not have a Splitway-managed password; to handle this gracefully, check the user's provider before showing the "Change password" option:

In the `// ── Account ──` section of `SettingsScreen.build()`, update the condition:
```dart
// Only show "change password" for email/password users
final isEmailUser = authService?.currentUser?.appMetadata['provider'] == 'email';
if (isEmailUser) ...[
  ListTile(
    title: Text(l.settingsChangePasswordLabel),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => _showChangePasswordDialog(context, l),
  ),
],
```

- [ ] **Step 2: Test on device**

Sign in with email/password. Go to Settings → Change password. Enter a new password (≥6 chars) and confirm. Expect a success snackbar. Sign out and sign back in with the new password to verify.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/features/settings/settings_screen.dart
git commit -m "feat(settings): implement change password via Supabase updateUser"
```

---

### Task 15: Delete account — Edge Function + UI

**Files:**
- Create: `supabase/functions/delete-user/index.ts`
- Modify: `movile_app/lib/src/features/settings/settings_screen.dart`

- [ ] **Step 1: Write the Edge Function**

Create `supabase/functions/delete-user/index.ts`:

```typescript
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return new Response('Unauthorized', { status: 401, headers: corsHeaders })
  }

  // Validate the caller's JWT using the anon key client
  const anonClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
  )
  const { data: { user }, error: authError } = await anonClient.auth.getUser(
    authHeader.replace('Bearer ', ''),
  )
  if (authError || !user) {
    return new Response('Unauthorized', { status: 401, headers: corsHeaders })
  }

  // Delete the user using the service role key (privileged)
  const adminClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  )
  const { error: deleteError } = await adminClient.auth.admin.deleteUser(user.id)
  if (deleteError) {
    return new Response(deleteError.message, { status: 500, headers: corsHeaders })
  }

  return new Response('OK', { status: 200, headers: corsHeaders })
})
```

- [ ] **Step 2: Deploy the Edge Function**

```bash
supabase functions deploy delete-user --no-verify-jwt
```

Expected: `Function delete-user deployed.`

> The `--no-verify-jwt` flag is safe here because the function does its own JWT validation via `getUser()`.

- [ ] **Step 3: Implement _deleteAccount() in SettingsScreen**

In `settings_screen.dart`, replace the stub `_deleteAccount()`:

```dart
Future<void> _deleteAccount(BuildContext context, AppLocalizations l) async {
  try {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;

    final response = await Supabase.instance.client.functions.invoke(
      'delete-user',
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );

    if (response.status != 200) throw Exception('status ${response.status}');

    // Sign out locally (the account is already gone server-side)
    await authService!.signOut();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.settingsDeleteAccountSuccess)),
    );
    context.go('/routes');
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.settingsDeleteAccountError)),
    );
  }
}
```

- [ ] **Step 4: Test on a staging account**

Create a throwaway account. Navigate to Settings → Delete account. Confirm. Verify:
- The account is removed from the Supabase Auth dashboard.
- The app redirects to `/routes`.
- Attempting to sign in with the deleted credentials fails.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/delete-user/ movile_app/lib/src/features/settings/settings_screen.dart
git commit -m "feat(settings): delete account via Supabase Edge Function"
```

---

### Task 16: Export history as CSV

**Files:**
- Modify: `movile_app/lib/src/features/settings/settings_screen.dart`

- [ ] **Step 1: Add imports**

In `settings_screen.dart`:
```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:splitway_core/splitway_core.dart';
```

- [ ] **Step 2: Implement _exportHistory()**

Replace the stub in `settings_screen.dart`:

```dart
Future<void> _exportHistory(BuildContext context, AppLocalizations l) async {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(l.settingsExportSharing)),
  );

  final routes = await repository.getAllRoutes();
  final sessions = await repository.getAllSessions();
  final freeRides = await repository.getAllFreeRides();

  final routeIndex = {for (final r in routes) r.id: r.name};

  final buffer = StringBuffer();
  buffer.writeln(
    'type,date,route,laps,best_lap_ms,distance_m,max_speed_mps,avg_speed_mps,vehicle_id',
  );

  for (final s in sessions) {
    final bestMs = s.laps.isEmpty
        ? ''
        : s.laps
            .map((l) => l.duration.inMilliseconds)
            .reduce((a, b) => a < b ? a : b)
            .toString();
    buffer.writeln([
      'session',
      s.startedAt.toIso8601String(),
      routeIndex[s.routeTemplateId] ?? s.routeTemplateId,
      s.laps.length,
      bestMs,
      s.totalDistanceMeters.toStringAsFixed(0),
      s.maxSpeedMps.toStringAsFixed(2),
      s.avgSpeedMps.toStringAsFixed(2),
      s.vehicleId ?? '',
    ].join(','));
  }

  for (final r in freeRides) {
    buffer.writeln([
      'free_ride',
      r.startedAt.toIso8601String(),
      '',   // no route
      '',   // no laps
      '',   // no best lap
      r.totalDistanceMeters.toStringAsFixed(0),
      r.maxSpeedMps.toStringAsFixed(2),
      r.avgSpeedMps.toStringAsFixed(2),
      r.vehicleId ?? '',
    ].join(','));
  }

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/splitway_history.csv');
  await file.writeAsString(buffer.toString());

  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'text/csv')],
    subject: 'Splitway history export',
  );
}
```

- [ ] **Step 3: Check FreeRideRun fields exist**

Open `packages/splitway_core/lib/src/models/free_ride_run.dart` and confirm it has `totalDistanceMeters`, `maxSpeedMps`, `avgSpeedMps`, and `vehicleId`. If any field is missing, use what's available and remove the missing column from the CSV header and row.

- [ ] **Step 4: Test on device**

Go to Settings → Export history. The system share sheet should appear with a `.csv` file. Open it in a spreadsheet app and verify rows are correct.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/features/settings/settings_screen.dart
git commit -m "feat(settings): export history as CSV via share sheet"
```

---

### Task 17: Clear local cache

**Files:**
- Modify: `movile_app/lib/src/data/repositories/local_draft_repository.dart`
- Modify: `movile_app/lib/src/features/settings/settings_screen.dart`

- [ ] **Step 1: Add deleteAllUserData() to LocalDraftRepository**

In `movile_app/lib/src/data/repositories/local_draft_repository.dart`, add after the existing delete methods:

```dart
/// Deletes all routes, sessions, and free rides owned by the current user.
/// Demo rows (owner_id IS NULL) are not affected.
Future<void> deleteAllUserData() async {
  if (_userId == null) return; // nothing to clear for unauthenticated users
  await _db.transaction((txn) async {
    await txn.delete(
      'session_runs',
      where: 'owner_id = ?',
      whereArgs: [_userId],
    );
    await txn.delete(
      'free_ride_runs',
      where: 'owner_id = ?',
      whereArgs: [_userId],
    );
    // Deleting a route cascades to its sectors (enforced by foreign key in schema).
    await txn.delete(
      'route_templates',
      where: 'owner_id = ?',
      whereArgs: [_userId],
    );
  });
  _changes.add(null);
}
```

> **Note:** Verify the table names `session_runs`, `free_ride_runs`, `route_templates` match the actual schema by checking `movile_app/lib/src/data/local/splitway_local_database.dart`.

- [ ] **Step 2: Implement _clearCache() in SettingsScreen**

Replace the stub in `settings_screen.dart`:

```dart
Future<void> _clearCache(BuildContext context, AppLocalizations l) async {
  await repository.deleteAllUserData();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(l.settingsClearCacheDone)),
  );
}
```

- [ ] **Step 3: Verify table names**

Open `movile_app/lib/src/data/local/splitway_local_database.dart` and confirm `session_runs`, `free_ride_runs`, and `route_templates` are the correct table names. Adjust `deleteAllUserData()` if they differ.

- [ ] **Step 4: Test on device**

1. Create a route and record a session.
2. Go to Settings → Clear local data → confirm.
3. Navigate to History — it should be empty (demo data may still show).
4. Navigate to Routes — user routes gone, demo routes remain.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/data/repositories/local_draft_repository.dart movile_app/lib/src/features/settings/settings_screen.dart
git commit -m "feat(settings): clear all local user data from settings"
```

---

## Self-Review

**Spec coverage check:**
- ✅ Theme mode (light/dark/system) — Tasks 3, 6
- ✅ Unit system (metric/imperial) — Tasks 4, 5, 7
- ✅ Time format separator — Tasks 4, 5, 7
- ✅ Keep screen awake — Task 8
- ✅ Haptic feedback on sector/lap — Task 9
- ✅ Audio alerts — Task 10
- ✅ GPS sampling rate — Task 11
- ✅ Default routing profile — Task 12
- ✅ Default vehicle — Task 13
- ✅ Change password — Task 14
- ✅ Delete account — Task 15
- ✅ Export history (CSV) — Task 16
- ✅ Clear local cache — Task 17

**Placeholder scan:** No TBD or "implement later" stubs remain. Tasks 6 stubs for `_deleteAccount`, `_exportHistory`, `_clearCache` are intentionally empty at that commit point and filled by Tasks 15–17.

**Type consistency:** `GpsSamplingInterval` enum is defined in `app_settings_controller.dart` and referenced consistently in settings screen, tests, and controller. `UnitSystem` is passed as an optional named param with `UnitSystem.metric` as default throughout `Formatters`. `TrackingEvent` subtypes (`SectorCrossed`, `LapClosed`) match those defined in `packages/splitway_core/lib/src/tracking/tracking_engine.dart`.
