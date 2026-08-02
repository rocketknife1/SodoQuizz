import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../firebase_options.dart';
import 'cloud_sync_service.dart';
import 'player_profile_service.dart';
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

  /// Firebase poate fi neconfigurat pentru platforma curentă (ex. web, unde
  /// firebase_options.dart încă are valori placeholder — vezi comentariul
  /// de acolo) — orice acces la FirebaseAuth.instance aruncă sincron în
  /// acel caz ("auth/invalid-api-key"/"no-app"). Fără try/catch aici,
  /// excepția pica direct în build()-ul lui MyAvatar (folosit în
  /// LevelHeader, deci pe Home/Quests/Profile), iar Flutter înlocuia tot
  /// ecranul cu un ErrorWidget gri, needecodabil, în build-urile de release.
  Stream<User?> authStateChanges() {
    try {
      return FirebaseAuth.instance.authStateChanges().map(_realUserOrNull);
    } catch (e) {
      debugPrint('AuthService.authStateChanges a esuat: $e');
      return Stream.value(null);
    }
  }

  /// `null` dacă nimeni nu e logat, dacă userul curent e doar anonim
  /// (identitatea creată de multiplayer pentru Guest — nu numără ca
  /// "logat" aici), sau dacă Firebase nu e disponibil pe platforma curentă.
  User? get currentUser {
    try {
      return _realUserOrNull(FirebaseAuth.instance.currentUser);
    } catch (e) {
      debugPrint('AuthService.currentUser a esuat: $e');
      return null;
    }
  }

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

  /// Pornește fluxul de alegere cont Google și întoarce credențiala Firebase
  /// rezultată — folosit atât la [signInWithGoogle] (unde avem nevoie și de
  /// [GoogleSignInAccount] pentru nume/poză), cât și la reautentificarea
  /// cerută de [deleteAccount] când sesiunea curentă e prea veche pentru
  /// operația sensibilă de ștergere ("requires-recent-login").
  Future<({AuthCredential credential, GoogleSignInAccount account})> _authenticateGoogle() async {
    if (!_googleInitialized) {
      // Pe web, pluginul cere propriul client OAuth ("clientId") ca sa
      // porneasca fluxul din browser - si NU accepta deloc serverClientId
      // acolo (assertion: "serverClientId is not supported on Web").
      // Android e invers: are nevoie de serverClientId (ca sa verifice
      // id-token-ul), nu de clientId (vine din google-services.json). In
      // acest proiect e acelasi client "Web" auto-creat de Google/Firebase,
      // deci refolosim aceeasi valoare pe fiecare platforma unde e ceruta.
      await GoogleSignIn.instance.initialize(
        clientId: kIsWeb ? googleSignInServerClientId : null,
        serverClientId: kIsWeb ? null : googleSignInServerClientId,
      );
      _googleInitialized = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final credential = GoogleAuthProvider.credential(idToken: account.authentication.idToken);
    return (credential: credential, account: account);
  }

  Future<void> signInWithGoogle() async {
    try {
      final auth = await _authenticateGoogle();
      final credential = auth.credential;
      final account = auth.account;
      final anonymous = FirebaseAuth.instance.currentUser;
      if (anonymous != null && anonymous.isAnonymous) {
        // LEAGĂ contul Google de identitatea anonimă curentă (păstrează
        // ACELAȘI uid) în loc de signInWithCredential direct, care ar crea
        // un uid nou și ar rupe legătura cu tot ce s-a acumulat deja pe
        // identitatea asta (player_profiles/meciuri — vezi PlayerProfileService)
        // — jucătorul ar apărea "dublat" în leaderboard, cu istoricul de
        // Guest orfan sub uid-ul vechi. Eșuează doar dacă acest cont Google
        // are deja propriul istoric în altă parte (alt telefon/sesiune) —
        // în acel caz, acela câștigă (standard), iar progresul de Guest de
        // pe telefonul ăsta rămâne orfan (inevitabil fără Cloud Functions
        // care să contopească două conturi deja separate).
        try {
          await anonymous.linkWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          if (e.code != 'credential-already-in-use' && e.code != 'email-already-in-use') rethrow;
          await FirebaseAuth.instance.signInWithCredential(credential);
        }
      } else {
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
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

  /// Șterge definitiv contul Google curent — cerință Play Console: orice cont
  /// care se poate crea din aplicație trebuie să poată fi șters tot din
  /// aplicație. No-op dacă nimeni nu e logat cu Google (Guest nu are ce
  /// șterge). Curăță ÎNTÂI datele din Firestore (profil public, prieteni,
  /// cloud-save) și abia apoi contul Firebase Auth propriu-zis — pe dos ar
  /// invalida sesiunea înainte ca regulile Firestore (request.auth.uid) să
  /// mai poată autoriza ștergerile. Fără Cloud Functions în acest proiect nu
  /// există o tranzacție reală peste cei doi pași — dacă userul anulează
  /// reautentificarea de mai jos, datele din Firestore tot au fost șterse
  /// deja, dar contul Auth rămâne (poate reîncerca ștergerea din nou).
  /// Progresul local de pe telefon (StorageService) NU e atins — userul
  /// rămâne cu el, ca un Guest nou.
  Future<void> deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    await PlayerProfileService.instance.deleteMyProfile();
    await CloudSyncService.instance.deleteCloudSave();
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') rethrow;
      final auth = await _authenticateGoogle();
      await user.reauthenticateWithCredential(auth.credential);
      await user.delete();
    }
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // ignorat - la fel ca in signOut().
    }
  }
}
