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
          email: email.trim(), password: password);
      return cred.user;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  Future<User?> register(String email, String password) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      return cred.user;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  /// Sends a password-reset email. Firebase throws no error for
  /// unknown addresses (by design — it doesn't leak which accounts
  /// exist).
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  Future<void> signOut() => _auth.signOut();

  String _messageFor(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => 'Ugyldig e-postadresse.',
        'user-not-found' =>
          'Ingen konto funnet med denne e-posten.',
        'wrong-password' || 'invalid-credential' =>
          'Feil e-post eller passord.',
        'email-already-in-use' =>
          'Det finnes allerede en konto med denne e-posten.',
        'weak-password' =>
          'Passordet er for svakt – bruk minst 6 tegn.',
        'too-many-requests' =>
          'For mange forsøk – vent litt og prøv igjen.',
        'network-request-failed' =>
          'Nettverksfeil – sjekk tilkoblingen og prøv igjen.',
        'user-disabled' =>
          'Kontoen er deaktivert. Ta kontakt med support.',
        _ =>
          'Pålogging feilet (${e.code}). Prøv igjen.',
      };
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}
