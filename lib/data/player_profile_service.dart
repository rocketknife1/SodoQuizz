import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/player_profile.dart';
import 'auth_service.dart';
import 'multiplayer_service.dart';

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

  /// Praguri pentru curățarea conturilor Guest abandonate — vezi
  /// [_sweepStaleGuests]. Un cont e eligibil pentru ștergere doar dacă
  /// întrunește AMBELE condiții: inactiv de [guestSweepInactivity] ȘI sub
  /// [guestSweepMinMatches] meciuri jucate vreodată. Ținute și în
  /// firestore.rules (regula de `allow delete`) — dacă schimbi pragul aici,
  /// schimbă-l și acolo.
  static const guestSweepInactivity = Duration(days: 15);
  static const guestSweepMinMatches = 3;

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
      await _col.doc(uid).set({
        'name': identity.name,
        'photoUrl': identity.photoUrl,
        'avatarSeed': uid,
        'lastActive': FieldValue.serverTimestamp(),
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

  /// Curățare oportunistă a conturilor Guest abandonate — rulează cel mult o
  /// dată pe sesiune (nu la fiecare deschidere a leaderboard-ului), fără
  /// blocarea UI-ului (fire-and-forget din [fetchLeaderboard]). Fără Cloud
  /// Functions în acest proiect (vezi memoria de deploy), orice client activ
  /// face treaba asta — firestore.rules permite ștergerea unui document
  /// STRĂIN doar dacă întrunește exact condiția (nu are cont Google legat,
  /// inactiv 15+ zile, sub pragul de meciuri), deci nu poate fi abuzat pentru
  /// a șterge alte profiluri. Șterge DOAR documentul din `player_profiles`
  /// (leaderboard/profil public) — contul anonim din Firebase Authentication
  /// nu poate fi șters dintr-un alt client (ar necesita Admin SDK), dar
  /// rămâne fără nicio dată vizibilă/legată de el odată ce documentul
  /// dispare. Meciurile vechi din `matches` nu sunt atinse aici (curățare
  /// separată, deja flagged ca lucru viitor).
  Future<void> _sweepStaleGuests() async {
    if (_sweptStaleGuestsThisSession) return;
    _sweptStaleGuestsThisSession = true;
    try {
      final cutoff = DateTime.now().subtract(guestSweepInactivity);
      final snap = await _col.where('lastActive', isLessThan: Timestamp.fromDate(cutoff)).limit(300).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final matchesPlayed = data['matchesPlayed'] as int? ?? 0;
        if (matchesPlayed >= guestSweepMinMatches) continue;
        try {
          // firestore.rules verifică independent (din nou) că e într-adevăr
          // un Guest fără cont Google — dacă nu e, ștergerea pică cu
          // permission-denied, prins și ignorat mai jos, nimic nu se strică.
          await doc.reference.delete();
        } catch (e) {
          debugPrint('PlayerProfileService._sweepStaleGuests a esuat la stergerea ${doc.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('PlayerProfileService._sweepStaleGuests a esuat: $e');
    }
  }
}
