import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_games_services/firebase_auth_games_services.dart';
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
  /// [avatarStyle] e avatarul desenat ales de jucător din Profil (vezi
  /// widgets/avatar_art.dart). Călătorește odată cu numele și poza tocmai ca
  /// să ajungă în TOATE locurile unde apare jucătorul pentru ceilalți —
  /// lobby, meci, clasament, listă de prieteni — dintr-un singur loc.
  Future<({String name, String? photoUrl, String avatarStyle})> multiplayerIdentity() async {
    final avatarStyle = await StorageService.getAvatarStyleId();
    final u = currentUser;
    if (u != null) {
      final googleName = u.displayName;
      final name = (googleName != null && googleName.isNotEmpty) ? googleName : await StorageService.getDisplayName();
      return (name: name, photoUrl: u.photoURL, avatarStyle: avatarStyle);
    }
    return (name: await StorageService.getDisplayName(), photoUrl: null, avatarStyle: avatarStyle);
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
      var linked = false;
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
          linked = true;
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
      // Legarea (link) păstrează ACELAȘI uid, deci singurul cloud-save de sub
      // el e chiar cel urcat de telefonul ăsta cât era Guest — și poate fi mai
      // vechi decât ce are pe telefon acum (urcarea se face când aplicația
      // trece în fundal, vezi CloudSyncService.push). Un pullOrSeed aici ar
      // aplica regula "cloud-ul câștigă" peste propriul progres proaspăt și ar
      // da jucătorul cu o sesiune înapoi chiar în momentul în care se
      // conectează. Deci: la legare urcăm noi, la logarea într-un cont Google
      // care exista deja în altă parte rămâne cum a fost, cloud-ul câștigă.
      if (linked) {
        await CloudSyncService.instance.push();
      } else {
        await CloudSyncService.instance.pullOrSeed();
      }
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return; // userul a renuntat, nu e o eroare
      debugPrint('AuthService.signInWithGoogle a esuat: $e');
      throw const AccountUnavailableException();
    } catch (e) {
      debugPrint('AuthService.signInWithGoogle a esuat: $e');
      throw const AccountUnavailableException();
    }
  }

  /// Play Games există doar pe Android — pe web/desktop butonul de login nu
  /// trebuie nici măcar arătat (pluginul aruncă acolo, nu e o cale validă).
  bool get isPlayGamesAvailable {
    if (kIsWeb) return false;
    try {
      return FirebaseAuth.instance.isGamesServicesAvailable;
    } catch (e) {
      debugPrint('AuthService.isPlayGamesAvailable a esuat: $e');
      return false;
    }
  }

  /// Copiază gamer tag-ul din providerData pe user, dacă acesta a rămas fără
  /// displayName după login-ul prin Play Games. Eșuează silențios: un nume
  /// lipsă e o problemă cosmetică, nu un motiv să pice tot login-ul.
  Future<void> _adoptPlayGamesDisplayName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final current = user.displayName;
      if (current != null && current.isNotEmpty) return;
      String? tag;
      for (final info in user.providerData) {
        if (info.providerId != PlayGamesAuthProvider.PROVIDER_ID) continue;
        tag = info.displayName;
        break;
      }
      if (tag == null || tag.isEmpty) return;
      await user.updateProfile(displayName: tag);
      await user.reload();
    } catch (e) {
      debugPrint('AuthService._adoptPlayGamesDisplayName a esuat: $e');
    }
  }

  /// Login prin Play Games — alternativă la [signInWithGoogle] pentru cine are
  /// deja profil de jucător pe telefon (nu cere alegerea unui cont, contul
  /// Play Games e deja logat la nivel de sistem). Rezultatul e tot un user
  /// Firebase obișnuit, deci profilul public, prietenii și salvarea în cloud
  /// merg identic, fără nicio ramură separată în restul aplicației.
  /// Aceeași grijă ca la Google pentru identitatea anonimă a multiplayer-ului:
  /// legăm (link) în loc de sign-in curat, ca uid-ul — și tot ce s-a acumulat
  /// sub el — să rămână al aceluiași jucător.
  Future<void> signInWithPlayGames() async {
    try {
      final anonymous = FirebaseAuth.instance.currentUser;
      var linked = false;
      if (anonymous != null && anonymous.isAnonymous) {
        try {
          await anonymous.linkWithGamesServices();
          linked = true;
        } on FirebaseAuthException catch (e) {
          if (e.code != 'credential-already-in-use') rethrow;
          await FirebaseAuth.instance.signInWithGamesServices();
        }
      } else {
        await FirebaseAuth.instance.signInWithGamesServices();
      }
      // Spre deosebire de Google, Play Games nu dă email și nici poză de
      // profil, iar displayName-ul de pe user rămâne gol (verificat pe
      // telefon: fără asta, contul conectat apărea în Profil ca "Guest",
      // pentru că UI-ul cade pe displayName ?? email ?? 'Guest'). Numele
      // jucătorului (gamer tag) vine doar în providerData, sub intrarea
      // providerului Play Games — îl copiem pe user ca restul aplicației
      // să-l găsească unde se așteaptă.
      await _adoptPlayGamesDisplayName();
      if (linked) {
        await CloudSyncService.instance.push();
      } else {
        await CloudSyncService.instance.pullOrSeed();
      }
    } on FirebaseAuthGamesServicesException catch (e) {
      // Cel mai frecvent caz e că userul a închis fereastra Play Games —
      // nedistins de o eroare reală de configurare, pluginul dă același cod.
      debugPrint('AuthService.signInWithPlayGames a esuat: $e');
      throw const AccountUnavailableException('Nu ne-am putut conecta la Play Games.');
    } catch (e) {
      debugPrint('AuthService.signInWithPlayGames a esuat: $e');
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
