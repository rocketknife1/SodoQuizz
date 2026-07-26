import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../firebase_options.dart';
import 'cloud_sync_service.dart';

/// Aruncată când login-ul cu Google eșuează (Firebase neconfigurat încă,
/// fără rețea etc.) — UI-ul o prinde și arată un mesaj scurt, nu crash.
/// Anularea explicită de către user (a închis fereastra de cont) NU
/// generează această excepție, e tratată tăcut.
class AccountUnavailableException implements Exception {
  final String message;
  const AccountUnavailableException([this.message = 'Contul e indisponibil momentan.']);
  @override
  String toString() => message;
}

/// Login cu Google + Guest — separat de identitatea anonimă folosită de
/// multiplayer (vezi multiplayer_service.dart): FirebaseAuth ține un singur
/// user curent, deci dacă cineva e logat cu Google, multiplayer-ul îi
/// folosește automat aceeași identitate (nu mai creează una anonimă).
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  bool _googleInitialized = false;

  Stream<User?> authStateChanges() => FirebaseAuth.instance.authStateChanges().map(_realUserOrNull);

  /// `null` dacă nimeni nu e logat SAU dacă userul curent e doar anonim
  /// (identitatea creată de multiplayer pentru Guest) — Guest nu numără ca
  /// "logat" aici.
  User? get currentUser => _realUserOrNull(FirebaseAuth.instance.currentUser);

  User? _realUserOrNull(User? u) => (u != null && !u.isAnonymous) ? u : null;

  bool get isSignedIn => currentUser != null;

  Future<void> signInWithGoogle() async {
    try {
      if (!_googleInitialized) {
        await GoogleSignIn.instance.initialize(serverClientId: googleSignInServerClientId);
        _googleInitialized = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final credential = GoogleAuthProvider.credential(idToken: account.authentication.idToken);
      await FirebaseAuth.instance.signInWithCredential(credential);
      await CloudSyncService.instance.pullOrSeed();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return; // userul a renuntat, nu e o eroare
      debugPrint('AuthService.signInWithGoogle a esuat: $e');
      throw const AccountUnavailableException();
    } catch (e) {
      debugPrint('AuthService.signInWithGoogle a esuat: $e');
      throw const AccountUnavailableException();
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // ignorat - oricum ne deconectam din Firebase mai jos.
    }
    await FirebaseAuth.instance.signOut();
  }
}
