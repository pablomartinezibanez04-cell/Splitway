import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mbx;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/data/demo/demo_seed.dart';
import 'src/data/local/splitway_local_database.dart';
import 'src/data/repositories/local_draft_repository.dart';
import 'src/services/locale/locale_controller.dart';
import 'src/services/settings/app_settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Pre-load date formatting symbols for every supported locale so
  // Formatters.dateTime works regardless of which locale the user picks.
  await initializeDateFormatting('es_ES');
  await initializeDateFormatting('en_US');

  final config = await AppConfig.load();
  if (config.hasMapbox) {
    mbx.MapboxOptions.setAccessToken(config.mapboxToken!);
  }

  if (config.hasSupabase) {
    await Supabase.initialize(
      url: config.supabaseUrl!,
      anonKey: config.supabaseAnonKey!,
    );
  }

  final database = await SplitwayLocalDatabase.open();
  final seedRepo = LocalDraftRepository(database);
  await DemoSeed.ensureSeeded(seedRepo);
  await seedRepo.dispose();

  final deviceLocale =
      WidgetsBinding.instance.platformDispatcher.locale;
  final localeController =
      await LocaleController.load(deviceLocale: deviceLocale);
  final settingsController = await AppSettingsController.load();

  runApp(SplitwayApp(
    config: config,
    database: database,
    localeController: localeController,
    settingsController: settingsController,
  ));
}
