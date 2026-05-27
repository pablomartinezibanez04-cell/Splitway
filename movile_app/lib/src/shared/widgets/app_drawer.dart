import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/auth/auth_service.dart';
import '../../services/profile/profile_service.dart';
import '../../services/sync/sync_service.dart';

/// Dark-minimal drawer for Splitway.
///
/// When the user is logged in it shows avatar + name + sync status + menu.
/// When not logged in it shows a prominent "Iniciar sesión" button.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.authService,
    this.syncService,
    this.profileService,
    required this.onLoginTap,
  });

  final AuthService authService;
  final SyncService? syncService;
  final ProfileService? profileService;
  final VoidCallback onLoginTap;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0D1B2A),
      child: SafeArea(
        child: authService.isLoggedIn
            ? _LoggedInContent(
                authService: authService,
                syncService: syncService,
                profileService: profileService,
              )
            : _LoggedOutContent(onLoginTap: onLoginTap),
      ),
    );
  }
}

// =============================================================================
// Logged-in drawer
// =============================================================================

class _LoggedInContent extends StatelessWidget {
  const _LoggedInContent({
    required this.authService,
    this.syncService,
    this.profileService,
  });

  final AuthService authService;
  final SyncService? syncService;
  final ProfileService? profileService;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final user = authService.currentUser!;
    final initials = _initials(user);
    final profile = profileService?.profile;
    final displayName = profile?.nickname ??
        user.userMetadata?['full_name'] as String? ??
        user.email ??
        l.drawerDefaultUser;
    final email = user.email ?? '';

    return Column(
      children: [
        // ---- Header: avatar + name ----
        Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0x14FFFFFF)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: profile?.avatarUrl == null
                      ? const LinearGradient(
                          colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  shape: BoxShape.circle,
                  image: profile?.avatarUrl != null
                      ? DecorationImage(
                          image: NetworkImage(profile!.avatarUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: profile?.avatarUrl == null
                    ? Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Color(0xFFE0E0E0),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: const TextStyle(
                          color: Color(0xFF607D8B),
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ---- Sync section ----
        if (syncService != null)
          ListenableBuilder(
            listenable: syncService!,
            builder: (context, _) => _SyncSection(syncService: syncService!),
          ),

        // ---- Divider ----
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Divider(color: Color(0x0FFFFFFF), height: 1),
        ),

        // ---- Menu items ----
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            children: [
              _MenuItem(
                icon: Icons.person_outline,
                label: l.drawerProfile,
                onTap: () {
                  Navigator.pop(context);
                  context.push('/profile');
                },
              ),
              _MenuItem(
                icon: Icons.garage_outlined,
                label: l.navGarage,
                onTap: () {
                  Navigator.pop(context);
                  context.push('/garage');
                },
              ),
              _MenuItem(
                icon: Icons.speed_outlined,
                label: l.drawerSpeed,
                onTap: () {
                  Navigator.pop(context);
                  context.push('/speed');
                },
              ),
              _MenuItem(
                icon: Icons.settings_outlined,
                label: l.drawerSettings,
                onTap: () {
                  Navigator.pop(context);
                  context.push('/settings');
                },
              ),
              _MenuItem(
                icon: Icons.bar_chart_outlined,
                label: l.drawerStats,
                onTap: () {
                  Navigator.pop(context);
                  context.push('/stats');
                },
              ),
              _MenuItem(
                icon: Icons.help_outline,
                label: l.drawerHelp,
                onTap: () {
                  Navigator.pop(context);
                  // TODO: navigate to help
                },
              ),
            ],
          ),
        ),

        // ---- Footer ----
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0x0FFFFFFF)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l.drawerAppVersion('0.4.0'),
                style: const TextStyle(color: Color(0xFF455A64), fontSize: 10),
              ),
              GestureDetector(
                onTap: () async {
                  Navigator.pop(context);
                  await authService.signOut();
                },
                child: Text(
                  l.drawerSignOut,
                  style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _initials(user) {
    final name = (user.userMetadata?['full_name'] as String?) ??
        user.email ??
        '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }
}

// =============================================================================
// Sync section inside drawer
// =============================================================================

class _SyncSection extends StatelessWidget {
  const _SyncSection({required this.syncService});

  final SyncService syncService;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = syncService.status;
    final (dotColor, label) = switch (status) {
      SyncStatus.idle => (const Color(0xFF4CAF50), _idleLabel(l)),
      SyncStatus.syncing => (const Color(0xFF42A5F5), l.drawerSyncSyncing),
      SyncStatus.error => (const Color(0xFFEF5350), l.drawerSyncError),
      SyncStatus.success => (const Color(0xFF4CAF50), _idleLabel(l)),
      SyncStatus.offline => (const Color(0xFFFF9800), l.drawerSyncOffline),
    };

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF78909C),
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: status == SyncStatus.syncing
                      ? null
                      : () => syncService.sync(),
                  child: Center(
                    child: status == SyncStatus.syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('↻',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 14)),
                              const SizedBox(width: 6),
                              Text(
                                l.drawerSyncNow,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _idleLabel(AppLocalizations l) {
    final last = syncService.lastSyncedAt;
    if (last == null) return l.drawerSyncSynced;
    final diff = DateTime.now().difference(last);
    if (diff.inMinutes < 1) return l.drawerSyncSyncedNow;
    if (diff.inMinutes < 60) return l.drawerSyncSyncedMinutes(diff.inMinutes);
    final time =
        '${last.hour}:${last.minute.toString().padLeft(2, '0')}';
    return l.drawerSyncSyncedAt(time);
  }
}

// =============================================================================
// Logged-out drawer
// =============================================================================

class _LoggedOutContent extends StatelessWidget {
  const _LoggedOutContent({required this.onLoginTap});

  final VoidCallback onLoginTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        // ---- Login prompt ----
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: onLoginTap,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                l.drawerSignIn,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),

        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Divider(color: Color(0x0FFFFFFF), height: 1),
        ),

        // ---- Menu (reduced) ----
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            children: [
              _MenuItem(
                icon: Icons.settings_outlined,
                label: l.drawerSettings,
                onTap: () {
                  Navigator.pop(context);
                  context.push('/settings');
                },
              ),
              _MenuItem(
                icon: Icons.help_outline,
                label: l.drawerHelp,
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),

        // ---- Footer ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l.drawerAppVersion('0.4.0'),
              style: const TextStyle(color: Color(0xFF455A64), fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Shared menu item
// =============================================================================

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xB3B0BEC5)),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFB0BEC5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
