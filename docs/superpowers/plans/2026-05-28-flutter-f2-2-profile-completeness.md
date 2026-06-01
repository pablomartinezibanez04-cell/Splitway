# Flutter Profile Completeness — Phase F2.2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a successful sign-in (Google or email), force the user into a new `CompleteProfileScreen` until the profile has `nickname` + `date_of_birth` + a password set on `auth.users`. Match the exact same contract the admin panel enforces (spec §4). Also remove `ProfileService.ensureProfile(fallbackNickname:...)`'s silent auto-creation so Google users stop getting throw-away nicknames.

**Architecture:** Two new pieces of state on `ProfileService` — a nullable `isComplete` flag and a `refreshCompleteness()` async method that combines the existing profile fields with a call to the `user_has_password()` Postgres RPC (already shipped in F2.1). A new `completeProfile(nickname, dateOfBirth)` method upserts the profile row. A new `AuthService.setPassword()` wraps `updateUser({password})`. The router gains a `redirect` callback that returns `/complete-profile` whenever a logged-in user is incomplete, and a `refreshListenable` so the redirect re-runs whenever auth or profile state notifies.

**Tech Stack:** Existing Flutter app — Dart, `supabase_flutter`, `google_sign_in`, `go_router`, `Provider`-style ChangeNotifier. No new packages.

**Branch:** `feat/flutter-profile-onboarding` (already created from `main`).

**Out of scope for F2.2 (deferred):**
- Migrations / schema changes (everything lives in fields that already exist).
- Backfilling existing throw-away nicknames — enforcement is lazy and fires on next sign-in; users keep their current nickname pre-populated in the form.
- Changes to `signUpWithEmail` — the existing signup form already collects all three pieces correctly, so a brand-new email signup is already complete and skips onboarding.
- New auth providers (Apple, etc.).
- A skip button on the onboarding screen — the only escape is sign-out.

**Acceptance criteria (verified in Task 8, on a physical device or emulator):**
1. A signed-out user signs in via Google. If their profile is missing DOB or password (the common case for OAuth-only users), they land on a full-screen `CompleteProfileScreen` immediately after the Google flow returns; they cannot reach `HomeShell` until they submit the form.
2. The nickname field is pre-filled with the user's current `profiles.nickname` if one exists. The DOB field is pre-filled with `profiles.date_of_birth` if it exists. Password fields are always empty.
3. Submitting valid values (nickname ≥ 2 chars, DOB ≥ 13 years ago, password ≥ 6 chars, matching confirm) upserts the profile, sets the auth password, and navigates to `/routes`. The user can subsequently sign out and sign back in with email + password.
4. A user with an already-complete profile (e.g., an account created via the email signup form) signs in and lands on `/routes` directly — never sees the onboarding screen.
5. A signed-out user opens the app: stays on whichever public screen they were on (or the login flow). The redirect only fires once a session exists.
6. The Drawer's "Sign out" still works from `CompleteProfileScreen` — and after signing out the redirect releases.
7. `ProfileService.ensureProfile(fallbackNickname:...)` is gone. `app.dart` no longer derives a fallback nickname from `user_metadata`/`full_name`/email. Verified by grep.

---

## File Structure

**New files:**

```
movile_app/lib/src/features/profile/
└── complete_profile_screen.dart                # the onboarding form
```

**Modified files:**

```
movile_app/lib/src/services/profile/user_profile.dart
  + bool get hasRequiredFields                  # nickname + dob check

movile_app/lib/src/services/profile/profile_service.dart
  - Future<bool> ensureProfile(...)             # removed (auto-create gone)
  + bool? _isComplete                            # cached completeness
  + bool? get isComplete
  + Future<void> refreshCompleteness()
  + Future<bool> completeProfile({nickname, dateOfBirth})

movile_app/lib/src/services/auth/auth_service.dart
  + Future<bool> setPassword(String)

movile_app/lib/src/services/auth/auth_error_code.dart
  + passwordUpdateFailed                        # enum addition

movile_app/lib/src/app.dart
  - ensureProfile(fallbackNickname:...) call
  - fallback nickname derivation
  + refreshCompleteness() call
  + ChangeNotifier wiring so the router refreshes on state change

movile_app/lib/src/routing/app_router.dart
  + GoRoute('/complete-profile')
  + redirect: callback
  + refreshListenable: parameter

movile_app/lib/l10n/app_es.arb
movile_app/lib/l10n/app_en.arb
  + onboarding* string keys (title, description, button, errors)
```

---

## Task 1: `UserProfile.hasRequiredFields` getter

**Files:**
- Modify: `movile_app/lib/src/services/profile/user_profile.dart`

- [ ] **Step 1: Add the getter**

Open `movile_app/lib/src/services/profile/user_profile.dart`. After the `canChangeNickname` getter (around line 20), add:

```dart
  /// True when the profile has the fields the app requires for full use:
  /// a non-empty nickname AND a date of birth. Mirrors the admin panel's
  /// completeness contract (see admin/lib/supabase/proxy.ts).
  bool get hasRequiredFields =>
      nickname.trim().isNotEmpty && dateOfBirth != null;
```

- [ ] **Step 2: Verify the package still compiles**

Run from `movile_app/`:

```powershell
flutter analyze
```

Expected: no new errors. (Pre-existing warnings unrelated to this task may exist; do not fix them here.)

- [ ] **Step 3: Commit**

```powershell
git add movile_app/lib/src/services/profile/user_profile.dart
git commit -m "feat(mobile): UserProfile.hasRequiredFields getter"
```

---

## Task 2: `AuthService.setPassword`

**Files:**
- Modify: `movile_app/lib/src/services/auth/auth_service.dart`
- Modify: `movile_app/lib/src/services/auth/auth_error_code.dart`

- [ ] **Step 1: Add the new error code**

Open `movile_app/lib/src/services/auth/auth_error_code.dart`. Add `passwordUpdateFailed` to the enum. The full enum should read:

```dart
enum AuthErrorCode {
  googleTokenUnavailable,
  emailAlreadyRegistered,
  invalidCredentials,
  emailNotConfirmed,
  passwordTooShort,
  passwordUpdateFailed,
  noConnection,
  unexpected,
}
```

- [ ] **Step 2: Add `setPassword` to AuthService**

Open `movile_app/lib/src/services/auth/auth_service.dart`. Locate the `Password reset` section (around line 222). After the `resetPasswordForEmail` method, before the `Sign out` divider, insert:

```dart
  /// Sets a password on the currently signed-in user. For users created
  /// via OAuth (no `email` identity), this also makes email+password
  /// sign-in possible afterwards. Returns true on success.
  Future<bool> setPassword(String password) async {
    if (!isLoggedIn) {
      _errorCode = AuthErrorCode.unexpected;
      notifyListeners();
      return false;
    }

    try {
      await _client.auth.updateUser(UserAttributes(password: password));
      _errorCode = null;
      notifyListeners();
      return true;
    } on AuthException catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'auth',
        'setPassword failed',
        error: e,
        stackTrace: st,
        context: {'method': 'setPassword', 'code': e.code},
      );
      _errorCode = _mapAuthError(e);
      notifyListeners();
      return false;
    } catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'auth',
        'setPassword unexpected error',
        error: e,
        stackTrace: st,
        context: {'method': 'setPassword'},
      );
      _errorCode = AuthErrorCode.passwordUpdateFailed;
      notifyListeners();
      return false;
    }
  }
```

- [ ] **Step 3: Verify analyze passes**

```powershell
flutter analyze
```

Expected: no new errors.

- [ ] **Step 4: Commit**

```powershell
git add movile_app/lib/src/services/auth/auth_service.dart movile_app/lib/src/services/auth/auth_error_code.dart
git commit -m "feat(mobile): AuthService.setPassword for OAuth users"
```

---

## Task 3: ProfileService — completeness state, `completeProfile`, remove `ensureProfile`

**Files:**
- Modify: `movile_app/lib/src/services/profile/profile_service.dart`

This task is the biggest refactor in F2.2 because `ProfileService` is the central piece. Replace the file **in its entirety** with the version below. Compare against the current file (Task 8 will look at the diff) — the changes are:

- Add `_isComplete` field + `isComplete` getter.
- Add `refreshCompleteness()` — loads profile if needed, calls `user_has_password` RPC, recomputes `_isComplete`, notifies.
- Add `completeProfile({nickname, dateOfBirth})` — upserts the row.
- **Remove `ensureProfile(...)`** entirely — Google users no longer get an auto-created throw-away nickname.
- `loadProfile()` stays as the explicit refresh entry point.

- [ ] **Step 1: Replace `profile_service.dart`**

Replace `movile_app/lib/src/services/profile/profile_service.dart` ENTIRELY with:

```dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/profile_repository.dart';
import 'user_profile.dart';

class ProfileService extends ChangeNotifier {
  ProfileService(this._repository, {SupabaseClient? client}) : _client = client;

  final ProfileRepository _repository;
  final SupabaseClient? _client;

  UserProfile? _profile;
  UserProfile? get profile => _profile;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// Cached completeness state. `null` while the first load is in
  /// progress; `true` once nickname + DOB + password are all set;
  /// `false` if any of the three is missing.
  bool? _isComplete;
  bool? get isComplete => _isComplete;

  Future<void> loadProfile() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _profile = await _repository.getProfile();
    } catch (e) {
      debugPrint('ProfileService.loadProfile error: $e');
      _error = e.toString();
    }

    _loading = false;
    notifyListeners();
  }

  /// Loads the profile (if not already loaded) and re-evaluates whether
  /// the account is complete: nickname + DOB locally + the password check
  /// via the SECURITY DEFINER RPC. Call this after sign-in and after the
  /// onboarding form submits.
  Future<void> refreshCompleteness() async {
    await loadProfile();

    final hasRequiredFields = _profile?.hasRequiredFields ?? false;
    bool hasPassword = false;
    try {
      final result = await _client?.rpc('user_has_password');
      hasPassword = result == true;
    } catch (e) {
      debugPrint('ProfileService.refreshCompleteness rpc error: $e');
      // On failure, treat as "we don't know" → require onboarding to be
      // safe. The user can still sign out from the onboarding screen.
      hasPassword = false;
    }

    _isComplete = hasRequiredFields && hasPassword;
    notifyListeners();
  }

  /// Upserts the profile row with the given nickname + date of birth.
  /// Used by [CompleteProfileScreen] during onboarding. Returns true on
  /// success.
  Future<bool> completeProfile({
    required String nickname,
    required DateTime dateOfBirth,
  }) async {
    _error = null;

    try {
      if (_profile == null) {
        // First-time profile creation (typical for OAuth-only users).
        _profile = await _repository.createProfile(
          nickname: nickname,
          dateOfBirth: dateOfBirth,
        );
      } else {
        // Existing row: update nickname via the cooldown-respecting RPC
        // when it actually changed, then patch DOB.
        if (_profile!.nickname.trim() != nickname.trim()) {
          await _repository.updateNickname(nickname);
        }
        await _repository.updateDateOfBirth(dateOfBirth);
        _profile = _profile!.copyWith(
          nickname: nickname,
          dateOfBirth: dateOfBirth,
        );
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('ProfileService.completeProfile error: $e');
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateNickname(String newNickname) async {
    _error = null;
    notifyListeners();

    try {
      await _repository.updateNickname(newNickname);
      _profile = _profile?.copyWith(
        nickname: newNickname,
        nicknameChangedAt: DateTime.now(),
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('ProfileService.updateNickname error: $e');
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateBio(String? bio) async {
    _error = null;

    try {
      await _repository.updateBio(bio);
      _profile = _profile?.copyWith(bio: bio);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('ProfileService.updateBio error: $e');
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> uploadAvatar(Uint8List bytes, String extension) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final url = await _repository.uploadAvatar(bytes, extension);
      _profile = _profile?.copyWith(avatarUrl: url);
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('ProfileService.uploadAvatar error: $e');
      _error = e.toString();
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  void clear() {
    final oldUrl = _profile?.avatarUrl;
    _profile = null;
    _error = null;
    _loading = false;
    _isComplete = null;
    if (oldUrl != null) {
      PaintingBinding.instance.imageCache.evict(NetworkImage(oldUrl));
    }
    notifyListeners();
  }
}
```

- [ ] **Step 2: Add `updateDateOfBirth` to ProfileRepository**

`completeProfile` above calls `_repository.updateDateOfBirth(dateOfBirth)` which doesn't exist yet. Open `movile_app/lib/src/data/repositories/profile_repository.dart` and add this method right after `updateBio` (around line 65):

```dart
  Future<void> updateDateOfBirth(DateTime dateOfBirth) async {
    final iso =
        '${dateOfBirth.year}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}';
    await logSupabase(
      'profile.updateDateOfBirth',
      () => _client.from('profiles').update({
        'date_of_birth': iso,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _uid),
    );
  }
```

- [ ] **Step 3: Verify analyze passes**

```powershell
flutter analyze
```

Expected: errors about `ensureProfile` being missing if other code calls it (app.dart will be fixed in Task 4). That's expected for this intermediate state — note the error count but do not edit other files yet.

- [ ] **Step 4: Commit**

```powershell
git add movile_app/lib/src/services/profile/profile_service.dart movile_app/lib/src/data/repositories/profile_repository.dart
git commit -m "feat(mobile): ProfileService completeness state and completeProfile"
```

---

## Task 4: `app.dart` — call `refreshCompleteness`, drop fallback nickname

**Files:**
- Modify: `movile_app/lib/src/app.dart`

- [ ] **Step 1: Update `_createProfileService`**

Open `movile_app/lib/src/app.dart`. The current `_createProfileService` (around line 133–154) extracts a fallback nickname from `user_metadata`/`full_name`/email and calls `ensureProfile(fallbackNickname:..., dateOfBirth:...)`. Replace the entire method body with:

```dart
  void _createProfileService(SupabaseClient client, {bool updateRouter = true}) {
    final repo = ProfileRepository(client);
    _profileService = ProfileService(repo, client: client);
    if (updateRouter) _router.profileService = _profileService;

    // Re-fetch profile + check completeness from scratch on every login.
    // Triggers a router redirect via the refresh listenable if the user
    // ends up incomplete.
    _profileService!.refreshCompleteness();
    _profileService!.addListener(_routerRefresh.notify);

    final garageRepo = GarageRepository(client);
    _garageService = GarageService(garageRepo);
    if (updateRouter) _router.garageService = _garageService;
    _garageService!.loadVehicles();
  }
```

- [ ] **Step 2: Add `_routerRefresh` field and class**

At the top of `_SplitwayAppState` (right after the existing `_garageService` field around line 48), add:

```dart
  final _RouterRefresh _routerRefresh = _RouterRefresh();
```

At the very bottom of the file (after the closing `}` of `SplitwayApp`), add the helper class:

```dart
/// Tiny ChangeNotifier exposed to GoRouter as `refreshListenable` so the
/// router re-evaluates its `redirect` whenever auth or profile state
/// changes (login, logout, profile loaded, completeness changed).
class _RouterRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}
```

- [ ] **Step 3: Wire AuthService into the same listener**

In `initState`, right after `_authService!.addListener(_onAuthStateChanged);`, add:

```dart
      _authService!.addListener(_routerRefresh.notify);
```

In `_onAuthStateChanged`, after the `_router.profileService = _profileService;` line inside the `if (isLoggedIn ...)` branch, the profile listener is set up by `_createProfileService` (Step 1) — no additional wiring needed here.

- [ ] **Step 4: Pass `_routerRefresh` to AppRouter**

In `initState`, change the AppRouter construction to pass it:

```dart
    _router = AppRouter(
      repository: _repository,
      speedRepository: _speedRepository,
      config: widget.config,
      authService: _authService,
      syncService: _syncService,
      profileService: _profileService,
      garageService: _garageService,
      localeController: widget.localeController,
      settingsController: widget.settingsController,
      refreshListenable: _routerRefresh,
    );
```

(`AppRouter` will accept this in Task 7.)

- [ ] **Step 5: Dispose `_routerRefresh`**

In the existing `dispose` method, before `super.dispose();`, add:

```dart
    _routerRefresh.dispose();
```

- [ ] **Step 6: Skip analyze until Task 7**

`AppRouter` doesn't accept `refreshListenable` yet, so analyze will fail. Don't fix here.

- [ ] **Step 7: Commit**

```powershell
git add movile_app/lib/src/app.dart
git commit -m "feat(mobile): app.dart wires refreshCompleteness and router refresh"
```

---

## Task 5: Localization strings (ES + EN)

**Files:**
- Modify: `movile_app/lib/l10n/app_es.arb`
- Modify: `movile_app/lib/l10n/app_en.arb`

- [ ] **Step 1: Add ES strings**

Open `movile_app/lib/l10n/app_es.arb`. Right after the `loginDateOfBirthHint` line (around line 105), insert:

```json
  "onboardingTitle": "Completa tu perfil",
  "onboardingDescription": "Necesitamos algunos datos para terminar de configurar tu cuenta. La contraseña te permitirá iniciar sesión también con email.",
  "onboardingSubmit": "Guardar y continuar",
  "onboardingSubmitLoading": "Guardando…",
  "onboardingDobInvalid": "Debes tener al menos 13 años.",
  "onboardingProfileFailed": "No se pudo guardar el perfil. Inténtalo de nuevo.",
  "onboardingPasswordFailed": "No se pudo establecer la contraseña.",
```

- [ ] **Step 2: Add EN strings**

Open `movile_app/lib/l10n/app_en.arb`. Right after `loginDateOfBirthHint` (around line 105), insert:

```json
  "onboardingTitle": "Complete your profile",
  "onboardingDescription": "We need a few things to finish setting up your account. The password will let you sign in with email too.",
  "onboardingSubmit": "Save and continue",
  "onboardingSubmitLoading": "Saving…",
  "onboardingDobInvalid": "You must be at least 13 years old.",
  "onboardingProfileFailed": "Could not save the profile. Please try again.",
  "onboardingPasswordFailed": "Could not set the password.",
```

- [ ] **Step 3: Regenerate localization classes**

```powershell
cd movile_app
flutter gen-l10n
cd ..
```

Expected: generated files in `lib/l10n/` updated with the new getters (`onboardingTitle`, etc.). Inspect `lib/l10n/app_localizations_es.dart` quickly to confirm the new keys appear.

- [ ] **Step 4: Commit**

```powershell
git add movile_app/lib/l10n/
git commit -m "feat(mobile): localization strings for complete-profile screen"
```

---

## Task 6: `CompleteProfileScreen` widget

**Files:**
- Create: `movile_app/lib/src/features/profile/complete_profile_screen.dart`

- [ ] **Step 1: Create the screen**

Create `movile_app/lib/src/features/profile/complete_profile_screen.dart` with EXACTLY:

```dart
import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/auth/auth_service.dart';
import '../../services/profile/profile_service.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({
    super.key,
    required this.authService,
    required this.profileService,
  });

  final AuthService authService;
  final ProfileService profileService;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _confirmCtrl;
  DateTime? _dateOfBirth;

  bool _submitting = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    final profile = widget.profileService.profile;
    _nicknameCtrl = TextEditingController(text: profile?.nickname ?? '');
    _passwordCtrl = TextEditingController();
    _confirmCtrl = TextEditingController();
    _dateOfBirth = profile?.dateOfBirth;
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);

    if (!_formKey.currentState!.validate()) return;
    if (_dateOfBirth == null) {
      setState(() => _formError = l.onboardingDobInvalid);
      return;
    }
    // 13-year age check.
    final now = DateTime.now();
    final minDate = DateTime(now.year - 13, now.month, now.day);
    if (_dateOfBirth!.isAfter(minDate)) {
      setState(() => _formError = l.onboardingDobInvalid);
      return;
    }

    setState(() {
      _submitting = true;
      _formError = null;
    });

    final profileOk = await widget.profileService.completeProfile(
      nickname: _nicknameCtrl.text.trim(),
      dateOfBirth: _dateOfBirth!,
    );
    if (!mounted) return;
    if (!profileOk) {
      setState(() {
        _submitting = false;
        _formError = l.onboardingProfileFailed;
      });
      return;
    }

    final passwordOk =
        await widget.authService.setPassword(_passwordCtrl.text);
    if (!mounted) return;
    if (!passwordOk) {
      setState(() {
        _submitting = false;
        _formError = l.onboardingPasswordFailed;
      });
      return;
    }

    // Re-evaluate completeness; the router's redirect will pick this up
    // via _routerRefresh and navigate away from /complete-profile.
    await widget.profileService.refreshCompleteness();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false, // The only escape is sign-out, handled below.
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.onboardingTitle),
          actions: [
            IconButton(
              tooltip: l.drawerSignOut,
              icon: const Icon(Icons.logout),
              onPressed: _submitting
                  ? null
                  : () async {
                      await widget.authService.signOut();
                    },
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.onboardingDescription,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nicknameCtrl,
                    decoration: InputDecoration(
                      labelText: l.loginNicknameHint,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return l.loginNicknameRequired;
                      }
                      if (v.trim().length < 2) {
                        return l.loginNicknameMinLength;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _submitting
                        ? null
                        : () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _dateOfBirth ??
                                  DateTime(now.year - 18, now.month, now.day),
                              firstDate: DateTime(1900),
                              lastDate: now,
                            );
                            if (picked != null) {
                              setState(() => _dateOfBirth = picked);
                            }
                          },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: l.loginDateOfBirthHint,
                        border: const OutlineInputBorder(),
                      ),
                      child: Text(
                        _dateOfBirth != null
                            ? '${_dateOfBirth!.day.toString().padLeft(2, '0')}/${_dateOfBirth!.month.toString().padLeft(2, '0')}/${_dateOfBirth!.year}'
                            : l.loginDateOfBirthHint,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: l.loginPasswordHint,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return l.loginPasswordRequired;
                      }
                      if (v.length < 6) return l.loginPasswordMinLength;
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: l.loginConfirmPasswordHint,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v != _passwordCtrl.text) {
                        return l.loginPasswordMismatch;
                      }
                      return null;
                    },
                  ),
                  if (_formError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _formError!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: Text(
                      _submitting
                          ? l.onboardingSubmitLoading
                          : l.onboardingSubmit,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Skip analyze until Task 7**

The router doesn't reference this screen yet — analyze will say it's unused. That's fine, Task 7 wires it up.

- [ ] **Step 3: Commit**

```powershell
git add movile_app/lib/src/features/profile/complete_profile_screen.dart
git commit -m "feat(mobile): CompleteProfileScreen onboarding form"
```

---

## Task 7: Router — `/complete-profile` route + redirect + refreshListenable

**Files:**
- Modify: `movile_app/lib/src/routing/app_router.dart`

- [ ] **Step 1: Add the import and constructor param**

Open `movile_app/lib/src/routing/app_router.dart`. Add this import near the other feature imports (around line 16):

```dart
import '../features/profile/complete_profile_screen.dart';
```

In the constructor parameter list (around line 38–47), add a final `refreshListenable` parameter:

```dart
  AppRouter({
    required this.repository,
    required this.speedRepository,
    required this.config,
    required this.localeController,
    required this.settingsController,
    required this.refreshListenable,
    this.authService,
    SyncService? syncService,
    ProfileService? profileService,
    GarageService? garageService,
  })  : _editorController = RouteEditorController(
```

And as a field (next to `final AppSettingsController settingsController;` around line 76):

```dart
  final Listenable refreshListenable;
```

- [ ] **Step 2: Add the route and redirect to the GoRouter**

Replace the `late final GoRouter router = GoRouter(...)` block (starting around line 94) with the version below. The changes vs. the current router are:
- new `refreshListenable: refreshListenable`
- new `redirect:` callback
- new `/complete-profile` route just below `/login`

```dart
  late final GoRouter router = GoRouter(
    initialLocation: '/routes',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final isLoggedIn = authService?.isLoggedIn ?? false;
      if (!isLoggedIn) return null;

      final isComplete = profileService?.isComplete;
      // null = haven't checked yet. Don't redirect; let the current
      // navigation proceed. The refresh listenable will re-run this
      // callback once refreshCompleteness() resolves.
      if (isComplete == null) return null;

      final path = state.uri.path;
      if (!isComplete && path != '/complete-profile') {
        return '/complete-profile';
      }
      if (isComplete && path == '/complete-profile') {
        return '/routes';
      }
      return null;
    },
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

      // Onboarding — only reachable when logged in + profile incomplete.
      GoRoute(
        path: '/complete-profile',
        builder: (context, state) => CompleteProfileScreen(
          authService: authService!,
          profileService: profileService!,
        ),
      ),

      GoRoute(
        path: '/settings',
        builder: (_, __) => SettingsScreen(
          localeController: localeController,
          settingsController: settingsController,
          authService: authService,
          repository: repository,
          garageService: garageService,
        ),
      ),

      GoRoute(
        path: '/settings/logs',
        builder: (_, __) {
          final sink = AppLogger.localSink;
          final uploader = AppLogger.uploader;
          if (sink == null || uploader == null) {
            return const Scaffold(
              body: Center(child: Text('Logger not initialized')),
            );
          }
          return LogsScreen(sink: sink, uploader: uploader);
        },
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

      GoRoute(
        path: '/stats',
        builder: (_, __) => StatsScreen(
          repository: repository,
          settingsController: settingsController,
          speedRepository: speedRepository,
          garageService: garageService,
          authService: authService,
        ),
      ),

      // Velocidad (drag-strip measurements).
      GoRoute(
        path: '/speed',
        builder: (context, _) => SpeedSetupScreen(
          garageService: garageService,
          onContinue: (result) {
            final controller = SpeedSessionController(
              userId: authService?.currentUser?.id,
              vehicleId: result.vehicle.id,
              vehicleName: result.vehicle.name,
              metrics: result.metrics,
              countdownSeconds: result.countdownSeconds,
              userProvidedName: result.name,
              repository: speedRepository,
            );
            context.push(
              '/speed/ready',
              extra: _SpeedNavExtra(
                controller: controller,
                view: result.view,
              ),
            );
          },
        ),
      ),
      GoRoute(
        path: '/speed/ready',
        builder: (context, state) {
          final extra = state.extra as _SpeedNavExtra;
          return SpeedReadyScreen(
            onStart: () => context.pushReplacement(
              '/speed/session',
              extra: extra,
            ),
          );
        },
      ),
      GoRoute(
        path: '/speed/session',
        builder: (context, state) {
          final extra = state.extra as _SpeedNavExtra;
          return SpeedSessionScreen(
            controller: extra.controller,
            view: extra.view,
            onSaved: (id) => context.go('/history/speed/$id'),
            onDiscarded: () => context.go('/routes'),
            onCancelled: () => context.go('/routes'),
          );
        },
      ),
      GoRoute(
        path: '/history/speed/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return FutureBuilder(
            future: speedRepository.getById(id),
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final s = snap.data;
              if (s == null) {
                return const Scaffold(
                  body: Center(child: Text('Not found')),
                );
              }
              return SpeedSessionDetailScreen(session: s);
            },
          );
        },
      ),

      // Main tabbed shell.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(
          shell: shell,
          authService: authService,
          syncService: syncService,
          profileService: profileService,
          settingsController: settingsController,
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
                  settingsController: settingsController,
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
                  settingsController: settingsController,
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
                  settingsController: settingsController,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (context, state) => HistoryScreen(
                  repository: repository,
                  config: config,
                  authService: authService,
                  profileService: profileService,
                  garageService: garageService,
                  speedRepository: speedRepository,
                  settingsController: settingsController,
                  initialTab: state.uri.queryParameters['tab'] == 'speed'
                      ? 'speed'
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
```

- [ ] **Step 3: Run analyze end-to-end**

```powershell
cd movile_app
flutter analyze
cd ..
```

Expected: zero NEW errors. Any pre-existing analyze warnings stay but no failures from F2.2 changes.

- [ ] **Step 4: Build the app for a smoke check**

```powershell
cd movile_app
flutter build apk --debug
cd ..
```

Expected: build succeeds. (You can also do `flutter run` directly if you have a device/emulator hooked up, in which case skip the explicit build.)

- [ ] **Step 5: Commit**

```powershell
git add movile_app/lib/src/routing/app_router.dart
git commit -m "feat(mobile): /complete-profile route and completeness redirect"
```

---

## Task 8: Manual end-to-end verification

**Files:** none — verification only.

Performed by a human on a real device or emulator. Two test accounts are useful:

- A Google account whose profile is missing DOB and password (the "fresh" path). If you don't have one, sign out any existing test user and have them call `update public.profiles set date_of_birth = null where id = '<that-user-id>'` from the Supabase SQL editor to simulate.
- A second account that already has a complete profile (email signup, or one you put through onboarding already).

- [ ] **Step 1: Launch the app**

```powershell
cd movile_app
flutter run
```

(Pick the target device when prompted. If you only have Android handy, `flutter run -d <android-device-id>`. Note: profile completion needs Supabase reachable — make sure your `--dart-define` flags are set as usual.)

- [ ] **Step 2: Fresh Google user → onboarding screen (criterion 1, 2, 3)**

1. Make sure you're signed out.
2. From the login screen, tap **Continuar con Google**, pick the incomplete Google account.
3. Expected: after the Google round-trip, the screen replaces with **Completa tu perfil**. The nickname field is pre-populated with whatever nickname was already in the DB (could be the throw-away one). DOB and password are empty. There is no bottom nav, no drawer — just the form.
4. Tap the back button (Android) — it should NOT close the screen (`PopScope canPop:false`).
5. Fill the form: tweak the nickname if desired, pick a DOB more than 13 years ago, type a password ≥6 chars twice. Submit.
6. Expected: brief "Guardando…" state, then the app navigates to the routes tab inside `HomeShell`.
7. Verify via SQL:
   ```sql
   select nickname, date_of_birth from public.profiles
   where id = (select id from auth.users where email = '<your-google-email>');
   ```
   Both should now be filled with what you submitted.

- [ ] **Step 3: Sign out + sign in with email + password (criterion 3, second half)**

1. From the drawer, sign out.
2. From the login screen, enter the same email + the password you just set. Submit.
3. Expected: lands directly on `/routes`, no onboarding screen.

- [ ] **Step 4: Already-complete user → no onboarding (criterion 4)**

1. Sign out.
2. Sign in (Google or email) with the complete account.
3. Expected: lands on `/routes` immediately, never sees the onboarding screen.

- [ ] **Step 5: Sign out from onboarding (criterion 6)**

1. Sign out, sign back in with the incomplete Google account → onboarding screen.
2. Tap the logout icon in the AppBar.
3. Expected: app returns to the public flow (login screen). Cookies cleared.

- [ ] **Step 6: Grep verification (criterion 7)**

Run from repo root:

```powershell
git grep -n "ensureProfile" movile_app/
```

Expected: zero matches. If anything remains, fix it before declaring done.

```powershell
git grep -n "fallbackNickname" movile_app/
```

Expected: zero matches.

- [ ] **Step 7: Done**

If all six checks pass → F2.2 is complete. Close branch via `superpowers:finishing-a-development-branch`.

---

## Notes for the executor

- **No backend changes.** Migrations and RPCs (`user_has_password`, `find_*`) are already live from F2.1.
- **`flutter gen-l10n`** must be run after editing `.arb` files — Flutter doesn't auto-regenerate. The CI runs it via `flutter pub run intl_utils:generate` in some projects; this one uses the built-in `flutter gen-l10n`.
- **The router redirect is conservative on `null` completeness.** If `refreshCompleteness()` is slow, the user briefly sees the home screen before being redirected. Acceptable for v1; revisit if it feels jarring.
- **The Drawer's existing "Sign out"** continues to work everywhere — including from `CompleteProfileScreen` via its own AppBar logout icon.
- **`PopScope canPop:false`** is the Flutter 3.16+ replacement for `WillPopScope`. It prevents back-button dismissal without allocating new state. If the project's analysis options forbid it, swap for `WillPopScope` with `onWillPop: () async => false`.
- **Existing user nicknames are preserved.** Users who currently have a throw-away nickname will see it in the pre-populated form on next sign-in and can decide whether to keep or change.
