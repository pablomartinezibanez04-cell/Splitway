import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/features/history/history_screen.dart';
import 'package:splitway_mobile/src/services/locale/locale_controller.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

Widget _harness({required Widget child}) => MaterialApp(
      locale: const Locale('es'),
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
        'file:history_group_test_$_dbCounter?mode=memory&cache=shared',
  );
  return (db: db, repo: LocalDraftRepository(db));
}

RouteTemplate _makeRoute(String id, String name) => RouteTemplate(
      id: id,
      name: name,
      path: const [
        GeoPoint(latitude: 40.0, longitude: -3.0),
        GeoPoint(latitude: 40.001, longitude: -3.0),
      ],
      startFinishGate: GateDefinition(
        left: const GeoPoint(latitude: 40.0, longitude: -3.0),
        right: const GeoPoint(latitude: 40.001, longitude: -3.0),
      ),
      sectors: const [],
      difficulty: RouteDifficulty.medium,
      createdAt: DateTime(2024, 1, 1),
    );

SessionRun _makeSession(String id, String routeId, DateTime startedAt) =>
    SessionRun(
      id: id,
      routeTemplateId: routeId,
      startedAt: startedAt,
      status: SessionStatus.completed,
      points: const [],
      laps: const [],
      sectorSummaries: const [],
      totalDistanceMeters: 1000,
      maxSpeedMps: 30,
      avgSpeedMps: 20,
    );

FreeRideRun _makeFreeRide(String id, String name) => FreeRideRun(
      id: id,
      startedAt: DateTime(2024, 6, 2, 10, 0),
      status: FreeRideStatus.completed,
      points: const [],
      totalDistanceMeters: 5000,
      maxSpeedMps: 15,
      avgSpeedMps: 10,
      name: name,
    );

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('grouping by route collapses sessions and drills in',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _openRepo();
      settings = await AppSettingsController.load();
      boot.repo.userId = 'test-user';
      await boot.repo.saveRouteTemplate(_makeRoute('route-a', 'Ruta A'));
      await boot.repo.saveRouteTemplate(_makeRoute('route-b', 'Ruta B'));
      // Two sessions on Ruta A, one on Ruta B, plus a free ride.
      await boot.repo
          .saveSessionRun(_makeSession('s-a1', 'route-a', DateTime(2024, 6, 3)));
      await boot.repo
          .saveSessionRun(_makeSession('s-a2', 'route-a', DateTime(2024, 6, 1)));
      await boot.repo
          .saveSessionRun(_makeSession('s-b1', 'route-b', DateTime(2024, 6, 4)));
      await boot.repo.saveFreeRideRun(_makeFreeRide('fr-1', 'Paseo casual'));
    });

    await tester.pumpWidget(_harness(
      child: HistoryScreen(
        repository: boot.repo,
        settingsController: settings,
      ),
    ));
    await _pumpUntilLoaded(tester);

    // Open filters, enable "Agrupar por ruta", apply.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agrupar por ruta'));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await _pumpUntilLoaded(tester);

    // One row per route + a "Rutas libres" group. Ruta A shows 2 sessions.
    expect(find.widgetWithText(Card, 'Ruta A'), findsOneWidget);
    expect(find.widgetWithText(Card, 'Ruta B'), findsOneWidget);
    expect(find.widgetWithText(Card, 'Rutas libres'), findsOneWidget);
    expect(find.textContaining('2 sesiones'), findsOneWidget);

    // Drill into Ruta A → both of its sessions are listed.
    await tester.tap(find.widgetWithText(Card, 'Ruta A'));
    await tester.pumpAndSettle();
    await _pumpUntilLoaded(tester);

    // The detail screen shows two session tiles for Ruta A.
    expect(find.widgetWithText(Card, 'Ruta A'), findsNWidgets(2));

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });
}
