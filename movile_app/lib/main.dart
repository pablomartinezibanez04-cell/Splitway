import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'src/services/logging/app_logger.dart';
import 'src/services/logging/device_metadata.dart';
import 'src/services/logging/log_uploader.dart';
import 'src/services/logging/network_error.dart';
import 'src/services/logging/sinks/console_sink.dart';
import 'src/services/logging/sinks/local_sink.dart';
import 'src/services/logging/sinks/log_sink.dart';
import 'src/services/logging/sinks/remote_sink.dart';
import 'src/services/routing/elevation_service.dart';
import 'src/services/settings/app_settings_controller.dart';
import 'src/services/tracking/background_tracking_service.dart';

bool _supabaseInitialized = false;

Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Pre-load date formatting symbols for every supported locale.
    await initializeDateFormatting('es_ES');
    await initializeDateFormatting('en_US');

    BackgroundTrackingService.init();

    final database = await SplitwayLocalDatabase.open();
    final settingsController = await AppSettingsController.load();
    final metadata = await DeviceMetadata.capture();

    // Logger must come BEFORE Supabase/Mapbox init so we capture their errors.
    final localSink = LocalSink(database);
    final sinks = <LogSink>[const ConsoleSink(), localSink];

    AppLogger.install(
      sinks: sinks,
      metadata: metadata,
      minLevel: () => settingsController.minLogLevel,
      userId: () => _supabaseInitialized
          ? Supabase.instance.client.auth.currentUser?.id
          : null,
    );

    FlutterError.onError = (details) {
      AppLogger.instance.error(
        'flutter',
        details.exceptionAsString(),
        error: details.exception,
        stackTrace: details.stack,
        context: {'library': details.library},
      );
      if (!kReleaseMode) FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      AppLogger.instance.error('dart', error.toString(),
          error: error, stackTrace: stack);
      return true;
    };

    final config = await AppConfig.load();
    if (config.hasMapbox) {
      mbx.MapboxOptions.setAccessToken(config.mapboxToken!);
    }

    if (config.hasSupabase) {
      try {
        await Supabase.initialize(
          url: config.supabaseUrl!,
          anonKey: config.supabaseAnonKey!,
        );
        _supabaseInitialized = true;
      } catch (e, st) {
        await AppLogger.instance.error('supabase', 'Supabase.initialize failed',
            error: e, stackTrace: st);
      }
    }

    // Wire the remote uploader now that Supabase has had a chance to init.
    final uploader = LogUploader(
      sink: localSink,
      upload: (batch) async {
        if (!_supabaseInitialized) {
          throw StateError('Supabase not initialized');
        }
        await Supabase.instance.client.from('app_logs').insert(
              batch.map((e) => e.toRemoteJson()).toList(),
            );
      },
      enabled: () => settingsController.remoteLogsEnabled,
    );
    sinks.add(RemoteSink(uploader));
    AppLogger.attachUiHandles(sink: localSink, uploader: uploader);
    // Initial drain in case there are leftovers from a previous run.
    unawaited(uploader.drain());

    final seedRepo = LocalDraftRepository(database);
    await DemoSeed.ensureSeeded(
      seedRepo,
      settingsController,
      elevationService: ElevationService(),
    );
    await seedRepo.dispose();

    final deviceLocale =
        WidgetsBinding.instance.platformDispatcher.locale;
    final localeController =
        await LocaleController.load(deviceLocale: deviceLocale);

    runApp(SplitwayApp(
      config: config,
      database: database,
      localeController: localeController,
      settingsController: settingsController,
    ));
  }, (error, stack) {
    final logger = AppLogger.maybeInstance;
    if (logger == null) {
      debugPrint('Uncaught zone error before logger init: $error\n$stack');
      return;
    }
    // Transport failures (DNS, socket, retryable auth refresh) bubble here on
    // every background timer tick when offline. Downgrade them to a warning
    // under a dedicated `network` tag so they don't flood the error stream.
    if (isTransportError(error)) {
      logger.warning('network', error.toString(),
          error: error, stackTrace: stack);
    } else {
      logger.error('zone', error.toString(), error: error, stackTrace: stack);
    }
  });
}
