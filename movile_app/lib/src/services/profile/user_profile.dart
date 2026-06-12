import 'user_role.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    required this.nickname,
    this.avatarUrl,
    this.bio,
    this.dateOfBirth,
    required this.nicknameChangedAt,
    this.role = UserRole.user,
  });

  final String id;
  final String nickname;
  final String? avatarUrl;
  final String? bio;
  final DateTime? dateOfBirth;
  final DateTime nicknameChangedAt;
  final UserRole role;

  static const _cooldown = Duration(days: 3);

  bool get canChangeNickname =>
      DateTime.now().difference(nicknameChangedAt) >= _cooldown;

  /// True when the profile has the fields the app requires for full use:
  /// a non-empty nickname AND a date of birth. Mirrors the admin panel's
  /// completeness contract (see admin/lib/supabase/proxy.ts).
  bool get hasRequiredFields =>
      nickname.trim().isNotEmpty && dateOfBirth != null;

  Duration get nicknameCooldownRemaining {
    final elapsed = DateTime.now().difference(nicknameChangedAt);
    final remaining = _cooldown - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final dob = json['date_of_birth'] as String?;
    return UserProfile(
      id: json['id'] as String,
      nickname: json['nickname'] as String,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      dateOfBirth: dob != null ? DateTime.parse(dob) : null,
      nicknameChangedAt: DateTime.parse(json['nickname_changed_at'] as String),
      role: UserRole.fromString(json['role'] as String?),
    );
  }

  UserProfile copyWith({
    String? nickname,
    Object? avatarUrl = _sentinel,
    Object? bio = _sentinel,
    Object? dateOfBirth = _sentinel,
    DateTime? nicknameChangedAt,
    UserRole? role,
  }) {
    return UserProfile(
      id: id,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl == _sentinel ? this.avatarUrl : avatarUrl as String?,
      bio: bio == _sentinel ? this.bio : bio as String?,
      dateOfBirth: dateOfBirth == _sentinel
          ? this.dateOfBirth
          : dateOfBirth as DateTime?,
      nicknameChangedAt: nicknameChangedAt ?? this.nicknameChangedAt,
      role: role ?? this.role,
    );
  }

  static const _sentinel = Object();
}
