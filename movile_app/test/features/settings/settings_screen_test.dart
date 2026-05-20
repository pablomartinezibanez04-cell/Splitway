import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/features/settings/settings_screen.dart';
import 'package:splitway_mobile/src/services/locale/locale_controller.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

Widget _harness(
  LocaleController controller,
  AppSettingsController settings,
  LocalDraftRepository repository,
) {
  return ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      locale: controller.locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: SettingsScreen(
        localeController: controller,
        settingsController: settings,
        repository: repository,
      ),
    ),
  );
}

int _dbCounter = 0;

Future<({SplitwayLocalDatabase db, LocalDraftRepository repo})>
    _openRepo() async {
  _dbCounter += 1;
  final db = await SplitwayLocalDatabase.open(
    overridePath:
        'file:settings_test_$_dbCounter?mode=memory&cache=shared',
  );
  return (db: db, repo: LocalDraftRepository(db));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows both language options and marks current', (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _openRepo();
      settings = await AppSettingsController.load();
    });
    final ctrl = await LocaleController.load(deviceLocale: const Locale('es'));
    await tester.pumpWidget(_harness(ctrl, settings, boot.repo));
    await tester.pumpAndSettle();

    expect(find.text('Español'), findsOneWidget);
    expect(find.text('Inglés'), findsOneWidget);

    final radioGroup = tester.widget<RadioGroup<Locale>>(
      find.byType(RadioGroup<Locale>),
    );
    expect(radioGroup.groupValue, const Locale('es'));
    await tester.runAsync(() async {
      await boot.repo.dispose();
      await boot.db.close();
    });
  });

  testWidgets('tapping English switches locale and updates UI', (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _openRepo();
      settings = await AppSettingsController.load();
    });
    final ctrl = await LocaleController.load(deviceLocale: const Locale('es'));
    await tester.pumpWidget(_harness(ctrl, settings, boot.repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inglés'));
    await tester.pumpAndSettle();

    expect(ctrl.locale, const Locale('en'));
    // After switching, the screen title is now in English ("Settings").
    expect(find.text('Settings'), findsOneWidget);
    await tester.runAsync(() async {
      await boot.repo.dispose();
      await boot.db.close();
    });
  });
}
