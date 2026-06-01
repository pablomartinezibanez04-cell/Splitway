import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/auth/auth_error_code.dart';
import '../../services/auth/auth_service.dart';

/// Fullscreen login with blue gradient, Google + Email/Password.
///
/// If [redirect] is provided, the screen navigates there after a successful
/// login. Otherwise it simply pops back.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authService,
    this.redirect,
    this.bannerMessage,
  });

  final AuthService authService;

  /// go_router path to navigate to after successful login (e.g. `/editor`).
  final String? redirect;

  /// Optional message shown as a banner at the top (e.g. "Sign in to
  /// continue").
  final String? bannerMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

String _localizedAuthError(
  AppLocalizations l,
  AuthErrorCode code,
  DateTime? bannedUntil,
) {
  switch (code) {
    case AuthErrorCode.googleTokenUnavailable:
      return l.authErrorGoogleToken;
    case AuthErrorCode.emailAlreadyRegistered:
      return l.authErrorEmailAlreadyRegistered;
    case AuthErrorCode.invalidCredentials:
      return l.authErrorInvalidCredentials;
    case AuthErrorCode.emailNotConfirmed:
      return l.authErrorEmailNotConfirmed;
    case AuthErrorCode.passwordTooShort:
      return l.authErrorPasswordTooShort;
    case AuthErrorCode.passwordUpdateFailed:
      return l.authErrorUnexpected;
    case AuthErrorCode.userBanned:
      return bannedUntil != null
          ? l.authErrorBannedUntil(bannedUntil)
          : l.authErrorBanned;
    case AuthErrorCode.noConnection:
      return l.authErrorNoConnection;
    case AuthErrorCode.unexpected:
      return l.authErrorUnexpected;
  }
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  DateTime? _dateOfBirth;

  @override
  void initState() {
    super.initState();
    widget.authService.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    widget.authService.removeListener(_onAuthChanged);
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _nicknameCtrl.dispose();
    super.dispose();
  }

  /// Only used to rebuild the UI (error messages, loading spinner).
  /// Navigation is handled directly in the button callbacks to avoid
  /// GoRouter stack conflicts when pop() fires from a listener.
  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  void _popSuccess() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
    // If this screen is a GoRouter root route there is nothing to pop —
    // the AuthService listener in app.dart will rebuild the tree instead.
  }

  Future<void> _handleGoogleSignIn() async {
    final success = await widget.authService.signInWithGoogle();
    if (success) _popSuccess();
  }

  Future<void> _handleEmailSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    final bool success;
    if (_isSignUp) {
      final nickname = _nicknameCtrl.text.trim();
      success = await widget.authService.signUpWithEmail(
        email,
        password,
        nickname: nickname.isNotEmpty ? nickname : null,
        dateOfBirth: _dateOfBirth,
      );
      // Show "check your inbox" dialog if confirmation email was sent.
      if (!success &&
          widget.authService.pendingEmailConfirmation &&
          mounted) {
        widget.authService.clearPendingConfirmation();
        await _showConfirmationEmailDialog(email);
        return;
      }
    } else {
      success = await widget.authService.signInWithEmail(email, password);
    }
    if (success) _popSuccess();
  }

  Future<void> _handleForgotPassword() async {
    final l = AppLocalizations.of(context);
    final resetEmailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l.loginForgotPasswordTitle),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.loginForgotPasswordBody,
                style: const TextStyle(fontSize: 13, color: Color(0xFF616161)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: resetEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: l.loginEmailHint,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return l.loginEmailRequired;
                  if (!v.contains('@') || !v.contains('.')) {
                    return l.loginEmailInvalid;
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: Text(l.loginForgotPasswordButton),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final email = resetEmailCtrl.text.trim();
    final success = await widget.authService.resetPasswordForEmail(email);

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (success) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.loginForgotPasswordSuccess(email))),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(l.loginForgotPasswordError)),
      );
    }
  }

  Future<void> _showConfirmationEmailDialog(String email) {
    final l = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_unread_outlined,
                size: 34,
                color: Color(0xFF1565C0),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l.loginConfirmationTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              l.loginConfirmationBody(email),
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF616161),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.commonClose),
          ),
        ],
      ),
    );
  }

  void _handleSkip() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.authService;
    final l = AppLocalizations.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Banner message
                  if (widget.bannerMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: Colors.white70, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.bannerMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Logo + tagline
                  const Text('🏁',
                      style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 8),
                  Text(
                    l.appTitle,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.appTagline,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Auth container
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Google button
                          _GoogleSignInButton(
                            onPressed: auth.loading ? null : _handleGoogleSignIn,
                          ),

                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                  child: Divider(
                                      color:
                                          Colors.white.withValues(alpha: 0.3))),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  l.loginOrSeparator,
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Expanded(
                                  child: Divider(
                                      color:
                                          Colors.white.withValues(alpha: 0.3))),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Nickname + date of birth fields (signup only)
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
                            GestureDetector(
                              onTap: () async {
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
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _dateOfBirth != null
                                      ? '${_dateOfBirth!.day.toString().padLeft(2, '0')}/${_dateOfBirth!.month.toString().padLeft(2, '0')}/${_dateOfBirth!.year}'
                                      : l.loginDateOfBirthHint,
                                  style: TextStyle(
                                    color: _dateOfBirth != null
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.5),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],

                          // Email field
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration(l.loginEmailHint),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return l.loginEmailRequired;
                              }
                              if (!v.contains('@') || !v.contains('.')) {
                                return l.loginEmailInvalid;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 10),

                          // Password field
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscurePassword,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration(l.loginPasswordHint).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.white54,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return l.loginPasswordRequired;
                              }
                              if (v.length < 6) {
                                return l.loginPasswordMinLength;
                              }
                              return null;
                            },
                          ),

                          // Confirm password field (signup only)
                          if (_isSignUp) ...[
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _confirmPasswordCtrl,
                              obscureText: _obscureConfirmPassword,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration(l.loginConfirmPasswordHint).copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirmPassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.white54,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                      () => _obscureConfirmPassword = !_obscureConfirmPassword),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return l.loginPasswordRequired;
                                }
                                if (v != _passwordCtrl.text) {
                                  return l.loginPasswordMismatch;
                                }
                                return null;
                              },
                            ),
                          ],
                          const SizedBox(height: 6),

                          // Forgot password (sign-in mode only)
                          if (!_isSignUp)
                            Align(
                              alignment: Alignment.centerRight,
                              child: GestureDetector(
                                onTap: auth.loading
                                    ? null
                                    : _handleForgotPassword,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Text(
                                    l.loginForgotPassword,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.8),
                                      fontSize: 12,
                                      decoration: TextDecoration.underline,
                                      decorationColor:
                                          Colors.white.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 8),

                          // Error message
                          if (auth.errorCode != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.redAccent
                                        .withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                _localizedAuthError(
                                  l,
                                  auth.errorCode!,
                                  auth.bannedUntil,
                                ),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],

                          // Submit button
                          SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed:
                                  auth.loading ? null : _handleEmailSubmit,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF1565C0),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: auth.loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Text(
                                      _isSignUp
                                          ? l.loginSignUpButton
                                          : l.loginSignInButton,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Toggle sign-in / sign-up
                  GestureDetector(
                    onTap: () => setState(() {
                      _isSignUp = !_isSignUp;
                      _confirmPasswordCtrl.clear();
                      widget.authService.clearError();
                    }),
                    child: Text.rich(
                      TextSpan(
                        text: _isSignUp
                            ? l.loginToggleToSignIn
                            : l.loginToggleToSignUp,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                        children: [
                          TextSpan(
                            text: _isSignUp
                                ? l.loginToggleSignInAction
                                : l.loginToggleSignUpAction,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Skip
                  TextButton(
                    onPressed: _handleSkip,
                    child: Text(
                      l.loginSkipButton,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
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

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      errorStyle: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF333333),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: BorderSide.none,
        ),
        icon: const Text('G',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4285F4))),
        label: Text(
          l.loginContinueWithGoogle,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
