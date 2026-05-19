import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/auth/auth_service.dart';
import '../../services/profile/profile_service.dart';
import '../../services/sync/sync_service.dart';
import '../../shared/widgets/app_drawer.dart';
import '../auth/login_screen.dart';

/// Shell widget that wraps the three main tabs with a NavigationBar and
/// an optional dark-minimal Drawer (when Supabase auth is configured).
///
/// Inner screens access the drawer via [Scaffold.of(context).openDrawer()]
/// using their build context (which is *above* their own returned Scaffold,
/// so it finds this one).
class HomeShell extends StatelessWidget {
  const HomeShell({
    super.key,
    required this.shell,
    this.authService,
    this.syncService,
    this.profileService,
  });

  final StatefulNavigationShell shell;
  final AuthService? authService;
  final SyncService? syncService;
  final ProfileService? profileService;

  @override
  Widget build(BuildContext context) {
    if (authService == null) return _buildScaffold(context);

    final listenable = profileService != null
        ? Listenable.merge([authService!, profileService!])
        : authService!;

    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      drawer: authService != null
          ? AppDrawer(
              authService: authService!,
              syncService: syncService,
              profileService: profileService,
              onLoginTap: () {
                Navigator.pop(context); // close drawer
                _navigateToLogin(context);
              },
            )
          : null,
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(
          i,
          initialLocation: i == shell.currentIndex,
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
            selectedIcon: const Icon(Icons.history_toggle_off),
            label: AppLocalizations.of(context).navHistory,
          ),
        ],
      ),
    );
  }

  void _navigateToLogin(BuildContext context) {
    if (authService == null) return;
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LoginScreen(authService: authService!),
      ),
    );
  }
}

/// Builds the leading widget for an inner screen's AppBar.
///
/// Shows a circular avatar with initials when logged in, or a hamburger
/// icon when not. Tapping opens the HomeShell's drawer.
///
/// **Important**: [context] must be the State's build context (above the
/// inner Scaffold), not a context from within the AppBar.
Widget? buildDrawerLeading(
  BuildContext context,
  AuthService? authService,
  ProfileService? profileService,
) {
  if (authService == null) return null;

  final user = authService.currentUser;
  final isLoggedIn = user != null;
  final avatarUrl = profileService?.profile?.avatarUrl;

  return IconButton(
    tooltip: AppLocalizations.of(context).drawerMenu,
    icon: isLoggedIn
        ? CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF1565C0),
            backgroundImage:
                avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(
                    _userInitials(user),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          )
        : const Icon(Icons.menu),
    onPressed: () => Scaffold.of(context).openDrawer(),
  );
}

String _userInitials(dynamic user) {
  final name =
      (user.userMetadata?['full_name'] as String?) ?? user.email ?? '?';
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
}
