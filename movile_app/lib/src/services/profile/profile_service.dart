import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/profile_repository.dart';
import 'user_profile.dart';

class ProfileService extends ChangeNotifier {
  ProfileService(this._repository, {SupabaseClient? client}) : _client = client;

  final ProfileRepository _repository;
  final SupabaseClient? _client;

  /// Set when [dispose] runs. Async methods kicked off before dispose may
  /// still complete afterwards and attempt to mutate state / notify
  /// listeners — both become no-ops once this is true.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

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

  bool get isAdmin => _profile?.role.isAdmin ?? false;

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

    // Email-signup users typed their nickname + DOB into the signup
    // form, which stores them in auth.user_metadata. If the profile
    // row doesn't exist yet (first sign-in after email confirmation),
    // auto-create it from that metadata so they don't bounce through
    // the onboarding screen. Google OAuth users won't have DOB in
    // metadata, so they fall through to onboarding as expected.
    if (_profile == null && _client != null) {
      final user = _client.auth.currentUser;
      final meta = user?.userMetadata;
      final metaNickname = meta?['nickname'] as String?;
      final metaDobStr = meta?['date_of_birth'] as String?;
      final metaDob = metaDobStr != null ? DateTime.tryParse(metaDobStr) : null;
      if (metaNickname != null &&
          metaNickname.trim().isNotEmpty &&
          metaDob != null) {
        try {
          _profile = await _repository.createProfile(
            nickname: metaNickname.trim(),
            dateOfBirth: metaDob,
          );
        } catch (e) {
          debugPrint('ProfileService bootstrap from metadata failed: $e');
        }
      }
    }

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
