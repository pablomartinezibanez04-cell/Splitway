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
