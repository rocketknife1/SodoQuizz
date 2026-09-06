import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'multiplayer_service.dart';

/// Un rând din clasamentul unui eveniment limitat (vezi core/game_event.dart).
/// Câmpurile de afişare sunt denormalizate, ca la Provocarea Zilei.
class EventScoreEntry {
  final String uid;
  final String name;
  final int points;
  final String avatarStyle;
  final String? photoUrl;
  final String equippedFrame;
  final String equippedTitle;
  final int level;
  final int leaguePoints;

  const EventScoreEntry({
    required this.uid,
    required this.name,
    required this.points,
    required this.avatarStyle,
    required this.photoUrl,
    required this.equippedFrame,
    required this.equippedTitle,
    required this.level,
    required this.leaguePoints,
  });

  factory EventScoreEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return EventScoreEntry(
      uid: doc.id,
      name: d['name'] as String? ?? '?',
      points: (d['points'] as num?)?.toInt() ?? 0,
      avatarStyle: d['avatarStyle'] as String? ?? '',
      photoUrl: d['photoUrl'] as String?,
      equippedFrame: d['equippedFrame'] as String? ?? 'none',
      equippedTitle: d['equippedTitle'] as String? ?? 'novice',
      level: (d['level'] as num?)?.toInt() ?? 0,
      leaguePoints: (d['leaguePoints'] as num?)?.toInt() ?? 0,
    );
  }
}

class EventLeaderboard {
  final List<EventScoreEntry> top;
  final EventScoreEntry? me;
  final int? myRankBelowTop;
  const EventLeaderboard({required this.top, this.me, this.myRankBelowTop});
}

class EventService {
  EventService._();
  static final instance = EventService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _scores(String eventId) =>
      _db.collection('events').doc(eventId).collection('scores');

  /// Adaugă [points] la scorul meu în evenimentul [eventId]. Best-effort:
  /// eşuează în tăcere (e un bonus, nu are voie să strice runda). Plafonat la
  /// +50 per apel — regula Firestore verifică şi ea (o rundă nu poate da mai
  /// mult). `points <= 0` = no-op.
  Future<void> addPoints(String eventId, int points) async {
    if (points <= 0 || eventId.isEmpty) return;
    final uid = MultiplayerService.instance.currentPlayerId;
    if (uid.isEmpty) return;
    final delta = points > 50 ? 50 : points;
    try {
      final id = await AuthService.instance.multiplayerIdentity();
      await _scores(eventId).doc(uid).set({
        'name': id.name,
        'points': FieldValue.increment(delta),
        'avatarStyle': id.avatarStyle,
        'photoUrl': id.photoUrl,
        'equippedFrame': id.equippedFrame,
        'equippedTitle': id.equippedTitle,
        'level': id.level,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('EventService.addPoints a esuat: $e');
    }
  }

  Future<EventLeaderboard> leaderboard({required String eventId, int limit = 20}) async {
    final uid = MultiplayerService.instance.currentPlayerId;
    try {
      final topSnap = await _scores(eventId)
          .orderBy('points', descending: true)
          .limit(limit)
          .get();
      final top = topSnap.docs.map(EventScoreEntry.fromDoc).toList();

      EventScoreEntry? me;
      int? rankBelowTop;
      if (uid.isNotEmpty && !top.any((e) => e.uid == uid)) {
        final mine = await _scores(eventId).doc(uid).get();
        if (mine.exists) {
          me = EventScoreEntry.fromDoc(mine);
          final agg = await _scores(eventId)
              .where('points', isGreaterThan: me.points)
              .count()
              .get();
          rankBelowTop = (agg.count ?? top.length) + 1;
        }
      }
      return EventLeaderboard(top: top, me: me, myRankBelowTop: rankBelowTop);
    } catch (e) {
      debugPrint('EventService.leaderboard a esuat: $e');
      return const EventLeaderboard(top: []);
    }
  }
}
