import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'data/local/splitway_local_database.dart';
import 'data/repositories/local_draft_repository.dart';
import 'data/repositories/supabase_repository.dart';
import 'data/services/route_thumbnail_service.dart';
import 'routing/app_router.dart';
import 'services/auth/auth_service.dart';
import 'services/locale/locale_controller.dart';
import 'services/settings/app_settings_controller.dart';
import 'data/repositories/garage_repository.dart';
import 'data/repositories/profile_repository.dart';
import 'services/garage/garage_service.dart';
import 'services/profile/profile_service.dart';
import 'services/sync/sync_service.dart';

class SplitwayApp extends StatefulWidget {
  const SplitwayApp({
    super.key,
    required this.config,
    required this.database,
    required this.localeController,
    required this.settingsController,
  });

  final AppConfig config;
  final SplitwayLocalDatabase database;
  final LocaleController localeController;
  final AppSettingsController settingsController;

  @override
  State<SplitwayApp> createState() => _SplitwayAppState();
}

class _SplitwayAppState extends State<SplitwayApp> {
  late final LocalDraftRepository _repository;
  late final AppRouter _router;
  AuthService? _authService;
  SyncService? _syncService;
  ProfileService? _profileService;
  GarageService? _garageService;

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
        _createProfileService(client, updateRouter: false);
      }
    }

    _router = AppRouter(
      repository: _repository,
      config: widget.config,
      authService: _authService,
      syncService: _syncService,
      profileService: _profileService,
      garageService: _garageService,
      localeController: widget.localeController,
      settingsController: widget.settingsController,
    );
  }

  void _onAuthStateChanged() {
    final isLoggedIn = _authService?.isLoggedIn ?? false;

    if (isLoggedIn && _syncService == null && widget.config.hasSupabase) {
      _repository.userId = Supabase.instance.client.auth.currentUser?.id;
      _createSyncService(Supabase.instance.client);
      _router.syncService = _syncService;
      if (_profileService == null && widget.config.hasSupabase) {
        _createProfileService(Supabase.instance.client);
      }
    } else if (!isLoggedIn && _syncService != null) {
      _syncService!.stopPeriodicSync();
      _syncService!.dispose();
      _syncService = null;
      _router.syncService = null;
      _profileService?.clear();
      _profileService?.dispose();
      _profileService = null;
      _router.profileService = null;
      _garageService?.clear();
      _garageService?.dispose();
      _garageService = null;
      _router.garageService = null;
      _repository.userId = null;
    }
  }

  void _createSyncService(SupabaseClient client) {
    RouteThumbnailService? thumbnailService;
    if (widget.config.hasMapbox) {
      thumbnailService = RouteThumbnailService(
        supabase: client,
        mapboxToken: widget.config.mapboxToken!,
      );
    }

    _syncService = SyncService(
      local: _repository,
      remote: SupabaseRepository(client, thumbnailService: thumbnailService),
    );
    _syncService!.startPeriodicSync();
  }

  void _createProfileService(SupabaseClient client, {bool updateRouter = true}) {
    final repo = ProfileRepository(client);
    _profileService = ProfileService(repo);
    if (updateRouter) _router.profileService = _profileService;

    final user = client.auth.currentUser;
    final nickname = user?.userMetadata?['nickname'] as String? ??
        user?.userMetadata?['full_name'] as String? ??
        user?.email?.split('@').first ??
        'User';
    final dobStr = user?.userMetadata?['date_of_birth'] as String?;
    final dateOfBirth = dobStr != null ? DateTime.tryParse(dobStr) : null;
    _profileService!.ensureProfile(
      fallbackNickname: nickname,
      dateOfBirth: dateOfBirth,
    );

    final garageRepo = GarageRepository(client);
    _garageService = GarageService(garageRepo);
    if (updateRouter) _router.garageService = _garageService;
    _garageService!.loadVehicles();
  }

  @override
  void dispose() {
    _authService?.removeListener(_onAuthStateChanged);
    _authService?.dispose();
    _syncService?.dispose();
    _profileService?.dispose();
    _garageService?.dispose();
    _router.dispose();
    _repository.dispose();
    widget.database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.localeController,
        widget.settingsController,
      ]),
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
        themeMode: widget.settingsController.flutterThemeMode,
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
