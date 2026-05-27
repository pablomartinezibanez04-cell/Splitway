import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/logging/app_logger.dart';
import '../../services/logging/http_logging.dart';
import '../../services/profile/user_profile.dart';

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  static const _avatarBucket = 'avatars';
  static const _signedUrlExpiry = 365 * 24 * 3600; // 1 year

  String get _uid => _client.auth.currentUser!.id;

  Future<UserProfile?> getProfile() async {
    final response = await logSupabase(
      'profile.getProfile',
      () => _client.from('profiles').select().eq('id', _uid).maybeSingle(),
    );
    if (response == null) return null;
    return UserProfile.fromJson(response);
  }

  Future<UserProfile> createProfile({
    required String nickname,
    DateTime? dateOfBirth,
  }) async {
    final data = <String, dynamic>{
      'id': _uid,
      'nickname': nickname,
    };
    if (dateOfBirth != null) {
      data['date_of_birth'] =
          '${dateOfBirth.year}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}';
    }
    final response = await logSupabase(
      'profile.createProfile',
      () => _client.from('profiles').insert(data).select().single(),
    );
    return UserProfile.fromJson(response);
  }

  Future<void> updateNickname(String newNickname) async {
    await logSupabase(
      'profile.updateNickname',
      () => _client.rpc('update_nickname', params: {
        'new_nickname': newNickname,
      }),
    );
  }

  Future<void> updateBio(String? bio) async {
    await logSupabase(
      'profile.updateBio',
      () => _client.from('profiles').update({
        'bio': bio,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _uid),
    );
  }

  Future<String> uploadAvatar(Uint8List bytes, String extension) async {
    try {
      final old = await _client.storage.from(_avatarBucket).list(path: _uid);
      if (old.isNotEmpty) {
        await _client.storage.from(_avatarBucket).remove(
              old.map((o) => '$_uid/${o.name}').toList(),
            );
      }
    } catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'supabase',
        'profile.uploadAvatar cleanup failed',
        error: e,
        stackTrace: st,
      );
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$_uid/avatar_$timestamp.$extension';
    await logSupabase(
      'profile.uploadAvatar.upload',
      () => _client.storage.from(_avatarBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: 'image/$extension',
            ),
          ),
    );
    final signedUrl = await logSupabase(
      'profile.uploadAvatar.signedUrl',
      () => _client.storage
          .from(_avatarBucket)
          .createSignedUrl(path, _signedUrlExpiry),
    );

    await logSupabase(
      'profile.uploadAvatar.update',
      () => _client.from('profiles').update({
        'avatar_url': signedUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _uid),
    );

    return signedUrl;
  }
}
