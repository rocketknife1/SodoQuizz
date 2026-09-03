import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/admin.dart';
import '../core/chat_filter.dart';
import '../models/admin_message.dart';
import 'auth_service.dart';
import 'multiplayer_service.dart';

/// Firul de mesaje dintre un jucător și administrator — canalul de feedback
/// din joc, în DOUĂ sensuri.
///
/// ## De ce o colecție proprie, nu `friend_chats`
///
/// Firul prieteni-cu-prieteni se numește după cele două uid-uri sortate, iar
/// regulile despică numele ca să verifice apartenența. Aici asta n-ar merge:
/// jucătorul nu știe uid-ul adminului (nu are cum să-l afle, și nici n-ar
/// trebui), deci n-ar putea construi numele firului. Numele documentului e
/// pur și simplu uid-ul JUCĂTORULUI, iar cealaltă parte e „adminul" ca rol,
/// verificat în reguli după emailul din token.
///
/// Consecința bună: adminul poate deschide fir cu oricine fără să existe
/// vreo prietenie, iar jucătorul poate scrie din prima secundă în joc.
///
/// ## Mesajele NU se șterg
///
/// Firele rămân în bază și după ce discuția s-a încheiat: sunt arhiva de
/// feedback a jocului (rapoarte de bug, propuneri). Singura ștergere e cea de
/// la „Șterge complet" pe un cont — vezi [deleteThreadOf].
class AdminChatService {
  AdminChatService._();
  static final instance = AdminChatService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid => MultiplayerService.instance.currentPlayerId;

  /// Cât se încarcă din istoric, ca la [FriendChatService].
  static const _historyLimit = 100;

  /// Aprins când adminul a răspuns și jucătorul n-a deschis încă firul.
  /// Ascultat de butonul SETĂRI din meniul principal, ca să-i pună bulină.
  ///
  /// E un [ValueNotifier], nu un `Stream` recitit de fiecare ecran: bulina se
  /// vede din Home, iar Home nu trebuie să plătească o citire Firestore la
  /// fiecare reconstrucție.
  final ValueNotifier<bool> hasUnreadReply = ValueNotifier<bool>(false);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _mySub;

  /// Publica uid-ul adminului in `config/admin`, ca sa-l poata citi Cloud
  /// Function-ul care trimite push-ul catre el.
  ///
  /// DE CE E NEVOIE: functia stia sa-l caute in Firebase Auth dupa email
  /// (`getUserByEmail`), dar cautarea PICA — „There is no user record
  /// corresponding to the provided identifier". Contul de admin e legat prin
  /// Google/Play Games, iar inregistrarea lui Auth nu are emailul pe campul de
  /// nivel superior dupa care cauta API-ul; emailul exista doar in TOKEN, de
  /// unde il citesc regulile Firestore (de-aia panoul de admin merge).
  ///
  /// Aplicatia adminului stie insa amandoua lucrurile deodata — emailul din
  /// token SI propriul uid — deci le poate lega ea, o data pe pornire. Nimeni
  /// altcineva nu poate scrie documentul (vezi firestore.rules), iar niciun
  /// client nu-l poate citi: singurul cititor e Admin SDK-ul din Functions,
  /// caruia regulile nu i se aplica.
  Future<void> _publishAdminUidIfAdmin() async {
    try {
      final user = AuthService.instance.currentUser;
      if (user == null || user.email != kAdminEmail) return;
      final me = _uid;
      if (me.isEmpty) return;
      await _db.collection('config').doc('admin').set({
        'uid': me,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('AdminChatService._publishAdminUidIfAdmin a esuat: $e');
    }
  }

  DocumentReference<Map<String, dynamic>> _thread(String playerUid) =>
      _db.collection('admin_threads').doc(playerUid);

  // ─── Partea jucătorului ───────────────────────────────────────────────────

  /// Abonament pe PROPRIUL fir, pentru bulina de pe SETĂRI. Pornit/oprit de
  /// LiveSync odată cu restul abonamentelor, ca să nu curgă în fundal.
  void startLive() {
    final me = _uid;
    if (me.isEmpty) return;
    unawaited(_publishAdminUidIfAdmin());
    stopLive();
    try {
      _mySub = _thread(me).snapshots().listen(
        (snap) {
          hasUnreadReply.value =
              snap.exists && AdminThreadSummary.fromDoc(snap).hasUnreadForPlayer;
        },
        onError: (Object e) => debugPrint('AdminChatService._mySub a esuat: $e'),
      );
    } catch (e) {
      debugPrint('AdminChatService.startLive a esuat: $e');
    }
  }

  void stopLive() {
    _mySub?.cancel();
    _mySub = null;
  }

  // ─── Firul propriu-zis (aceleași metode pentru ambele părți) ──────────────

  Stream<List<AdminMessage>> watchMessages(String playerUid) {
    if (playerUid.isEmpty) return Stream.value(const []);
    return _thread(playerUid)
        .collection('messages')
        .orderBy('sentAt')
        .limitToLast(_historyLimit)
        .snapshots()
        .map((s) => s.docs.map(AdminMessage.fromDoc).toList());
  }

  /// Trimite un mesaj în firul lui [playerUid].
  ///
  /// [asAdmin] spune în ce calitate scriu. NU se ghicește aici din email:
  /// apelantul știe din ce ecran a venit, iar regulile Firestore sunt oricum
  /// cele care decid — un jucător care ar trimite `fromAdmin: true` e respins
  /// de server, nu de codul ăsta.
  ///
  /// Mesajul și rezumatul firului se scriu într-un batch, ca la
  /// [FriendChatService.sendMessage]: altfel o cădere între ele ar lăsa lista
  /// din panoul de Admin arătând alt „ultim mesaj" decât firul.
  Future<bool> sendMessage(String playerUid, String rawText, {required bool asAdmin}) async {
    final me = _uid;
    if (me.isEmpty || playerUid.isEmpty) return false;
    final text = sanitizeChatMessage(rawText);
    if (text.isEmpty) return false;
    try {
      final batch = _db.batch();
      batch.set(_thread(playerUid).collection('messages').doc(), {
        'senderId': me,
        'fromAdmin': asAdmin,
        'text': text,
        'sentAt': FieldValue.serverTimestamp(),
      });
      batch.set(_thread(playerUid), {
        'playerUid': playerUid,
        // Numele se împrospătează la fiecare mesaj al jucătorului: dacă și-a
        // schimbat numele între timp, lista adminului nu trebuie să rămână cu
        // cel vechi. Adminul NU îl rescrie (n-are numele celuilalt la
        // îndemână și oricum nu e al lui de scris).
        if (!asAdmin) 'playerName': (await AuthService.instance.multiplayerIdentity()).name,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastText': text,
        'lastFromAdmin': asAdmin,
      }, SetOptions(merge: true));
      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('AdminChatService.sendMessage a esuat: $e');
      return false;
    }
  }

  /// Marchează firul citit de partea care tocmai l-a deschis.
  Future<void> markRead(String playerUid, {required bool asAdmin}) async {
    if (playerUid.isEmpty) return;
    try {
      await _thread(playerUid).set({
        asAdmin ? 'readAtAdmin' : 'readAtPlayer': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!asAdmin) hasUnreadReply.value = false;
    } catch (e) {
      debugPrint('AdminChatService.markRead a esuat: $e');
    }
  }

  // ─── Partea adminului ─────────────────────────────────────────────────────

  /// Toate firele, cel mai recent primul. Interogare pe colecție, permisă
  /// fiindcă regula de citire e `isAdmin()` — nu depinde de conținutul
  /// documentelor, deci motorul o poate demonstra pentru toată colecția
  /// (spre deosebire de `friend_chats`, unde numele documentului e cel
  /// verificat și un query pe colecție e imposibil de dovedit).
  Stream<List<AdminThreadSummary>> watchAllThreads() {
    try {
      return _db
          .collection('admin_threads')
          .orderBy('lastMessageAt', descending: true)
          .limit(200)
          .snapshots()
          .map((s) => s.docs.map(AdminThreadSummary.fromDoc).toList());
    } catch (e) {
      debugPrint('AdminChatService.watchAllThreads a esuat: $e');
      return Stream.value(const []);
    }
  }

  /// Șterge firul unui jucător, cu mesaje cu tot. Chemat DOAR la „Șterge
  /// complet" pe un cont — vezi nota din capul clasei pentru de ce firele nu
  /// se șterg altfel.
  Future<void> deleteThreadOf(String playerUid) async {
    if (playerUid.isEmpty) return;
    try {
      final messages = await _thread(playerUid).collection('messages').get();
      final batch = _db.batch();
      for (final doc in messages.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_thread(playerUid));
      await batch.commit();
    } catch (e) {
      debugPrint('AdminChatService.deleteThreadOf a esuat: $e');
    }
  }
}
