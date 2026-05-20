import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import '../data/repositories/local_draft_repository.dart';
import '../features/auth/login_screen.dart';
import '../features/editor/route_editor_controller.dart';
import '../features/editor/route_editor_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_shell.dart';
import '../features/free_ride/free_ride_controller.dart';
import '../features/free_ride/free_ride_screen.dart';
import '../features/session/live_session_controller.dart';
import '../features/session/live_session_screen.dart';
import '../features/garage/garage_screen.dart';
import '../features/settings/settings_screen.dart';
import '../services/auth/auth_service.dart';
import '../services/garage/garage_service.dart';
import '../services/locale/locale_controller.dart';
import '../services/settings/app_settings_controller.dart';
import '../services/geocoding/reverse_geocoding_service.dart';
import '../services/routing/routing_service.dart';
import '../features/profile/profile_screen.dart';
import '../services/profile/profile_service.dart';
import '../services/sync/sync_service.dart';

class AppRouter {
  AppRouter({
    required this.repository,
    required this.config,
    required this.localeController,
    required this.settingsController,
    this.authService,
    SyncService? syncService,
    ProfileService? profileService,
    GarageService? garageService,
  })  : _editorController = RouteEditorController(
          repository,
          routingService: config.hasMapbox
              ? RoutingService(mapboxToken: config.mapboxToken!)
              : null,
          geocodingService: config.hasMapbox
              ? ReverseGeocodingService(accessToken: config.mapboxToken!)
              : null,
        ),
        _sessionController = LiveSessionController(repository),
        _freeRideController = FreeRideController(repository) {
    if (syncService != null) this.syncService = syncService;
    if (profileService != null) this.profileService = profileService;
    if (garageService != null) this.garageService = garageService;
  }

  final LocalDraftRepository repository;
  final AppConfig config;
  final LocaleController localeController;
  final AppSettingsController settingsController;
  final AuthService? authService;
  ProfileService? profileService;
  GarageService? garageService;
  late final RouteEditorController _editorController;
  late final LiveSessionController _sessionController;
  late final FreeRideController _freeRideController;

  SyncService? _syncService;

  /// Mutable so [SplitwayApp] can attach/detach after login/logout.
  /// Propagates to [_editorController] so route deletions also hit the remote.
  SyncService? get syncService => _syncService;
  set syncService(SyncService? value) {
    _syncService = value;
    _editorController.syncService = value;
  }

  late final GoRouter router = GoRouter(
    initialLocation: '/routes',
    routes: [
      // Login screen (outside the shell — no bottom nav).
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final redirect = state.uri.queryParameters['redirect'];
          final banner = state.uri.queryParameters['message'];
          return LoginScreen(
            authService: authService!,
            redirect: redirect,
            bannerMessage: banner,
          );
        },
      ),

      GoRoute(
        path: '/settings',
        builder: (_, __) => SettingsScreen(
          localeController: localeController,
          settingsController: settingsController,
          authService: authService,
          repository: repository,
        ),
      ),

      GoRoute(
        path: '/profile',
        builder: (_, __) => ProfileScreen(
          profileService: profileService!,
          authService: authService!,
        ),
      ),

      GoRoute(
        path: '/garage',
        builder: (_, __) => GarageScreen(
          garageService: garageService!,
          config: config,
          authService: authService,
          profileService: profileService,
        ),
      ),

      // Main tabbed shell.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(
          shell: shell,
          authService: authService,
          syncService: syncService,
          profileService: profileService,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/routes',
                builder: (_, __) => RouteEditorScreen(
                  controller: _editorController,
                  config: config,
                  authService: authService,
                  profileService: profileService,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/session',
                builder: (_, __) => LiveSessionScreen(
                  controller: _sessionController,
                  config: config,
                  authService: authService,
                  profileService: profileService,
                  garageService: garageService,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/free-ride',
                builder: (_, __) => FreeRideScreen(
                  controller: _freeRideController,
                  config: config,
                  authService: authService,
                  profileService: profileService,
                  garageService: garageService,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (_, __) => HistoryScreen(
                  repository: repository,
                  config: config,
                  authService: authService,
                  profileService: profileService,
                  garageService: garageService,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  void dispose() {
    _editorController.dispose();
    _sessionController.dispose();
    _freeRideController.dispose();
  }
}

/// Helper to check auth and navigate to login if needed.
///
/// Returns `true` if the user is already logged in or successfully logged in
/// after being redirected, `false` if they skipped.
Future<bool> requireAuth(
  BuildContext context,
  AuthService? authService, {
  required String message,
}) async {
  if (authService == null || authService.isLoggedIn) return true;

  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => LoginScreen(
        authService: authService,
        bannerMessage: message,
      ),
    ),
  );
  return result == true;
}
