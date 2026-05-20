import 'package:flutter/foundation.dart';

import 'api.dart';
import 'google_auth_provider.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required MicroLedgerApi api,
    required GoogleAuthProvider googleAuthProvider,
  }) : _api = api,
       _googleAuthProvider = googleAuthProvider;

  final MicroLedgerApi _api;
  final GoogleAuthProvider _googleAuthProvider;

  AuthSession? session;
  bool loading = true;
  bool signingIn = false;
  bool loggingOut = false;
  String? error;

  Future<void> loadCurrentSession() async {
    loading = true;
    error = null;
    notifyListeners();

    try {
      session = await _api.getCurrentSession();
    } catch (err) {
      error = err.toString();
      session = null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loginWithGoogle() async {
    signingIn = true;
    error = null;
    notifyListeners();

    try {
      final idToken = await _googleAuthProvider.signInIdToken(
        _api.authLoginUri(),
      );
      if (idToken == null) {
        return;
      }
      session = await _api.loginWithGoogleIdToken(idToken);
    } catch (err) {
      error = err.toString();
    } finally {
      if (!_googleAuthProvider.usesRedirect) {
        signingIn = false;
        notifyListeners();
      }
    }
  }

  Future<void> logout() async {
    loggingOut = true;
    error = null;
    notifyListeners();

    try {
      await _api.logout();
      await _googleAuthProvider.signOut();
      session = null;
    } catch (err) {
      error = err.toString();
    } finally {
      loggingOut = false;
      notifyListeners();
    }
  }

  Future<void> switchAccount() async {
    await logout();
    if (session == null) {
      loginWithGoogle();
    }
  }
}
