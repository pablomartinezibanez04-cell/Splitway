import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/src/config/app_config.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/features/session/live_session_controller.dart';
import 'package:splitway_mobile/src/features/session/live_session_screen.dart';
import 'package:splitway_mobile/src/services/locale/locale_controller.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

Widget _harness({required Locale locale, required Widget child}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

int _dbCounter = 0;

Future<({SplitwayLocalDatabase db, LocalDraftRepository repo})>
    _openRepo() async {
  _dbCounter += 1;
  final db = await SplitwayLocalDatabase.open(
    overridePath:
        'file:session_l10n_test_$_dbCounter?mode=memory&cache=shared',
  );
  return (db: db, repo: LocalDraftRepository(db));
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('live_session renders Spanish title under es locale',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late LiveSessionController controller;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _openRepo();
      controller = LiveSessionController(boot.repo);
      settings = await AppSettingsController.load();
    });
    await tester.pumpWidget(_harness(
      locale: const Locale('es'),
      child: LiveSessionScreen(
        controller: controller,
        config: const AppConfig(),
        settingsController: settings,
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
    }
    expect(find.text('Sesión en vivo'), findsOneWidget);
    controller.dispose();
    await tester.runAsync(() => boot.db.close());
  });

  testWidgets('live_session renders English title under en locale',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late LiveSessionController controller;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _openRepo();
      controller = LiveSessionController(boot.repo);
      settings = await AppSettingsController.load();
    });
    await tester.pumpWidget(_harness(
      locale: const Locale('en'),
      child: LiveSessionScreen(
        controller: controller,
        config: const AppConfig(),
        settingsController: settings,
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
    }
    expect(find.text('Live session'), findsOneWidget);
    controller.dispose();
    await tester.runAsync(() => boot.db.close());
  });
}
