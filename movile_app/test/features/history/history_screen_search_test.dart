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
import 'package:splitway_mobile/src/services/garage/garage_service.dart';
import 'package:splitway_mobile/src/services/garage/vehicle.dart';
import 'package:splitway_mobile/src/services/locale/locale_controller.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

// (GarageService.withVehicles is used directly in tests — no fake class needed.)

Vehicle _makeVehicle(String id, String name) => Vehicle(
      id: id,
      userId: 'test-user',
      name: name,
      type: VehicleType.car,
      createdAt: DateTime(2024, 1, 1),
    );

// ---------------------------------------------------------------------------

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

SessionRun _makeSession(String id, String routeId, {String? vehicleId}) =>
    SessionRun(
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
      vehicleId: vehicleId,
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

    // Wait for the 250 ms debounce to fire, then let the full-load complete.
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntilLoaded(tester);

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
    await _pumpUntilLoaded(tester);

    // Filtered to one entry.
    expect(find.text('Montmeló'), findsNothing);

    // Tap the clear (✕) icon button.
    await tester.tap(find.byIcon(Icons.clear));
    // The clear button fires _onQueryChanged('') → debounce → _onFiltersChanged.
    // Wait for debounce + paginated reload to complete.
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntilLoaded(tester);

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
    await _pumpUntilLoaded(tester);

    // Filtered empty state.
    expect(find.text('Sin resultados'), findsOneWidget);

    // Tap the "Limpiar filtros" button.
    await tester.tap(find.text('Limpiar filtros'));
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntilLoaded(tester);

    // All entries are restored.
    expect(find.text('Jarama'), findsOneWidget);
    expect(find.text('Montmeló'), findsOneWidget);
    expect(find.text('Paseo casual'), findsOneWidget);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });

  // ---------------------------------------------------------------------------
  // Test 4: Tapping the tune icon opens the filters sheet
  // ---------------------------------------------------------------------------
  testWidgets('tapping tune icon opens the filters sheet', (tester) async {
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

    // Tap the tune (filter) icon button.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    // The filters sheet should be open and show its title.
    expect(find.text('Filtros'), findsOneWidget);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });

  // ---------------------------------------------------------------------------
  // Test 6: Vehicle chip appears with vehicle name after applying filter
  // ---------------------------------------------------------------------------
  testWidgets('vehicle chip appears with vehicle name after applying filter',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;

    const vehicleAId = 'vehicle-chip-a';

    await tester.runAsync(() async {
      boot = await _openRepo();
      settings = await AppSettingsController.load();
      final routeA = _makeRoute('route-chip-a', 'Ruta Chip A');
      await boot.repo.saveRouteTemplate(routeA);
      await boot.repo.saveSessionRun(
        _makeSession('session-chip-a', 'route-chip-a', vehicleId: vehicleAId),
      );
    });

    // ignore: invalid_use_of_visible_for_testing_member
    final garageService = GarageService.withVehicles([
      _makeVehicle(vehicleAId, 'Coche Chip A'),
    ]);

    await tester.pumpWidget(_harness(
      child: HistoryScreen(
        repository: boot.repo,
        settingsController: settings,
        garageService: garageService,
      ),
    ));

    await _pumpUntilLoaded(tester);

    // Open filters sheet.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    // Select vehicle A.
    await tester.tap(find.widgetWithText(FilterChip, 'Coche Chip A'));
    await tester.pump();

    // Apply.
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
    // Close animation for the bottom sheet.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    // Allow the _loadAll to complete.
    await _pumpUntilLoaded(tester);

    // An InputChip with the vehicle name should now be visible in the chip row.
    expect(
      find.widgetWithText(InputChip, 'Coche Chip A'),
      findsOneWidget,
    );

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });

  // ---------------------------------------------------------------------------
  // Test 7: Tapping the chip's delete icon clears that filter
  // ---------------------------------------------------------------------------
  testWidgets('tapping vehicle chip delete icon clears the vehicle filter',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;

    const vehicleAId = 'vehicle-del-a';
    const vehicleBId = 'vehicle-del-b';

    await tester.runAsync(() async {
      boot = await _openRepo();
      settings = await AppSettingsController.load();
      final routeA = _makeRoute('route-del-a', 'Ruta Del A');
      final routeB = _makeRoute('route-del-b', 'Ruta Del B');
      await boot.repo.saveRouteTemplate(routeA);
      await boot.repo.saveRouteTemplate(routeB);
      await boot.repo.saveSessionRun(
        _makeSession('session-del-a', 'route-del-a', vehicleId: vehicleAId),
      );
      await boot.repo.saveSessionRun(
        _makeSession('session-del-b', 'route-del-b', vehicleId: vehicleBId),
      );
    });

    // ignore: invalid_use_of_visible_for_testing_member
    final garageService = GarageService.withVehicles([
      _makeVehicle(vehicleAId, 'Coche Del A'),
      _makeVehicle(vehicleBId, 'Coche Del B'),
    ]);

    await tester.pumpWidget(_harness(
      child: HistoryScreen(
        repository: boot.repo,
        settingsController: settings,
        garageService: garageService,
      ),
    ));

    await _pumpUntilLoaded(tester);

    // Both routes visible initially.
    expect(find.text('Ruta Del A'), findsOneWidget);
    expect(find.text('Ruta Del B'), findsOneWidget);

    // Apply vehicle A filter via sheet.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Coche Del A'));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await _pumpUntilLoaded(tester);

    // Only Ruta Del A visible; Ruta Del B is hidden.
    expect(find.text('Ruta Del A'), findsOneWidget);
    expect(find.text('Ruta Del B'), findsNothing);

    // Chip is shown.
    expect(find.widgetWithText(InputChip, 'Coche Del A'), findsOneWidget);

    // Tap the delete button on the InputChip (the chip internally wraps its
    // delete icon in a Semantics node with deleteButtonTooltip).
    final chipFinder = find.widgetWithText(InputChip, 'Coche Del A');
    final chip = tester.widget<InputChip>(chipFinder);
    // InputChip.onDeleted is set — call it directly via the chip's semantics.
    // Use the tooltip-based finder as MaterialLocalizations provides the label.
    final mLocalizations = MaterialLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    final deleteButtonTooltip = mLocalizations.deleteButtonTooltip;
    final deleteIcon = find.descendant(
      of: chipFinder,
      matching: find.byTooltip(deleteButtonTooltip),
    );
    // If no tooltip widget found, fall back to calling onDeleted directly.
    if (deleteIcon.evaluate().isEmpty) {
      chip.onDeleted?.call();
    } else {
      await tester.tap(deleteIcon);
    }
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntilLoaded(tester);

    // Both routes are visible again and chip is gone.
    expect(find.text('Ruta Del A'), findsOneWidget);
    expect(find.text('Ruta Del B'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Coche Del A'), findsNothing);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });

  // ---------------------------------------------------------------------------
  // Test 8: Full-load triggered when filtering reveals items past first page
  // ---------------------------------------------------------------------------
  testWidgets('filter triggers full-load and reveals items beyond page 1',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;

    await tester.runAsync(() async {
      boot = await _openRepo();
      settings = await AppSettingsController.load();

      // Create one special "needle" route/session with the oldest date so it
      // sorts last in the descending-date order (i.e. it will be beyond the
      // first 30 entries when pagination is active).
      final needleRoute = _makeRoute('route-needle', 'needle-in-haystack');
      await boot.repo.saveRouteTemplate(needleRoute);

      // Seed 35 "common" sessions with recent dates to fill the first page.
      for (var i = 0; i < 35; i++) {
        final routeId = 'route-common-$i';
        await boot.repo.saveRouteTemplate(_makeRoute(routeId, 'Common $i'));
        await boot.repo.saveSessionRun(
          SessionRun(
            id: 'session-common-$i',
            routeTemplateId: routeId,
            startedAt: DateTime(2025, 1, 2, 0, 0, i), // newer dates
            status: SessionStatus.completed,
            points: const [],
            laps: const [],
            sectorSummaries: const [],
            totalDistanceMeters: 1000,
            maxSpeedMps: 30,
            avgSpeedMps: 20,
          ),
        );
      }

      // The needle session has the oldest date so it's at the very end.
      await boot.repo.saveSessionRun(
        SessionRun(
          id: 'session-needle',
          routeTemplateId: 'route-needle',
          startedAt: DateTime(2024, 1, 1), // oldest → sorts last (index 35)
          status: SessionStatus.completed,
          points: const [],
          laps: const [],
          sectorSummaries: const [],
          totalDistanceMeters: 1000,
          maxSpeedMps: 30,
          avgSpeedMps: 20,
        ),
      );
    });

    await tester.pumpWidget(_harness(
      child: HistoryScreen(
        repository: boot.repo,
        settingsController: settings,
      ),
    ));

    // Wait for initial load (first 30 items — needle is NOT yet loaded).
    await _pumpUntilLoaded(tester);

    // The needle should NOT be visible in the paginated (first-page-only) view.
    expect(find.text('needle-in-haystack'), findsNothing);

    // Type into the search field to activate the query filter.
    await tester.enterText(find.byType(TextField).first, 'needle');

    // Wait for debounce (250 ms) plus a bit of async-load time.
    await tester.pump(const Duration(milliseconds: 300));
    // Allow the async _loadAll to complete.
    await _pumpUntilLoaded(tester);

    // After full-load, the needle session should be visible.
    expect(find.text('needle-in-haystack'), findsOneWidget);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });

  // ---------------------------------------------------------------------------
  // Test 9: Clearing filters returns to paginated mode
  // ---------------------------------------------------------------------------
  testWidgets('clearing filters returns to paginated mode', (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;

    // We need an item that is only loaded when ALL entries are fetched (i.e.
    // in full-load mode).  Seed 35 sessions with recent timestamps (so they
    // land in the first page in descending date order) plus one extra session
    // with the oldest date so it is always the last item (index 35 in the
    // full list, beyond the 30-item paginated first page).
    const String oldestRouteId = 'route-old-pg';
    const String oldestRouteName = 'OldestRoutePG';

    await tester.runAsync(() async {
      boot = await _openRepo();
      settings = await AppSettingsController.load();

      // 35 "filler" sessions with newer dates.
      for (var i = 0; i < 35; i++) {
        final routeId = 'route-pg-$i';
        await boot.repo.saveRouteTemplate(_makeRoute(routeId, 'Route PG $i'));
        await boot.repo.saveSessionRun(
          SessionRun(
            id: 'session-pg-$i',
            routeTemplateId: routeId,
            startedAt: DateTime(2025, 1, 2, 0, 0, i),
            status: SessionStatus.completed,
            points: const [],
            laps: const [],
            sectorSummaries: const [],
            totalDistanceMeters: 1000,
            maxSpeedMps: 30,
            avgSpeedMps: 20,
          ),
        );
      }

      // The oldest session — only visible in full-load mode.
      await boot.repo.saveRouteTemplate(
          _makeRoute(oldestRouteId, oldestRouteName));
      await boot.repo.saveSessionRun(
        SessionRun(
          id: 'session-oldest-pg',
          routeTemplateId: oldestRouteId,
          startedAt: DateTime(2020, 1, 1), // oldest → last in desc sort
          status: SessionStatus.completed,
          points: const [],
          laps: const [],
          sectorSummaries: const [],
          totalDistanceMeters: 1000,
          maxSpeedMps: 30,
          avgSpeedMps: 20,
        ),
      );
    });

    await tester.pumpWidget(_harness(
      child: HistoryScreen(
        repository: boot.repo,
        settingsController: settings,
      ),
    ));

    await _pumpUntilLoaded(tester);

    // The oldest item is NOT shown in paginated mode (only first 30 loaded).
    expect(find.text(oldestRouteName), findsNothing);

    // Apply a query filter — this triggers _loadAll which fetches all 36.
    await tester.enterText(find.byType(TextField).first, 'OldestRoutePG');
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntilLoaded(tester);

    // The oldest item IS now visible because full-load fetched everything.
    // Use widgetWithText(Card, ...) to avoid matching the search TextField.
    expect(find.widgetWithText(Card, oldestRouteName), findsOneWidget);

    // Clear the search filter by tapping the ✕ icon.
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump(const Duration(milliseconds: 300));
    await _pumpUntilLoaded(tester);

    // After clearing filters, we're back to paginated mode (only 30 loaded).
    // The oldest item is no longer visible — it's beyond the first page.
    expect(find.widgetWithText(Card, oldestRouteName), findsNothing);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });

  // ---------------------------------------------------------------------------
  // Test 5: Vehicle filter via filters sheet narrows the list
  // ---------------------------------------------------------------------------
  testWidgets('vehicle filter via sheet reduces displayed entries',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;

    const vehicleAId = 'vehicle-a';
    const vehicleBId = 'vehicle-b';

    await tester.runAsync(() async {
      boot = await _openRepo();
      settings = await AppSettingsController.load();

      // Two routes.
      final routeA = _makeRoute('route-a', 'Ruta A');
      final routeB = _makeRoute('route-b', 'Ruta B');
      await boot.repo.saveRouteTemplate(routeA);
      await boot.repo.saveRouteTemplate(routeB);

      // Two sessions: one for vehicle A, one for vehicle B.
      await boot.repo.saveSessionRun(
        _makeSession('session-a', 'route-a', vehicleId: vehicleAId),
      );
      await boot.repo.saveSessionRun(
        _makeSession('session-b', 'route-b', vehicleId: vehicleBId),
      );
    });

    // ignore: invalid_use_of_visible_for_testing_member
    final garageService = GarageService.withVehicles([
      _makeVehicle(vehicleAId, 'Coche A'),
      _makeVehicle(vehicleBId, 'Coche B'),
    ]);

    await tester.pumpWidget(_harness(
      child: HistoryScreen(
        repository: boot.repo,
        settingsController: settings,
        garageService: garageService,
      ),
    ));

    await _pumpUntilLoaded(tester);

    // Both routes are visible initially.
    expect(find.text('Ruta A'), findsOneWidget);
    expect(find.text('Ruta B'), findsOneWidget);

    // Open the filters sheet.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    // Tap the "Coche A" vehicle FilterChip (inside the sheet).
    await tester.tap(find.widgetWithText(FilterChip, 'Coche A'));
    await tester.pump();

    // Scroll to bring "Aplicar" into view (sheet may be taller than viewport).
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pump();

    // Tap "Aplicar".
    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await _pumpUntilLoaded(tester);

    // Only "Ruta A" (linked to vehicle A) should appear.
    expect(find.text('Ruta A'), findsOneWidget);
    expect(find.text('Ruta B'), findsNothing);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });
}
