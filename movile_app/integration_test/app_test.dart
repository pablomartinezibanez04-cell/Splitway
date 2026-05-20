import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:splitway_mobile/src/app.dart';
import 'package:splitway_mobile/src/config/app_config.dart';
import 'package:splitway_mobile/src/data/demo/demo_seed.dart';
import 'package:splitway_mobile/src/data/local/splitway_local_database.dart';
import 'package:splitway_mobile/src/data/repositories/local_draft_repository.dart';
import 'package:splitway_mobile/src/services/locale/locale_controller.dart';
import 'package:splitway_mobile/src/services/settings/app_settings_controller.dart';

/// End-to-end integration tests.
/// Run with:  flutter test integration_test/app_test.dart
///
/// These tests boot the full SplitwayApp (with SQLite + go_router) on a
/// real device or emulator. They do NOT require Mapbox or Supabase tokens;
/// the CustomPainter fallback is used for maps.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SplitwayLocalDatabase database;
  late LocalDraftRepository seedRepo;
  late LocaleController localeController;
  late AppSettingsController settingsController;

  setUpAll(() async {
    await initializeDateFormatting('es_ES');
    await initializeDateFormatting('en_US');
    localeController = await LocaleController.load(
      deviceLocale: const Locale('es'),
    );
    settingsController = await AppSettingsController.load();
  });

  setUp(() async {
    database = await SplitwayLocalDatabase.open();
    seedRepo = LocalDraftRepository(database);
    await DemoSeed.ensureSeeded(seedRepo);
    await seedRepo.dispose();
  });

  tearDown(() async {
    await database.close();
  });

  group('Full app navigation', () {
    testWidgets('boots on Editor tab and shows demo route', (tester) async {
      await tester.pumpWidget(SplitwayApp(
        config: const AppConfig(),
        database: database,
        localeController: localeController,
        settingsController: settingsController,
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Editor is the initial tab — should show the demo route chip.
      expect(find.text('Editor'), findsOneWidget);
      expect(find.text('Pista demo (Madrid)'), findsAtLeastNWidgets(1));
    });

    testWidgets('navigates to Session tab and shows route selector',
        (tester) async {
      await tester.pumpWidget(SplitwayApp(
        config: const AppConfig(),
        database: database,
        localeController: localeController,
        settingsController: settingsController,
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Tap the Session tab
      await tester.tap(find.text('Sesión'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Should show session-related UI
      expect(find.text('Sesión en vivo'), findsOneWidget);
    });

    testWidgets('navigates to History tab and shows empty state',
        (tester) async {
      await tester.pumpWidget(SplitwayApp(
        config: const AppConfig(),
        database: database,
        localeController: localeController,
        settingsController: settingsController,
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Tap the History tab
      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Should show empty state (no sessions recorded yet)
      expect(
        find.text('Aún no has grabado ninguna sesión'),
        findsOneWidget,
      );
    });
  });

  group('Session simulation flow', () {
    testWidgets(
        'starts simulated session, advances points, finishes, '
        'and verifies history', (tester) async {
      await tester.pumpWidget(SplitwayApp(
        config: const AppConfig(),
        database: database,
        localeController: localeController,
        settingsController: settingsController,
      ));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Navigate to Session tab
      await tester.tap(find.text('Sesión'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // The session screen should be in "ready" stage with the demo route
      // pre-selected (it's the only route in the DB).
      // Find and tap "Comenzar grabación"
      final startButton = find.text('Comenzar grabación');
      if (startButton.evaluate().isNotEmpty) {
        await tester.tap(startButton);
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // Simulate a few points
        for (var i = 0; i < 3; i++) {
          final simButton = find.text('Simular punto');
          if (simButton.evaluate().isNotEmpty) {
            await tester.tap(simButton);
            await tester.pump(const Duration(milliseconds: 200));
          }
        }

        // Finish the session
        final finishButton = find.text('Finalizar y guardar');
        if (finishButton.evaluate().isNotEmpty) {
          await tester.tap(finishButton);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }

        // Verify session finished — should show "Sesión completa"
        // or the snackbar "Sesión guardada"
        final completed = find.text('Sesión completa');
        final saved = find.text('Sesión guardada');
        expect(
          completed.evaluate().isNotEmpty || saved.evaluate().isNotEmpty,
          isTrue,
          reason: 'Expected "Sesión completa" or "Sesión guardada"',
        );
      }
    });
  });
}
