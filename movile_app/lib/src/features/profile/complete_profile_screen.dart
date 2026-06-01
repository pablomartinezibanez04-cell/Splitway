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
                      if (v.length < 8) return l.onboardingPasswordMinLength;
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
