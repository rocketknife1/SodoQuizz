import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/multiplayer_activity.dart';

/// Jurnalul camerelor de multiplayer terminate (`multiplayer_activity`).
///
/// DE CE EXISTĂ, pe scurt: `matches/{matchId}` se șterge în clipa în care
/// pleacă ultimul jucător, deci nu se poate vedea niciodată ce s-a întâmplat
/// la o masă. `completed_matches/{matchId}` rămâne, dar are doar mod, număr de
/// jucători și oră — destul pentru a număra meciuri, nu și pentru a vedea cine
/// a jucat și cu câte monede a plecat. Colecția asta ține tabloul complet și
/// se autodistruge după [roomActivityRetention].
///
/// CUM SE ȘTERGE, fără Cloud Functions și fără să lărgim accesul de citire:
/// politica TTL de Firestore n-a putut fi activată pe proiectul ăsta
/// (PERMISSION_DENIED pe planul curent), iar o curățare "de către oricine" ar
/// fi cerut drept de LISTARE pentru toți jucătorii — adică oricine ar fi putut
/// citi mesele tuturor. Soluția: fiecare client își ține minte LOCAL id-urile
/// camerelor pe care le-a scris și le șterge țintit când le expiră termenul.
/// Ștergerea țintită după id nu are nevoie de drept de citire, iar regula din
/// firestore.rules verifică oricum `expiresAt` pe server, deci nimeni nu poate
/// șterge o cameră încă activă. Camerele rămase de la jucători care n-au mai
/// deschis aplicația sunt măturate de admin, din tab-ul Camere.
class MultiplayerActivityService {
  MultiplayerActivityService._();
  static final instance = MultiplayerActivityService._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => _db.collection('multiplayer_activity');

  /// Camerele scrise de telefonul ăsta care încă n-au fost șterse, ca
  /// `matchId|millisecundeExpirare`. Plafonat la [_pendingCap] — dacă lista ar
  /// crește la nesfârșit, ar umfla degeaba și cloud-save-ul, fiindcă
  /// `StorageService.exportAll` urcă toate cheile din SharedPreferences.
  static const _pendingKey = 'mp_activity_pending';
  static const _pendingCap = 20;

  /// Scrie camera terminată. Id-ul documentului = [matchId], deci apelurile
  /// independente ale tuturor jucătorilor pentru ACELAȘI meci converg în
  /// același document, fără dubluri — fiecare client calculează aceleași
  /// plăți din aceleași date publice (vezi MultiplayerResultsScreen).
  ///
  /// No-op sub 2 jucători: o masă cu un singur om nu e un meci.
  Future<void> recordRoom({
    required String matchId,
    required String gameModeId,
    required List<RoomActivityPlayer> players,
    int pool = 0,
    int stake = 0,
  }) async {
    if (players.length < 2) return;
    final expires = DateTime.now().add(roomActivityRetention);
    try {
      await _col.doc(matchId).set({
        'gameModeId': gameModeId,
        'playerCount': players.length,
        'pool': pool,
        'stake': stake,
        'finishedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expires),
        'players': [for (final p in players) p.toMap()],
      }, SetOptions(merge: true));
      await _remember(matchId, expires);
    } catch (e) {
      debugPrint('MultiplayerActivityService.recordRoom a esuat: $e');
    }
  }

  Future<void> _remember(String matchId, DateTime expires) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_pendingKey) ?? <String>[];
      list.removeWhere((e) => e.startsWith('$matchId|'));
      list.add('$matchId|${expires.millisecondsSinceEpoch}');
      if (list.length > _pendingCap) {
        list.removeRange(0, list.length - _pendingCap);
      }
      await prefs.setStringList(_pendingKey, list);
    } catch (e) {
      debugPrint('MultiplayerActivityService._remember a esuat: $e');
    }
  }

  /// Șterge camerele scrise de telefonul ăsta cărora le-a expirat termenul.
  /// Ștergere țintită după id — fără listare, deci fără drept de citire.
  /// Sigur de apelat oricând, inclusiv la pornirea aplicației.
  Future<void> sweepMine() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_pendingKey);
      if (list == null || list.isEmpty) return;
      final now = DateTime.now();
      final kept = <String>[];
      for (final entry in list) {
        final parts = entry.split('|');
        if (parts.length != 2) continue;
        final expires = DateTime.fromMillisecondsSinceEpoch(int.tryParse(parts[1]) ?? 0);
        if (expires.isAfter(now)) {
          kept.add(entry);
          continue;
        }
        try {
          await _col.doc(parts[0]).delete();
        } catch (e) {
          // Poate a șters-o deja alt jucător de la aceeași masă — normal,
          // toți o au în listă. Orice altă eroare: o scoatem oricum din
          // listă, ca să nu reîncercăm la nesfârșit.
          debugPrint('MultiplayerActivityService.sweepMine, ${parts[0]}: $e');
        }
      }
      await prefs.setStringList(_pendingKey, kept);
    } catch (e) {
      debugPrint('MultiplayerActivityService.sweepMine a esuat: $e');
    }
  }

  /// Camerele încă vizibile, cele mai recente primele. Doar adminul are drept
  /// de citire pe colecția asta (vezi firestore.rules).
  Future<List<RoomActivity>> fetchRooms({int limit = 100}) async {
    try {
      final snap = await _col.orderBy('finishedAt', descending: true).limit(limit).get();
      return [for (final d in snap.docs) RoomActivity.fromDoc(d)];
    } catch (e) {
      debugPrint('MultiplayerActivityService.fetchRooms a esuat: $e');
      return const [];
    }
  }

  /// Mătură camerele expirate rămase de la jucători care n-au mai deschis
  /// aplicația. Doar adminul poate rula asta (are nevoie de listare).
  /// Întoarce câte au fost șterse.
  Future<int> sweepExpiredAsAdmin() async {
    try {
      final snap = await _col.where('expiresAt', isLessThan: Timestamp.now()).limit(200).get();
      if (snap.docs.isEmpty) return 0;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      return snap.docs.length;
    } catch (e) {
      debugPrint('MultiplayerActivityService.sweepExpiredAsAdmin a esuat: $e');
      return 0;
    }
  }
}
