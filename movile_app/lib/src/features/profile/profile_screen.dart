import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/auth/auth_service.dart';
import '../../services/profile/profile_service.dart';
import '../../services/profile/user_profile.dart';
import '../../shared/image_utils.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.profileService,
    required this.authService,
  });

  final ProfileService profileService;
  final AuthService authService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nicknameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _nicknameFormKey = GlobalKey<FormState>();
  bool _showCooldownWarning = false;

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
    final compressed = await compressToWebp(bytes, maxWidth: 512, maxHeight: 512);
    if (compressed == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).profileErrorUnexpected)),
      );
      return;
    }

    final success = await widget.profileService.uploadAvatar(compressed, 'webp');
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? l.profileAvatarUpdated : l.profileErrorUnexpected)),
    );
  }

  Future<void> _handleSaveNickname() async {
    if (!_nicknameFormKey.currentState!.validate()) return;
    final newNickname = _nicknameCtrl.text.trim();
    final profile = widget.profileService.profile;
    if (profile == null || newNickname == profile.nickname) return;

    if (!profile.canChangeNickname) {
      if (!mounted) return;
      setState(() => _showCooldownWarning = true);
      return;
    }

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
    final email = widget.authService.currentUser?.email ?? '';

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
                              decoration: const BoxDecoration(
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
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
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
                            onPressed: _handleSaveNickname,
                            icon: const Icon(Icons.check, size: 20),
                          ),
                        ],
                      ),
                      if (_showCooldownWarning &&
                          !profile.canChangeNickname) ...[
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
                const SizedBox(height: 28),

                // Email section
                Text(
                  l.profileEmailLabel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.email_outlined,
                          size: 18, color: Theme.of(context).hintColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          email,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Date of birth section
                Text(
                  l.profileDateOfBirthLabel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cake_outlined,
                          size: 18, color: Theme.of(context).hintColor),
                      const SizedBox(width: 8),
                      Text(
                        profile.dateOfBirth != null
                            ? intl.DateFormat.yMMMd(
                                    Localizations.localeOf(context)
                                        .toLanguageTag())
                                .format(profile.dateOfBirth!)
                            : '—',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
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

  final UserProfile profile;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final remaining = profile.nicknameCooldownRemaining;
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
