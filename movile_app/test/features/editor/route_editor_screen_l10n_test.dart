import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/src/config/app_config.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/features/editor/route_editor_controller.dart';
import 'package:splitway_mobile/src/features/editor/route_editor_screen.dart';
import 'package:splitway_mobile/src/services/locale/locale_controller.dart';

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
    overridePath: 'file:l10n_test_$_dbCounter?mode=memory&cache=shared',
  );
  return (db: db, repo: LocalDraftRepository(db));
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('route_editor renders Spanish title under es locale',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late RouteEditorController controller;
    await tester.runAsync(() async {
      boot = await _openRepo();
      controller = RouteEditorController(boot.repo);
    });
    await tester.pumpWidget(_harness(
      locale: const Locale('es'),
      child: RouteEditorScreen(
        controller: controller,
        config: const AppConfig(),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
    }
    expect(find.text('Mis rutas'), findsOneWidget);
    controller.dispose();
    await tester.runAsync(() => boot.db.close());
  });

  testWidgets('route_editor renders English title under en locale',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late RouteEditorController controller;
    await tester.runAsync(() async {
      boot = await _openRepo();
      controller = RouteEditorController(boot.repo);
    });
    await tester.pumpWidget(_harness(
      locale: const Locale('en'),
      child: RouteEditorScreen(
        controller: controller,
        config: const AppConfig(),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
    }
    expect(find.text('My routes'), findsOneWidget);
    controller.dispose();
    await tester.runAsync(() => boot.db.close());
  });
}
