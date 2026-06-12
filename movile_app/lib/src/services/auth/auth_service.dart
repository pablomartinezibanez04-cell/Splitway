import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_logger.dart';
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

  /// The most recent [AuthChangeEvent] emitted by Supabase, exposed so the
  /// app can distinguish e.g. `initialSession` (cold-start hydration) from
  /// `signedIn` (explicit login).
  AuthChangeEvent? _lastEvent;
  AuthChangeEvent? get lastEvent => _lastEvent;

  /// Set the first time we force a local `signOut` in response to a
  /// `signedOut` event. Prevents the resulting follow-up `signedOut` events
  /// (which Supabase emits as part of the cleanup) from re-triggering the
  /// same cleanup in an infinite loop. Reset when a fresh session arrives.
  bool _localCleanupDone = false;

  bool _loading = false;
  bool get loading => _loading;

  AuthErrorCode? _errorCode;
  AuthErrorCode? get errorCode => _errorCode;

  /// True when the last sign-up succeeded but requires email confirmation.
  /// The UI should show a "check your inbox" dialog and stay on the screen.
  bool _pendingEmailConfirmation = false;
  bool get pendingEmailConfirmation => _pendingEmailConfirmation;

  /// When the most recent sign-in attempt failed because the user is
  /// banned, this holds the `banned_until` timestamp returned by the
  /// `get_user_ban_until` RPC (null if the ban is permanent / unknown
  /// or if the last failure was something else).
  DateTime? _bannedUntil;
  DateTime? get bannedUntil => _bannedUntil;

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
    _lastEvent = state.event;
    switch (state.event) {
      case AuthChangeEvent.signedOut:
        // If Supabase emits signedOut because the persisted refresh token
        // is invalid (e.g. the user was deleted on the backend, or the
        // project's JWT secret rotated), the local storage still holds a
        // stale session and `currentUser` will be hydrated on every cold
        // start, looping the same failure. Force a local-only signOut to
        // wipe that storage so the next start boots cleanly without ever
        // calling refresh.
        //
        // The signOut call itself triggers further signedOut events as it
        // tears down the session; guard with `_localCleanupDone` to avoid
        // an infinite loop.
        if (!_localCleanupDone) {
          _localCleanupDone = true;
          unawaited(
            _client.auth.signOut(scope: SignOutScope.local).catchError((_) {}),
          );
        }
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
        // A fresh, valid session is now active — arm the cleanup again so
        // that a future stale-refresh logout is handled correctly.
        _localCleanupDone = false;
      default:
        break;
    }
    _errorCode = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Google OAuth
  // ---------------------------------------------------------------------------

  /// Initializes the [GoogleSignIn] singleton. Must be called once at app
  /// startup before any sign-in attempt.
  static Future<void> initGoogleSignIn() async {
    await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
  }

  Future<bool> signInWithGoogle() async {
    _loading = true;
    _errorCode = null;
    _bannedUntil = null;
    notifyListeners();

    try {
      // Force the account picker every time. Without this, google_sign_in
      // silently returns the last-used Google account on subsequent calls,
      // which surprises users who expect to choose which account to use
      // and looks like the consent step was skipped.
      await GoogleSignIn.instance.signOut();
      final GoogleSignInAccount googleUser;
      try {
        googleUser = await GoogleSignIn.instance.authenticate();
      } on GoogleSignInException {
        // User cancelled the sign-in flow.
        _loading = false;
        notifyListeners();
        return false;
      }

      final idToken = googleUser.authentication.idToken;
      // accessToken is no longer part of authentication in google_sign_in v7;
      // Supabase's signInWithIdToken only requires idToken.

      if (idToken == null) {
        _errorCode = AuthErrorCode.googleTokenUnavailable;
        _loading = false;
        notifyListeners();
        return false;
      }

      try {
        await _client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
        );
      } on AuthException catch (e, st) {
        AppLogger.maybeInstance?.warning(
          'auth',
          'signInWithGoogle id-token exchange failed',
          error: e,
          stackTrace: st,
          context: {'method': 'signInWithGoogle', 'code': e.code},
        );
        _errorCode = _mapAuthError(e);
        if (_errorCode == AuthErrorCode.userBanned) {
          await _fetchBanInfo(googleUser.email);
        }
        _loading = false;
        notifyListeners();
        return false;
      }

      _loading = false;
      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('signInWithGoogle error: $e');
      AppLogger.maybeInstance?.warning(
        'auth',
        'signInWithGoogle failed',
        error: e,
        stackTrace: st,
        context: {'method': 'signInWithGoogle'},
      );
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
    _bannedUntil = null;
    notifyListeners();

    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      _loading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'auth',
        'signInWithEmail failed',
        error: e,
        stackTrace: st,
        context: {'method': 'signInWithEmail', 'code': e.code},
      );
      _errorCode = _mapAuthError(e);
      if (_errorCode == AuthErrorCode.userBanned) {
        await _fetchBanInfo(email);
      }
      _loading = false;
      notifyListeners();
      return false;
    } catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'auth',
        'signInWithEmail unexpected error',
        error: e,
        stackTrace: st,
        context: {'method': 'signInWithEmail'},
      );
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
    DateTime? dateOfBirth,
  }) async {
    _loading = true;
    _errorCode = null;
    notifyListeners();

    try {
      final metadata = <String, dynamic>{};
      if (nickname != null) metadata['nickname'] = nickname;
      if (dateOfBirth != null) {
        metadata['date_of_birth'] = dateOfBirth.toIso8601String();
      }
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: metadata.isNotEmpty ? metadata : null,
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
    } on AuthException catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'auth',
        'signUpWithEmail failed',
        error: e,
        stackTrace: st,
        context: {'method': 'signUpWithEmail', 'code': e.code},
      );
      _errorCode = _mapAuthError(e);
      _loading = false;
      notifyListeners();
      return false;
    } catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'auth',
        'signUpWithEmail unexpected error',
        error: e,
        stackTrace: st,
        context: {'method': 'signUpWithEmail'},
      );
      _errorCode = _mapGenericError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Password reset
  // ---------------------------------------------------------------------------

  Future<bool> resetPasswordForEmail(String email) async {
    _loading = true;
    _errorCode = null;
    notifyListeners();

    try {
      await _client.auth.resetPasswordForEmail(email);
      _loading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'auth',
        'resetPasswordForEmail failed',
        error: e,
        stackTrace: st,
        context: {'method': 'resetPasswordForEmail', 'code': e.code},
      );
      _errorCode = _mapAuthError(e);
      _loading = false;
      notifyListeners();
      return false;
    } catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'auth',
        'resetPasswordForEmail unexpected error',
        error: e,
        stackTrace: st,
        context: {'method': 'resetPasswordForEmail'},
      );
      _errorCode = _mapGenericError(e);
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Sets a password on the currently signed-in user. For users created
  /// via OAuth (no `email` identity), this also makes email+password
  /// sign-in possible afterwards. Returns true on success.
  Future<bool> setPassword(String password) async {
    if (!isLoggedIn) {
      _errorCode = AuthErrorCode.unexpected;
      notifyListeners();
      return false;
    }

    try {
      await _client.auth.updateUser(UserAttributes(password: password));
      _errorCode = null;
      notifyListeners();
      return true;
    } on AuthException catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'auth',
        'setPassword failed',
        error: e,
        stackTrace: st,
        context: {'method': 'setPassword', 'code': e.code},
      );
      _errorCode = _mapAuthError(e);
      notifyListeners();
      return false;
    } catch (e, st) {
      AppLogger.maybeInstance?.warning(
        'auth',
        'setPassword unexpected error',
        error: e,
        stackTrace: st,
        context: {'method': 'setPassword'},
      );
      _errorCode = AuthErrorCode.passwordUpdateFailed;
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
    } catch (e, st) {
      debugPrint('signOut error: $e');
      AppLogger.maybeInstance?.warning(
        'auth',
        'signOut failed',
        error: e,
        stackTrace: st,
      );
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

  Future<void> _fetchBanInfo(String email) async {
    try {
      final result = await _client.rpc(
        'get_user_ban_until',
        params: {'p_email': email},
      );
      if (result is String) {
        _bannedUntil = DateTime.tryParse(result);
      } else {
        _bannedUntil = null;
      }
    } catch (e) {
      debugPrint('AuthService._fetchBanInfo error: $e');
      _bannedUntil = null;
    }
  }

  AuthErrorCode _mapAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    final code = e.code?.toLowerCase() ?? '';
    if (code == 'user_banned' ||
        msg.contains('user is banned') ||
        msg.contains('user banned')) {
      return AuthErrorCode.userBanned;
    }
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
