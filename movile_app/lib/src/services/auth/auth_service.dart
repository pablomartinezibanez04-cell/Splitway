import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_error_code.dart';

/// Wraps [SupabaseAuth] and exposes a simple API for sign-in / sign-out.
///
/// Listens to [onAuthStateChange] so the UI reacts to login, logout and
/// token-refresh events automatically.
class AuthService extends ChangeNotifier {
  AuthService({required SupabaseClient client}) : _client = client {
    _subscription = _client.auth.onAuthStateChange.listen(_onAuthEvent);
  }

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _subscription;

  User? get currentUser => _client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  bool _loading = false;
  bool get loading => _loading;

  AuthErrorCode? _errorCode;
  AuthErrorCode? get errorCode => _errorCode;

  /// True when the last sign-up succeeded but requires email confirmation.
  /// The UI should show a "check your inbox" dialog and stay on the screen.
  bool _pendingEmailConfirmation = false;
  bool get pendingEmailConfirmation => _pendingEmailConfirmation;

  void clearPendingConfirmation() {
    _pendingEmailConfirmation = false;
  }

  void clearError() {
    if (_errorCode == null) return;
    _errorCode = null;
    notifyListeners();
  }

  void _onAuthEvent(AuthState state) {
    debugPrint('AuthService: ${state.event}');
    _errorCode = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Google OAuth
  // ---------------------------------------------------------------------------

  Future<bool> signInWithGoogle() async {
    _loading = true;
    _errorCode = null;
    notifyListeners();

    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: _webClientId,
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the sign-in flow.
        _loading = false;
        notifyListeners();
        return false;
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        _errorCode = AuthErrorCode.googleTokenUnavailable;
        _loading = false;
        notifyListeners();
        return false;
      }

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('signInWithGoogle error: $e');
      _errorCode = _mapGenericError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Email / Password
  // ---------------------------------------------------------------------------

  Future<bool> signInWithEmail(String email, String password) async {
    _loading = true;
    _errorCode = null;
    notifyListeners();

    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      _loading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorCode = _mapAuthError(e);
      _loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorCode = _mapGenericError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signUpWithEmail(
    String email,
    String password, {
    String? nickname,
  }) async {
    _loading = true;
    _errorCode = null;
    notifyListeners();

    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: nickname != null ? {'nickname': nickname} : null,
      );
      // When email enumeration protection is ON, Supabase returns
      // session=null for BOTH new users and duplicate emails.
      // The only way to tell them apart: duplicate signups get
      // identities=[] (empty list), new users get identities=[{...}].
      if (response.session == null) {
        final isDuplicate = response.user?.identities?.isEmpty ?? false;
        if (isDuplicate) {
          _errorCode = AuthErrorCode.emailAlreadyRegistered;
          _loading = false;
          notifyListeners();
          return false;
        }
        _pendingEmailConfirmation = true;
        _loading = false;
        notifyListeners();
        return false; // new user, session pending email confirmation
      }
      _loading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorCode = _mapAuthError(e);
      _loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorCode = _mapGenericError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Sign out
  // ---------------------------------------------------------------------------

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      debugPrint('signOut error: $e');
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Google Web Client ID — must match the one configured in Supabase Dashboard
  /// Auth → Providers → Google. On Android the native client ID is pulled from
  /// google-services.json, but serverClientId is needed for the id-token flow.
  static const _webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  AuthErrorCode _mapAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return AuthErrorCode.invalidCredentials;
    }
    if (msg.contains('email not confirmed')) {
      return AuthErrorCode.emailNotConfirmed;
    }
    if (msg.contains('user already registered')) {
      return AuthErrorCode.emailAlreadyRegistered;
    }
    if (msg.contains('password') && msg.contains('at least')) {
      return AuthErrorCode.passwordTooShort;
    }
    return AuthErrorCode.unexpected;
  }

  AuthErrorCode _mapGenericError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('connection')) {
      return AuthErrorCode.noConnection;
    }
    return AuthErrorCode.unexpected;
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
