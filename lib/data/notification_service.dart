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
  Future<void> addLocal(AppNotification notification) async {
    final current = await loadStored();
    if (current.any((n) => n.id == notification.id)) return;
    final updated = [notification, ...current].take(_maxStored).toList();
    await StorageService.setNotifications(updated.map((n) => n.encode()).toList());
    await refreshUnread();
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
    final uid = _uid;
    if (uid.isEmpty) return;
    try {
      final snap = await _cloudBox(uid).get();
      if (snap.docs.isEmpty) return;
      for (final doc in snap.docs) {
        final data = doc.data();
        final sentAt = data['sentAt'] as Timestamp?;
        await addLocal(AppNotification(
          id: doc.id,
          type: AppNotificationType.system,
          title: data['title'] as String? ?? tr('Anunț', 'Announcement'),
          body: data['body'] as String? ?? '',
          createdAt: sentAt?.toDate() ?? DateTime.now(),
        ));
        // Ștearsă abia după ce a fost scrisă local — altfel o pică între cele
        // două operații ar fi pierdut anunțul definitiv.
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('NotificationService.pullFromCloud a esuat: $e');
    }
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
      unreadCount.value = stored.where((n) => n.createdAt.millisecondsSinceEpoch > readAt).length;
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
