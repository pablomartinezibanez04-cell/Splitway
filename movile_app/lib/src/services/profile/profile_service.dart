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
