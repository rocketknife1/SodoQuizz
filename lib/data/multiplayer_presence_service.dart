import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// „Cineva tocmai a intrat în Multiplayer" — semnalul din care ceilalți află
/// că merită și ei să dea Join chiar acum.
///
/// PROBLEMA PE CARE O REZOLVĂ: multiplayer-ul e gol nu pentru că nu vrea
/// nimeni să joace, ci pentru că fiecare intră, vede zero camere, și iese în
/// zece secunde. Doi oameni care ar fi jucat împreună ratează asta fiindcă
/// au intrat la un minut distanță. Un anunț scurt, oriunde ai fi în joc, îi
/// pune pe aceeași fereastră de timp.
///
/// CUM E FĂCUT IEFTIN, fiindcă asculta TOATĂ lumea, tot timpul:
///  • un singur document per jucător (`multiplayer_presence/{uid}`), rescris
///    la fiecare intrare — nu se adună niciodată un istoric;
///  • ascultătorul cere doar ultimele [_watchLimit] intrări, deci o
///    reconectare costă cel mult atâtea citiri, indiferent câți jucători are
///    jocul;
///  • anunțul se scrie cel mult o dată la [_announceCooldown] de pe același
///    telefon, deci nici cineva care intră și iese din Multiplayer în buclă
///    nu poate genera trafic.
class MultiplayerPresenceService {
  MultiplayerPresenceService._();
  static final instance = MultiplayerPresenceService._();

  static const _collection = 'multiplayer_presence';

  /// Cât timp e considerat „proaspăt" un anunț. Peste asta nu se mai arată:
  /// un jucător care a intrat acum zece minute aproape sigur nu mai e acolo,
  /// iar un anunț fals e mai rău decât niciunul — te duce degeaba.
  static const Duration freshness = Duration(seconds: 45);

  static const Duration _announceCooldown = Duration(minutes: 4);
  static const int _watchLimit = 4;

  DateTime? _lastAnnounce;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Anunță că jucătorul curent a deschis Multiplayer. Eșuează în tăcere: e
  /// o notificare de curtoazie, nu are voie să strice intrarea în ecran dacă
  /// pică rețeaua.
  Future<void> announceEntered({required String name, String? photoUrl, String avatarStyle = ''}) async {
    final me = _uid;
    if (me.isEmpty || name.isEmpty) return;
    final now = DateTime.now();
    if (_lastAnnounce != null && now.difference(_lastAnnounce!) < _announceCooldown) return;
    _lastAnnounce = now;
    try {
      await _db.collection(_collection).doc(me).set({
        'name': name,
        'photoUrl': photoUrl,
        'avatarStyle': avatarStyle,
        'at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('MultiplayerPresenceService.announceEntered a esuat: $e');
    }
  }

  /// Anunțurile PROASPETE ale ALTORA, câte unul pe eveniment.
  ///
  /// Filtrarea pe vechime se face aici, în client, nu în interogare: o
  /// condiție `where('at' > acum - 45s)` ar fi înghețat pragul în clipa
  /// abonării și ar fi rămas în urmă după câteva minute de aplicație
  /// deschisă. Cu `orderBy` + `limit` interogarea rămâne valabilă la
  /// nesfârșit, iar prospețimea se recalculează la fiecare snapshot.
  /// Din fiecare snapshot iese CEL MULT un anunț, chiar dacă s-au schimbat
  /// mai multe documente: primul snapshot aduce tot istoricul recent, iar
  /// fără regula asta deschiderea aplicației ar fi putut arunca patru
  /// bannere unul peste altul.
  Stream<MultiplayerPresencePing> watchOthers() {
    final me = _uid;
    final seen = <String>{};
    return _db
        .collection(_collection)
        .orderBy('at', descending: true)
        .limit(_watchLimit)
        .snapshots()
        .map<MultiplayerPresencePing?>((snap) {
          final now = DateTime.now();
          MultiplayerPresencePing? newest;
          for (final doc in snap.docs) {
            if (doc.id == me) continue;
            final at = (doc.data()['at'] as Timestamp?)?.toDate();
            if (at == null) continue;
            // Marcat ca văzut chiar dacă e prea vechi ca să fie arătat:
            // altfel un anunț expirat ar fi recalculat la fiecare snapshot.
            if (!seen.add('${doc.id}@${at.millisecondsSinceEpoch}')) continue;
            if (now.difference(at) > freshness) continue;
            if (newest != null && !at.isAfter(newest.at)) continue;
            newest = MultiplayerPresencePing(
              uid: doc.id,
              name: doc.data()['name'] as String? ?? '?',
              photoUrl: doc.data()['photoUrl'] as String?,
              avatarStyle: doc.data()['avatarStyle'] as String? ?? '',
              at: at,
            );
          }
          return newest;
        })
        .handleError((Object e) => debugPrint('MultiplayerPresenceService.watchOthers a esuat: $e'))
        .where((ping) => ping != null)
        .cast<MultiplayerPresencePing>();
  }
}

/// Un jucător care tocmai a deschis Multiplayer.
class MultiplayerPresencePing {
  final String uid;
  final String name;
  final String? photoUrl;
  final String avatarStyle;
  final DateTime at;

  const MultiplayerPresencePing({
    required this.uid,
    required this.name,
    required this.at,
    this.photoUrl,
    this.avatarStyle = '',
  });
}
