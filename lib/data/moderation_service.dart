import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/moderation.dart';
import 'auth_service.dart';
import 'multiplayer_service.dart';

/// Jumătatea umană a moderării: raportarea unui jucător și blocarea lui.
/// (Jumătatea automată — cenzura de cuvinte — e în core/chat_filter.dart.)
///
/// Cele două fac lucruri diferite, deliberat:
///  - BLOCAREA are efect imediat și e strict personală: mesajele celui blocat
///    dispar de pe ecranul TĂU, pe loc, fără să treacă pe la nimeni. Nu-i
///    spune celuilalt nimic și nu-l împiedică să scrie mai departe pentru
///    restul mesei.
///  - RAPORTAREA nu schimbă nimic pe loc; lasă o urmă în panoul de admin,
///    unde un om decide dacă urmează ban.
///
/// De ce blocarea NU se aplică pe server: fără Cloud Functions în proiect
/// (vezi firestore.rules), n-ar exista cine să filtreze scrierile altcuiva.
/// Filtrarea la afișare e onestă față de ce promite butonul — „nu mai vezi
/// mesajele lui" — și e singura care se poate face de aici.
class ModerationService {
  ModerationService._();
  static final instance = ModerationService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid => MultiplayerService.instance.currentPlayerId;

  CollectionReference<Map<String, dynamic>> _blockedCol(String uid) =>
      _db.collection('player_profiles').doc(uid).collection('blocked');

  /// Uid-urile blocate de contul de pe telefonul ăsta, ținute în memorie ca
  /// filtrarea chatului să fie SINCRONĂ. Fără asta, fiecare bulă de chat ar fi
  /// avut nevoie de un FutureBuilder propriu, iar mesajul unui blocat ar fi
  /// clipit pe ecran înainte să dispară — exact ce nu trebuie să facă.
  ///
  /// E un [ValueNotifier] ca ecranele deschise să se împrospăteze singure în
  /// clipa în care blochezi pe cineva, fără reîncărcare.
  final ValueNotifier<Set<String>> blockedIds = ValueNotifier(const {});

  /// Pentru CE cont e încărcat setul de mai sus. Nu un simplu bool „încărcat":
  /// uid-ul se schimbă sub picioare când un Guest se loghează cu un cont
  /// Google care are deja istoric (vezi AuthService.signInWithGoogle), iar
  /// lista de blocați a identității anonime n-are ce căuta pe contul nou.
  String _loadedForUid = '';

  bool isBlocked(String uid) => blockedIds.value.contains(uid);

  /// Încărcată la pornire (vezi main.dart) și la fiecare revenire din fundal,
  /// unde e gratis: dacă e deja încărcată pentru uid-ul curent, nu face nimic.
  /// Eșecul e nefatal — lista rămâne goală, adică nu se filtrează nimic. Mai
  /// bine chat nefiltrat decât aplicație care nu pornește.
  Future<void> loadBlocked({bool force = false}) async {
    final me = _uid;
    if (me.isEmpty) return;
    if (_loadedForUid == me && !force) return;
    try {
      final snap = await _blockedCol(me).get();
      blockedIds.value = snap.docs.map((d) => d.id).toSet();
      _loadedForUid = me;
    } catch (e) {
      debugPrint('ModerationService.loadBlocked a esuat: $e');
    }
  }

  /// Lista completă, cu nume și dată — pentru ecranul de unde se deblochează.
  Future<List<BlockedPlayer>> fetchBlocked() async {
    final me = _uid;
    if (me.isEmpty) return [];
    try {
      final snap = await _blockedCol(me).get();
      final items = snap.docs.map(BlockedPlayer.fromDoc).toList();
      items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return items;
    } catch (e) {
      debugPrint('ModerationService.fetchBlocked a esuat: $e');
      return [];
    }
  }

  /// Blochează pe loc, chiar dacă scrierea în Firestore întârzie sau eșuează:
  /// setul din memorie se actualizează primul, ca mesajele să dispară în
  /// aceeași clipă în care se apasă butonul. Dacă scrierea pică, blocarea
  /// ține până la următoarea pornire — vizibil pentru user ca „s-a dezblocat
  /// singur", ceea ce e mai bun decât un buton care pare că n-a făcut nimic.
  Future<bool> blockPlayer(String uid, {required String name}) async {
    final me = _uid;
    if (me.isEmpty || uid.isEmpty || uid == me) return false;
    blockedIds.value = {...blockedIds.value, uid};
    try {
      await _blockedCol(me).doc(uid).set({
        'name': name,
        'blockedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('ModerationService.blockPlayer a esuat: $e');
      return false;
    }
  }

  Future<bool> unblockPlayer(String uid) async {
    final me = _uid;
    if (me.isEmpty) return false;
    blockedIds.value = {...blockedIds.value}..remove(uid);
    try {
      await _blockedCol(me).doc(uid).delete();
      return true;
    } catch (e) {
      debugPrint('ModerationService.unblockPlayer a esuat: $e');
      return false;
    }
  }

  /// Trimite o raportare. Id-ul documentului e `{reporter}_{target}_{moment}`
  /// — cu momentul în el, deliberat: același jucător poate fi reclamat de mai
  /// multe ori de aceeași persoană, iar un id fără timp ar fi suprascris
  /// tăcut raportarea dinainte, adică exact dovada de comportament repetat
  /// pentru care are rost panoul.
  Future<bool> submitReport({
    required String targetUid,
    required String targetName,
    required ReportReason reason,
    String messageText = '',
    String context = '',
  }) async {
    final me = _uid;
    if (me.isEmpty || targetUid.isEmpty || targetUid == me) return false;
    try {
      final identity = await AuthService.instance.multiplayerIdentity();
      final id = '${me}_${targetUid}_${DateTime.now().millisecondsSinceEpoch}';
      await _db.collection('reports').doc(id).set({
        'reporterUid': me,
        'reporterName': identity.name,
        'targetUid': targetUid,
        'targetName': targetName,
        'reason': reason.name,
        'messageText': messageText,
        'context': context,
        'createdAt': FieldValue.serverTimestamp(),
        'handled': false,
      });
      return true;
    } catch (e) {
      debugPrint('ModerationService.submitReport a esuat: $e');
      return false;
    }
  }

  // ─── Doar admin (vezi firestore.rules) ────────────────────────────────────

  /// Raportările, cele mai noi primele. Fără `orderBy` pe server, din același
  /// motiv ca la fetchPendingAuthDeletions: un document scris de un client
  /// care n-a apucat să pună `createdAt` ar dispărea tăcut din listă — exact
  /// ce nu vrei de la un panou de reclamații.
  Future<List<PlayerReport>> fetchReports({int limit = 200}) async {
    try {
      final snap = await _db.collection('reports').limit(limit).get();
      final items = snap.docs.map(PlayerReport.fromDoc).toList();
      items.sort((a, b) {
        final ta = a.createdAt, tb = b.createdAt;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
      return items;
    } catch (e) {
      debugPrint('ModerationService.fetchReports a esuat: $e');
      return [];
    }
  }

  /// Câte raportări încă nerezolvate — pentru bulina de pe tab-ul de admin.
  Future<int> pendingReportCount() async {
    try {
      final agg = await _db.collection('reports').where('handled', isEqualTo: false).count().get();
      return agg.count ?? 0;
    } catch (e) {
      debugPrint('ModerationService.pendingReportCount a esuat: $e');
      return 0;
    }
  }

  Future<bool> markReportHandled(String reportId, {bool handled = true}) async {
    try {
      await _db.collection('reports').doc(reportId).set({'handled': handled}, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('ModerationService.markReportHandled a esuat: $e');
      return false;
    }
  }

  Future<bool> deleteReport(String reportId) async {
    try {
      await _db.collection('reports').doc(reportId).delete();
      return true;
    } catch (e) {
      debugPrint('ModerationService.deleteReport a esuat: $e');
      return false;
    }
  }

  /// Șterge lista proprie de blocați — apelată la ștergerea completă a
  /// contului, ca subcolecția să nu rămână orfană sub un profil care nu mai
  /// există (documentele-copil supraviețuiesc ștergerii părintelui în
  /// Firestore, nu dispar odată cu el).
  Future<void> deleteMyBlockList() async {
    final me = _uid;
    if (me.isEmpty) return;
    try {
      final snap = await _blockedCol(me).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      blockedIds.value = const {};
    } catch (e) {
      debugPrint('ModerationService.deleteMyBlockList a esuat: $e');
    }
  }

  /// Aceeași curățare, dar pentru contul ALTCUIVA — din „Șterge complet" al
  /// adminului (vezi PlayerProfileService.purgePlayer). Permisă de
  /// firestore.rules doar emailului de admin.
  Future<void> deleteBlockListOf(String uid) async {
    if (uid.isEmpty) return;
    try {
      final snap = await _blockedCol(uid).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('ModerationService.deleteBlockListOf a esuat: $e');
    }
  }
}
