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
