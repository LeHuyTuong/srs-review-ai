import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:srs_review_ai_mobile/firebase_options.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
    : _firebaseAuth = auth,
      _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth? _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  Future<void>? _googleInitialization;

  FirebaseAuth get _auth => _firebaseAuth ?? FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<User?> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    try {
      final googleUser = await _googleSignIn.authenticate();
      final idToken = googleUser.authentication.idToken;
      if (idToken == null) {
        throw FirebaseAuthException(
          code: 'missing-google-id-token',
          message: 'Google Sign-In không trả về ID token.',
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final user = (await _auth.signInWithCredential(credential)).user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'missing-firebase-user',
          message: 'Firebase Authentication không trả về người dùng.',
        );
      }
      return user;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _ensureGoogleInitialized();
      await _googleSignIn.signOut();
    } finally {
      await _auth.signOut();
    }
  }

  Future<void> _ensureGoogleInitialized() async {
    final initialization = _googleInitialization ??= _googleSignIn.initialize(
      serverClientId: DefaultFirebaseOptions.googleSignInServerClientId,
    );
    try {
      await initialization;
    } catch (_) {
      if (identical(_googleInitialization, initialization)) {
        _googleInitialization = null;
      }
      rethrow;
    }
  }
}
