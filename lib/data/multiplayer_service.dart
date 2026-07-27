import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/multiplayer_models.dart';

/// Aruncată când Firebase nu e (încă) configurat corect — [firebase_options.dart]
/// are valori placeholder până userul pune un proiect real. UI-ul o prinde și
/// arată un fallback prietenos, nu lasă aplicația să crape.
class MultiplayerUnavailableException implements Exception {
  final String message;
  const MultiplayerUnavailableException([this.message = 'Multiplayer indisponibil momentan.']);
  @override
  String toString() => message;
}

/// Capacitatea maximă a unei camere private (Create Room / Join with Code).
const int matchPlayerCount = 5;

/// Câți jucători reali formează un meci prin matchmaking public (Join
/// Online) — 1 vs 1, fără completare cu boți: se așteaptă un adversar real.
const int matchmakingOpponentCount = 2;
const _codeChars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // fara 0/O/1/I - usor de dictat

/// Toată logica de rețea (Firestore + Auth anonim) pentru multiplayer —
/// separată de UI, conform planului. O singură colecție `matches` deservește
/// atât camerele private (cu `code`) cât și meciurile de matchmaking public
/// (fără cod) — vezi [MatchInfo].
class MultiplayerService {
  MultiplayerService._();
  static final instance = MultiplayerService._();

  bool _initialized = false;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Asigură o identitate (Google, dacă userul e logat prin Cont în Profil,
  /// altfel anonimă) — LAZY, doar când multiplayer-ul chiar e folosit.
  /// Firebase core e deja inițializat la pornirea aplicației (vezi
  /// main.dart); aici doar ne asigurăm că există un user curent. Aruncă
  /// [MultiplayerUnavailableException] dacă eșuează (ex. Firebase
  /// neconfigurat corect încă, sau fără rețea).
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    try {
      await Future(() async {
        if (FirebaseAuth.instance.currentUser == null) {
          await FirebaseAuth.instance.signInAnonymously();
        }
      }).timeout(const Duration(seconds: 8));
      _initialized = true;
    } catch (e) {
      // detaliul tehnic (poate fi un stack trace nativ foarte lung) merge
      // doar in log - userul vede mereu mesajul scurt, prietenos.
      debugPrint('MultiplayerService.ensureInitialized a esuat: $e');
      throw const MultiplayerUnavailableException();
    }
  }

  String get currentPlayerId => FirebaseAuth.instance.currentUser?.uid ?? '';

  String _randomCode() {
    final rnd = Random();
    return List.generate(5, (_) => _codeChars[rnd.nextInt(_codeChars.length)]).join();
  }

  // ─── Camera privată ─────────────────────────────────────────────────────

  Future<MatchInfo> createRoom({required String displayName, String? photoUrl}) async {
    await ensureInitialized();
    final me = currentPlayerId;
    final code = _randomCode();
    final ref = _db.collection('matches').doc();
    final info = MatchInfo(id: ref.id, mode: MatchMode.private, code: code, status: MatchStatus.lobby, hostId: me);
    await ref.set(info.toMap());
    await ref.collection('players').doc(me).set(
          MatchPlayer(id: me, name: displayName, avatarSeed: me, photoUrl: photoUrl, score: 0, isHost: true).toMap(),
        );
    return info;
  }

  /// Caută o cameră după cod și te alătură ca jucător — aruncă dacă nu
  /// există, dacă meciul a pornit deja, sau dacă e plină.
  Future<MatchInfo> joinRoomByCode({required String code, required String displayName, String? photoUrl}) async {
    await ensureInitialized();
    final query = await _db
        .collection('matches')
        .where('code', isEqualTo: code.toUpperCase())
        .where('status', isEqualTo: MatchStatus.lobby.name)
        .limit(1)
        .get();
    if (query.docs.isEmpty) {
      throw const MultiplayerUnavailableException('Cod invalid sau camera a pornit deja.');
    }
    final doc = query.docs.first;
    final players = await doc.reference.collection('players').get();
    if (players.docs.length >= matchPlayerCount) {
      throw const MultiplayerUnavailableException('Camera e plină.');
    }
    final me = currentPlayerId;
    await doc.reference.collection('players').doc(me).set(
          MatchPlayer(id: me, name: displayName, avatarSeed: me, photoUrl: photoUrl, score: 0).toMap(),
        );
    return MatchInfo.fromDoc(doc);
  }

  Future<void> startMatch(String matchId) => _db.collection('matches').doc(matchId).update({'status': MatchStatus.playing.name});

  Future<void> sendChatMessage({required String matchId, required String senderName, required String text}) async {
    final me = currentPlayerId;
    await _db.collection('matches').doc(matchId).collection('chat').add(
          ChatMessage(id: '', senderId: me, senderName: senderName, text: text).toMap(),
        );
  }

  Stream<List<ChatMessage>> watchChat(String matchId) {
    return _db
        .collection('matches')
        .doc(matchId)
        .collection('chat')
        .orderBy('sentAt')
        .limitToLast(100)
        .snapshots()
        .map((s) => s.docs.map(ChatMessage.fromDoc).toList());
  }

  /// Părăsește meciul — dacă hostul pleacă în timp ce meciul e încă în
  /// lobby, ștergem camera întreagă (players + chat) ca să nu rămână
  /// listeners orfani pentru ceilalți; altfel propriul jucător e scos, iar
  /// dacă era ultimul rămas, ștergem și noi camera întreagă (players + chat
  /// + documentul meciului) — altfel meciurile terminate s-ar acumula la
  /// nesfârșit în Firestore, fără niciun cleanup automat (nu avem Cloud
  /// Functions/TTL configurate).
  Future<void> leaveMatch(String matchId) async {
    final me = currentPlayerId;
    final matchRef = _db.collection('matches').doc(matchId);
    final matchDoc = await matchRef.get();
    if (!matchDoc.exists) return;
    final info = MatchInfo.fromDoc(matchDoc);
    if (info.hostId == me && info.status == MatchStatus.lobby) {
      await _deleteMatch(matchRef);
      return;
    }
    await matchRef.collection('players').doc(me).delete();
    final remaining = await matchRef.collection('players').limit(1).get();
    if (remaining.docs.isEmpty) {
      await _deleteMatch(matchRef);
    }
  }

  Future<void> _deleteMatch(DocumentReference<Map<String, dynamic>> matchRef) async {
    final players = await matchRef.collection('players').get();
    final chat = await matchRef.collection('chat').get();
    final batch = _db.batch();
    for (final d in players.docs) {
      batch.delete(d.reference);
    }
    for (final d in chat.docs) {
      batch.delete(d.reference);
    }
    batch.delete(matchRef);
    await batch.commit();
  }

  // ─── Meci (comun ambelor fluxuri) ───────────────────────────────────────

  Stream<MatchInfo> watchMatch(String matchId) => _db.collection('matches').doc(matchId).snapshots().map(MatchInfo.fromDoc);

  Stream<List<MatchPlayer>> watchPlayers(String matchId) {
    return _db.collection('matches').doc(matchId).collection('players').snapshots().map(
          (s) => s.docs.map(MatchPlayer.fromDoc).toList(),
        );
  }

  Future<void> updateScore({required String matchId, required int score}) {
    return _db.collection('matches').doc(matchId).collection('players').doc(currentPlayerId).update({'score': score});
  }

  // ─── Matchmaking public ─────────────────────────────────────────────────

  Future<void> joinMatchmakingQueue({required String displayName, String? photoUrl}) async {
    await ensureInitialized();
    final me = currentPlayerId;
    await _db.collection('matchmaking_queue').doc(me).set({
      'name': displayName,
      'avatarSeed': me,
      'photoUrl': photoUrl,
      'matchId': null,
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Streamul propriei intrări din coadă — când un alt client (liderul)
  /// formează meciul, îi scrie `matchId` aici; UI-ul ascultă asta ca să
  /// navigheze automat, fără sa aiba nevoie de Cloud Functions.
  Stream<String?> watchOwnQueueEntry() {
    final me = currentPlayerId;
    return _db.collection('matchmaking_queue').doc(me).snapshots().map((d) => d.data()?['matchId'] as String?);
  }

  Future<void> leaveQueue() async {
    await _db.collection('matchmaking_queue').doc(currentPlayerId).delete();
  }

  /// Doar clientul cel mai "vechi" din coadă (primul intrat) încearcă să
  /// formeze un meci — reduce coliziunile, deși tranzacția de mai jos e
  /// oricum sigură chiar dacă doi clienți ar încerca simultan. Formează
  /// meciul DOAR când există [matchmakingOpponentCount] jucători reali în
  /// coadă — fără completare cu boți, se așteaptă cât e nevoie de un
  /// adversar real.
  Future<String?> attemptFormMatch() async {
    final me = currentPlayerId;
    final queueSnap = await _db.collection('matchmaking_queue').orderBy('joinedAt').limit(matchmakingOpponentCount).get();
    if (queueSnap.docs.isEmpty || queueSnap.docs.first.id != me) return null;
    if (queueSnap.docs.length < matchmakingOpponentCount) return null;

    final candidates = queueSnap.docs;
    final matchRef = _db.collection('matches').doc();

    try {
      await _db.runTransaction((tx) async {
        // re-verifica in tranzactie ca niciun candidat n-a fost deja
        // "furat" de o alta tranzactie concurenta intre timp.
        for (final c in candidates) {
          final fresh = await tx.get(c.reference);
          if (!fresh.exists || fresh.data()?['matchId'] != null) {
            throw StateError('candidat deja revendicat');
          }
        }

        final info = MatchInfo(id: matchRef.id, mode: MatchMode.public, status: MatchStatus.playing, hostId: me);
        tx.set(matchRef, info.toMap());

        for (final c in candidates) {
          final data = c.data();
          tx.set(
            matchRef.collection('players').doc(c.id),
            MatchPlayer(
              id: c.id,
              name: data['name'] as String? ?? '?',
              avatarSeed: data['avatarSeed'] as String? ?? c.id,
              photoUrl: data['photoUrl'] as String?,
              score: 0,
              isHost: c.id == me,
            ).toMap(),
          );
          tx.update(c.reference, {'matchId': matchRef.id});
        }
      });
      return matchRef.id;
    } catch (_) {
      // un alt client a format deja meciul intre timp cu acesti candidati -
      // e ok, ascultatorul propriei intrari din coada va prelua matchId-ul.
      return null;
    }
  }
}
