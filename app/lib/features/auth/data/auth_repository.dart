import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The OAuth client `google_sign_in` authenticates against on Android.
///
/// **This is the *web* client, not the Android one**, and that is the part that
/// catches everyone. `google-services.json` lists three OAuth clients for this
/// project: two of `client_type` 1 — one per registered signing certificate,
/// debug and release — and one of `client_type` 3. Android needs the
/// `client_type: 3` entry, because the token being requested is the one a
/// *server* would verify. Firebase Auth is that server.
///
/// Passing an Android client id here instead produces a sign-in that fails
/// with no useful message at all.
///
/// Not a secret: it is already in the committed `google-services.json`
/// ([ADR 0008](../../../../docs/adr/0008-committing-firebase-config.md)). It
/// lives here as a named constant so that the value has one home and an
/// explanation, rather than being an opaque string inside a call.
const String _serverClientId =
    '194239310855-6009h2cqica1npmuh6kcrg1cv83nm3n3.apps.googleusercontent.com';

/// The only place in the app that talks to Firebase Auth.
///
/// Why this file exists: the project convention (`CLAUDE.md` → Engineering
/// conventions) is that UI code never calls Firebase directly. A thin repository
/// sits in between, so:
///   * the sign-in flow can be read in one place instead of being spread across
///     button callbacks,
///   * Firebase's exception types are translated into messages a human can read
///     before they ever reach a widget,
///   * and a fake implementation can be swapped in for widget tests later.
///
/// This class holds no state of its own. The *state* — who is signed in — lives
/// in Firebase and is exposed as [authStateChanges], a stream. That matters:
/// Firebase restores a persisted session asynchronously at startup, so "who is
/// signed in" is never a value you can just read once and trust.
class AuthRepository {
  AuthRepository({FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignIn})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

  /// Emits the current user on subscribe, then again on every sign-in,
  /// sign-out, and token refresh. `null` means signed out.
  ///
  /// The whole auth gate is driven off this one stream — see
  /// `lib/core/router/app_router.dart`.
  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  /// The user right now, or `null`. Only safe to use for one-off reads *after*
  /// [authStateChanges] has emitted; prefer the stream for anything that
  /// should react to change.
  User? get currentUser => _firebaseAuth.currentUser;

  /// Whether the Google button should be offered at all.
  ///
  /// `google_sign_in` has no Windows implementation, so on desktop this returns
  /// false and the UI falls back to email/password — which the PRD already
  /// allows (FR-2). See `docs/adr/0005-android-first.md`.
  bool get supportsGoogleSignIn =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      _googleSignIn.supportsAuthenticate();

  /// Must be called once before [signInWithGoogle].
  ///
  /// **`serverClientId` has to be passed explicitly.** An earlier version left
  /// it out, on the reasonable-sounding assumption that the plugin would read
  /// it from `google-services.json` the way the old Play-services-based
  /// versions did. `google_sign_in` 7.x does not: it fails at sign-in time with
  /// *"serverClientId must be provided on Android"*, which is a long way from
  /// the line that caused it.
  Future<void> initializeGoogleSignIn() async {
    if (!supportsGoogleSignIn) return;
    await _googleSignIn.initialize(serverClientId: _serverClientId);
  }

  /// Interactive Google sign-in, then exchange the Google ID token for a
  /// Firebase session.
  ///
  /// Two separate identity systems are involved: `google_sign_in` proves *who
  /// the Google user is* and hands back an ID token; Firebase Auth takes that
  /// token and mints its own session, which is what Firestore security rules
  /// actually check.
  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount account = await _googleSignIn.authenticate();
      final String? idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AuthFailure(
          'Google did not return an ID token. Check that the app\'s SHA-1 '
          'fingerprint is registered in the Firebase console.',
        );
      }
      await _firebaseAuth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthFailure.cancelled();
      }
      throw AuthFailure('Google sign-in failed: ${e.description ?? e.code}');
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageFor(e));
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageFor(e));
    }
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageFor(e));
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_messageFor(e));
    }
  }

  /// Signs out of Firebase *and* Google.
  ///
  /// Signing out of Firebase alone leaves the Google account cached, so the
  /// next sign-in silently reuses it and there is no way to switch accounts.
  Future<void> signOut() async {
    if (supportsGoogleSignIn) {
      // Best-effort: if the Google SDK is unhappy we still want the Firebase
      // session gone, which is the part that actually grants data access.
      try {
        await _googleSignIn.signOut();
      } on GoogleSignInException {
        // Intentionally ignored.
      }
    }
    await _firebaseAuth.signOut();
  }

  /// Turns Firebase's error codes into something worth showing a person.
  ///
  /// Firebase deliberately collapses "no such user" and "wrong password" into
  /// `invalid-credential` so an attacker cannot probe which emails exist — the
  /// message below keeps that ambiguity rather than leaking it back.
  String _messageFor(FirebaseAuthException e) {
    return switch (e.code) {
      'invalid-email' => 'That email address is not valid.',
      'user-disabled' => 'This account has been disabled.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' => 'Incorrect email or password.',
      'email-already-in-use' => 'An account already exists for that email.',
      'weak-password' => 'Password must be at least 6 characters.',
      'operation-not-allowed' =>
        'That sign-in method is not enabled for this Firebase project.',
      'network-request-failed' =>
        'No connection. Check your network and try again.',
      'too-many-requests' => 'Too many attempts. Try again in a few minutes.',
      _ => e.message ?? 'Sign-in failed (${e.code}).',
    };
  }
}

/// A sign-in error that is safe and useful to show in the UI.
///
/// Widgets catch this instead of [FirebaseAuthException] so that presentation
/// code never has to know Firebase's error codes.
@immutable
class AuthFailure implements Exception {
  const AuthFailure(this.message) : wasCancelled = false;

  /// The user backed out of the Google account picker. Not an error to report —
  /// the UI just quietly stops showing a spinner.
  const AuthFailure.cancelled()
    : message = 'Sign-in cancelled.',
      wasCancelled = true;

  final String message;
  final bool wasCancelled;

  @override
  String toString() => message;
}
