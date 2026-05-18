import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'data/local/splitway_local_database.dart';
import 'data/repositories/local_draft_repository.dart';
import 'data/repositories/supabase_repository.dart';
import 'routing/app_router.dart';
import 'services/auth/auth_service.dart';
import 'services/locale/locale_controller.dart';
import 'services/sync/sync_service.dart';

class SplitwayApp extends StatefulWidget {
  const SplitwayApp({
    super.key,
    required this.config,
    required this.database,
    required this.localeController,
  });

  final AppConfig config;
  final SplitwayLocalDatabase database;
  final LocaleController localeController;

  @override
  State<SplitwayApp> createState() => _SplitwayAppState();
}

class _SplitwayAppState extends State<SplitwayApp> {
  late final LocalDraftRepository _repository;
  late final AppRouter _router;
  AuthService? _authService;
  SyncService? _syncService;

  @override
  void initState() {
    super.initState();
    _repository = LocalDraftRepository(widget.database);

    if (widget.config.hasSupabase) {
      final client = Supabase.instance.client;
      _authService = AuthService(client: client);
      _authService!.addListener(_onAuthStateChanged);
      if (client.auth.currentUser != null) {
        _repository.userId = client.auth.currentUser!.id;
        _createSyncService(client);
      }
    }

    _router = AppRouter(
      repository: _repository,
      config: widget.config,
      authService: _authService,
      syncService: _syncService,
      localeController: widget.localeController,
    );
  }

  void _onAuthStateChanged() {
    final isLoggedIn = _authService?.isLoggedIn ?? false;

    if (isLoggedIn && _syncService == null && widget.config.hasSupabase) {
      _repository.userId = Supabase.instance.client.auth.currentUser?.id;
      _createSyncService(Supabase.instance.client);
      _router.syncService = _syncService;
    } else if (!isLoggedIn && _syncService != null) {
      _syncService!.stopPeriodicSync();
      _syncService!.dispose();
      _syncService = null;
      _router.syncService = null;
      _repository.userId = null;
    }
  }

  void _createSyncService(SupabaseClient client) {
    _syncService = SyncService(
      local: _repository,
      remote: SupabaseRepository(client),
    );
    _syncService!.startPeriodicSync();
  }

  @override
  void dispose() {
    _authService?.removeListener(_onAuthStateChanged);
    _authService?.dispose();
    _syncService?.dispose();
    _router.dispose();
    _repository.dispose();
    widget.database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.localeController,
      builder: (context, _) => MaterialApp.router(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        locale: widget.localeController.locale,
        supportedLocales: LocaleController.supported,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1565C0),
            brightness: Brightness.dark,
          ),
        ),
        routerConfig: _router.router,
      ),
    );
  }
}
