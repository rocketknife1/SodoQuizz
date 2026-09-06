import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/daily_challenge.dart';
import 'auth_service.dart';
import 'multiplayer_service.dart';

/// Un rând din clasamentul „de azi" al Provocării Zilei. Câmpurile de afişare
/// sunt denormalizate în doc — o singură scriere pe zi per jucător, iar la
/// citire clasamentul nu mai are nevoie de câte un `get()` pe `player_profiles`
/// pentru fiecare rând.
class DailyScoreEntry {
  final String uid;
  final String name;
  final int correct;
  final int coins;
  final String avatarStyle;
  final String avatarSeed;
  final String? photoUrl;
  final String equippedFrame;
  final String equippedTitle;
  final int level;
  final int leaguePoints;

  const DailyScoreEntry({
    required this.uid,
    required this.name,
    required this.correct,
    required this.coins,
    required this.avatarStyle,
    required this.avatarSeed,
    required this.photoUrl,
    required this.equippedFrame,
    required this.equippedTitle,
    required this.level,
    required this.leaguePoints,
  });

  factory DailyScoreEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return DailyScoreEntry(
      uid: doc.id,
      name: d['name'] as String? ?? '?',
      correct: (d['correct'] as num?)?.toInt() ?? 0,
      coins: (d['coins'] as num?)?.toInt() ?? 0,
      avatarStyle: d['avatarStyle'] as String? ?? '',
      avatarSeed: d['avatarSeed'] as String? ?? doc.id,
      photoUrl: d['photoUrl'] as String?,
      equippedFrame: d['equippedFrame'] as String? ?? 'none',
      equippedTitle: d['equippedTitle'] as String? ?? 'novice',
      level: (d['level'] as num?)?.toInt() ?? 0,
      leaguePoints: (d['leaguePoints'] as num?)?.toInt() ?? 0,
    );
  }
}

class DailyChallengeToday {
  final List<DailyScoreEntry> top;
  final DailyScoreEntry? me;

  /// Locul meu (1-based) dacă nu sunt în [top]; `null` dacă sunt în [top] sau
  /// n-am jucat azi.
  final int? myRankBelowTop;

  /// Citirea a EȘUAT (fără rețea, index lipsă, reguli). Fără el, un clasament
  /// gol din eroare arată identic cu unul gol fiindcă n-a jucat nimeni, iar
  /// ecranul îi spunea jucătorului „ești primul" când de fapt nu știa nimic —
  /// exact ce s-a întâmplat la proba cu doi jucători din 2026-09-06, unde
  /// lipsea indexul compus (`correct` desc + `ts`).
  final bool failed;

  const DailyChallengeToday({
    required this.top,
    this.me,
    this.myRankBelowTop,
    this.failed = false,
  });
}

class DailyChallengeService {
  DailyChallengeService._();
  static final instance = DailyChallengeService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _scores(String dateKey) =>
      _db.collection('daily_challenges').doc(dateKey).collection('scores');

  /// Scrie scorul meu de azi. O singură dată pe zi (ecranul nu lasă rejucarea),
  /// dar folosim `set` cu `merge:false` ca o eventuală a doua scriere să nu
  /// lase câmpuri vechi. `correct` e plafonat 0..[dailyChallengeQuestionCount]
  /// — regulile Firestore îl verifică şi ele.
  Future<void> submitScore({
    required String dateKey,
    required int correct,
    required int coins,
  }) async {
    final uid = MultiplayerService.instance.currentPlayerId;
    if (uid.isEmpty) return;
    final id = await AuthService.instance.multiplayerIdentity();
    final c = correct.clamp(0, dailyChallengeQuestionCount);
    try {
      await _scores(dateKey).doc(uid).set({
        'name': id.name,
        'correct': c,
        'coins': coins,
        'avatarStyle': id.avatarStyle,
        'photoUrl': id.photoUrl,
        'equippedFrame': id.equippedFrame,
        'equippedTitle': id.equippedTitle,
        'level': id.level,
        'ts': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('DailyChallengeService.submitScore a esuat: $e');
    }
  }

  /// Top [limit] scoruri de azi (după `correct`, apoi cel mai devreme `ts`) +
  /// rândul meu şi locul meu dacă nu sunt în top.
  Future<DailyChallengeToday> today({required String dateKey, int limit = 20}) async {
    final uid = MultiplayerService.instance.currentPlayerId;
    try {
      final topSnap = await _scores(dateKey)
          .orderBy('correct', descending: true)
          .orderBy('ts')
          .limit(limit)
          .get();
      final top = topSnap.docs.map(DailyScoreEntry.fromDoc).toList();

      DailyScoreEntry? me;
      int? rankBelowTop;
      final inTop = top.any((e) => e.uid == uid);
      if (uid.isNotEmpty && !inTop) {
        final mineDoc = await _scores(dateKey).doc(uid).get();
        if (mineDoc.exists) {
          me = DailyScoreEntry.fromDoc(mineDoc);
          // Câţi m-au bătut: scor strict mai mare. Egalii nu schimbă „locul"
          // suficient cât să merite o a doua interogare pe `ts`.
          final agg = await _scores(dateKey)
              .where('correct', isGreaterThan: me.correct)
              .count()
              .get();
          rankBelowTop = (agg.count ?? top.length) + 1;
        }
      }
      return DailyChallengeToday(top: top, me: me, myRankBelowTop: rankBelowTop);
    } catch (e) {
      debugPrint('DailyChallengeService.today a esuat: $e');
      return const DailyChallengeToday(top: [], failed: true);
    }
  }
}
