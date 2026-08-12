import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../core/chat_filter.dart';
import '../models/friend_chat.dart';
import 'multiplayer_service.dart';

/// Chatul privat dintre doi prieteni — complet separat de chatul din camera
/// multiplayer (acela rămâne cum era: legat de meci, șters odată cu el).
///
/// Unde se vede: DOAR intrând în firul unui prieten anume, din ecranul de
/// Prieteni. Nu există o listă globală de conversații și nu apare nicăieri
/// altundeva în joc — a fost cerut exact așa.
///
/// CUM SE NUMEȘTE UN FIR: cele două uid-uri, sortate alfabetic, lipite cu
/// „_" („A_B", niciodată „B_A"). Sortarea e ce face numele să iasă identic
/// indiferent cine deschide primul, deci amândoi ajung în același document
/// fără să existe undeva o evidență a firelor. Tot ea e și verificarea de
/// securitate: firestore.rules despică id-ul după „_" și cere ca `auth.uid`
/// să fie una din cele două bucăți — nimeni altcineva nu poate citi firul.
/// Funcționează fiindcă uid-urile Firebase sunt alfanumerice, fără „_".
///
/// Ce NU verifică regulile: dacă cei doi chiar sunt prieteni. Ar fi cerut o
/// citire în plus la fiecare mesaj (un `get()` pe subcolecția de prieteni),
/// iar ecranul se deschide oricum numai din lista de prieteni. Cel mai rău
/// caz posibil e ca doi oameni care s-au șters din prieteni să-și mai poată
/// scrie — nu e o scurgere de date, firul e tot al lor.
class FriendChatService {
  FriendChatService._();
  static final instance = FriendChatService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid => MultiplayerService.instance.currentPlayerId;

  /// Cât se ține minte din fiecare fir la afișarea în ecran. Ca la chatul din
  /// cameră (limitToLast(100)) — un fir vechi nu are de ce să se încarce
  /// întreg pe telefon.
  static const _historyLimit = 100;

  /// Numele firului dintre mine și [otherUid]. Vezi nota din capul clasei
  /// pentru de ce se sortează.
  static String threadIdFor(String a, String b) {
    final pair = [a, b]..sort();
    return '${pair[0]}_${pair[1]}';
  }

  String? _myThreadWith(String otherUid) {
    final me = _uid;
    if (me.isEmpty || otherUid.isEmpty || otherUid == me) return null;
    return threadIdFor(me, otherUid);
  }

  DocumentReference<Map<String, dynamic>> _thread(String threadId) => _db.collection('friend_chats').doc(threadId);

  Stream<List<FriendMessage>> watchMessages(String otherUid) {
    final threadId = _myThreadWith(otherUid);
    if (threadId == null) return Stream.value(const []);
    return _thread(threadId)
        .collection('messages')
        .orderBy('sentAt')
        .limitToLast(_historyLimit)
        .snapshots()
        .map((s) => s.docs.map(FriendMessage.fromDoc).toList());
  }

  /// Scrie mesajul ȘI rezumatul firului, într-un batch — dacă s-ar scrie
  /// separat, o cădere între ele ar lăsa ecranul de Prieteni arătând un alt
  /// „ultim mesaj" decât cel din fir.
  ///
  /// Textul trece prin [sanitizeChatMessage] înainte de scriere, la fel ca în
  /// camera multiplayer. Întoarce false dacă n-a mai rămas nimic de trimis
  /// (mesaj gol sau numai spații).
  Future<bool> sendMessage(String otherUid, String rawText) async {
    final threadId = _myThreadWith(otherUid);
    if (threadId == null) return false;
    final text = sanitizeChatMessage(rawText);
    if (text.isEmpty) return false;
    final me = _uid;
    try {
      final batch = _db.batch();
      batch.set(_thread(threadId).collection('messages').doc(), {
        'senderId': me,
        'text': text,
        'sentAt': FieldValue.serverTimestamp(),
      });
      batch.set(_thread(threadId), {
        'members': [me, otherUid]..sort(),
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderId': me,
        'lastText': text,
      }, SetOptions(merge: true));
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('FriendChatService.sendMessage a esuat: $e');
      return false;
    }
  }

  /// Marchează firul ca citit de mine. Scrisă la deschiderea ecranului și la
  /// fiecare mesaj nou primit cât ecranul e deschis — altfel bulina de
  /// „necitit" ar reapărea pe ecranul de Prieteni pentru mesaje pe care
  /// tocmai le-am văzut cu ochii mei.
  Future<void> markRead(String otherUid) async {
    final threadId = _myThreadWith(otherUid);
    if (threadId == null) return;
    try {
      await _thread(threadId).set({
        'readAt': {_uid: FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('FriendChatService.markRead a esuat: $e');
    }
  }

  /// Rezumatele firelor cu prietenii dați, pentru ecranul de Prieteni.
  /// Cheia din rezultat e uid-ul prietenului, nu id-ul firului. Firele care
  /// nu există încă (n-au vorbit niciodată) pur și simplu lipsesc.
  Future<Map<String, FriendChatSummary>> fetchSummaries(List<String> friendUids) async {
    final me = _uid;
    if (me.isEmpty || friendUids.isEmpty) return const {};
    final result = <String, FriendChatSummary>{};
    await Future.wait(friendUids.map((uid) async {
      try {
        final doc = await _thread(threadIdFor(me, uid)).get();
        if (doc.exists) result[uid] = FriendChatSummary.fromDoc(doc);
      } catch (e) {
        debugPrint('FriendChatService.fetchSummaries a esuat pentru $uid: $e');
      }
    }));
    return result;
  }

  /// Șterge firul cu un prieten, cu mesaje cu tot. Apelat la ștergerea
  /// completă a contului — un fir rămas în urmă ar fi însemnat mesajele
  /// cuiva care și-a șters contul, păstrate mai departe în bază.
  ///
  /// Ștergerea e simetrică prin natura ei: firul e unul singur pentru
  /// amândoi, deci dispare și de la celălalt. E alegerea corectă aici (contul
  /// dispare cu totul), dar de-aia NU se apelează la simpla scoatere din
  /// prieteni — acolo ar șterge din greșeală și istoricul celuilalt.
  Future<void> deleteThreadWith(String otherUid, {String? forUid}) async {
    final me = forUid ?? _uid;
    if (me.isEmpty || otherUid.isEmpty) return;
    final threadId = threadIdFor(me, otherUid);
    try {
      final messages = await _thread(threadId).collection('messages').get();
      final batch = _db.batch();
      for (final doc in messages.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_thread(threadId));
      await batch.commit();
    } catch (e) {
      debugPrint('FriendChatService.deleteThreadWith a esuat: $e');
    }
  }
}
