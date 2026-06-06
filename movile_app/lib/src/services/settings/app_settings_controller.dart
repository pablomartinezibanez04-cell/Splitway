import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/log_level.dart';

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
    _audioAlerts = _prefs.getBool(_kAudioAlerts) ?? true;
    _gpsSamplingInterval = GpsSamplingInterval.values.byName(
      _prefs.getString(_kGpsSamplingInterval) ??
          GpsSamplingInterval.oneSecond.name,
    );
    _defaultVehicleId = _prefs.getString(_kDefaultVehicleId);
    _defaultRoutingProfile =
        _prefs.getString(_kDefaultRoutingProfile) ?? 'driving';
    _minLogLevel = LogLevel.fromName(
      _prefs.getString(_kMinLogLevel) ?? LogLevel.warning.name,
    );
    _remoteLogsEnabled = _prefs.getBool(_kRemoteLogsEnabled) ?? true;
    _maybeMigrateLegacyDismissals();
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
  static const _kNotificationPermissionAsked = 'notification_permission_asked';
  static const _kDismissedOfficialRoutes = 'dismissed_official_routes';
  static const _kMinLogLevel = 'min_log_level';
  static const _kRemoteLogsEnabled = 'remote_logs_enabled';

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
  late LogLevel _minLogLevel;
  late bool _remoteLogsEnabled;

  UnitSystem get unitSystem => _unitSystem;
  AppThemeMode get themeMode => _themeMode;
  bool get timeFormatDot => _timeFormatDot;
  bool get keepScreenAwake => _keepScreenAwake;
  bool get hapticFeedback => _hapticFeedback;
  bool get audioAlerts => _audioAlerts;
  GpsSamplingInterval get gpsSamplingInterval => _gpsSamplingInterval;
  String? get defaultVehicleId => _defaultVehicleId;
  String get defaultRoutingProfile => _defaultRoutingProfile;
  LogLevel get minLogLevel => _minLogLevel;
  bool get remoteLogsEnabled => _remoteLogsEnabled;
  bool get notificationPermissionAsked =>
      _prefs.getBool(_kNotificationPermissionAsked) ?? false;

  Map<String, int> get dismissedOfficialRoutes {
    final raw = _prefs.getString(_kDismissedOfficialRoutes);
    if (raw == null || raw.isEmpty) return const {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

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

  Future<void> markNotificationPermissionAsked() async {
    await _prefs.setBool(_kNotificationPermissionAsked, true);
  }

  Future<void> recordDismissal(String routeId, int updatedAtMillis) async {
    final current = Map<String, int>.from(dismissedOfficialRoutes);
    current[routeId] = updatedAtMillis;
    await _prefs.setString(_kDismissedOfficialRoutes, jsonEncode(current));
  }

  Future<void> clearDismissal(String routeId) async {
    final current = Map<String, int>.from(dismissedOfficialRoutes);
    if (current.remove(routeId) == null) return;
    await _prefs.setString(_kDismissedOfficialRoutes, jsonEncode(current));
  }

  void _maybeMigrateLegacyDismissals() {
    const legacyKey = 'dismissed_demo_route_ids';
    if (!_prefs.containsKey(legacyKey)) return;
    final legacy = _prefs.getStringList(legacyKey) ?? const [];
    final migrated = <String, int>{
      for (final id in legacy) id: 0,
    };
    _prefs.setString(_kDismissedOfficialRoutes, jsonEncode(migrated));
    _prefs.remove(legacyKey);
  }

  @Deprecated('Use dismissedOfficialRoutes. Removed in T11/T14.')
  Set<String> get dismissedDemoIds => dismissedOfficialRoutes.keys.toSet();

  @Deprecated('Use recordDismissal. Removed in T11/T14.')
  Future<void> dismissDemoRoute(String id) => recordDismissal(id, 0);

  Future<void> setMinLogLevel(LogLevel v) async {
    if (_minLogLevel == v) return;
    _minLogLevel = v;
    await _prefs.setString(_kMinLogLevel, v.name);
    notifyListeners();
  }

  Future<void> setRemoteLogsEnabled(bool v) async {
    if (_remoteLogsEnabled == v) return;
    _remoteLogsEnabled = v;
    await _prefs.setBool(_kRemoteLogsEnabled, v);
    notifyListeners();
  }
}
