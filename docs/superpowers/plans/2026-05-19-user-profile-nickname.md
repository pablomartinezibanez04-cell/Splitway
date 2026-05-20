# User Profile & Nickname Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add user profiles with nickname (collected at signup), avatar photo, bio, and a 3-day cooldown on nickname changes.

**Architecture:** New `profiles` table in Supabase stores nickname, avatar URL, bio, and `nickname_changed_at` for cooldown enforcement. A server-side RPC function enforces the 3-day cooldown. The Flutter app adds a nickname field to signup, a ProfileService (ChangeNotifier) for state, and a new profile screen accessible from the drawer. Avatar images are uploaded to a Supabase Storage bucket.

**Tech Stack:** Supabase (Postgres + Storage + RLS), Flutter (ChangeNotifier, image_picker, go_router)

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `supabase/migrations/20260520000000_add_profiles.sql` | Profiles table, RLS, storage bucket, RPC |
| Create | `movile_app/lib/src/services/profile/user_profile.dart` | Immutable UserProfile model |
| Create | `movile_app/lib/src/data/repositories/profile_repository.dart` | Supabase CRUD for profiles |
| Create | `movile_app/lib/src/services/profile/profile_service.dart` | ChangeNotifier wrapping repository |
| Create | `movile_app/lib/src/features/profile/profile_screen.dart` | Profile editing screen UI |
| Modify | `movile_app/lib/src/features/auth/login_screen.dart` | Add nickname field to signup form |
| Modify | `movile_app/lib/src/services/auth/auth_service.dart` | Accept nickname in signUpWithEmail |
| Modify | `movile_app/lib/src/routing/app_router.dart` | Add /profile route |
| Modify | `movile_app/lib/src/app.dart` | Create and wire ProfileService |
| Modify | `movile_app/lib/src/shared/widgets/app_drawer.dart` | Show nickname + avatar, add profile menu item |
| Modify | `movile_app/lib/src/features/home/home_shell.dart` | Update avatar/initials to use profile data |
| Modify | `movile_app/lib/l10n/app_localizations_en.dart` | English strings |
| Modify | `movile_app/lib/l10n/app_localizations_es.dart` | Spanish strings |
| Modify | `movile_app/lib/l10n/app_localizations.dart` | Abstract string getters |
| Modify | `movile_app/pubspec.yaml` | Add image_picker dependency |
| Create | `movile_app/test/services/profile/user_profile_test.dart` | Model unit tests |
| Create | `movile_app/test/services/profile/profile_service_test.dart` | Service unit tests |

---

### Task 1: Supabase Migration — profiles Table, Storage & RPC

**Files:**
- Create: `supabase/migrations/20260520000000_add_profiles.sql`

- [ ] **Step 1: Write the migration SQL**

```sql
-- Splitway: User profiles with nickname, avatar, bio, and nickname cooldown.

-- 1. Create profiles table
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  avatar_url text,
  bio text,
  nickname_changed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2. Enable RLS
alter table public.profiles enable row level security;

-- 3. RLS policies — users can read/update only their own profile
create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- 4. RPC: update nickname with 3-day cooldown enforcement
create or replace function public.update_nickname(new_nickname text)
returns void
language plpgsql
security definer
as $$
declare
  last_change timestamptz;
begin
  select nickname_changed_at into last_change
  from public.profiles
  where id = auth.uid();

  if last_change is not null and (now() - last_change) < interval '3 days' then
    raise exception 'Nickname cooldown active. Wait 3 days between changes.'
      using errcode = 'P0001';
  end if;

  update public.profiles
  set nickname = new_nickname,
      nickname_changed_at = now(),
      updated_at = now()
  where id = auth.uid();
end;
$$;

-- 5. Storage bucket for avatars
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false)
on conflict (id) do nothing;

-- 6. Storage policies — users can upload/read/delete their own avatars
create policy "Users can upload own avatar"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can read own avatar"
  on storage.objects for select
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can update own avatar"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can delete own avatar"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
```

- [ ] **Step 2: Apply migration locally**

Run: `supabase db reset` (or `supabase migration up` if remote)
Expected: Migration applies without errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260520000000_add_profiles.sql
git commit -m "feat(db): add profiles table with RLS, nickname cooldown RPC, and avatars bucket"
```

---

### Task 2: UserProfile Model

**Files:**
- Create: `movile_app/lib/src/services/profile/user_profile.dart`
- Create: `movile_app/test/services/profile/user_profile_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// movile_app/test/services/profile/user_profile_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/profile/user_profile.dart';

void main() {
  group('UserProfile', () {
    test('fromJson parses all fields', () {
      final json = {
        'id': 'abc-123',
        'nickname': 'SpeedKing',
        'avatar_url': 'https://example.com/avatar.png',
        'bio': 'I love fast laps',
        'nickname_changed_at': '2026-05-10T12:00:00Z',
        'created_at': '2026-05-01T10:00:00Z',
        'updated_at': '2026-05-10T12:00:00Z',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, 'abc-123');
      expect(profile.nickname, 'SpeedKing');
      expect(profile.avatarUrl, 'https://example.com/avatar.png');
      expect(profile.bio, 'I love fast laps');
      expect(profile.nicknameChangedAt, DateTime.utc(2026, 5, 10, 12));
    });

    test('fromJson handles null optionals', () {
      final json = {
        'id': 'abc-123',
        'nickname': 'Rider',
        'avatar_url': null,
        'bio': null,
        'nickname_changed_at': '2026-05-01T10:00:00Z',
        'created_at': '2026-05-01T10:00:00Z',
        'updated_at': '2026-05-01T10:00:00Z',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.avatarUrl, isNull);
      expect(profile.bio, isNull);
    });

    test('canChangeNickname returns false within 3 days', () {
      final profile = UserProfile(
        id: 'abc',
        nickname: 'Test',
        nicknameChangedAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(profile.canChangeNickname, isFalse);
    });

    test('canChangeNickname returns true after 3 days', () {
      final profile = UserProfile(
        id: 'abc',
        nickname: 'Test',
        nicknameChangedAt: DateTime.now().subtract(const Duration(days: 4)),
      );

      expect(profile.canChangeNickname, isTrue);
    });

    test('nicknameCooldownRemaining returns Duration.zero when expired', () {
      final profile = UserProfile(
        id: 'abc',
        nickname: 'Test',
        nicknameChangedAt: DateTime.now().subtract(const Duration(days: 5)),
      );

      expect(profile.nicknameCooldownRemaining, Duration.zero);
    });

    test('nicknameCooldownRemaining returns remaining time', () {
      final profile = UserProfile(
        id: 'abc',
        nickname: 'Test',
        nicknameChangedAt: DateTime.now().subtract(const Duration(days: 2)),
      );

      final remaining = profile.nicknameCooldownRemaining;
      expect(remaining.inHours, greaterThan(20));
      expect(remaining.inHours, lessThanOrEqualTo(24));
    });

    test('copyWith creates new instance with overrides', () {
      final original = UserProfile(
        id: 'abc',
        nickname: 'Old',
        nicknameChangedAt: DateTime.now(),
      );

      final updated = original.copyWith(
        nickname: 'New',
        bio: 'Hello',
      );

      expect(updated.nickname, 'New');
      expect(updated.bio, 'Hello');
      expect(updated.id, 'abc');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd movile_app && flutter test test/services/profile/user_profile_test.dart`
Expected: FAIL — file not found / class not defined.

- [ ] **Step 3: Write the UserProfile model**

```dart
// movile_app/lib/src/services/profile/user_profile.dart

class UserProfile {
  const UserProfile({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.bio,
    required this.nicknameChangedAt,
  });

  final String id;
  final String nickname;
  final String? avatarUrl;
  final String? bio;
  final DateTime nicknameChangedAt;

  static const _cooldown = Duration(days: 3);

  bool get canChangeNickname =>
      DateTime.now().difference(nicknameChangedAt) >= _cooldown;

  Duration get nicknameCooldownRemaining {
    final elapsed = DateTime.now().difference(nicknameChangedAt);
    final remaining = _cooldown - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      nickname: json['nickname'] as String,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      nicknameChangedAt: DateTime.parse(json['nickname_changed_at'] as String),
    );
  }

  UserProfile copyWith({
    String? nickname,
    String? avatarUrl,
    String? bio,
    DateTime? nicknameChangedAt,
  }) {
    return UserProfile(
      id: id,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      nicknameChangedAt: nicknameChangedAt ?? this.nicknameChangedAt,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd movile_app && flutter test test/services/profile/user_profile_test.dart`
Expected: All 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/src/services/profile/user_profile.dart movile_app/test/services/profile/user_profile_test.dart
git commit -m "feat(profile): add UserProfile model with cooldown logic"
```

---

### Task 3: ProfileRepository — Supabase CRUD

**Files:**
- Create: `movile_app/lib/src/data/repositories/profile_repository.dart`

- [ ] **Step 1: Write the ProfileRepository**

```dart
// movile_app/lib/src/data/repositories/profile_repository.dart
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/profile/user_profile.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  static const _avatarBucket = 'avatars';
  static const _signedUrlExpiry = 365 * 24 * 3600; // 1 year

  String get _uid => _client.auth.currentUser!.id;

  Future<UserProfile?> getProfile() async {
    final response = await _client
        .from('profiles')
        .select()
        .eq('id', _uid)
        .maybeSingle();
    if (response == null) return null;
    return UserProfile.fromJson(response);
  }

  Future<UserProfile> createProfile({required String nickname}) async {
    final data = {
      'id': _uid,
      'nickname': nickname,
    };
    final response =
        await _client.from('profiles').insert(data).select().single();
    return UserProfile.fromJson(response);
  }

  Future<void> updateNickname(String newNickname) async {
    await _client.rpc('update_nickname', params: {
      'new_nickname': newNickname,
    });
  }

  Future<void> updateBio(String? bio) async {
    await _client.from('profiles').update({
      'bio': bio,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', _uid);
  }

  Future<String> uploadAvatar(Uint8List bytes, String extension) async {
    final path = '$_uid/avatar.$extension';
    await _client.storage.from(_avatarBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/*',
          ),
        );
    final signedUrl = await _client.storage
        .from(_avatarBucket)
        .createSignedUrl(path, _signedUrlExpiry);

    await _client.from('profiles').update({
      'avatar_url': signedUrl,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', _uid);

    return signedUrl;
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add movile_app/lib/src/data/repositories/profile_repository.dart
git commit -m "feat(profile): add ProfileRepository for Supabase CRUD and avatar upload"
```

---

### Task 4: ProfileService — ChangeNotifier

**Files:**
- Create: `movile_app/lib/src/services/profile/profile_service.dart`

- [ ] **Step 1: Write the ProfileService**

```dart
// movile_app/lib/src/services/profile/profile_service.dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../data/repositories/profile_repository.dart';
import 'user_profile.dart';

class ProfileService extends ChangeNotifier {
  ProfileService(this._repository);

  final ProfileRepository _repository;

  UserProfile? _profile;
  UserProfile? get profile => _profile;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

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

  Future<bool> ensureProfile({required String fallbackNickname}) async {
    if (_profile != null) return true;

    try {
      _profile = await _repository.getProfile();
      if (_profile != null) {
        notifyListeners();
        return true;
      }

      _profile = await _repository.createProfile(nickname: fallbackNickname);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('ProfileService.ensureProfile error: $e');
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
    _profile = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add movile_app/lib/src/services/profile/profile_service.dart
git commit -m "feat(profile): add ProfileService ChangeNotifier for profile state management"
```

---

### Task 5: Add image_picker Dependency

**Files:**
- Modify: `movile_app/pubspec.yaml`

- [ ] **Step 1: Add image_picker to dependencies**

In `movile_app/pubspec.yaml`, add `image_picker: ^1.1.0` under `dependencies:`, after `http: ^1.3.0`:

```yaml
  http: ^1.3.0
  image_picker: ^1.1.0
  path: ^1.9.0
```

- [ ] **Step 2: Run flutter pub get**

Run: `cd movile_app && flutter pub get`
Expected: Dependencies resolve successfully.

- [ ] **Step 3: Commit**

```bash
git add movile_app/pubspec.yaml movile_app/pubspec.lock
git commit -m "chore: add image_picker dependency for avatar upload"
```

---

### Task 6: Localization Strings

**Files:**
- Modify: `movile_app/lib/l10n/app_localizations.dart`
- Modify: `movile_app/lib/l10n/app_localizations_en.dart`
- Modify: `movile_app/lib/l10n/app_localizations_es.dart`

- [ ] **Step 1: Add abstract getters to app_localizations.dart**

Add the following abstract getters to the `AppLocalizations` class, after the existing `settingsLanguageDescription` getter:

```dart
  // Profile
  String get profileTitle;
  String get profileNicknameLabel;
  String get profileBioLabel;
  String get profileBioHint;
  String get profileChangeAvatar;
  String get profileSaved;
  String get profileNicknameCooldown;
  String profileNicknameCooldownDays(int days);
  String profileNicknameCooldownHours(int hours);
  String get profileNicknameRequired;
  String get profileNicknameMinLength;
  String get profileNicknameTooLong;
  String get profileNicknameUpdated;
  String get profileBioUpdated;
  String get profileAvatarUpdated;
  String get profileErrorCooldown;
  String get profileErrorUnexpected;

  // Signup nickname
  String get loginNicknameHint;
  String get loginNicknameRequired;
  String get loginNicknameMinLength;

  // Drawer
  String get drawerProfile;
```

- [ ] **Step 2: Add English translations to app_localizations_en.dart**

Add the following overrides to `AppLocalizationsEn`, after the `settingsLanguageDescription` getter:

```dart
  @override
  String get profileTitle => 'My profile';

  @override
  String get profileNicknameLabel => 'Nickname';

  @override
  String get profileBioLabel => 'About me';

  @override
  String get profileBioHint => 'Tell others about yourself…';

  @override
  String get profileChangeAvatar => 'Change photo';

  @override
  String get profileSaved => 'Profile saved';

  @override
  String get profileNicknameCooldown => 'You can change your nickname again in:';

  @override
  String profileNicknameCooldownDays(int days) {
    return '$days ${days == 1 ? 'day' : 'days'}';
  }

  @override
  String profileNicknameCooldownHours(int hours) {
    return '$hours ${hours == 1 ? 'hour' : 'hours'}';
  }

  @override
  String get profileNicknameRequired => 'Enter a nickname';

  @override
  String get profileNicknameMinLength => 'Minimum 2 characters';

  @override
  String get profileNicknameTooLong => 'Maximum 24 characters';

  @override
  String get profileNicknameUpdated => 'Nickname updated';

  @override
  String get profileBioUpdated => 'Bio updated';

  @override
  String get profileAvatarUpdated => 'Photo updated';

  @override
  String get profileErrorCooldown => 'Wait 3 days between nickname changes.';

  @override
  String get profileErrorUnexpected => 'Something went wrong. Try again.';

  @override
  String get loginNicknameHint => 'Nickname';

  @override
  String get loginNicknameRequired => 'Choose a nickname';

  @override
  String get loginNicknameMinLength => 'Minimum 2 characters';

  @override
  String get drawerProfile => 'Profile';
```

- [ ] **Step 3: Add Spanish translations to app_localizations_es.dart**

Add the following overrides to `AppLocalizationsEs`, after the `settingsLanguageDescription` getter:

```dart
  @override
  String get profileTitle => 'Mi perfil';

  @override
  String get profileNicknameLabel => 'Apodo';

  @override
  String get profileBioLabel => 'Sobre mí';

  @override
  String get profileBioHint => 'Cuéntanos sobre ti…';

  @override
  String get profileChangeAvatar => 'Cambiar foto';

  @override
  String get profileSaved => 'Perfil guardado';

  @override
  String get profileNicknameCooldown => 'Puedes cambiar tu apodo de nuevo en:';

  @override
  String profileNicknameCooldownDays(int days) {
    return '$days ${days == 1 ? 'día' : 'días'}';
  }

  @override
  String profileNicknameCooldownHours(int hours) {
    return '$hours ${hours == 1 ? 'hora' : 'horas'}';
  }

  @override
  String get profileNicknameRequired => 'Introduce un apodo';

  @override
  String get profileNicknameMinLength => 'Mínimo 2 caracteres';

  @override
  String get profileNicknameTooLong => 'Máximo 24 caracteres';

  @override
  String get profileNicknameUpdated => 'Apodo actualizado';

  @override
  String get profileBioUpdated => 'Descripción actualizada';

  @override
  String get profileAvatarUpdated => 'Foto actualizada';

  @override
  String get profileErrorCooldown => 'Espera 3 días entre cambios de apodo.';

  @override
  String get profileErrorUnexpected => 'Algo salió mal. Inténtalo de nuevo.';

  @override
  String get loginNicknameHint => 'Apodo';

  @override
  String get loginNicknameRequired => 'Elige un apodo';

  @override
  String get loginNicknameMinLength => 'Mínimo 2 caracteres';

  @override
  String get drawerProfile => 'Perfil';
```

- [ ] **Step 4: Verify compilation**

Run: `cd movile_app && flutter analyze`
Expected: No errors (both En and Es implement all abstract getters).

- [ ] **Step 5: Commit**

```bash
git add movile_app/lib/l10n/app_localizations.dart movile_app/lib/l10n/app_localizations_en.dart movile_app/lib/l10n/app_localizations_es.dart
git commit -m "feat(l10n): add profile and nickname localization strings (en/es)"
```

---

### Task 7: Add Nickname Field to Signup Flow

**Files:**
- Modify: `movile_app/lib/src/services/auth/auth_service.dart:131-172`
- Modify: `movile_app/lib/src/features/auth/login_screen.dart:51-114`

- [ ] **Step 1: Update AuthService.signUpWithEmail to accept nickname**

In `auth_service.dart`, change the `signUpWithEmail` method signature and pass nickname as user metadata:

Replace lines 131-172:

```dart
  Future<bool> signUpWithEmail(
    String email,
    String password, {
    String? nickname,
  }) async {
    _loading = true;
    _errorCode = null;
    notifyListeners();

    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: nickname != null ? {'nickname': nickname} : null,
      );
      if (response.session == null) {
        final isDuplicate = response.user?.identities?.isEmpty ?? false;
        if (isDuplicate) {
          _errorCode = AuthErrorCode.emailAlreadyRegistered;
          _loading = false;
          notifyListeners();
          return false;
        }
        _pendingEmailConfirmation = true;
        _loading = false;
        notifyListeners();
        return false;
      }
      _loading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorCode = _mapAuthError(e);
      _loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorCode = _mapGenericError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }
```

- [ ] **Step 2: Add nickname field and controller to LoginScreen**

In `login_screen.dart`, add a `_nicknameCtrl` controller in `_LoginScreenState`:

After line 53 (`final _passwordCtrl = TextEditingController();`), add:

```dart
  final _nicknameCtrl = TextEditingController();
```

In the `dispose()` method, add `_nicknameCtrl.dispose();` after `_passwordCtrl.dispose();`.

- [ ] **Step 3: Pass nickname to signUpWithEmail in _handleEmailSubmit**

In `_handleEmailSubmit`, replace the `signUpWithEmail` call (around line 101):

Replace:
```dart
      success = await widget.authService.signUpWithEmail(email, password);
```

With:
```dart
      final nickname = _nicknameCtrl.text.trim();
      success = await widget.authService.signUpWithEmail(
        email,
        password,
        nickname: nickname.isNotEmpty ? nickname : null,
      );
```

- [ ] **Step 4: Add nickname TextFormField to the signup form UI**

In the `build` method, add a nickname field that only shows when `_isSignUp` is true. Insert it right before the email field (before the `TextFormField` for email at approximately line 296):

```dart
                          // Nickname field (signup only)
                          if (_isSignUp) ...[
                            TextFormField(
                              controller: _nicknameCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration(l.loginNicknameHint),
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
                            const SizedBox(height: 10),
                          ],
```

- [ ] **Step 5: Build and verify**

Run: `cd movile_app && flutter analyze`
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add movile_app/lib/src/services/auth/auth_service.dart movile_app/lib/src/features/auth/login_screen.dart
git commit -m "feat(auth): add nickname field to signup form and pass to Supabase metadata"
```

---

### Task 8: Profile Screen UI

**Files:**
- Create: `movile_app/lib/src/features/profile/profile_screen.dart`

- [ ] **Step 1: Write the ProfileScreen**

```dart
// movile_app/lib/src/features/profile/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/profile/profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.profileService});

  final ProfileService profileService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nicknameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _nicknameFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    widget.profileService.addListener(_onProfileChanged);
    _syncControllers();
  }

  @override
  void dispose() {
    widget.profileService.removeListener(_onProfileChanged);
    _nicknameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) {
      _syncControllers();
      setState(() {});
    }
  }

  void _syncControllers() {
    final p = widget.profileService.profile;
    if (p == null) return;
    if (_nicknameCtrl.text != p.nickname) _nicknameCtrl.text = p.nickname;
    if (_bioCtrl.text != (p.bio ?? '')) _bioCtrl.text = p.bio ?? '';
  }

  Future<void> _handlePickAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (image == null) return;

    final bytes = await image.readAsBytes();
    final ext = image.name.split('.').last.toLowerCase();
    final extension = ['jpg', 'jpeg', 'png', 'webp'].contains(ext)
        ? ext
        : 'jpg';

    final success = await widget.profileService.uploadAvatar(bytes, extension);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).profileAvatarUpdated)),
      );
    }
  }

  Future<void> _handleSaveNickname() async {
    if (!_nicknameFormKey.currentState!.validate()) return;
    final newNickname = _nicknameCtrl.text.trim();
    final profile = widget.profileService.profile;
    if (profile == null || newNickname == profile.nickname) return;

    final l = AppLocalizations.of(context);
    final success = await widget.profileService.updateNickname(newNickname);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? l.profileNicknameUpdated : l.profileErrorCooldown),
      ),
    );
  }

  Future<void> _handleSaveBio() async {
    final newBio = _bioCtrl.text.trim();
    final success = await widget.profileService.updateBio(
      newBio.isEmpty ? null : newBio,
    );
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).profileBioUpdated)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final service = widget.profileService;
    final profile = service.profile;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.profileTitle),
        leading: IconButton(
          icon: const BackButtonIcon(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/routes');
            }
          },
        ),
      ),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              children: [
                // Avatar section
                Center(
                  child: GestureDetector(
                    onTap: service.loading ? null : _handlePickAvatar,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: const Color(0xFF1565C0),
                          backgroundImage: profile.avatarUrl != null
                              ? NetworkImage(profile.avatarUrl!)
                              : null,
                          child: profile.avatarUrl == null
                              ? Text(
                                  _initials(profile.nickname),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                        if (service.loading)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    l.profileChangeAvatar,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Nickname section
                Form(
                  key: _nicknameFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.profileNicknameLabel,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _nicknameCtrl,
                              enabled: profile.canChangeNickname,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return l.profileNicknameRequired;
                                }
                                if (v.trim().length < 2) {
                                  return l.profileNicknameMinLength;
                                }
                                if (v.trim().length > 24) {
                                  return l.profileNicknameTooLong;
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: profile.canChangeNickname
                                ? _handleSaveNickname
                                : null,
                            icon: const Icon(Icons.check, size: 20),
                          ),
                        ],
                      ),
                      if (!profile.canChangeNickname) ...[
                        const SizedBox(height: 8),
                        _CooldownIndicator(profile: profile, l: l),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Bio section
                Text(
                  l.profileBioLabel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _bioCtrl,
                  maxLines: 4,
                  maxLength: 200,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: l.profileBioHint,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _handleSaveBio,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(l.commonSave),
                  ),
                ),
              ],
            ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }
}

class _CooldownIndicator extends StatelessWidget {
  const _CooldownIndicator({required this.profile, required this.l});

  final dynamic profile;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final remaining = profile.nicknameCooldownRemaining as Duration;
    final text = remaining.inHours >= 24
        ? l.profileNicknameCooldownDays(remaining.inDays)
        : l.profileNicknameCooldownHours(remaining.inHours);

    return Row(
      children: [
        Icon(Icons.timer_outlined, size: 14, color: Colors.orange[700]),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '${l.profileNicknameCooldown} $text',
            style: TextStyle(fontSize: 12, color: Colors.orange[700]),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd movile_app && flutter analyze`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add movile_app/lib/src/features/profile/profile_screen.dart
git commit -m "feat(profile): add ProfileScreen with avatar picker, nickname cooldown, and bio"
```

---

### Task 9: Wire Up Navigation, App Initialization & Drawer

**Files:**
- Modify: `movile_app/lib/src/app.dart`
- Modify: `movile_app/lib/src/routing/app_router.dart`
- Modify: `movile_app/lib/src/shared/widgets/app_drawer.dart`
- Modify: `movile_app/lib/src/features/home/home_shell.dart`

- [ ] **Step 1: Add ProfileService creation to app.dart**

In `app.dart`, add imports at the top:

```dart
import 'data/repositories/profile_repository.dart';
import 'services/profile/profile_service.dart';
```

Add `ProfileService? _profileService;` field to `_SplitwayAppState`, after `SyncService? _syncService;`.

In the `initState` method, after `_createSyncService(client);` (line 49), add:

```dart
        _createProfileService(client);
```

In `_onAuthStateChanged`, inside the `if (isLoggedIn ...)` block, after `_router.syncService = _syncService;`, add:

```dart
      if (_profileService == null && widget.config.hasSupabase) {
        _createProfileService(Supabase.instance.client);
      }
```

In the `else if (!isLoggedIn ...)` block, add before `_repository.userId = null;`:

```dart
      _profileService?.clear();
      _profileService?.dispose();
      _profileService = null;
      _router.profileService = null;
```

Add a `_createProfileService` method:

```dart
  void _createProfileService(SupabaseClient client) {
    final repo = ProfileRepository(client);
    _profileService = ProfileService(repo);
    _router.profileService = _profileService;

    final user = client.auth.currentUser;
    final nickname = user?.userMetadata?['nickname'] as String? ??
        user?.userMetadata?['full_name'] as String? ??
        user?.email?.split('@').first ??
        'User';
    _profileService!.ensureProfile(fallbackNickname: nickname);
  }
```

In `dispose()`, add before `_router.dispose();`:

```dart
    _profileService?.dispose();
```

Pass `_profileService` to `AppRouter` constructor:

```dart
    _router = AppRouter(
      repository: _repository,
      config: widget.config,
      authService: _authService,
      syncService: _syncService,
      localeController: widget.localeController,
      profileService: _profileService,
    );
```

- [ ] **Step 2: Update AppRouter with profile route and service**

In `app_router.dart`, add imports:

```dart
import '../features/profile/profile_screen.dart';
import '../services/profile/profile_service.dart';
```

Add `ProfileService? profileService;` as a mutable field in `AppRouter` (similar to `syncService`).

Update the constructor to accept it:

```dart
  AppRouter({
    required this.repository,
    required this.config,
    required this.localeController,
    this.authService,
    SyncService? syncService,
    ProfileService? profileService,
  }) {
    // ... existing controller setup ...
    if (syncService != null) this.syncService = syncService;
    if (profileService != null) this.profileService = profileService;
  }
```

Add the `/profile` route after the `/settings` route:

```dart
      GoRoute(
        path: '/profile',
        builder: (_, __) => ProfileScreen(
          profileService: profileService!,
        ),
      ),
```

- [ ] **Step 3: Update AppDrawer to show nickname, avatar, and profile link**

In `app_drawer.dart`, add import:

```dart
import '../../services/profile/profile_service.dart';
```

Add `ProfileService? profileService` parameter to `AppDrawer` and `_LoggedInContent`:

```dart
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
```

Pass `profileService` to `_LoggedInContent`:

```dart
        ? _LoggedInContent(
            authService: authService,
            syncService: syncService,
            profileService: profileService,
          )
```

In `_LoggedInContent`, add the field:

```dart
  final ProfileService? profileService;
```

In its `build` method, override `displayName` and initials with profile data when available:

```dart
    final profile = profileService?.profile;
    final displayName = profile?.nickname ??
        user.userMetadata?['full_name'] as String? ??
        user.email ??
        l.drawerDefaultUser;
```

Replace the avatar Container (the gradient circle with initials) to show avatar image when available:

```dart
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
                        _initials(user),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : null,
              ),
```

Add a "Profile" menu item in the `ListView` children, before the Settings item:

```dart
              _MenuItem(
                icon: Icons.person_outline,
                label: l.drawerProfile,
                onTap: () {
                  Navigator.pop(context);
                  context.push('/profile');
                },
              ),
```

- [ ] **Step 4: Update HomeShell to pass profileService through**

In `home_shell.dart`, add import:

```dart
import '../../services/profile/profile_service.dart';
```

Add `profileService` parameter to `HomeShell`:

```dart
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
```

Pass it to `AppDrawer`:

```dart
      drawer: authService != null
          ? AppDrawer(
              authService: authService!,
              syncService: syncService,
              profileService: profileService,
              onLoginTap: () {
                Navigator.pop(context);
                _navigateToLogin(context);
              },
            )
          : null,
```

Update `buildDrawerLeading` to optionally accept profile and show avatar image:

In the function signature, add `ProfileService? profileService` parameter:

```dart
Widget? buildDrawerLeading(
  BuildContext context,
  AuthService? authService, {
  ProfileService? profileService,
}) {
```

Replace the `CircleAvatar` for logged-in state to use profile avatar:

```dart
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
```

In `app_router.dart`, update the `HomeShell` builder to pass `profileService`:

```dart
        builder: (context, state, shell) => HomeShell(
          shell: shell,
          authService: authService,
          syncService: syncService,
          profileService: profileService,
        ),
```

- [ ] **Step 5: Update callers of buildDrawerLeading**

Search for every call to `buildDrawerLeading` in the codebase and add the `profileService` parameter. These are in the various screen files (route_editor_screen.dart, live_session_screen.dart, free_ride_screen.dart, history_screen.dart). Each call needs to pass the profileService from the AppRouter down.

For this, add `ProfileService? profileService` to each screen's constructor and pass it through from AppRouter. Then in each `buildDrawerLeading` call:

```dart
buildDrawerLeading(context, authService, profileService: profileService)
```

**However**, to keep this task manageable and avoid modifying 4+ screens, an alternative is to make `buildDrawerLeading` resolve the profileService from the drawer itself (which already has it). Since the drawer is what displays the avatar, and the leading icon is just a small circle, we can skip passing profileService to `buildDrawerLeading` for now and only update the drawer's header display. The small app-bar icon will continue showing initials.

- [ ] **Step 6: Verify the app compiles and runs**

Run: `cd movile_app && flutter analyze`
Expected: No errors.

- [ ] **Step 7: Commit**

```bash
git add movile_app/lib/src/app.dart movile_app/lib/src/routing/app_router.dart movile_app/lib/src/shared/widgets/app_drawer.dart movile_app/lib/src/features/home/home_shell.dart
git commit -m "feat(profile): wire up ProfileService, /profile route, and update drawer with avatar/nickname"
```

---

### Task 10: Manual Testing & Visual Verification

- [ ] **Step 1: Test signup with nickname**

1. Run the app: `cd movile_app && flutter run`
2. Go to login screen, switch to "Create account" mode
3. Verify the nickname field appears above the email field
4. Fill in nickname, email, password
5. Submit — verify confirmation email dialog appears
6. Confirm email and sign in
7. Verify drawer shows the nickname instead of email

- [ ] **Step 2: Test profile screen**

1. Open drawer → tap "Profile"
2. Verify nickname, avatar placeholder (initials), and bio fields are shown
3. Change bio, tap Save → verify "Bio updated" snackbar
4. Tap avatar → verify image picker opens
5. Select an image → verify upload spinner, then "Photo updated" snackbar
6. Verify avatar shows in drawer header

- [ ] **Step 3: Test nickname cooldown**

1. In profile screen, change nickname → verify "Nickname updated" snackbar
2. Try to change nickname again immediately → verify field is disabled
3. Verify cooldown timer text appears (e.g. "2 days 23 hours")

- [ ] **Step 4: Test Google OAuth user**

1. Sign out, sign in with Google
2. Verify profile is auto-created with Google display name as nickname
3. Verify profile screen works normally

- [ ] **Step 5: Commit any visual fixes**

```bash
git add -A
git commit -m "fix(profile): visual adjustments from manual testing"
```

---

## Summary of Key Decisions

| Decision | Rationale |
|----------|-----------|
| Separate `profiles` table (not user_metadata) | Need server-side cooldown enforcement and structured queries |
| RPC function for nickname update | Ensures 3-day cooldown is enforced server-side, not just client-side |
| No local SQLite cache for profiles | Profile data is small and only relevant when online (logged in) |
| Nickname stored in signup metadata AND profiles table | Metadata captures it at signup time; profiles table is the source of truth after first login |
| `ensureProfile` on login | Auto-creates profile row on first login using metadata nickname (email signup) or Google display name (OAuth) |
| image_picker with 512px max + 80% quality | Keeps avatar uploads small (~50-100KB) for fast loading |
| `_CooldownIndicator` as separate widget | Keeps profile screen build method readable |
| No nickname uniqueness constraint | User didn't request it; avoids UX friction during signup |
