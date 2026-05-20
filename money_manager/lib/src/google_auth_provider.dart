import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api.dart';
import 'launcher.dart';

abstract class GoogleAuthProvider {
  bool get usesRedirect;

  Future<String?> signInIdToken(Uri loginUri);

  Future<void> signOut();
}

GoogleAuthProvider createGoogleAuthProvider(UrlLauncher launcher) {
  if (kIsWeb) {
    return RedirectGoogleAuthProvider(launcher: launcher);
  }
  return NativeGoogleAuthProvider();
}

class RedirectGoogleAuthProvider implements GoogleAuthProvider {
  const RedirectGoogleAuthProvider({required UrlLauncher launcher})
    : _launcher = launcher;

  final UrlLauncher _launcher;

  @override
  bool get usesRedirect => true;

  @override
  Future<String?> signInIdToken(Uri loginUri) async {
    _launcher.open(loginUri.toString());
    return null;
  }

  @override
  Future<void> signOut() async {}
}

class NativeGoogleAuthProvider implements GoogleAuthProvider {
  NativeGoogleAuthProvider({
    GoogleSignIn? googleSignIn,
    String clientId = ApiConfig.googleClientId,
    String serverClientId = ApiConfig.googleServerClientId,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _clientId = clientId,
       _serverClientId = serverClientId;

  static Future<void>? _initializeFuture;

  final GoogleSignIn _googleSignIn;
  final String _clientId;
  final String _serverClientId;

  @override
  bool get usesRedirect => false;

  @override
  Future<String?> signInIdToken(Uri loginUri) async {
    await _initialize();
    if (!_googleSignIn.supportsAuthenticate()) {
      throw StateError('google sign-in is not supported on this platform');
    }

    final account = await _googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.trim().isEmpty) {
      throw StateError('google sign-in did not return an id token');
    }
    return idToken;
  }

  @override
  Future<void> signOut() async {
    await _initialize();
    await _googleSignIn.signOut();
  }

  Future<void> _initialize() async {
    final clientId = _clientId.trim();
    final serverClientId = _serverClientId.trim();
    _initializeFuture ??= _googleSignIn.initialize(
      clientId: clientId.isEmpty ? null : clientId,
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
    await _initializeFuture;
  }
}
