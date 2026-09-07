import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'multiplayer_service.dart';

/// O provocare async — un singur doc `challenges/{id}`. Creatorul joacă la
/// creare (scorul lui e fix din prima), un singur adversar poate răspunde.
class AsyncChallenge {
  final String id;
  final String creatorUid;
  final String creatorName;
  final int creatorScore;
  final int creatorCorrect;
  final String creatorAvatarStyle;
  final String? creatorPhotoUrl;
  final String creatorFrame;
  final String creatorTitle;

  /// `null` cât timp nimeni n-a răspuns.
  final String? opponentUid;
  final String? opponentName;
  final int? opponentScore;
  final int? opponentCorrect;

  const AsyncChallenge({
    required this.id,
    required this.creatorUid,
    required this.creatorName,
    required this.creatorScore,
    required this.creatorCorrect,
    required this.creatorAvatarStyle,
    required this.creatorPhotoUrl,
    required this.creatorFrame,
    required this.creatorTitle,
    this.opponentUid,
    this.opponentName,
    this.opponentScore,
    this.opponentCorrect,
  });

  bool get isAnswered => opponentUid != null;

  factory AsyncChallenge.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return AsyncChallenge(
      id: doc.id,
      creatorUid: d['creatorUid'] as String? ?? '',
      creatorName: d['creatorName'] as String? ?? '?',
      creatorScore: (d['creatorScore'] as num?)?.toInt() ?? 0,
      creatorCorrect: (d['creatorCorrect'] as num?)?.toInt() ?? 0,
      creatorAvatarStyle: d['creatorAvatarStyle'] as String? ?? '',
      creatorPhotoUrl: d['creatorPhotoUrl'] as String?,
      creatorFrame: d['creatorFrame'] as String? ?? 'none',
      creatorTitle: d['creatorTitle'] as String? ?? 'novice',
      opponentUid: d['opponentUid'] as String?,
      opponentName: d['opponentName'] as String?,
      opponentScore: (d['opponentScore'] as num?)?.toInt(),
      opponentCorrect: (d['opponentCorrect'] as num?)?.toInt(),
    );
  }
}

class AsyncChallengeService {
  AsyncChallengeService._();
  static final instance = AsyncChallengeService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => _db.collection('challenges');

  /// Creează provocarea cu [id] (generat pe client ÎNAINTE de joc, ca să
  /// derive aceleași întrebări) și scorul creatorului deja jucat. `false`
  /// dacă scrierea a eșuat.
  Future<bool> create({
    required String id,
    required int score,
    required int correct,
  }) async {
    final uid = MultiplayerService.instance.currentPlayerId;
    if (uid.isEmpty) return false;
    final me = await AuthService.instance.multiplayerIdentity();
    try {
      await _col.doc(id).set({
        'creatorUid': uid,
        'creatorName': me.name,
        'creatorScore': score,
        'creatorCorrect': correct,
        'creatorAvatarStyle': me.avatarStyle,
        'creatorPhotoUrl': me.photoUrl,
        'creatorFrame': me.equippedFrame,
        'creatorTitle': me.equippedTitle,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('AsyncChallengeService.create a esuat: $e');
      return false;
    }
  }

  Future<AsyncChallenge?> fetch(String id) async {
    try {
      final doc = await _col.doc(id).get();
      return doc.exists ? AsyncChallenge.fromDoc(doc) : null;
    } catch (e) {
      debugPrint('AsyncChallengeService.fetch a esuat: $e');
      return null;
    }
  }

  /// Live — pentru ecranul creatorului care așteaptă răspunsul adversarului.
  Stream<AsyncChallenge?> watch(String id) => _col
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? AsyncChallenge.fromDoc(d) : null);

  /// Adversarul își scrie scorul. Tranzacție: prinde cazul „doi oameni au
  /// deschis linkul și au jucat aproape simultan" — doar primul care ajunge
  /// aici e adversarul, al doilea primește `false` și vede doar rezultatul.
  Future<bool> submitOpponentScore({
    required String id,
    required int score,
    required int correct,
  }) async {
    final uid = MultiplayerService.instance.currentPlayerId;
    if (uid.isEmpty) return false;
    final me = await AuthService.instance.multiplayerIdentity();
    try {
      return await _db.runTransaction<bool>((tx) async {
        final ref = _col.doc(id);
        final snap = await tx.get(ref);
        if (!snap.exists) return false;
        final data = snap.data()!;
        if (data['opponentUid'] != null) return false; // deja revendicată
        if (data['creatorUid'] == uid) return false; // nu-ți răspunzi singur
        tx.update(ref, {
          'opponentUid': uid,
          'opponentName': me.name,
          'opponentScore': score,
          'opponentCorrect': correct,
          'finishedAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
    } catch (e) {
      debugPrint('AsyncChallengeService.submitOpponentScore a esuat: $e');
      return false;
    }
  }
}
