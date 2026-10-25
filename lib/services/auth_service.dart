import 'package:firebase_auth/firebase_auth.dart';

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

  /// Re-authenticates the signed-in user with their password.
  /// Required before sensitive actions such as account deletion.
  Future<void> reauthenticate(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw const AuthException('Du er ikke innlogget.');
    }
    try {
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
