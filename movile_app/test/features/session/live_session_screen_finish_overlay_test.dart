import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:splitway_mobile/src/config/app_config.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/features/session/live_session_controller.dart';
import 'package:splitway_mobile/src/features/session/live_session_screen.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

Widget _harness({required Locale locale, required Widget child}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('es')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

int _dbCounter = 0;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => SharedPreferences.setMockInitialValues({
        // Disable audio + haptic so the audioplayers plugin is never initialised
        // (it has no test stub and throws MissingPluginException in the test env).
        'audio_alerts': false,
        'haptic_feedback': false,
      }));

  RouteTemplate openRoute() => RouteTemplate(
        id: 'r-open',
        name: 'Open',
        path: const [
          GeoPoint(latitude: 40.0, longitude: -3.0),
          GeoPoint(latitude: 40.00018, longitude: -3.0),
          GeoPoint(latitude: 40.00036, longitude: -3.0),
        ],
        startFinishGate: GateDefinition(
          left: GeoPoint(latitude: 40.0, longitude: -3.0001),
          right: GeoPoint(latitude: 40.0, longitude: -2.9999),
        ),
        sectors: const [],
        difficulty: RouteDifficulty.easy,
        createdAt: DateTime.utc(2026, 1, 1),
        expectedDuration: const Duration(seconds: 200),
      );

  TelemetryPoint tp(double lat, DateTime t) => TelemetryPoint(
      timestamp: t,
      location: GeoPoint(latitude: lat, longitude: -3.0),
      speedMps: 12);

  testWidgets('finish overlay shows on summary stage and Continue advances',
      (tester) async {
    _dbCounter += 1;
    late SplitwayLocalDatabase db;
    late LiveSessionController ctrl;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      db = await SplitwayLocalDatabase.open(
        overridePath:
            'file:finish_overlay_test_$_dbCounter?mode=memory&cache=shared',
      );
      final repo = LocalDraftRepository(db)..userId = 'user-1';
      await repo.saveRouteTemplate(openRoute());
      ctrl = LiveSessionController(repo);
      settings = await AppSettingsController.load();
    });

    await tester.pumpWidget(_harness(
      locale: const Locale('en'),
      child: LiveSessionScreen(
        controller: ctrl,
        config: const AppConfig(),
        settingsController: settings,
      ),
    ));

    // Let initState's load() settle (stage → ready, route selected).
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
    }

    // Force simulated source so startSession never reaches the GPS plugin.
    await tester.runAsync(() async {
      await ctrl.setSource(TrackingSource.simulated);
      await ctrl.startSession(
          includeHistorical: false, useCompassHeading: false);
    });
    await tester.pump();
    expect(ctrl.stage, LiveSessionStage.running);

    // Drive to the end so the session auto-finishes into the summary stage.
    // finishSession() awaits a real repo save → run it inside runAsync.
    final base = DateTime(2026, 5, 9, 10);
    final t = ctrl.tracker!;
    await tester.runAsync(() async {
      t.ingestSimulatedPoint(tp(39.9999, base));
      t.ingestSimulatedPoint(tp(40.00005, base.add(const Duration(seconds: 1))));
      t.ingestSimulatedPoint(tp(40.00036, base.add(const Duration(seconds: 2))));
      // Give the async auto-finish chain time to complete (engine → tracker →
      // controller._onTrackerChange → finishSession() → repo save → notifyListeners).
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump();

    expect(ctrl.stage, LiveSessionStage.summary);
    expect(find.text('Route finished'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(ctrl.stage, LiveSessionStage.finished);
    expect(find.text('Route finished'), findsNothing);

    ctrl.dispose();
    await tester.runAsync(() => db.close());
  });
}
