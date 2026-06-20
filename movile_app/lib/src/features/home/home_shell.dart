import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/auth/auth_service.dart';
import '../../services/profile/profile_service.dart';
import '../../services/settings/app_settings_controller.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/widgets/app_drawer.dart';
import '../auth/login_screen.dart';
import '../editor/route_editor_controller.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.shell,
    required this.settingsController,
    this.authService,
    this.syncService,
    this.profileService,
    this.routeEditorController,
  });

  final StatefulNavigationShell shell;
  final AppSettingsController settingsController;
  final AuthService? authService;
  final SyncService? syncService;
  final ProfileService? profileService;

  /// Used to hide the bottom navigation bar while a route is being drawn,
  /// so the user can only leave the drawing screen via its own close button.
  final RouteEditorController? routeEditorController;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAskNotificationPermission();
    });
  }

  Future<void> _maybeAskNotificationPermission() async {
    if (widget.settingsController.notificationPermissionAsked) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final status = await Permission.notification.status;
    if (status.isGranted) {
      await widget.settingsController.markNotificationPermissionAsked();
      return;
    }

    if (!mounted) return;
    await _showNotificationDialog(context);
    await widget.settingsController.markNotificationPermissionAsked();
  }

  Future<void> _showNotificationDialog(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final allow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_outlined, size: 32),
        title: Text(l.notificationDialogTitle),
        content: Text(l.notificationDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.notificationDialogSkip),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.notificationDialogAllow),
          ),
        ],
      ),
    );

    if (allow == true) {
      await Permission.notification.request();
    }
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[
      if (widget.authService != null) widget.authService!,
      if (widget.profileService != null) widget.profileService!,
      if (widget.routeEditorController != null) widget.routeEditorController!,
    ];
    if (listenables.isEmpty) return _buildScaffold(context);

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    // While drawing a route the bottom nav is hidden so the user can only
    // leave via the drawing screen's own close button.
    final drawing = widget.routeEditorController?.drawing ?? false;
    return Scaffold(
      // The drawer can only be opened via the hamburger button, not by
      // dragging from the left edge.
      drawerEnableOpenDragGesture: false,
      drawer: widget.authService != null
          ? AppDrawer(
              authService: widget.authService!,
              syncService: widget.syncService,
              profileService: widget.profileService,
              onLoginTap: () {
                Navigator.pop(context);
                _navigateToLogin(context);
              },
            )
          : null,
      body: widget.shell,
      bottomNavigationBar: drawing
          ? null
          : NavigationBar(
        selectedIndex: widget.shell.currentIndex,
        onDestinationSelected: (i) => widget.shell.goBranch(
          i,
          initialLocation: i == widget.shell.currentIndex,
        ),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.route_outlined),
            selectedIcon: const Icon(Icons.route),
            label: AppLocalizations.of(context).navRoutes,
          ),
          NavigationDestination(
            icon: const Icon(Icons.play_circle_outline),
            selectedIcon: const Icon(Icons.play_circle),
            label: AppLocalizations.of(context).navSession,
          ),
          NavigationDestination(
            icon: const Icon(Icons.explore_outlined),
            selectedIcon: const Icon(Icons.explore),
            label: AppLocalizations.of(context).navFreeRide,
          ),
          NavigationDestination(
            icon: const Icon(Icons.history),
            selectedIcon: const Icon(Icons.history),
            label: AppLocalizations.of(context).navHistory,
          ),
        ],
      ),
    );
  }

  void _navigateToLogin(BuildContext context) {
    if (widget.authService == null) return;
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LoginScreen(authService: widget.authService!),
      ),
    );
  }
}

/// Builds the leading widget for an inner screen's AppBar.
///
/// Always shows a hamburger icon that opens the HomeShell's drawer.
///
/// **Important**: [context] must be the State's build context (above the
/// inner Scaffold), not a context from within the AppBar.
Widget? buildDrawerLeading(
  BuildContext context,
  AuthService? authService,
  ProfileService? profileService,
) {
  if (authService == null) return null;

  return IconButton(
    tooltip: AppLocalizations.of(context).drawerMenu,
    icon: const Icon(Icons.menu),
    onPressed: () => Scaffold.of(context).openDrawer(),
  );
}
