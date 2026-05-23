import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/src/config/app_config.dart';
import 'package:splitway_mobile/src/data/demo/demo_seed.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/features/editor/route_editor_controller.dart';
import 'package:splitway_mobile/src/features/editor/route_editor_screen.dart';
import 'package:splitway_mobile/src/features/history/history_screen.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

/// Iter 1 test strategy: pure-Dart tests for the data layer, and widget tests
/// that mount individual screens (NOT the full SplitwayApp). The full app
/// would need `integration_test` because `MaterialApp.router` +
/// `StatefulShellRoute.indexedStack` plus `sqflite_common_ffi` don't play
/// nicely with the FakeAsync zone used by `flutter_test`. Iter 2 will switch
/// to `integration_test` for full-app coverage.
int _dbCounter = 0;

Future<({SplitwayLocalDatabase db, LocalDraftRepository repo})> _bootRepo({
  bool seed = true,
  AppSettingsController? settingsController,
}) async {
  // Each test needs a fresh in-memory DB; sqflite_common_ffi caches
  // connections by path, so we use a counter to keep them distinct.
  _dbCounter += 1;
  final db = await SplitwayLocalDatabase.open(
    overridePath: 'file:test_$_dbCounter?mode=memory&cache=shared',
  );
  final repo = LocalDraftRepository(db);
  if (seed) {
    final settings = settingsController ?? await AppSettingsController.load();
    await DemoSeed.ensureSeeded(repo, settings);
  }
  return (db: db, repo: repo);
}

Future<void> _shutdown(
  ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot,
) async {
  await boot.repo.dispose();
  await boot.db.close();
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('es_ES');
  });

  test('SplitwayLocalDatabase + DemoSeed populate the demo route', () async {
    final boot = await _bootRepo();
    final routes = await boot.repo.getAllRoutes();
    expect(routes, hasLength(1));
    expect(routes.first.name, 'Circuito del Jarama');
    expect(routes.first.sectors, hasLength(2));
    expect(routes.first.startFinishGate, isA<GateDefinition>());
    await _shutdown(boot);
  });

  test('LocalDraftRepository round-trips a SessionRun', () async {
    final boot = await _bootRepo();
    final route = (await boot.repo.getAllRoutes()).first;
    final now = DateTime.parse('2026-04-29T10:00:00Z');
    final session = SessionRun(
      id: 'sess-test',
      routeTemplateId: route.id,
      startedAt: now,
      endedAt: now.add(const Duration(seconds: 90)),
      status: SessionStatus.completed,
      points: [
        TelemetryPoint(
          timestamp: now,
          location: route.startFinishGate.center,
          speedMps: 10,
        ),
      ],
      laps: [
        LapSummary(
          lapNumber: 1,
          duration: const Duration(seconds: 45),
          startedAt: now,
          endedAt: now.add(const Duration(seconds: 45)),
          distanceMeters: 500,
          avgSpeedMps: 11.1,
        ),
      ],
      sectorSummaries: const [],
      totalDistanceMeters: 500,
      maxSpeedMps: 12,
      avgSpeedMps: 10,
    );
    await boot.repo.saveSessionRun(session);
    final reloaded = await boot.repo.getSessionRun('sess-test');
    expect(reloaded, isNotNull);
    expect(reloaded!.laps, hasLength(1));
    expect(reloaded.points, hasLength(1));
    expect(reloaded.totalDistanceMeters, 500);
    await _shutdown(boot);
  });

  testWidgets('RouteEditorScreen renders the demo route after load',
      (tester) async {
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late RouteEditorController controller;
    await tester.runAsync(() async {
      boot = await _bootRepo();
      controller = RouteEditorController(boot.repo);
    });

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es'), Locale('en')],
      home: RouteEditorScreen(
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

    expect(find.text('Circuito del Jarama'), findsAtLeastNWidgets(1));

    controller.dispose();
    await tester.runAsync(() => _shutdown(boot));
  });

  testWidgets('HistoryScreen shows the empty state with no sessions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _bootRepo(seed: false);
      settings = await AppSettingsController.load();
    });

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es'), Locale('en')],
      home: HistoryScreen(repository: boot.repo, settingsController: settings),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
    }

    expect(find.text('Aún no hay actividad'), findsOneWidget);

    await tester.runAsync(() => _shutdown(boot));
  });
}
