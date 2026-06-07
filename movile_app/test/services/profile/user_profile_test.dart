import 'package:flutter_test/flutter_test.dart';
import 'package:splitway_mobile/src/services/profile/user_profile.dart';
import 'package:splitway_mobile/src/services/profile/user_role.dart';

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

    test('copyWith can set bio to null', () {
      final original = UserProfile(
        id: 'abc',
        nickname: 'Test',
        bio: 'Some bio',
        nicknameChangedAt: DateTime.now(),
      );

      final updated = original.copyWith(bio: null);

      expect(updated.bio, isNull);
      expect(updated.nickname, 'Test');
    });

    group('role', () {
      Map<String, dynamic> baseJson({String? role}) => {
            'id': 'abc',
            'nickname': 'Rider',
            'avatar_url': null,
            'bio': null,
            'nickname_changed_at': '2026-05-01T10:00:00Z',
            'created_at': '2026-05-01T10:00:00Z',
            'updated_at': '2026-05-01T10:00:00Z',
            if (role != null) 'role': role,
          };

      test('fromJson defaults missing role to user', () {
        final profile = UserProfile.fromJson(baseJson());
        expect(profile.role, UserRole.user);
        expect(profile.role.isAdmin, isFalse);
      });

      test('fromJson reads admin role', () {
        final profile = UserProfile.fromJson(baseJson(role: 'admin'));
        expect(profile.role, UserRole.admin);
        expect(profile.role.isAdmin, isTrue);
      });

      test('fromJson reads superadmin role', () {
        final profile = UserProfile.fromJson(baseJson(role: 'superadmin'));
        expect(profile.role, UserRole.superadmin);
        expect(profile.role.isAdmin, isTrue);
      });

      test('fromJson maps unknown role to user', () {
        final profile = UserProfile.fromJson(baseJson(role: 'pirate'));
        expect(profile.role, UserRole.user);
      });

      test('copyWith updates role', () {
        final p = UserProfile(
          id: 'a',
          nickname: 'n',
          nicknameChangedAt: DateTime.now(),
        );
        expect(p.copyWith(role: UserRole.admin).role, UserRole.admin);
        expect(p.copyWith().role, UserRole.user);
      });
    });

    test('copyWith preserves bio when not passed', () {
      final original = UserProfile(
        id: 'abc',
        nickname: 'Test',
        bio: 'Keep this',
        nicknameChangedAt: DateTime.now(),
      );

      final updated = original.copyWith(nickname: 'New');

      expect(updated.bio, 'Keep this');
    });
  });
}
