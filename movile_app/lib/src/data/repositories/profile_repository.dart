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
    try {
      final old = await _client.storage.from(_avatarBucket).list(path: _uid);
      if (old.isNotEmpty) {
        await _client.storage.from(_avatarBucket).remove(
              old.map((o) => '$_uid/${o.name}').toList(),
            );
      }
    } catch (_) {}

    final path = '$_uid/avatar.$extension';
    await _client.storage.from(_avatarBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: 'image/$extension',
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
