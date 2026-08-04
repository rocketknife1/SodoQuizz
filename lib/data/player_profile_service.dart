import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/player_profile.dart';
import 'auth_service.dart';
import 'multiplayer_service.dart';
import 'storage_service.dart';

/// Rezultatul unei [PlayerProfileService.sendFriendRequest] — UI-ul arată un
/// mesaj diferit pentru fiecare caz.
enum FriendRequestOutcome { sent, autoAccepted, alreadyFriends, notFound, isSelf }

/// Profilul public (leaderboard, ligă, statistici) — separat de
/// CloudSyncService (acela e privat, doar cloud-save de progres local pentru
/// conturi Google). Acesta scrie pentru ORICE identitate (Google sau
/// anonimă/Guest — vezi MultiplayerService.currentPlayerId), fiindcă
/// intenția e ca toți userii care au intrat vreodată în joc să apară în
/// leaderboard, nu doar cei logați cu Google.
class PlayerProfileService {
  PlayerProfileService._();
  static final instance = PlayerProfileService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => _db.collection('player_profiles');

  /// Userii inactivi de mai mult timp dispar din LISTA leaderboard-ului
  /// (filtrare client-side, ca _openRoomFreshness din multiplayer_service.dart)
  /// dar doc-ul lor nu se șterge niciodată — punctele revin vizibile automat
  /// dacă redevin activi (heartbeat-ul le actualizează lastActive).
  static const leaderboardFreshness = Duration(days: 3);

  /// Numere de playtesting, nu literă de lege — puncte de ligă cumulate pe
  /// viață (fără sezoane în v1).
  static const winPoints = 20;
  static const lossPoints = 8;

  /// Prag pentru curățarea conturilor Guest abandonate — vezi
  /// [_sweepStaleGuests]. Ținut și în firestore.rules (regula de `allow
  /// delete`) — dacă îl schimbi aici, schimbă-l și acolo.
  ///
  /// Se șterge DOAR contul complet gol: fără cont Google, fără niciun meci,
  /// fără niciun semn de activitate (vezi StorageService.getActivityEvents —
  /// o rotire de roată sau orice mișcare de balanță ajunge ca să fie păstrat
  /// definitiv) și neatins de [guestSweepInactivity]. Cine a apucat să facă
  /// măcar ceva rămâne, oricât ar lipsi — pierderea unui jucător real e mult
  /// mai scumpă decât un document rămas degeaba în bază.
  static const guestSweepInactivity = Duration(days: 15);

  bool _sweptStaleGuestsThisSession = false;

  String get _uid => MultiplayerService.instance.currentPlayerId;

  /// Scrie/actualizează identitatea publică + "ultima activitate" — apelată
  /// la pornirea aplicației (după ce identitatea anonimă/Google există deja,
  /// vezi main.dart) și la fiecare revenire din fundal. `merge: true` ca să
  /// nu suprascrie statisticile deja acumulate (wins/matchesPlayed/...),
  /// doar câmpurile de identitate + timestamp.
  Future<void> ensureProfileHeartbeat() async {
    final uid = _uid;
    if (uid.isEmpty) return;
    try {
      final identity = await AuthService.instance.multiplayerIdentity();
      final ref = _col.doc(uid);
      // Citire prealabilă doar ca sa stim daca documentul e nou - necesar
      // pentru createdAt (vezi mai jos), care trebuie scris o SINGURA data,
      // niciodata rescris la heartbeat-urile ulterioare (spre deosebire de
      // restul campurilor din acest merge, care se rescriu mereu).
      final isNew = !(await ref.get()).exists;
      await ref.set({
        'name': identity.name,
        'photoUrl': identity.photoUrl,
        'avatarSeed': uid,
        'lastActive': FieldValue.serverTimestamp(),
        'hasGoogleAccount': AuthService.instance.isSignedIn,
        if (isNew) 'createdAt': FieldValue.serverTimestamp(),
        // Contorul local de semne de activitate (roată învârtită, balanță
        // mișcată) — urcat aici fiindca stergerea automata a Guest-ilor
        // abandonati se decide in firestore.rules, care poate citi DOAR
        // profilul public, nu si salvarea privata din `users/{uid}`. E un
        // simplu numar de interactiuni, nu o balanta — oglindirea balantei
        // in profilul public a fost respinsa explicit (ar fi facut-o
        // vizibila tuturor jucatorilor, vezi firestore.rules).
        'activityEvents': await StorageService.getActivityEvents(),
        // increment(0) creează câmpul pe 0 dacă lipsește (jucător nou) și nu
        // atinge valoarea deja acumulată dacă există — necesar fiindcă
        // Firestore EXCLUDE din orderBy('leaguePoints', ...) orice document
        // căruia îi lipsește total acel câmp, deci un jucător care doar a
        // deschis aplicația (fără niciun meci jucat încă) ar rămâne invizibil
        // în leaderboard fără asta.
        'leaguePoints': FieldValue.increment(0),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('PlayerProfileService.ensureProfileHeartbeat a esuat: $e');
    }
  }

  /// Scrie rezultatul unui meci ÎNCHEIAT NORMAL (nu un abandon devreme —
  /// vezi hook-ul din MultiplayerResultsScreen) pe profilul PROPRIU, singurul
  /// doc pe care avem voie să scriem (vezi firestore.rules). Fiecare jucător
  /// își scrie doar rezultatul lui — nu există o singură sursă de adevăr
  /// server-side, fără Cloud Functions în acest proiect, la fel ca restul
  /// multiplayer-ului (ex. attemptFormMatch în multiplayer_service.dart).
  Future<void> recordMatchResult({
    required String gameModeId,
    required bool won,
    required bool draw,
  }) async {
    final uid = _uid;
    if (uid.isEmpty) return;
    final delta = won ? winPoints : (draw ? 0 : -lossPoints);
    try {
      await _db.runTransaction((tx) async {
        final ref = _col.doc(uid);
        final snap = await tx.get(ref);
        final data = snap.data() ?? const <String, dynamic>{};
        final prevStreak = data['currentStreak'] as int? ?? 0;
        final currentStreak = won ? prevStreak + 1 : 0;
        final longestStreak = max(data['longestStreak'] as int? ?? 0, currentStreak);
        final leaguePoints = max(0, (data['leaguePoints'] as int? ?? 0) + delta);
        final breakdown = Map<String, int>.from(data['modeBreakdown'] as Map? ?? const {});
        breakdown[gameModeId] = (breakdown[gameModeId] ?? 0) + delta;
        tx.set(ref, {
          'matchesPlayed': (data['matchesPlayed'] as int? ?? 0) + 1,
          'wins': (data['wins'] as int? ?? 0) + (won ? 1 : 0),
          'losses': (data['losses'] as int? ?? 0) + (!won && !draw ? 1 : 0),
          'currentStreak': currentStreak,
          'longestStreak': longestStreak,
          'leaguePoints': leaguePoints,
          'modeBreakdown': breakdown,
          'lastActive': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('PlayerProfileService.recordMatchResult a esuat: $e');
    }
  }

  /// Înregistrează O SINGURĂ dată per meci (doc id = [matchId], deci apelul
  /// independent al fiecărui jucător pentru ACELAȘI meci converge în
  /// același document — merge:true, idempotent, nu se dublează) că un meci
  /// s-a încheiat normal, cu cel puțin 2 jucători reali. Fără asta, singura
  /// cifră disponibilă era matchesPlayed per jucător (vezi recordMatchResult
  /// mai jos), care numără fiecare meci de N ori — o dată per participant —
  /// nepotrivit pentru "câte meciuri au fost jucate în total" (vezi
  /// AdminScreen, tab Statistici). No-op dacă meciul n-a avut măcar 2
  /// jucători (ex. adversarul a plecat înainte de final).
  Future<void> recordCompletedMatch({required String matchId, required String gameModeId, required int playerCount}) async {
    if (playerCount < 2) return;
    try {
      await _db.collection('completed_matches').doc(matchId).set({
        'gameModeId': gameModeId,
        'playerCount': playerCount,
        'finishedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('PlayerProfileService.recordCompletedMatch a esuat: $e');
    }
  }

  /// Numărul TOTAL de meciuri multiplayer încheiate normal între cel puțin
  /// 2 jucători — agregare reală pe server (`.count()`), spre deosebire de
  /// [fetchAllPlayers]/[fetchLeaderboard], care sunt plafonate la 300 de
  /// documente citite efectiv. Folosit de AdminScreen, tab Statistici.
  Future<int> fetchCompletedMatchesCount() async {
    try {
      final agg = await _db.collection('completed_matches').count().get();
      return agg.count ?? 0;
    } catch (e) {
      debugPrint('PlayerProfileService.fetchCompletedMatchesCount a esuat: $e');
      return 0;
    }
  }

  Future<PlayerProfile?> getProfile(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final doc = await _col.doc(uid).get();
      if (!doc.exists) return null;
      return PlayerProfile.fromDoc(doc);
    } catch (e) {
      debugPrint('PlayerProfileService.getProfile a esuat: $e');
      return null;
    }
  }

  Future<PlayerProfile?> getMyProfile() => getProfile(_uid);

  CollectionReference<Map<String, dynamic>> _friendsCol(String uid) => _col.doc(uid).collection('friends');
  CollectionReference<Map<String, dynamic>> _requestsCol(String uid) => _col.doc(uid).collection('friend_requests');

  /// Alfabet fără caractere ușor confundabile la dictare/tastare manuală
  /// (fără 0/O, 1/I).
  static const _friendCodeAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  Future<String> _generateUniqueFriendCode() async {
    final rnd = Random();
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = List.generate(6, (_) => _friendCodeAlphabet[rnd.nextInt(_friendCodeAlphabet.length)]).join();
      final existing = await _col.where('friendCode', isEqualTo: code).limit(1).get();
      if (existing.docs.isEmpty) return code;
    }
    // extrem de improbabil de ajuns aici (coliziune de 5 ori la rând) — cod
    // mai lung, ca să nu mai fie nevoie de alt query de verificare.
    return List.generate(9, (_) => _friendCodeAlphabet[rnd.nextInt(_friendCodeAlphabet.length)]).join();
  }

  /// Codul propriu de prietenie — generat o singură dată, lazy, la prima
  /// vizită pe ecranul de Prieteni (nu la heartbeat, ca să nu adauge un
  /// read în plus la fiecare pornire/revenire din fundal a aplicației).
  Future<String?> getOrCreateFriendCode() async {
    final uid = _uid;
    if (uid.isEmpty) return null;
    try {
      final ref = _col.doc(uid);
      final snap = await ref.get();
      final existing = snap.data()?['friendCode'] as String?;
      if (existing != null && existing.isNotEmpty) return existing;
      final code = await _generateUniqueFriendCode();
      await ref.set({'friendCode': code}, SetOptions(merge: true));
      return code;
    } catch (e) {
      debugPrint('PlayerProfileService.getOrCreateFriendCode a esuat: $e');
      return null;
    }
  }

  Future<PlayerProfile?> findByFriendCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    try {
      final snap = await _col.where('friendCode', isEqualTo: normalized).limit(1).get();
      if (snap.docs.isEmpty) return null;
      return PlayerProfile.fromDoc(snap.docs.first);
    } catch (e) {
      debugPrint('PlayerProfileService.findByFriendCode a esuat: $e');
      return null;
    }
  }

  /// Trimite o cerere de prietenie către jucătorul cu [code]. Dacă acela ne-a
  /// trimis deja o cerere (ambii au tastat codul unul altuia aproape
  /// simultan), acceptă direct în loc să creeze o a doua cerere în sens
  /// opus — evită cereri orfane.
  Future<FriendRequestOutcome> sendFriendRequest(String code) async {
    final me = _uid;
    if (me.isEmpty) return FriendRequestOutcome.notFound;
    final target = await findByFriendCode(code);
    if (target == null) return FriendRequestOutcome.notFound;
    if (target.uid == me) return FriendRequestOutcome.isSelf;
    try {
      final alreadyFriend = await _friendsCol(me).doc(target.uid).get();
      if (alreadyFriend.exists) return FriendRequestOutcome.alreadyFriends;
      final incoming = await _requestsCol(me).doc(target.uid).get();
      if (incoming.exists) {
        await acceptFriendRequest(target.uid);
        return FriendRequestOutcome.autoAccepted;
      }
      final myProfile = await getMyProfile();
      await _requestsCol(target.uid).doc(me).set({
        'fromName': myProfile?.name ?? '?',
        'fromAvatarSeed': myProfile?.avatarSeed ?? me,
        'fromPhotoUrl': myProfile?.photoUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return FriendRequestOutcome.sent;
    } catch (e) {
      debugPrint('PlayerProfileService.sendFriendRequest a esuat: $e');
      return FriendRequestOutcome.notFound;
    }
  }

  /// Acceptă o cerere primită de la [fromUid] — scrie ambele documente
  /// "oglindă" din `friends` (pe profilul propriu ȘI pe al celuilalt) și
  /// șterge cererea, într-un singur batch.
  Future<void> acceptFriendRequest(String fromUid) async {
    final me = _uid;
    if (me.isEmpty) return;
    try {
      final batch = _db.batch();
      batch.set(_friendsCol(me).doc(fromUid), {'addedAt': FieldValue.serverTimestamp()});
      batch.set(_friendsCol(fromUid).doc(me), {'addedAt': FieldValue.serverTimestamp()});
      batch.delete(_requestsCol(me).doc(fromUid));
      await batch.commit();
    } catch (e) {
      debugPrint('PlayerProfileService.acceptFriendRequest a esuat: $e');
    }
  }

  Future<void> declineFriendRequest(String fromUid) async {
    final me = _uid;
    if (me.isEmpty) return;
    try {
      await _requestsCol(me).doc(fromUid).delete();
    } catch (e) {
      debugPrint('PlayerProfileService.declineFriendRequest a esuat: $e');
    }
  }

  Future<void> removeFriend(String friendUid) async {
    final me = _uid;
    if (me.isEmpty) return;
    try {
      final batch = _db.batch();
      batch.delete(_friendsCol(me).doc(friendUid));
      batch.delete(_friendsCol(friendUid).doc(me));
      await batch.commit();
    } catch (e) {
      debugPrint('PlayerProfileService.removeFriend a esuat: $e');
    }
  }

  /// Profilurile complete ale prietenilor acceptați — id-urile vin din
  /// subcolecția proprie `friends`, statisticile sunt cerute live prin
  /// [getProfile] (nu denormalizate), ca lista să nu rămână cu scoruri vechi.
  Future<List<PlayerProfile>> fetchFriends() async {
    final me = _uid;
    if (me.isEmpty) return [];
    try {
      final snap = await _friendsCol(me).get();
      final profiles = await Future.wait(snap.docs.map((d) => getProfile(d.id)));
      return profiles.whereType<PlayerProfile>().toList();
    } catch (e) {
      debugPrint('PlayerProfileService.fetchFriends a esuat: $e');
      return [];
    }
  }

  /// Prietenii ORICUI, nu doar ai contului curent — pentru ecranul de detaliu
  /// din AdminScreen. Citirea subcolecției `friends` e permisă oricui e
  /// autentificat (vezi firestore.rules), deci nu cere drepturi speciale.
  Future<List<PlayerProfile>> fetchFriendsOf(String uid) async {
    if (uid.isEmpty) return [];
    try {
      final snap = await _friendsCol(uid).get();
      final profiles = await Future.wait(snap.docs.map((d) => getProfile(d.id)));
      return profiles.whereType<PlayerProfile>().toList();
    } catch (e) {
      debugPrint('PlayerProfileService.fetchFriendsOf a esuat: $e');
      return [];
    }
  }

  /// Cloud-save-ul privat al unui jucător (`users/{uid}`) — DOAR pentru
  /// AdminScreen. Regula din firestore.rules dă drept de citire exclusiv
  /// emailului de admin; pentru oricine altcineva apelul eșuează cu
  /// permission-denied și se întoarce null, ceea ce e comportamentul dorit.
  ///
  /// Null = jucătorul n-a apucat încă să urce nimic. Se întâmplă la un cont
  /// abia creat (documentul se scrie prima oară când trimite aplicația în
  /// fundal) sau la un Guest care nu a mai deschis jocul de dinainte ca
  /// Guest-ii să urce și ei (vezi CloudSyncService.push) — NU mai înseamnă
  /// "cont Guest", ca înainte.
  Future<Map<String, dynamic>?> fetchCloudSaveAsAdmin(String uid) async {
    if (uid.isEmpty) return null;
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return doc.data();
    } catch (e) {
      debugPrint('PlayerProfileService.fetchCloudSaveAsAdmin a esuat: $e');
      return null;
    }
  }

  Future<List<FriendRequest>> fetchIncomingRequests() async {
    final me = _uid;
    if (me.isEmpty) return [];
    try {
      final snap = await _requestsCol(me).orderBy('createdAt', descending: true).get();
      return snap.docs.map(FriendRequest.fromDoc).toList();
    } catch (e) {
      debugPrint('PlayerProfileService.fetchIncomingRequests a esuat: $e');
      return [];
    }
  }

  /// Folosit pentru bulina roșie de pe rândul "Prieteni" din Profil (același
  /// tipar ca StorageService.hasClaimableAchievements).
  Future<int> pendingFriendRequestCount() async {
    final me = _uid;
    if (me.isEmpty) return 0;
    try {
      final snap = await _requestsCol(me).get();
      return snap.docs.length;
    } catch (e) {
      debugPrint('PlayerProfileService.pendingFriendRequestCount a esuat: $e');
      return 0;
    }
  }

  /// Leaderboard global — top [limit] după puncte de ligă, filtrat la userii
  /// activi în ultimele [leaderboardFreshness] (client-side, fără index
  /// compus, fără Cloud Functions).
  Future<List<PlayerProfile>> fetchLeaderboard({int limit = 100}) async {
    unawaited(_sweepStaleGuests());
    try {
      final snap = await _col.orderBy('leaguePoints', descending: true).limit(limit).get();
      final cutoff = DateTime.now().subtract(leaderboardFreshness);
      return snap.docs
          .map(PlayerProfile.fromDoc)
          .where((p) => p.lastActive != null && p.lastActive!.toDate().isAfter(cutoff))
          .toList();
    } catch (e) {
      debugPrint('PlayerProfileService.fetchLeaderboard a esuat: $e');
      return [];
    }
  }

  /// TOȚI jucătorii înregistrați vreodată, fără filtrul de prospețime din
  /// [fetchLeaderboard] — pentru tab-ul "Toți jucătorii", care arată și data
  /// ultimei prezențe online a fiecăruia (spre deosebire de leaderboard-ul
  /// filtrat, unde absența acelui timestamp nu contează pentru că oricum
  /// sunt toți activi recent).
  Future<List<PlayerProfile>> fetchAllPlayers({int limit = 300}) async {
    unawaited(_sweepStaleGuests());
    try {
      final snap = await _col.orderBy('leaguePoints', descending: true).limit(limit).get();
      return snap.docs.map(PlayerProfile.fromDoc).toList();
    } catch (e) {
      debugPrint('PlayerProfileService.fetchAllPlayers a esuat: $e');
      return [];
    }
  }

  /// TOȚI jucătorii al căror profil a fost creat azi (dată calendaristică
  /// locală) — pentru tab-ul "Noi azi" din AdminScreen. Filtrare+sortare pe
  /// același câmp (`createdAt`), deci nu are nevoie de index compus.
  /// Profilurile create înainte de introducerea acestui câmp (fără
  /// migrare retroactivă, vezi PlayerProfile.createdAt) nu apar niciodată
  /// aici, indiferent cât de recent au fost active.
  Future<List<PlayerProfile>> fetchNewPlayersToday() async {
    try {
      final now = DateTime.now();
      final startOfDay = Timestamp.fromDate(DateTime(now.year, now.month, now.day));
      final snap = await _col.where('createdAt', isGreaterThanOrEqualTo: startOfDay).orderBy('createdAt', descending: true).get();
      return snap.docs.map(PlayerProfile.fromDoc).toList();
    } catch (e) {
      debugPrint('PlayerProfileService.fetchNewPlayersToday a esuat: $e');
      return [];
    }
  }

  /// Interzice definitiv un cont (AdminScreen, tab Jucători) — șterge
  /// profilul public (dispare imediat din leaderboard/"Toți jucătorii"; și
  /// din listele de prieteni ale altora, vezi [fetchFriends], care ignoră
  /// id-uri fără profil viu) și marchează uid-ul în `banned_players`, ca
  /// firestore.rules să-i refuze proprietarului orice scriere ulterioară pe
  /// `player_profiles/{uid}` — fără asta, următorul heartbeat al contului
  /// banat și-ar recrea singur profilul. Nu atinge `users/{uid}` (cloud-save
  /// privat) sau meciurile din `matches` — vezi domeniul ales în plan.
  Future<bool> banPlayer(String uid, {required String name}) async {
    if (uid.isEmpty) return false;
    try {
      final batch = _db.batch();
      batch.delete(_col.doc(uid));
      batch.set(_db.collection('banned_players').doc(uid), {
        'bannedAt': FieldValue.serverTimestamp(),
        'bannedName': name,
      });
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('PlayerProfileService.banPlayer a esuat: $e');
      return false;
    }
  }

  /// Șterge TOT ce ține de un cont, inițiat de admin (AdminScreen, tab
  /// Jucători) — spre deosebire de [banPlayer], care doar îl scoate din
  /// leaderboard și îi blochează recrearea profilului.
  ///
  /// Dispare: profilul public, legăturile de prietenie în ambele sensuri,
  /// cererile de prietenie primite, salvarea din cloud (`users/{uid}`), un
  /// eventual grant de resurse în așteptare și marcajul de ban. Funcționează
  /// identic pentru Guest și pentru conturi Google.
  ///
  /// Contul din Firebase **Authentication** nu poate fi șters de aici: un
  /// client n-are voie să șteargă contul altcuiva, operația cere Admin SDK,
  /// iar proiectul e pe planul gratuit (fără Cloud Functions). De-aia uid-ul
  /// se notează în `pending_auth_deletions`, iar `tools/purge_accounts.py`
  /// termină treaba la următoarea rulare. Până atunci contul rămâne în Auth,
  /// dar fără absolut nicio dată legată de el.
  ///
  /// Ștergerea pornită de jucătorul însuși (Profil → Șterge contul) nu are
  /// nevoie de coada asta — acolo `user.delete()` chiar șterge contul Auth,
  /// fiindcă îl șterge pe al lui.
  Future<bool> purgePlayer(String uid, {required String name}) async {
    if (uid.isEmpty) return false;
    try {
      final batch = _db.batch();

      final friendsSnap = await _friendsCol(uid).get();
      for (final doc in friendsSnap.docs) {
        batch.delete(doc.reference);
        batch.delete(_friendsCol(doc.id).doc(uid)); // oglinda din lista celuilalt
      }
      final requestsSnap = await _requestsCol(uid).get();
      for (final doc in requestsSnap.docs) {
        batch.delete(doc.reference);
      }

      batch.delete(_col.doc(uid));
      batch.delete(_db.collection('users').doc(uid));
      batch.delete(_db.collection('admin_grants').doc(uid));
      batch.delete(_db.collection('banned_players').doc(uid));

      batch.set(_db.collection('pending_auth_deletions').doc(uid), {
        'name': name,
        'requestedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('PlayerProfileService.purgePlayer a esuat: $e');
      return false;
    }
  }

  /// Aduce un cont la zero, din fișa jucătorului (AdminScreen) — pentru
  /// ORICINE, Guest sau cont Google, fiindcă ambele jumătăți ale operației se
  /// leagă de uid, nu de tipul contului.
  ///
  /// Se întâmplă în doi timpi, cu viteze diferite, și e important de știut la
  /// ce te uiți după apăsare:
  ///  1. IMEDIAT, aici: profilul public (puncte de ligă, meciuri, victorii,
  ///     serii, defalcarea pe moduri) se pune pe zero, deci jucătorul pică
  ///     instant la coada clasamentului. Documentul NU se șterge — numele,
  ///     prietenii și codul de prieten rămân, contul e resetat, nu desființat.
  ///  2. LA URMĂTOAREA DESCHIDERE a jocului de către el: telefonul lui își
  ///     golește progresul local și revine la zestrea de start (vezi
  ///     StorageService.resetToStartingBalance). Progresul stă în
  ///     SharedPreferences, pe telefon — nimeni nu-l poate șterge de la
  ///     distanță, deci cererea se lasă în aceeași cutie poștală ca
  ///     grant-urile de resurse și se aplică singură când ajunge acolo.
  ///
  /// Cererea se scrie fără `merge`, deliberat: dacă în cutie mai era un grant
  /// de resurse neridicat, resetul îl anulează. Altfel "l-am adus la zero" ar
  /// fi fost urmat, în aceeași secundă, de 5000 de monede trimise săptămâna
  /// trecută și uitate.
  Future<bool> resetPlayer(String uid) async {
    if (uid.isEmpty) return false;
    try {
      final batch = _db.batch();
      batch.set(_col.doc(uid), {
        'matchesPlayed': 0,
        'wins': 0,
        'losses': 0,
        'currentStreak': 0,
        'longestStreak': 0,
        'leaguePoints': 0,
        'modeBreakdown': <String, int>{},
        'activityEvents': 0,
      }, SetOptions(merge: true));
      batch.set(_db.collection('admin_grants').doc(uid), {
        'reset': true,
        'resetRequestedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('PlayerProfileService.resetPlayer a esuat: $e');
      return false;
    }
  }

  /// Conturile care așteaptă ștergerea din Firebase Authentication — afișate
  /// pe nume în AdminScreen (tab Statistici), nu doar numărate, ca să se vadă
  /// exact CINE e în coadă înainte de a rula scriptul care șterge definitiv.
  /// Vezi [PendingAuthDeletion] pentru de ce e nevoie de coadă.
  ///
  /// Cele mai recente primele. Fără `orderBy` pe server: coada are în mod
  /// normal câteva intrări, iar un `orderBy` ar cere ca fiecare document să
  /// aibă câmpul, ceea ce ar ascunde tăcut intrările vechi, scrise înainte ca
  /// `requestedAt` să existe.
  Future<List<PendingAuthDeletion>> fetchPendingAuthDeletions() async {
    try {
      final snap = await _db.collection('pending_auth_deletions').limit(100).get();
      final items = snap.docs.map(PendingAuthDeletion.fromDoc).toList();
      items.sort((a, b) {
        final ta = a.requestedAt, tb = b.requestedAt;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
      return items;
    } catch (e) {
      debugPrint('PlayerProfileService.fetchPendingAuthDeletions a esuat: $e');
      return [];
    }
  }

  /// Șterge definitiv profilul public + toate legăturile de prietenie ale
  /// contului curent — apelat DOAR de [AuthService.deleteAccount] la ștergere
  /// definitivă de cont, spre deosebire de [banPlayer] (inițiat de admin, nu
  /// atinge subcolecțiile de prietenie). Curăță și oglinzile din listele de
  /// prieteni ale celorlalți (`player_profiles/{friendUid}/friends/{uid}`),
  /// permis de firestore.rules pentru oricare din cele două uid-uri
  /// implicate — altfel userul șters ar rămâne "fantomă" în lista lor.
  /// Cererile de prietenie trimise altora (nu primite) nu sunt urmărite
  /// separat aici (ar necesita un collection-group query) — rămân orfane,
  /// la fel de inofensive ca orice cerere neacceptată niciodată.
  Future<void> deleteMyProfile() async {
    final uid = _uid;
    if (uid.isEmpty) return;
    try {
      final batch = _db.batch();
      final friendsSnap = await _friendsCol(uid).get();
      for (final doc in friendsSnap.docs) {
        batch.delete(doc.reference);
        batch.delete(_friendsCol(doc.id).doc(uid));
      }
      final requestsSnap = await _requestsCol(uid).get();
      for (final doc in requestsSnap.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_col.doc(uid));
      await batch.commit();
    } catch (e) {
      debugPrint('PlayerProfileService.deleteMyProfile a esuat: $e');
    }
  }

  /// Curățare oportunistă a conturilor Guest abandonate — rulează cel mult o
  /// dată pe sesiune (nu la fiecare deschidere a leaderboard-ului), fără
  /// blocarea UI-ului (fire-and-forget din [fetchLeaderboard]). Fără Cloud
  /// Functions în acest proiect (vezi memoria de deploy), orice client activ
  /// face treaba asta.
  ///
  /// Se șterge STRICT contul rămas gol — vezi [guestSweepInactivity] pentru
  /// criteriul complet și de ce e atât de conservator. Odată dispărut,
  /// contul nu mai e verificat niciodată (nu mai există ce verifica): nu
  /// rămâne nicio urmă care să-l readucă în listă, iar identitatea anonimă
  /// din Auth e legată de instalarea aceea, deci nici ea nu se mai întoarce.
  ///
  /// Se șterg amândouă documentele legate de cont, într-un batch atomic:
  /// profilul public și salvarea din cloud (`users/{uid}`, pe care Guest-ii
  /// o au și ei de la [CloudSyncService.push]). firestore.rules verifică
  /// independent, pentru fiecare, exact aceleași condiții — un client
  /// modificat nu poate șterge profilul altcuiva oricât ar încerca; dacă
  /// nu-s întrunite, batch-ul pică întreg cu permission-denied, e prins mai
  /// jos și nimic nu se strică.
  ///
  /// Ce NU se atinge: contul anonim din Firebase Authentication (ar cere
  /// Admin SDK, imposibil dintr-un alt client — dar rămâne inert, fără nicio
  /// dată legată de el) și meciurile vechi din `matches` (curățare separată,
  /// deja notată ca lucru viitor).
  Future<void> _sweepStaleGuests() async {
    if (_sweptStaleGuestsThisSession) return;
    _sweptStaleGuestsThisSession = true;
    try {
      final cutoff = DateTime.now().subtract(guestSweepInactivity);
      final snap = await _col.where('lastActive', isLessThan: Timestamp.fromDate(cutoff)).limit(300).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['hasGoogleAccount'] == true) continue;
        if ((data['matchesPlayed'] as int? ?? 0) > 0) continue;
        // Lipsa câmpului = profil scris înainte de introducerea contorului,
        // deci tratat ca 0. Nu e o regresie față de criteriul dinainte (care
        // ștergea sub 3 meciuri, fără să se uite deloc la activitate) și se
        // corectează singur: primul heartbeat de după actualizare urcă
        // numărul real, iar contul devine intangibil.
        if ((data['activityEvents'] as int? ?? 0) > 0) continue;
        try {
          final batch = _db.batch();
          batch.delete(doc.reference);
          batch.delete(_db.collection('users').doc(doc.id));
          await batch.commit();
        } catch (e) {
          debugPrint('PlayerProfileService._sweepStaleGuests a esuat la stergerea ${doc.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('PlayerProfileService._sweepStaleGuests a esuat: $e');
    }
  }
}
