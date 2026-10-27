import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Thin wrapper over Firebase Auth with Norwegian, user-friendly
/// error messages. The app never swallows auth errors silently —
/// they're surfaced to the UI as [AuthException].
class AuthService {
  // Lazy — touching FirebaseAuth.instance before Firebase is
  // initialized throws, so only resolve it on first use.
  FirebaseAuth get _auth => FirebaseAuth.instance;

  /// Emits the signed-in user (or null) whenever auth state changes.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<User?> signIn(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return cred.user;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e), e.code);
    }
  }

  Future<User?> register(String email, String password) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return cred.user;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e), e.code);
    }
  }

  /// Google sign-in. On the web this uses the Firebase popup flow;
  /// natively it goes through the google_sign_in plugin (Android's
  /// Credential Manager picks up the web client id from
  /// google-services.json). Returns null when the user cancels.
  /// Windows has no plugin — email sign-in stays the fallback there.
  Future<User?> signInWithGoogle() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      throw const AuthException(
        'Google-innlogging støttes ikke på Windows ennå – bruk e-post.',
      );
    }
    try {
      if (kIsWeb) {
        final cred = await _auth.signInWithPopup(GoogleAuthProvider());
        return cred.user;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final cred = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: account.authentication.idToken),
      );
      return cred.user;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw AuthException('Google-innlogging feilet (${e.code.name}).');
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e), e.code);
    }
  }

  /// Sign in with Apple (iOS/Android/macOS) or the Firebase popup
  /// on the web. Returns null when the user cancels.
  Future<User?> signInWithApple() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      throw const AuthException(
        'Apple-innlogging støttes ikke på Windows – bruk e-post.',
      );
    }
    try {
      if (kIsWeb) {
        final cred = await _auth.signInWithPopup(OAuthProvider('apple.com'));
        return cred.user;
      }
      final apple = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final cred = await _auth.signInWithCredential(
        OAuthProvider('apple.com').credential(
          idToken: apple.identityToken,
          accessToken: apple.authorizationCode,
        ),
      );
      return cred.user;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw AuthException('Apple-innlogging feilet (${e.code.name}).');
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e), e.code);
    }
  }

  /// Whether the signed-in account uses email+password (true) or a
  /// social provider such as Google/Apple (false) — decides how
  /// [reauthenticate] must run.
  bool get usesPasswordProvider {
    final user = _auth.currentUser;
    if (user == null) return true;
    return user.providerData.any((p) => p.providerId == 'password');
  }

  /// Sends a password-reset email. Firebase throws no error for
  /// unknown addresses (by design — it doesn't leak which accounts
  /// exist).
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e), e.code);
    }
  }

  Future<void> signOut() => _auth.signOut();

  /// Re-authenticates the signed-in user. Required before sensitive
  /// actions such as account deletion. Email+password users pass their
  /// [password]; Google/Apple users go through the provider flow again
  /// (pass null).
  Future<void> reauthenticate([String? password]) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('Du er ikke innlogget.');
    }
    final providers = user.providerData.map((p) => p.providerId).toSet();
    try {
      if (providers.contains(GoogleAuthProvider.PROVIDER_ID)) {
        final account = await GoogleSignIn.instance.authenticate();
        await user.reauthenticateWithCredential(
          GoogleAuthProvider.credential(
            idToken: account.authentication.idToken,
          ),
        );
        return;
      }
      if (providers.contains('apple.com')) {
        final apple = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        );
        await user.reauthenticateWithCredential(
          OAuthProvider('apple.com').credential(
            idToken: apple.identityToken,
            accessToken: apple.authorizationCode,
          ),
        );
        return;
      }
      final email = user.email;
      if (email == null || password == null) {
        throw const AuthException('Skriv inn passordet for å fortsette.');
      }
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e), e.code);
    }
  }

  /// Deletes the Firebase account. Firebase may answer
  /// 'requires-recent-login' — call [reauthenticate] and try again.
  /// Cloud data is deleted by the caller first, so nothing is left
  /// orphaned under the removed uid.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthException('Du er ikke innlogget.');
    }
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e), e.code);
    }
  }

  String _messageFor(FirebaseAuthException e) => switch (e.code) {
    'invalid-email' => 'Ugyldig e-postadresse.',
    'user-not-found' => 'Ingen konto funnet med denne e-posten.',
    'wrong-password' || 'invalid-credential' => 'Feil e-post eller passord.',
    'email-already-in-use' =>
      'Det finnes allerede en konto med denne e-posten.',
    'weak-password' => 'Passordet er for svakt – bruk minst 6 tegn.',
    'too-many-requests' => 'For mange forsøk – vent litt og prøv igjen.',
    'network-request-failed' =>
      'Nettverksfeil – sjekk tilkoblingen og prøv igjen.',
    'user-disabled' => 'Kontoen er deaktivert. Ta kontakt med support.',
    'requires-recent-login' =>
      'Av sikkerhetsgrunner må du skrive inn passordet på nytt.',
    _ => 'Pålogging feilet (${e.code}). Prøv igjen.',
  };
}

class AuthException implements Exception {
  final String message;
  final String? code;
  const AuthException(this.message, [this.code]);
  @override
  String toString() => message;
}
