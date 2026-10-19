/// The signed-in user as seen by the app, independent of the auth provider.
class AuthSession {
  const AuthSession({required this.uid, this.email, this.displayName, this.hasPassword = false});

  final String uid;
  final String? email;
  final String? displayName;

  /// Signs in with e-mail and password (a Google-only account has none).
  final bool hasPassword;
}

/// Sign-in failure with a message ready to be shown (pt-BR).
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => 'AuthFailure($message)';
}

/// The user closed the Google account picker; not an error to show.
class AuthCancelled implements Exception {
  const AuthCancelled();
}

/// Authentication port. The only implementation today is Firebase; keeping it
/// behind this interface lets the provider change without touching screens.
abstract class AuthRepository {
  /// Emits the current session (or null) and every change.
  Stream<AuthSession?> sessionChanges();

  AuthSession? get currentSession;

  /// Token sent to the backend, refreshed when close to expiry.
  Future<String?> idToken();

  Future<void> signInWithGoogle();

  Future<void> signInWithEmail(String email, String password);

  Future<void> registerWithEmail(String name, String email, String password);

  Future<void> sendPasswordReset(String email);

  /// Confirms [currentPassword] with the provider and sets [newPassword]; the
  /// user stays signed in. The backend never sees passwords.
  Future<void> changePassword({required String currentPassword, required String newPassword});

  Future<void> signOut();
}
