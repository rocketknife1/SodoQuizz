import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../core/lang.dart';
import '../models/app_notification.dart';
import 'friend_chat_service.dart';
import 'moderation_service.dart';
import 'multiplayer_service.dart';
import 'player_profile_service.dart';
import 'storage_service.dart';

/// Ce alimentează clopoțelul de lângă avatarul din meniul principal.
///
/// Notificările vin din trei locuri diferite și, deliberat, NU sunt ținute la
/// fel:
///
///  • ANUNȚURILE DE SISTEM (scrise de admin) sosesc într-o cutie poștală din
///    Firestore, `player_profiles/{uid}/notifications`, exact tiparul deja
///    folosit de `admin_grants` pentru resurse: se descarcă o dată, se scriu
///    pe telefon, se șterg din cloud. Așa merg și pentru un Guest (cutia e
///    legată de uid, iar un Guest are uid de la prima pornire), se citesc
///    offline după prima descărcare și nu costă o citire Firestore de fiecare
///    dată când cineva deschide panoul.
///
///  • CADOURILE („Felicitări, ai primit...") se scriu direct local, în clipa
///    în care resursele chiar intră în cont — vezi
///    CloudSyncService.consumePendingGrant. Nu vin din cloud fiindcă textul
///    lor se compune din ce s-a aplicat efectiv, nu din ce a apăsat adminul.
///
///  • MESAJELE NECITITE ȘI CERERILE DE PRIETENIE nu se salvează deloc. Sunt
///    stări care se schimbă și de pe alt telefon (citești mesajul pe tabletă,
///    accepți cererea din ecranul de Prieteni), deci o copie locală ar arăta
///    notificări pentru lucruri deja rezolvate. Se citesc live la fiecare
///    deschidere a panoului, vezi [fetchLive].
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  /// Câte lucruri necitite are jucătorul acum — bulina de pe clopoțel
  /// ascultă direct valoarea asta. Vezi [refreshUnread].
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  /// Câte notificări se țin pe telefon. Peste asta, cele mai vechi se aruncă:
  /// panoul nu e o arhivă, iar lista intră în cloud-save (vezi
  /// StorageService.exportAll), deci n-are voie să crească la nesfârșit.
  static const _maxStored = 40;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Vezi CloudSyncService._consumingGrant — același tipar, același motiv.
  /// Fără ea, două descărcări suprapuse pot pierde o notificare: [addLocal]
  /// citește lista, o modifică și o scrie înapoi, deci a doua rulare ar
  /// suprascrie ce tocmai a adăugat prima.
  bool _pulling = false;

  String get _uid {
    try {
      return MultiplayerService.instance.currentPlayerId;
    } catch (e) {
      debugPrint('NotificationService._uid a esuat: $e');
      return '';
    }
  }

  CollectionReference<Map<String, dynamic>> _cloudBox(String uid) =>
      _db.collection('player_profiles').doc(uid).collection('notifications');

  // ─── Cutia locală ─────────────────────────────────────────────────────────

  /// Notificările salvate pe telefon, cele mai noi primele.
  Future<List<AppNotification>> loadStored() async {
    final raw = await StorageService.getNotifications();
    final items = raw.map(AppNotification.decode).whereType<AppNotification>().toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// Adaugă o notificare locală. [AppNotification.id] e și cheia de
  /// dedublare: aceeași notificare ajunsă de două ori (o descărcare reluată
  /// după o pică de rețea) nu se dublează în panou.
  ///
  /// [refreshBadge] false: nu recalcula bulina acum. Folosit de
  /// [_pullFromCloud], care adaugă mai multe anunțuri în buclă și recalculează
  /// O SINGURĂ DATĂ la final — altfel fiecare anunț sosit ar fi costat `2 + N`
  /// citiri Firestore prin `refreshUnread` -> `fetchLive`, adică descărcarea a
  /// k anunțuri ar fi costat `k × (2 + N)`.
  Future<void> addLocal(AppNotification notification, {bool refreshBadge = true}) async {
    final current = await loadStored();
    if (current.any((n) => n.id == notification.id)) return;
    final updated = [notification, ...current].take(_maxStored).toList();
    await StorageService.setNotifications(updated.map((n) => n.encode()).toList());
    if (refreshBadge) await refreshUnread();
  }

  /// Compune și salvează notificarea de cadou din ce a intrat EFECTIV în cont.
  /// Chemată de CloudSyncService după ce resursele au fost deja aplicate —
  /// vezi nota din capul clasei pentru de ce nu vine gata scrisă din cloud.
  ///
  /// [grantId] face textul stabil la reluări: dacă scrierea locală pică după
  /// ce grant-ul a fost consumat, o a doua încercare nu produce o a doua
  /// notificare pentru același cadou.
  Future<void> addGrantNotification({
    required String grantId,
    int hearts = 0,
    int hints = 0,
    int coins = 0,
    int gems = 0,
    int xp = 0,
    bool wasReset = false,
  }) async {
    final gained = <String>[];
    final lost = <String>[];
    void add(int amount, String roOne, String enOne) {
      if (amount == 0) return;
      final text = '${amount.abs()} ${tr(roOne, enOne)}';
      (amount > 0 ? gained : lost).add(text);
    }

    add(coins, 'monede', 'coins');
    add(gems, 'gems', 'gems');
    add(hearts, 'vieți', 'lives');
    add(hints, 'hint-uri', 'hints');
    add(xp, 'XP', 'XP');

    if (gained.isEmpty && lost.isEmpty && !wasReset) return;

    final String title;
    final String body;
    if (gained.isNotEmpty) {
      title = tr('🎉 Felicitări, ai primit ceva!', '🎉 Congratulations, you got something!');
      final rest = lost.isEmpty ? '' : tr('\nS-au retras: ${lost.join(", ")}.', '\nRemoved: ${lost.join(", ")}.');
      body = tr(
        'Ai primit ${_join(gained)}. Sunt deja în contul tău.',
        'You received ${_join(gained)}. They are already in your account.',
      ) + rest;
    } else if (lost.isNotEmpty) {
      title = tr('Contul tău a fost ajustat', 'Your account was adjusted');
      body = tr('S-au retras ${_join(lost)}.', '${_join(lost)} were removed.');
    } else {
      title = tr('Contul tău a fost resetat', 'Your account was reset');
      body = tr(
        'Progresul a fost adus la valorile de început de către administrator.',
        'Your progress was reset to starting values by the administrator.',
      );
    }

    await addLocal(AppNotification(
      id: 'grant_$grantId',
      type: AppNotificationType.gift,
      title: title,
      body: body,
      createdAt: DateTime.now(),
    ));
  }

  /// „a, b și c" — lista de resurse, citibilă, nu înșiruire cu virgule.
  static String _join(List<String> parts) {
    if (parts.length == 1) return parts.first;
    return '${parts.sublist(0, parts.length - 1).join(", ")} ${tr("și", "and")} ${parts.last}';
  }

  // ─── Cutia poștală din cloud (anunțuri de la admin) ───────────────────────

  /// Descarcă ce a lăsat adminul, scrie local și șterge din cloud. No-op
  /// sigur fără identitate sau fără nimic în așteptare. Chemată la pornire și
  /// la revenirea din fundal, ca grant-urile.
  Future<void> pullFromCloud() async {
    if (_pulling) return;
    _pulling = true;
    try {
      await _pullFromCloud();
    } finally {
      _pulling = false;
    }
  }

  Future<void> _pullFromCloud() async {
    final uid = _uid;
    if (uid.isEmpty) return;
    try {
      final snap = await _cloudBox(uid).get();
      if (snap.docs.isEmpty) return;
      for (final doc in snap.docs) {
        final data = doc.data();
        final sentAt = data['sentAt'] as Timestamp?;
        // Anunțurile de admin (majoritatea) nu scriu un câmp `type` —
        // rămân `system`, retrocompatibil. De la notificările de depășire
        // de ligă încoace (scrise de UN PRIETEN, nu de admin — vezi
        // PlayerProfileService._notifyOvertake), cutia poate conține și alt
        // tip, deci se citește explicit dacă e prezent.
        final type = AppNotificationType.values.firstWhere(
          (t) => t.name == data['type'],
          orElse: () => AppNotificationType.system,
        );
        await addLocal(AppNotification(
          id: doc.id,
          type: type,
          title: data['title'] as String? ?? tr('Anunț', 'Announcement'),
          body: data['body'] as String? ?? '',
          createdAt: sentAt?.toDate() ?? DateTime.now(),
          peerUid: data['peerUid'] as String? ?? '',
          peerName: data['peerName'] as String? ?? '',
        ), refreshBadge: false);
        // Ștearsă abia după ce a fost scrisă local — altfel o pică între cele
        // două operații ar fi pierdut anunțul definitiv.
        await doc.reference.delete();
      }
      // Recalcularea bulinei se face AICI, o singură dată după buclă — nu în
      // `addLocal` per anunț. `refreshUnreadLocalOnly` (nu `refreshUnread`):
      // anunțurile sunt deja locale acum, deci partea locală ajunge și nu
      // atinge `fetchLive`. Apelantul (abonamentul din [startLive]) NU mai
      // recalculează separat.
      await refreshUnreadLocalOnly();
    } catch (e) {
      debugPrint('NotificationService.pullFromCloud a esuat: $e');
    }
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _inboxSub;

  /// Anunțurile lăsate de admin ajung acum cât jucătorul e în joc.
  ///
  /// Se cheamă [pullFromCloud], nu se procesează snapshot-ul direct: aceea
  /// știe deja să copieze anunțurile local ȘI să le șteargă din cloud, iar
  /// duplicarea acelei logici aici ar fi însemnat două căi care trebuie ținute
  /// în sincron. Garda `_pulling` face apelurile suprapuse inofensive.
  ///
  /// Se cheamă [refreshUnreadLocalOnly], nu [refreshUnread]: al doilea
  /// declanșează [fetchLive], adică `2 + N` citiri Firestore (N = numărul de
  /// prieteni) pentru un singur anunț sosit. Anunțurile sunt deja salvate local
  /// în acel moment, deci partea locală ajunge.
  void startLive() {
    final uid = _uid;
    if (uid.isEmpty) return;
    stopLive();
    try {
      _inboxSub = _cloudBox(uid).snapshots().listen((snap) {
        if (snap.metadata.hasPendingWrites) return;
        if (snap.docs.isEmpty) return;
        // `pullFromCloud` recalculează singură bulina la final (local-only) —
        // nu se mai adaugă un `refreshUnread*` aici.
        unawaited(pullFromCloud());
      }, onError: (Object e) {
        debugPrint('NotificationService._inboxSub a esuat: $e');
      });
    } catch (e) {
      debugPrint('NotificationService.startLive a esuat: $e');
    }
  }

  void stopLive() {
    _inboxSub?.cancel();
    _inboxSub = null;
  }

  // ─── Stările live (mesaje necitite, cereri de prietenie) ──────────────────

  /// Mesajele necitite de la prieteni și cererile de prietenie primite.
  /// Costă câteva citiri Firestore, deci se cheamă la deschiderea panoului și
  /// la calculul bulinei, nu în buclă.
  ///
  /// Jucătorii blocați sunt săriți: dacă cineva a apăsat „blochează", n-are
  /// sens ca mesajul lui să-i sune clopoțelul mai departe (vezi
  /// ModerationService).
  Future<List<AppNotification>> fetchLive() async {
    final me = _uid;
    if (me.isEmpty) return const [];
    final result = <AppNotification>[];
    try {
      final requests = await PlayerProfileService.instance.fetchIncomingRequests();
      for (final r in requests) {
        if (ModerationService.instance.isBlocked(r.fromUid)) continue;
        result.add(AppNotification(
          id: 'req_${r.fromUid}',
          type: AppNotificationType.friendRequest,
          title: tr('Cerere de prietenie', 'Friend request'),
          body: tr('${r.fromName} vrea să te adauge ca prieten.', '${r.fromName} wants to add you as a friend.'),
          createdAt: r.createdAt?.toDate() ?? DateTime.now(),
          peerUid: r.fromUid,
          peerName: r.fromName,
        ));
      }
    } catch (e) {
      debugPrint('NotificationService.fetchLive (cereri) a esuat: $e');
    }
    try {
      final friends = await PlayerProfileService.instance.fetchFriends();
      final visible = friends.where((f) => !ModerationService.instance.isBlocked(f.uid)).toList();
      final summaries = await FriendChatService.instance.fetchSummaries(visible.map((f) => f.uid).toList());
      for (final friend in visible) {
        final summary = summaries[friend.uid];
        if (summary == null || !summary.hasUnreadFor(me)) continue;
        result.add(AppNotification(
          id: 'msg_${friend.uid}',
          type: AppNotificationType.message,
          title: tr('Mesaj de la ${friend.name}', 'Message from ${friend.name}'),
          body: summary.lastText,
          createdAt: summary.lastMessageAt?.toDate() ?? DateTime.now(),
          peerUid: friend.uid,
          peerName: friend.name,
        ));
      }
    } catch (e) {
      debugPrint('NotificationService.fetchLive (mesaje) a esuat: $e');
    }
    return result;
  }

  /// Tot ce se vede în panou, într-o singură listă ordonată — salvate + live.
  Future<List<AppNotification>> fetchAll() async {
    final results = await Future.wait([loadStored(), fetchLive()]);
    final all = [...results[0], ...results[1]]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }

  // ─── Partea live a bulinei, ținută de abonamente ─────────────────────────

  /// Cea mai recentă cifră „live" (cereri în așteptare + fire cu mesaj
  /// necitit) primită de la abonamentele din LiveSync. Ținută separat ca
  /// [_recomputeUnread] s-o poată aduna cu partea locală fără nicio citire
  /// nouă. [refreshUnread] o resincronizează când chiar întreabă rețeaua.
  int _liveUnread = 0;

  /// Partea locală a bulinei, memorată din ultima citire de pe telefon
  /// (SharedPreferences). Ținută în cache ca [setLiveUnread] să poată actualiza
  /// [unreadCount] SINCRON — altfel un snapshot sosit ar mișca bulina abia
  /// după un `await` pe disc, iar testele n-ar avea de ce să se agațe.
  int _storedUnread = 0;

  /// Anunțat de abonamentele din LiveSync: câte cereri în așteptare și câte
  /// fire cu mesaj necitit există ACUM. Nu produce nicio citire în plus —
  /// cifrele vin din snapshot-urile deja primite. NU cheamă [refreshUnread]
  /// (aceea declanșează [fetchLive] = `2 + N` citiri per eveniment).
  void setLiveUnread({required int pendingRequests, required int unreadThreads}) {
    _liveUnread = pendingRequests + unreadThreads;
    // Sincron, din cifre deja în memorie: bulina reflectă imediat schimbarea.
    unreadCount.value = _storedUnread + _liveUnread;
    // Async, fără citiri de rețea: doar reîmprospătează partea locală de pe disc.
    unawaited(_recomputeUnread());
  }

  /// Reface [unreadCount] din partea locală (deja pe telefon) + [_liveUnread]
  /// (deja primit prin snapshot). Zero citiri Firestore.
  Future<void> _recomputeUnread() async {
    try {
      final readAt = await StorageService.getNotificationsReadAt();
      final stored = await loadStored();
      _storedUnread = stored.where((n) => n.createdAt.millisecondsSinceEpoch > readAt).length;
      unreadCount.value = _storedUnread + _liveUnread;
    } catch (e) {
      debugPrint('NotificationService._recomputeUnread a esuat: $e');
    }
  }

  // ─── Bulina ───────────────────────────────────────────────────────────────

  /// Recalculează bulina: notificările salvate venite după ultima deschidere
  /// a panoului + tot ce e live (un mesaj necitit sau o cerere în așteptare e
  /// necitit prin definiție, nu se compară cu nimic).
  ///
  /// Nu aruncă niciodată — clopoțelul e decor pe lângă restul jocului, iar o
  /// rețea căzută n-are voie să strice meniul principal.
  Future<void> refreshUnread() async {
    try {
      final readAt = await StorageService.getNotificationsReadAt();
      final stored = await loadStored();
      final unreadStored = stored.where((n) => n.createdAt.millisecondsSinceEpoch > readAt).length;
      final live = await fetchLive();
      // Resincronizează ambele jumătăți cu ce tocmai a întors rețeaua, ca un
      // [_recomputeUnread] ulterior (declanșat de un snapshot) să pornească de
      // la cifrele corecte.
      _storedUnread = unreadStored;
      _liveUnread = live.length;
      unreadCount.value = unreadStored + live.length;
    } catch (e) {
      debugPrint('NotificationService.refreshUnread a esuat: $e');
    }
  }

  /// Doar partea locală a bulinei — fără nicio citire Firestore. Folosită la
  /// pornire, ca meniul să arate imediat un număr corect-ish, înainte ca
  /// [refreshUnread] să apuce să întrebe rețeaua.
  Future<void> refreshUnreadLocalOnly() async {
    try {
      final readAt = await StorageService.getNotificationsReadAt();
      final stored = await loadStored();
      _storedUnread = stored.where((n) => n.createdAt.millisecondsSinceEpoch > readAt).length;
      unreadCount.value = _storedUnread + _liveUnread;
    } catch (e) {
      debugPrint('NotificationService.refreshUnreadLocalOnly a esuat: $e');
    }
  }

  /// Marchează notificările SALVATE ca văzute. Cele live (mesaje, cereri) nu
  /// se sting de aici, intenționat: un mesaj rămâne necitit până îl deschizi
  /// chiar tu, iar o cerere de prietenie până o accepți sau o refuzi — altfel
  /// o simplă privire prin panou le-ar fi făcut să dispară nerezolvate.
  Future<void> markStoredRead() async {
    await StorageService.setNotificationsReadAt(DateTime.now().millisecondsSinceEpoch);
    await refreshUnread();
  }

  /// Golește panoul (butonul „Șterge tot"). Nu atinge mesajele și cererile —
  /// alea sunt în Firestore, nu aici.
  Future<void> clearStored() async {
    await StorageService.setNotifications(const []);
    await refreshUnread();
  }
}
