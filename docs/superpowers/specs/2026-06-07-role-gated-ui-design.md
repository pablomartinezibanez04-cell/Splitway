# Role-gated UI for logs and telemetry source

## Goal

Hide admin-only UI from regular users in the mobile app. Specifically:

- **In-app log viewer** (Settings → Diagnostics → "Logs en la aplicación"): only `admin` / `superadmin` see the entry.
- **Telemetry source selector** (Live Session "ready" screen → "Fuente de telemetría"): only `admin` / `superadmin` see the segmented button; regular users go straight to real GPS.

Regular users still see the "Enviar logs al servidor" switch in Diagnostics — that capability is not admin-gated.

## Non-goals

- No new RLS, migrations, or RPCs. The `profiles.role` column and existing self-select policy already give the mobile client what it needs.
- No generic permission framework. Two gated surfaces only.
- No JWT custom claims or session-refresh logic.
- No persistent cache of `isAdmin`. The role is held in memory for the lifetime of the signed-in session.

## Source of truth

`public.profiles.role` (text, one of `user` / `admin` / `superadmin`, default `user`). Already enforced by the check constraint in `supabase/migrations/20260528000000_add_admin_role.sql`. Anonymous (signed-out) users are treated as `user`.

## Mobile model changes

### `UserRole` enum

New file `movile_app/lib/src/services/profile/user_role.dart`:

```dart
enum UserRole {
  user,
  admin,
  superadmin;

  bool get isAdmin => this == admin || this == superadmin;

  static UserRole fromString(String? value) => switch (value) {
        'admin' => admin,
        'superadmin' => superadmin,
        _ => user,
      };
}
```

Unknown / null / `'user'` all map to `UserRole.user` — the gate fails closed.

### `UserProfile`

Add a `role` field:

- Constructor gains `this.role = UserRole.user`.
- `fromJson` reads `UserRole.fromString(json['role'] as String?)`.
- `copyWith` accepts an optional `UserRole? role`.

### `ProfileService`

Expose:

```dart
bool get isAdmin => _profile?.role.isAdmin ?? false;
```

No new methods; the existing `loadProfile()` / `clear()` already cover the lifecycle. `notifyListeners` continues to fire on load/clear, so any `ListenableBuilder` keyed on the service rebuilds when the role becomes known or is cleared.

## UI gating

### Settings → Diagnostics

File: `movile_app/lib/src/features/settings/settings_screen.dart`.

- Add `final ProfileService? profileService;` to the constructor.
- Wrap the existing `Listenable.merge([localeController, settingsController])` in a `Listenable.merge` that also includes `profileService` when non-null, so the gated tile rebuilds on sign-in / sign-out / profile reload.
- The `_SectionHeader(l.settingsDiagnosticsSection)` and `SwitchListTile(remoteLogsEnabled)` remain visible to everyone.
- The `ListTile` whose `onTap: () => context.push('/settings/logs')` is rendered only when `profileService?.isAdmin == true`.

### Live Session → ready state

File: `movile_app/lib/src/features/session/live_session_screen.dart`.

- Add `final ProfileService? profileService;` to the widget.
- In `_buildReady`, wrap the `Text(l.sessionTelemetrySource, ...)`, the `SizedBox(height: 8)` before it, and the `SegmentedButton<TrackingSource>` in `if (widget.profileService?.isAdmin == true) ...[ ... ]`. The trailing `SizedBox(height: 16)` after the map stays as the visual separator before the next section.
- The `_PermissionBanner` block stays — non-admins also need to see permission state. (It only renders when `ctrl.permissionStatus != null`, which only happens on the real-GPS path, which is now the only path non-admins use.)
- Non-admin default source: `LiveSessionController._source` defaults to `TrackingSource.simulated` (controller line 39). The selector is the only way to flip it, so non-admins would otherwise be stuck on simulated. Fix it in the screen, not the controller: on first build, when `widget.profileService?.isAdmin != true` and `ctrl.source == TrackingSource.simulated`, schedule a post-frame `ctrl.setSource(TrackingSource.realGps)` once (guarded by a `bool _forcedRealGps` flag in the State). `setSource(realGps)` already triggers permission resolution and the existing `_PermissionBanner` surfaces the result — no extra wiring.
- Why not change the controller default: tests and the admin path rely on `simulated` being the cheap, permissionless default. Forcing real GPS at construction time would change side effects for every caller. Gating it in the screen keeps the controller's behavior untouched.

### `/settings/logs` — defense in depth

File: `movile_app/lib/src/features/logs/logs_screen.dart`.

A user could reach `/settings/logs` via deep link or via a stale build where the tile was visible at the moment of tap but the role changed since. In the screen's `initState` (or first build after the profile is loaded):

- If `profileService?.isAdmin != true`, schedule a post-frame `context.go('/settings')` and render an `EmptyState` placeholder in the meantime.
- If the profile is still loading (`profileService.loading == true` and `profileService.profile == null`), show a `CircularProgressIndicator` and wait for the next rebuild rather than redirecting.

This is intentionally conservative: the primary gate is hiding the entry; this only catches the redirect edge case.

## Wiring

Wherever `SettingsScreen`, `LiveSessionScreen`, and `LogsScreen` are constructed (typically the GoRouter route table in app composition), pass the existing `ProfileService` instance. No new providers or DI plumbing.

## Tests

Add or extend:

- `test/services/profile/user_profile_test.dart` — `UserProfile.fromJson` parses `role` for `'user'`, `'admin'`, `'superadmin'`, `null`, and an unknown string (all unknown / null map to `UserRole.user`).
- `test/features/settings/settings_screen_test.dart` —
  - With `profile.role == UserRole.user`: the "Logs en la aplicación" tile is absent, the remote-logs switch is present.
  - With `UserRole.admin` and `UserRole.superadmin`: the tile is present.
  - With `profileService == null`: tile is absent (matches signed-out behavior).
- `test/features/session/live_session_screen_l10n_test.dart` (or a new widget test) —
  - `UserRole.user`: `sessionTelemetrySource` label is not in the tree.
  - `UserRole.admin`: the label and the segmented button are in the tree.
- `test/features/logs/logs_screen_test.dart` (new, if it doesn't exist) — non-admin viewer redirects; admin renders normally.

## Out of scope (deliberately)

- Hiding logs / telemetry source on the web admin panel — already gated by `requireAdmin`.
- Caching role across cold starts — would add a stale-permission window with no clear benefit; sign-in re-fetches in seconds.
- Audit logging of admin UI usage — no requirement.
