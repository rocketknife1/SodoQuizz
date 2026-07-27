import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../firebase_options.dart';
import 'cloud_sync_service.dart';
import 'storage_service.dart';

/// Scope suplimentar necesar ca Google chiar să trimită poza de profil —
/// API-ul nou de "Sign in with Google" (Credential Manager) NU o include
/// în tokenul de bază, doar numele/email-ul (verificat direct: tokenul
/// brut nu are deloc câmpul "picture"). Cu acest scope autorizat, luăm
/// poza printr-un apel separat la endpoint-ul de userinfo al Google.
const _profileScope = 'https://www.googleapis.com/auth/userinfo.profile';

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

  /// Identitatea de folosit în multiplayer — dacă userul e logat cu Google,
  /// numele și poza vin din contul Google (nu se pot edita local); altfel
  /// (Guest) rămâne numele local generat, fără poză reală. Doar citește
  /// instantaneul curent al profilului Firebase — sincronizarea lui cu
  /// contul Google se face explicit, o singură dată, la [signInWithGoogle]
  /// (nicio reconectare automată în fundal aici).
  Future<({String name, String? photoUrl})> multiplayerIdentity() async {
    final u = currentUser;
    if (u != null) {
      final googleName = u.displayName;
      final name = (googleName != null && googleName.isNotEmpty) ? googleName : await StorageService.getDisplayName();
      return (name: name, photoUrl: u.photoURL);
    }
    return (name: await StorageService.getDisplayName(), photoUrl: null);
  }

  /// Cere autorizare pentru scope-ul de profil și ia poza direct de la
  /// endpoint-ul de userinfo al Google — necesar pentru ca noul API de
  /// Sign in with Google (Credential Manager) nu trimite poza în tokenul
  /// de bază. Poate cere încă o confirmare Google (o singură dată, prima
  /// oară); eșuează silențios (fără poză) dacă userul refuză sau nu are net.
  Future<String?> _fetchGooglePhotoUrl(GoogleSignInAccount account) async {
    try {
      final headers = await account.authorizationClient.authorizationHeaders(
        [_profileScope],
        promptIfNecessary: true,
      );
      if (headers == null) return null;
      final response = await http.get(Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'), headers: headers);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['picture'] as String?;
    } catch (e) {
      debugPrint('AuthService._fetchGooglePhotoUrl a esuat: $e');
      return null;
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      if (!_googleInitialized) {
        await GoogleSignIn.instance.initialize(serverClientId: googleSignInServerClientId);
        _googleInitialized = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final credential = GoogleAuthProvider.credential(idToken: account.authentication.idToken);
      await FirebaseAuth.instance.signInWithCredential(credential);
      final photoUrl = account.photoUrl ?? await _fetchGooglePhotoUrl(account);
      // FirebaseAuth seteaza displayName/photoURL doar la crearea contului -
      // le rescriem explicit din contul Google curent, ca sa fie mereu live.
      await FirebaseAuth.instance.currentUser?.updateProfile(
        displayName: account.displayName,
        photoURL: photoUrl,
      );
      await FirebaseAuth.instance.currentUser?.reload();
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
