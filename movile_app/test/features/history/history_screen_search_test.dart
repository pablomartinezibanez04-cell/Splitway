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
        'file:history_search_test_$_dbCounter?mode=memory&cache=shared',
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

SessionRun _makeSession(String id, String routeId) => SessionRun(
      id: id,
      routeTemplateId: routeId,
      startedAt: DateTime(2024, 6, 1, 10, 0),
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

/// Seeds the repository with Jarama route, Montmeló route, two sessions and a free ride.
Future<void> _seed(LocalDraftRepository repo) async {
  final jarama = _makeRoute('route-jarama', 'Jarama');
  final montmelo = _makeRoute('route-montmelo', 'Montmeló');
  await repo.saveRouteTemplate(jarama);
  await repo.saveRouteTemplate(montmelo);
  await repo.saveSessionRun(_makeSession('session-jarama', 'route-jarama'));
  await repo.saveSessionRun(_makeSession('session-montmelo', 'route-montmelo'));
  await repo.saveFreeRideRun(_makeFreeRide('ride-paseo', 'Paseo casual'));
}

/// Pump until the async loading completes (mirrors the existing l10n test pattern).
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

  // ---------------------------------------------------------------------------
  // Test 1: Search filters entries by route name (case-insensitive)
  // ---------------------------------------------------------------------------
  testWidgets('search filters entries by route name (case-insensitive)',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _openRepo();
      settings = await AppSettingsController.load();
      await _seed(boot.repo);
    });

    await tester.pumpWidget(_harness(
      child: HistoryScreen(
        repository: boot.repo,
        settingsController: settings,
      ),
    ));

    // Wait for initial load.
    await _pumpUntilLoaded(tester);

    // All three entries should be visible initially.
    expect(find.text('Jarama'), findsOneWidget);
    expect(find.text('Montmeló'), findsOneWidget);
    expect(find.text('Paseo casual'), findsOneWidget);

    // Type into the search field.
    await tester.enterText(find.byType(TextField).first, 'jara');

    // Wait for the 250 ms debounce to fire.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    // Only the Jarama session should remain.
    expect(find.text('Jarama'), findsOneWidget);
    expect(find.text('Montmeló'), findsNothing);
    expect(find.text('Paseo casual'), findsNothing);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });

  // ---------------------------------------------------------------------------
  // Test 2: Clear (✕) button restores the list
  // ---------------------------------------------------------------------------
  testWidgets('clear button restores the full list', (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _openRepo();
      settings = await AppSettingsController.load();
      await _seed(boot.repo);
    });

    await tester.pumpWidget(_harness(
      child: HistoryScreen(
        repository: boot.repo,
        settingsController: settings,
      ),
    ));

    await _pumpUntilLoaded(tester);

    // Type a query.
    await tester.enterText(find.byType(TextField).first, 'jara');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    // Filtered to one entry.
    expect(find.text('Montmeló'), findsNothing);

    // Tap the clear (✕) icon button.
    await tester.tap(find.byIcon(Icons.clear));
    // The clear button fires _onQueryChanged('') immediately — no debounce needed,
    // but we still need to let the debounce timer expire.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    // All entries are back.
    expect(find.text('Jarama'), findsOneWidget);
    expect(find.text('Montmeló'), findsOneWidget);
    expect(find.text('Paseo casual'), findsOneWidget);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });

  // ---------------------------------------------------------------------------
  // Test 3: Filtered empty state appears and "Limpiar filtros" button works
  // ---------------------------------------------------------------------------
  testWidgets('filtered empty state appears and clear action works',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _openRepo();
      settings = await AppSettingsController.load();
      await _seed(boot.repo);
    });

    await tester.pumpWidget(_harness(
      child: HistoryScreen(
        repository: boot.repo,
        settingsController: settings,
      ),
    ));

    await _pumpUntilLoaded(tester);

    // Type a query that matches nothing.
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    // Filtered empty state.
    expect(find.text('Sin resultados'), findsOneWidget);

    // Tap the "Limpiar filtros" button.
    await tester.tap(find.text('Limpiar filtros'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    // All entries are restored.
    expect(find.text('Jarama'), findsOneWidget);
    expect(find.text('Montmeló'), findsOneWidget);
    expect(find.text('Paseo casual'), findsOneWidget);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });
}
