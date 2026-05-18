import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import '../data/repositories/local_draft_repository.dart';
import '../features/auth/login_screen.dart';
import '../features/editor/route_editor_controller.dart';
import '../features/editor/route_editor_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_shell.dart';
import '../features/session/live_session_controller.dart';
import '../features/session/live_session_screen.dart';
import '../features/settings/settings_screen.dart';
import '../services/auth/auth_service.dart';
import '../services/locale/locale_controller.dart';
import '../services/geocoding/reverse_geocoding_service.dart';
import '../services/routing/routing_service.dart';
import '../services/sync/sync_service.dart';

class AppRouter {
  AppRouter({
    required this.repository,
    required this.config,
    required this.localeController,
    this.authService,
    this.syncService,
  })  : _editorController = RouteEditorController(
          repository,
          routingService: config.hasMapbox
              ? RoutingService(mapboxToken: config.mapboxToken!)
              : null,
          geocodingService: config.hasMapbox
              ? ReverseGeocodingService(accessToken: config.mapboxToken!)
              : null,
        ),
        _sessionController = LiveSessionController(repository);

  final LocalDraftRepository repository;
  final AppConfig config;
  final LocaleController localeController;
  final AuthService? authService;

  /// Mutable so [SplitwayApp] can attach/detach after login/logout.
  SyncService? syncService;

  final RouteEditorController _editorController;
  final LiveSessionController _sessionController;

  late final GoRouter router = GoRouter(
    initialLocation: '/editor',
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
        builder: (_, __) => SettingsScreen(localeController: localeController),
      ),

      // Main tabbed shell.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(
          shell: shell,
          authService: authService,
          syncService: syncService,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/editor',
                builder: (_, __) => RouteEditorScreen(
                  controller: _editorController,
                  config: config,
                  authService: authService,
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
