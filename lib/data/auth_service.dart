import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_games_services/firebase_auth_games_services.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../firebase_options.dart';
import '../core/display_name.dart';
import '../core/progression.dart';
import 'cloud_sync_service.dart';
import 'player_profile_service.dart';
import 'storage_service.dart';
import '../core/error_reporting.dart';

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

  /// `true` cât rulează un login (Google sau Play Games), din clipa în care
  /// se deschide fereastra de cont până după ce identitatea finală e gata.
  ///
  /// De ce contează: fereastra Google e o Activitate externă, deci aplicația
  /// trece prin fundal și revine. La revenire, main.dart cheamă heartbeat-ul
  /// de profil — iar în acel moment userul curent e ÎNCĂ identitatea anonimă.
  /// Dacă login-ul ajunge pe un cont Google care exista deja, identitatea
  /// anonimă e aruncată ([_discardAnonymousIdentity]), dar scrierea
  /// heartbeat-ului putea ateriza DUPĂ ștergere și reînvia profilul
  /// `JucatorXXX` — pe care apoi nu-l mai putea șterge nimeni (contul Auth
  /// era deja dus). Bug găsit în date pe 2026-09-10: profil public fără cont
  /// Auth, atins exact în secunda login-ului. main.dart sare peste heartbeat
  /// și push cât timp e `true`.
  bool get signInInProgress => _signInInProgress;
  bool _signInInProgress = false;

  /// Rulează un login sub [signInInProgress], apoi face heartbeat-ul sărit
  /// la revenirea din fereastra de cont — pe identitatea FINALĂ, nu pe cea
  /// anonimă de dinainte.
  Future<void> _guardSignIn(Future<void> Function() body) async {
    _signInInProgress = true;
    try {
      await body();
    } finally {
      _signInInProgress = false;
    }
    unawaited(PlayerProfileService.instance.ensureProfileHeartbeat());
  }

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
  Future<({String name, String? photoUrl, String avatarStyle,
      String equippedFrame, String equippedTitle, int level})>
      multiplayerIdentity() async {
    final avatarStyle = await StorageService.getAvatarStyleId();
    final u = currentUser;
    // Ordinea numelor stă într-un singur loc, testabil: core/display_name.dart.
    final resolved = resolveDisplayName(
      forcedName: await StorageService.getForcedName(),
      chosenName: await StorageService.getChosenDisplayName(),
      googleName: u?.displayName ?? '',
    );
    // Gol înseamnă „nicio sursă": Guest care nu și-a ales încă nimic. Abia
    // aici se cade pe numele local generat — [getDisplayName] îl și creează
    // dacă lipsește, deci nu are voie să fie chemat pe calea de mai sus.
    final name = resolved.isNotEmpty ? resolved : await StorageService.getDisplayName();
    return (
      name: name,
      photoUrl: u?.photoURL,
      avatarStyle: avatarStyle,
      equippedFrame: await StorageService.getEquippedFrame(),
      equippedTitle: await StorageService.getEquippedTitle(),
      level: levelForXp(await StorageService.getXp()),
    );
  }

  /// Instanța clasică (SDK vechi de Google, NU Credential Manager) — vezi
  /// nota de la `google_sign_in:` din pubspec.yaml pentru de ce s-a coborât
  /// de la v7. Pe web cere `clientId`, pe Android `serverClientId` (ca să
  /// verifice id-token-ul) — assertion-ul pluginului interzice explicit
  /// combinația inversă pe web. E același client OAuth "Web" auto-creat de
  /// Google/Firebase, deci refolosim aceeași valoare pe ambele platforme.
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? googleSignInServerClientId : null,
    serverClientId: kIsWeb ? null : googleSignInServerClientId,
  );

  Future<({AuthCredential credential, GoogleSignInAccount account})?> _authenticateGoogle() async {
    final account = await _googleSignIn.signIn(); // null = userul a renunțat (nu e eroare)
    if (account == null) return null;
    final auth = await account.authentication;
    final credential = GoogleAuthProvider.credential(idToken: auth.idToken, accessToken: auth.accessToken);
    return (credential: credential, account: account);
  }

  /// Pe web `signIn()` programatic e interzis de Google (politica GIS/FedCM
  /// anti-clickjacking) — userul trebuie să apese butonul LOR randat direct
  /// în DOM (vezi data/google_web_signin_button.dart). Fluxul devine deci
  /// pasiv: randăm butonul, iar UI-ul ascultă acest stream pentru contul
  /// apărut și apelează [completeWebGoogleSignIn].
  Stream<GoogleSignInAccount?> get googleAuthenticationEvents => _googleSignIn.onCurrentUserChanged;

  /// Continuarea fluxului de web, apelată de UI după ce
  /// [googleAuthenticationEvents] a emis un cont.
  Future<void> completeWebGoogleSignIn(GoogleSignInAccount account) => _guardSignIn(() async {
        try {
          final auth = await account.authentication;
          final credential = GoogleAuthProvider.credential(idToken: auth.idToken, accessToken: auth.accessToken);
          await _finishGoogleSignIn(account, credential);
        } catch (e) {
          debugPrint('AuthService.completeWebGoogleSignIn a esuat: $e');
          throw const AccountUnavailableException();
        }
      });

  Future<void> signInWithGoogle() => _guardSignIn(() async {
        try {
          final auth = await _authenticateGoogle();
          if (auth == null) return; // userul a renunțat, nu e o eroare
          await _finishGoogleSignIn(auth.account, auth.credential);
        } catch (e, s) {
          reportError(e, s, unde: 'AuthService.signInWithGoogle');
          throw const AccountUnavailableException();
        }
      });

  /// Partea comună fluxurilor mobil (signIn() direct) și web (buton
  /// randat + [googleAuthenticationEvents]): leagă/loghează în Firebase,
  /// sincronizează numele/poza și cloud save-ul.
  Future<void> _finishGoogleSignIn(GoogleSignInAccount account, AuthCredential credential) async {
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
        // Contul Google are deja istoric în altă parte, deci acela câștigă
        // și identitatea anonimă de pe telefonul ăsta rămâne fără rost.
        // O aruncăm ÎNAINTE de a comuta pe contul Google — altfel rămâne
        // în urmă ca un al doilea "cont al meu": profilul ei de Guest
        // continuă să apară în clasament la nesfârșit, iar userul vede
        // două intrări cu numele lui și nu înțelege de unde vin.
        await _discardAnonymousIdentity(anonymous);
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
    } else {
      await FirebaseAuth.instance.signInWithCredential(credential);
    }
    final photoUrl = account.photoUrl; // v6.x o trimite direct, spre deosebire de v7/Credential Manager
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
  Future<void> signInWithPlayGames() => _guardSignIn(_signInWithPlayGames);

  Future<void> _signInWithPlayGames() async {
    try {
      final anonymous = FirebaseAuth.instance.currentUser;
      var linked = false;
      if (anonymous != null && anonymous.isAnonymous) {
        try {
          await anonymous.linkWithGamesServices();
          linked = true;
        } on FirebaseAuthException catch (e) {
          if (e.code != 'credential-already-in-use') rethrow;
          // Aceeași grijă ca la Google — vezi [signInWithGoogle].
          await _discardAnonymousIdentity(anonymous);
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
      await _googleSignIn.signOut();
    } catch (_) {
      // ignorat - oricum ne deconectam din Firebase mai jos.
    }
    await FirebaseAuth.instance.signOut();
    // Identitate anonimă nouă, imediat — același motiv ca la [deleteAccount]:
    // `MultiplayerService.ensureInitialized` are zăvorul deja închis de la
    // pornire, deci până la repornire jucătorul rămânea fără uid (multiplayer
    // cu eroare, absent din clasament).
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (e) {
      debugPrint('AuthService.signOut: identitatea anonima noua a esuat: $e');
    }
  }

  /// Șterge definitiv contul curent — cerință Play Console: orice cont care
  /// se poate crea din aplicație trebuie să poată fi șters tot din aplicație.
  /// Merge pentru ORICE fel de cont: Google, Play Games și **Guest**.
  ///
  /// Curăță ÎNTÂI datele din Firestore (profil public, prieteni, cloud-save)
  /// și abia apoi contul Firebase Auth propriu-zis — pe dos ar invalida
  /// sesiunea înainte ca regulile Firestore (request.auth.uid) să mai poată
  /// autoriza ștergerile. Fără Cloud Functions în acest proiect nu există o
  /// tranzacție reală peste cei doi pași — dacă userul anulează
  /// reautentificarea, datele din Firestore tot au fost șterse deja, dar
  /// contul Auth rămâne (poate reîncerca ștergerea din nou).
  ///
  /// DIFERENȚA DINTRE GUEST ȘI CONT CU LOGIN, și de ce există:
  /// la un cont cu login progresul local NU se atinge — userul rămâne cu el
  /// pe telefon ca un Guest nou, iar dacă se răzgândește se poate reloga
  /// altundeva. La un **Guest** progresul local SE ȘTERGE, altfel ștergerea
  /// ar fi teatru: identitatea anonimă e legată de instalare, deci la
  /// următoarea pornire s-ar crea alt uid anonim (main.dart), iar
  /// `ensureProfileHeartbeat` + prima sincronizare ar reface exact aceleași
  /// documente sub uid-ul nou. Datele ar reapărea în consolă imediat, iar
  /// jucătorul ar rămâne convins că și-a șters contul.
  /// Aruncă identitatea anonimă rămasă fără rost când login-ul a dus la un
  /// cont care exista deja în altă parte (vezi [signInWithGoogle]).
  ///
  /// ORDINEA CONTEAZĂ, la fel ca în [deleteAccount]: întâi documentele din
  /// Firestore (cât timp `request.auth.uid` e ÎNCĂ uid-ul anonim, deci
  /// regulile permit ștergerea), abia apoi contul Auth. Invers, ștergerile
  /// ar fi respinse.
  ///
  /// Progresul local NU se atinge: rămâne pe telefon și e urcat sub contul
  /// nou dacă e cazul. Aici se aruncă doar identitatea goală, nu ce a jucat
  /// omul.
  ///
  /// Totul e „cea mai bună încercare": dacă vreun pas pică (rețea, reguli),
  /// login-ul TREBUIE să continue oricum — un cont dublu rămas în clasament
  /// e mult mai puțin grav decât un login care eșuează.
  Future<void> _discardAnonymousIdentity(User anonymous) async {
    try {
      await PlayerProfileService.instance.deleteMyProfile();
    } catch (e) {
      debugPrint('AuthService._discardAnonymousIdentity: profilul nu s-a sters: $e');
    }
    try {
      await CloudSyncService.instance.deleteCloudSave();
    } catch (e) {
      debugPrint('AuthService._discardAnonymousIdentity: cloud-save-ul nu s-a sters: $e');
    }
    try {
      await anonymous.delete();
    } catch (e) {
      debugPrint('AuthService._discardAnonymousIdentity: contul anonim nu s-a sters: $e');
    }
  }

  Future<void> deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final eraGuest = user.isAnonymous;

    await PlayerProfileService.instance.deleteMyProfile();
    await CloudSyncService.instance.deleteCloudSave();
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') rethrow;
      // Un cont anonim nu poate cere reautentificare (n-are cu ce), deci
      // ramura asta e strict pentru conturile cu login.
      final auth = await _authenticateGoogle();
      if (auth == null) rethrow; // userul a renuntat la reautentificare
      await user.reauthenticateWithCredential(auth.credential);
      await user.delete();
    }

    if (eraGuest) {
      await StorageService.resetAll();
    } else {
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // ignorat - la fel ca in signOut().
      }
    }

    // Identitate anonimă nouă, imediat. Fără ea aplicația rămâne cu
    // `currentUser == null` până la următoarea pornire: singurul loc care
    // cheamă signInAnonymously e MultiplayerService.ensureInitialized, iar
    // acela are un zăvor (`_initialized`) deja închis de la pornirea
    // aplicației, deci n-ar mai crea nimic. Jucătorul ar continua să joace
    // fără uid — nu ar apărea în clasament și multiplayer-ul ar da eroare,
    // fără niciun semn că de la ștergere i se trage.
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (e) {
      debugPrint('AuthService.deleteAccount: identitatea noua a esuat: $e');
    }
  }
}
