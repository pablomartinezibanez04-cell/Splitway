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
import 'package:splitway_mobile/src/shared/widgets/sector_chip.dart';

Widget _harness({required Locale locale, required Widget child}) => MaterialApp(
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

Future<({SplitwayLocalDatabase db, LocalDraftRepository repo})> _openRepo() async {
  _dbCounter += 1;
  final db = await SplitwayLocalDatabase.open(
    overridePath:
        'file:session_detail_test_$_dbCounter?mode=memory&cache=shared',
  );
  return (db: db, repo: LocalDraftRepository(db));
}

GateDefinition _gate() => const GateDefinition(
      left: GeoPoint(latitude: 40.0, longitude: -3.0),
      right: GeoPoint(latitude: 40.001, longitude: -3.0),
    );

RouteTemplate _route() => RouteTemplate(
      id: 'route-x',
      name: 'Circuito X',
      path: const [
        GeoPoint(latitude: 40.0, longitude: -3.0),
        GeoPoint(latitude: 40.001, longitude: -3.0),
      ],
      startFinishGate: _gate(),
      sectors: [
        SectorDefinition(id: 'sec-1', order: 0, label: 'Sector 1', gate: _gate()),
        SectorDefinition(id: 'sec-2', order: 1, label: 'Sector 2', gate: _gate()),
      ],
      difficulty: RouteDifficulty.medium,
      createdAt: DateTime(2024, 1, 1),
    );

SessionRun _session() {
  final lap1Start = DateTime(2024, 6, 1, 10, 0, 0);
  final lap1End = DateTime(2024, 6, 1, 10, 1, 20); // 80 s
  final lap2Start = lap1End;
  final lap2End = DateTime(2024, 6, 1, 10, 2, 38); // 78 s (best)
  return SessionRun(
    id: 'session-x',
    routeTemplateId: 'route-x',
    startedAt: lap1Start,
    endedAt: lap2End,
    status: SessionStatus.completed,
    points: [
      TelemetryPoint(
        timestamp: DateTime(2024, 6, 1, 10, 0, 40),
        location: const GeoPoint(latitude: 40.0005, longitude: -3.0),
        speedMps: 25,
      ),
      TelemetryPoint(
        timestamp: DateTime(2024, 6, 1, 10, 1, 50),
        location: const GeoPoint(latitude: 40.0005, longitude: -3.0),
        speedMps: 33,
      ),
    ],
    laps: [
      LapSummary(
        lapNumber: 1,
        duration: const Duration(seconds: 80),
        startedAt: lap1Start,
        endedAt: lap1End,
        distanceMeters: 1000,
        avgSpeedMps: 12.5,
      ),
      LapSummary(
        lapNumber: 2,
        duration: const Duration(seconds: 78),
        startedAt: lap2Start,
        endedAt: lap2End,
        distanceMeters: 1000,
        avgSpeedMps: 12.8,
      ),
    ],
    sectorSummaries: [
      SectorSummary(
        sectorId: 'sec-1',
        lapNumber: 1,
        duration: const Duration(seconds: 40),
        startedAt: lap1Start,
        endedAt: lap1Start.add(const Duration(seconds: 40)),
        distanceMeters: 500,
        avgSpeedMps: 12.5,
      ),
      SectorSummary(
        sectorId: 'sec-2',
        lapNumber: 1,
        duration: const Duration(seconds: 40),
        startedAt: lap1Start.add(const Duration(seconds: 40)),
        endedAt: lap1End,
        distanceMeters: 500,
        avgSpeedMps: 12.5,
      ),
      SectorSummary(
        sectorId: 'sec-1',
        lapNumber: 2,
        duration: const Duration(seconds: 38),
        startedAt: lap2Start,
        endedAt: lap2Start.add(const Duration(seconds: 38)),
        distanceMeters: 500,
        avgSpeedMps: 13.2,
      ),
      SectorSummary(
        sectorId: 'sec-2',
        lapNumber: 2,
        duration: const Duration(seconds: 40),
        startedAt: lap2Start.add(const Duration(seconds: 38)),
        endedAt: lap2End,
        distanceMeters: 500,
        avgSpeedMps: 12.5,
      ),
    ],
    totalDistanceMeters: 2000,
    maxSpeedMps: 33,
    avgSpeedMps: 12.6,
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
  }
}

/// Use a tall viewport so the whole (lazy) ListView is laid out and findable
/// without scrolling.
void _useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('defaults to best lap and shows colored sector chips',
      (tester) async {
    _useTallScreen(tester);
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _openRepo();
      boot.repo.userId = 'test-user';
      await boot.repo.saveRouteTemplate(_route());
      await boot.repo.saveSessionRun(_session());
      settings = await AppSettingsController.load();
    });

    await tester.pumpWidget(_harness(
      locale: const Locale('es'),
      child: SessionDetailScreen(
        sessionId: 'session-x',
        repository: boot.repo,
        settingsController: settings,
      ),
    ));
    await _settle(tester);

    // Best lap (lap 2, 78 s = 01:18.000) is selected by default.
    expect(find.text('01:18.000'), findsWidgets);
    // Two gates → three sector chips (S1, S2 and the implicit final S3).
    expect(find.text('S1'), findsOneWidget);
    expect(find.text('S2'), findsOneWidget);
    expect(find.text('S3'), findsOneWidget);

    // sec-1 in the best lap (38 s) is the all-time record -> purple chip.
    final s1Chip = tester.widget<SectorChip>(
      find.ancestor(of: find.text('S1'), matching: find.byType(SectorChip)),
    );
    expect(s1Chip.tier, SectorChipTier.overall);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });

  testWidgets('selecting another lap updates the displayed time',
      (tester) async {
    _useTallScreen(tester);
    late ({SplitwayLocalDatabase db, LocalDraftRepository repo}) boot;
    late AppSettingsController settings;
    await tester.runAsync(() async {
      boot = await _openRepo();
      boot.repo.userId = 'test-user';
      await boot.repo.saveRouteTemplate(_route());
      await boot.repo.saveSessionRun(_session());
      settings = await AppSettingsController.load();
    });

    await tester.pumpWidget(_harness(
      locale: const Locale('es'),
      child: SessionDetailScreen(
        sessionId: 'session-x',
        repository: boot.repo,
        settingsController: settings,
      ),
    ));
    await _settle(tester);

    // Open the lap dropdown and pick lap 1.
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vuelta 1').last);
    await tester.pumpAndSettle();

    // Lap 1 = 80 s = 01:20.000 now shown.
    expect(find.text('01:20.000'), findsWidgets);

    await tester.runAsync(() => boot.repo.dispose());
    await tester.runAsync(() => boot.db.close());
  });
}
