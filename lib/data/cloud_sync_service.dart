import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../core/error_reporting.dart';
import 'auth_service.dart';
import 'multiplayer_service.dart';
import 'notification_service.dart';
import 'player_profile_service.dart';
import 'storage_service.dart';

/// Sincronizează progresul local (tot ce ține `StorageService` prin
/// SharedPreferences) cu Firestore. Sincronizare generică (vezi
/// `StorageService.exportAll/importAll`), nu câmp-cu-câmp.
///
/// URCAREA ([push]) se face pentru ORICINE are o identitate, inclusiv Guest
/// (anonim). Nu ca să-i dea Guest-ului salvare în cloud — [pullOrSeed]
/// rămâne strict pentru conturi Google, deci un Guest tot nu-și recuperează
/// progresul pe alt telefon (identitatea lui anonimă e legată de instalare) —
/// ci pentru ca fișa din AdminScreen să arate aceleași cifre pentru toată
/// lumea. Fără asta, un "mi-au dispărut monedele" sau o suspiciune de trișare
/// venită de la un Guest nu se putea verifica în niciun fel.
class CloudSyncService {
  CloudSyncService._();
  static final instance = CloudSyncService._();

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) => FirebaseFirestore.instance.collection('users').doc(uid);

  /// Blochează consumarea simultană a aceleiași cutii poștale. Pornirea
  /// aplicației și revenirea din fundal pot declanșa amândouă [consumePendingGrant]
  /// aproape în același timp (vezi main.dart); fără garda asta, ambele apucă să
  /// citească documentul înainte ca vreuna să-l șteargă, iar grant-ul se aplică
  /// de două ori — jucătorul primea dublu, iar un reset se aplica de două ori.
  bool _consumingGrant = false;

  /// Vezi [_consumingGrant] — același tipar. O trecere în fundal pe Android
  /// livrează `hidden` și `paused` sincron, una după alta (vezi main.dart), deci
  /// [push] era chemat de două ori: primul apel stătea în rețea când al doilea
  /// citea aceeași amprentă veche, și amândouă scriau documentul.
  bool _pushing = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _grantSub;

  /// Uid-ul identității curente — Google dacă e logat, altfel cel anonim
  /// creat la pornire (vezi main.dart). Gol dacă Firebase n-a pornit deloc pe
  /// platforma asta: accesul la FirebaseAuth.instance aruncă sincron în acel
  /// caz ("core/no-app"), iar [push] e apelat fără `await` din
  /// didChangeAppLifecycleState, deci excepția ar rămâne neprinsă — același
  /// motiv pentru care AuthService.currentUser își prinde singur excepția.
  String get _uid {
    try {
      return MultiplayerService.instance.currentPlayerId;
    } catch (e) {
      debugPrint('CloudSyncService._uid a esuat: $e');
      return '';
    }
  }

  /// Apelat imediat după logarea într-un cont Google care exista deja în altă
  /// parte. Dacă acel cont are progres salvat în cloud (de pe alt
  /// telefon/instalare), CLOUD-UL CÂȘTIGĂ — se suprascrie local cu el
  /// (decizie explicită, comportament standard de cloud save). Dacă nu are,
  /// progresul local curent se urcă și devine punctul de plecare.
  ///
  /// NU se apelează când contul Google tocmai s-a legat de identitatea
  /// anonimă de pe telefonul ăsta (același uid) — acolo local-ul e cel bun,
  /// vezi AuthService.signInWithGoogle.
  Future<void> pullOrSeed() async {
    final user = AuthService.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    try {
      final doc = await _userDoc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        await StorageService.importAll(doc.data()!);
      } else {
        await push();
      }
    } catch (e) {
      debugPrint('CloudSyncService.pullOrSeed a esuat: $e');
    }
  }

  /// Amprenta exactă a ceea ce s-ar urca acum: uid-ul + toate cheile locale,
  /// ordonate alfabetic ca două export-uri identice să dea mereu același șir.
  ///
  /// Uid-ul face parte din amprentă intenționat — la schimbarea identității
  /// (Guest care se conectează cu Google, sau delogare, care dă alt uid
  /// anonim) documentul destinație e altul, deci prima urcare pe el nu are
  /// voie să fie sărită, oricât de neschimbate ar fi datele.
  ///
  /// Se compară șirul întreg, nu un hash: o coliziune de hash ar însemna o
  /// urcare sărită pe tăcute, adică progres pierdut din cloud — exact felul
  /// de bug care iese la iveală abia când cineva chiar are nevoie de salvare.
  String _snapshotOf(String uid, Map<String, dynamic> data) =>
      jsonEncode({'uid': uid, 'data': SplayTreeMap<String, dynamic>.from(data)});

  /// Urcă progresul local — și pentru Guest, vezi comentariul clasei. No-op
  /// sigur dacă nu există nicio identitate (Firebase nepornit), deci se poate
  /// apela oricând fără ca apelantul să verifice starea de login.
  ///
  /// Sare peste scriere dacă de la ultima urcare nu s-a schimbat absolut
  /// nimic. Se apelează la fiecare trecere în fundal (vezi main.dart), deci
  /// fără verificarea asta orice sesiune în care jucătorul doar a deschis
  /// aplicația și a închis-o costa o scriere Firestore — înmulțit cu toți
  /// jucătorii, de câteva ori pe zi, pe planul gratuit.
  Future<void> push() async {
    final uid = _uid;
    // `_pushing`: o trecere în fundal pe Android livrează `hidden` apoi `paused`
    // sincron (vezi main.dart), amândouă chemând `push()` fără `await`. Fără
    // zăvorul ăsta, primul apel stă în rețea când al doilea citește aceeași
    // amprentă veche, și amândouă scriu `users/{uid}`.
    if (uid.isEmpty || _pushing) return;
    _pushing = true;
    try {
      final data = await StorageService.exportAll();
      final snapshot = _snapshotOf(uid, data);
      if (snapshot == await StorageService.getCloudPushSnapshot()) return;
      await _userDoc(uid).set(data);
      // Abia după ce scrierea a reușit — dacă pică (fără net), amprenta rămâne
      // cea veche și următoarea încercare reia urcarea, nu o sare.
      await StorageService.setCloudPushSnapshot(snapshot);
    } catch (e, s) {
      // Cel mai scump esec tacut din tot proiectul: jucatorul continua sa
      // joace crezand ca e salvat, si afla abia la reinstalare, cand pierde
      // tot. Vezi core/error_reporting.dart.
      reportError(e, s, unde: 'CloudSyncService.push');
    } finally {
      _pushing = false;
    }
  }

  /// Șterge cloud-save-ul privat (progres local urcat) + un eventual grant
  /// de admin în așteptare — apelat DOAR de [AuthService.deleteAccount] la
  /// ștergere definitivă de cont. Nu atinge progresul local de pe telefon;
  /// de asta se ocupă [AuthService.deleteAccount], și doar pentru Guest.
  ///
  /// Merge și pentru conturile anonime: un Guest are uid de la prima
  /// pornire și are deci `users/{uid}` de șters ca oricine altcineva.
  /// Sărea peste ele înainte, așa că un Guest nu avea nicio cale să-și
  /// șteargă datele din cloud (vezi [AuthService.deleteAccount]).
  Future<void> deleteCloudSave() async {
    // [_uid], nu AuthService.currentUser: acela întoarce null și pentru
    // identitatea anonimă, deci exact pentru Guest — cazul pentru care a fost
    // deschisă metoda asta — ștergerea ar fi fost sărită în tăcere.
    final uid = _uid;
    if (uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('admin_grants').doc(uid).delete();
    } catch (_) {
      // ignorat - fara grant in asteptare, e deja no-op.
    }
    try {
      await _userDoc(uid).delete();
    } catch (e) {
      debugPrint('CloudSyncService.deleteCloudSave a esuat: $e');
    }
  }

  /// Ascultă cutia poștală a acestui cont, ca resursele trimise de admin să
  /// intre în cont CÂT timp jucătorul e în joc — nu abia la următoarea
  /// pornire, cum era înainte.
  ///
  /// Se ignoră două feluri de snapshot-uri, amândouă produse de noi înșine:
  /// cele cu scrieri locale în așteptare, și cele în care documentul nu mai
  /// există — tranzacția de revendicare din [consumePendingGrant] tocmai l-a
  /// șters, deci ascultătorul se aprinde imediat după fiecare consum.
  void startLive() {
    final uid = _uid;
    if (uid.isEmpty) return;
    stopLive();
    try {
      _grantSub = FirebaseFirestore.instance
          .collection('admin_grants')
          .doc(uid)
          .snapshots()
          .listen((snap) {
        if (snap.metadata.hasPendingWrites) return;
        if (!snap.exists) return;
        consumePendingGrant();
      });
    } catch (e) {
      debugPrint('CloudSyncService.startLive a esuat: $e');
    }
  }

  void stopLive() {
    _grantSub?.cancel();
    _grantSub = null;
  }

  /// "Ridică" ce a lăsat adminul în cutia poștală a acestui cont (vezi
  /// AdminScreen + firestore.rules `admin_grants/{uid}`): un reset de cont,
  /// resurse, sau amândouă. Merge pentru ORICINE, Guest inclusiv — cutia
  /// poștală e legată de uid, iar un Guest are uid (anonim) de la prima
  /// pornire, deci nu are nevoie de cont Google ca să primească.
  ///
  /// No-op sigur dacă nu există identitate sau dacă nu e nimic în așteptare.
  /// Apelată alături de PlayerProfileService.ensureProfileHeartbeat
  /// (main.dart), deci rulează la fiecare pornire/revenire din fundal —
  /// ajunge la jucător cel târziu la următoarea deschidere, nu instant.
  Future<void> consumePendingGrant() async {
    final uid = _uid;
    if (uid.isEmpty || _consumingGrant) return;
    _consumingGrant = true;
    try {
      final ref = FirebaseFirestore.instance.collection('admin_grants').doc(uid);

      // REVENDICĂ grantul înainte să-l aplici: citește + șterge documentul
      // într-o singură tranzacție, abia apoi umblă la balanța locală. Garda
      // `_consumingGrant` protejează doar în cadrul aceluiași proces; dacă
      // aplicația era omorâtă între „aplică local" și „șterge documentul"
      // (frecvent pe Android), grantul rămânea în cutia poștală și se aplica
      // din nou la următoarea pornire — jucătorul primea de două ori. Acum,
      // dacă tranzacția reușește, documentul e deja șters când începe
      // aplicarea; dacă procesul moare după aceea, grantul se pierde (rar,
      // și preferabil unei dublări de monede reale).
      final Map<String, dynamic> data;
      try {
        data = await FirebaseFirestore.instance.runTransaction((tx) async {
          final snap = await tx.get(ref);
          if (!snap.exists) return const <String, dynamic>{};
          tx.delete(ref);
          return snap.data() ?? const <String, dynamic>{};
        });
      } catch (e) {
        debugPrint('CloudSyncService.consumePendingGrant: revendicarea a esuat: $e');
        return;
      }
      if (data.isEmpty) return;

      // ÎNTÂI resetul, abia apoi resursele: dacă adminul a resetat contul și
      // i-a trimis apoi și ceva de pornire, jucătorul trebuie să rămână cu
      // acel ceva, nu să i-l șteargă resetul aplicat după. (Resursele trimise
      // ÎNAINTE de reset nu supraviețuiesc — cererea de reset le suprascrie
      // în cutia poștală, vezi PlayerProfileService.resetPlayer.)
      final reset = data['reset'] == true;
      if (reset) await StorageService.resetToStartingBalance();

      final hearts = data['hearts'] as int? ?? 0;
      final hints = data['hints'] as int? ?? 0;
      final coins = data['coins'] as int? ?? 0;
      final gems = data['gems'] as int? ?? 0;
      final xp = data['xp'] as int? ?? 0;
      // hearts foloseste getLives/setLives (nu exista un StorageService.adjustLives
      // dedicat - setLives deja clampeaza sub 0, la fel ca restul adjust*-urilor).
      if (hearts != 0) await StorageService.setLives(await StorageService.getLives() + hearts);
      if (hints != 0) await StorageService.adjustHints(hints);
      if (coins != 0) await StorageService.adjustCoins(coins);
      if (gems != 0) await StorageService.adjustGems(gems);
      if (xp != 0) await StorageService.adjustXp(xp);

      // „Felicitări, ai primit..." — compusă din ce s-a aplicat EFECTIV, nu
      // din ce a apăsat adminul. Id-ul stabil (uid + momentul cererii)
      // împiedică notificarea să apară de două ori pentru același cadou.
      //
      // Fără ea, resursele intrau în cont în tăcere: jucătorul vedea altă
      // balanță decât și-o amintea și n-avea de unde să afle de ce.
      //
      // Id-ul vine din marcajul de timp pus de admin la trimitere
      // (`sentAt`/`resetRequestedAt`, vezi AdminScreen), NU din id-ul
      // documentului: acela e chiar uid-ul jucătorului, deci ar fi fost
      // același pentru toate cadourile lui, iar al doilea „+100 monede"
      // trimis vreodată n-ar mai fi produs nicio notificare. Pentru un grant
      // vechi, rămas în cutie de dinaintea acestui cod, se cade pe momentul
      // consumării — unic prin construcție.
      final sentAt = (data['sentAt'] as Timestamp?) ?? (data['resetRequestedAt'] as Timestamp?);
      await NotificationService.instance.addGrantNotification(
        grantId: '${sentAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}',
        hearts: hearts,
        hints: hints,
        coins: coins,
        gems: gems,
        xp: xp,
        wasReset: reset,
      );

      // (documentul admin_grants a fost deja șters în tranzacția de
      // revendicare de la începutul funcției)

      // Balanța se anunță acum singură din StorageService: consumePendingGrant
      // trece prin adjustCoins/adjustGems/setLives/adjustHints/adjustXp și
      // resetToStartingBalance, toate cu bump pe balanceRevision — ecranele
      // deschise ascultă direct acolo.

      if (reset) {
        // Profilul public a fost deja pus la zero de admin; heartbeat-ul de
        // aici doar confirmă starea nouă a telefonului (contorul de
        // activitate golit de reset), altfel ar rămâne în profil valoarea de
        // dinainte până la următoarea pornire.
        await PlayerProfileService.instance.ensureProfileHeartbeat();
        await push();
      }
    } catch (e) {
      debugPrint('CloudSyncService.consumePendingGrant a esuat: $e');
    } finally {
      _consumingGrant = false;
    }
  }
}
