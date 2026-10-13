import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/config/app_config.dart';
import 'auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth, this._google);

  final FirebaseAuth _auth;
  final GoogleSignIn _google;
  Future<void>? _googleReady;

  @override
  Stream<AuthSession?> sessionChanges() => _auth.authStateChanges().map(_session);

  @override
  AuthSession? get currentSession => _session(_auth.currentUser);

  @override
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();

  @override
  Future<void> signInWithGoogle() async {
    _googleReady ??= _google.initialize(
      serverClientId: AppConfig.googleServerClientId.isEmpty ? null : AppConfig.googleServerClientId,
    );
    await _googleReady;
    final GoogleSignInAccount account;
    try {
      account = await _google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthCancelled();
      }
      throw const AuthFailure('Não foi possível entrar com o Google. Tente novamente.');
    }
    final idToken = account.authentication.idToken;
    await _guard(() => _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken)));
  }

  @override
  Future<void> signInWithEmail(String email, String password) =>
      _guard(() => _auth.signInWithEmailAndPassword(email: email.trim(), password: password));

  @override
  Future<void> registerWithEmail(String name, String email, String password) => _guard(() async {
        final credential =
            await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
        await credential.user?.updateDisplayName(name.trim());
      });

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {
      // Not signed in with Google; nothing to undo.
    }
    await _auth.signOut();
  }

  static AuthSession? _session(User? user) => user == null
      ? null
      : AuthSession(uid: user.uid, email: user.email, displayName: user.displayName);

  static Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(messageFor(e.code));
    }
  }

  /// pt-BR message for a Firebase Auth error code.
  static String messageFor(String code) => switch (code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' => 'E-mail ou senha incorretos.',
        'invalid-email' => 'E-mail inválido.',
        'email-already-in-use' => 'Já existe uma conta com este e-mail.',
        'weak-password' => 'Senha fraca: use pelo menos 6 caracteres.',
        'user-disabled' => 'Esta conta foi desativada.',
        'too-many-requests' => 'Muitas tentativas. Aguarde um pouco e tente novamente.',
        'network-request-failed' => 'Sem conexão. Verifique sua internet.',
        _ => 'Não foi possível entrar. Tente novamente.',
      };
}
