import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../models/friend_chat.dart';
import 'cloud_sync_service.dart';
import 'friend_chat_service.dart';
import 'moderation_service.dart';
import 'multiplayer_service.dart';
import 'notification_service.dart';
import 'player_profile_service.dart';

/// Pornește și oprește, dintr-un singur loc, toate abonamentele care aduc
/// schimbări din exterior cât timp jocul e deschis (resurse de la admin,
/// redenumire, anunțuri, blocări, cereri de prietenie, mesaje).
///
/// DE CE E LEGAT DE IDENTITATE, NU DOAR DE CICLUL DE VIAȚĂ: un abonament
/// pornit pentru un uid și rămas deschis după ce identitatea s-a schimbat ar
/// livra datele altcuiva. Căile prin care uid-ul se schimbă sunt mai multe
/// decât pare — legare Google, legare Play Games, `credential-already-in-use`
/// (uid nou), delogare (uid GOL, fără identitate nouă până la repornire) și
/// ștergere de cont (șterge profilul cu uid-ul vechi ÎNCĂ activ). De aceea
/// [_applyIdentity] anulează tot NECONDIȚIONAT, înainte de orice verificare,
/// și abia apoi decide dacă repornește.
///
/// `userChanges()`, nu `authStateChanges()`: la legarea unui cont Google
/// peste identitatea anonimă uid-ul NU se schimbă, deci `authStateChanges`
/// poate să nu emită deloc — dar numele afișat se schimbă, iar de el depinde
/// ce se vede în joc.
///
/// DOUĂ STĂRI ȚINUTE SEPARAT, [_foreground] și [_running]: prima înseamnă
/// „aplicația e în prim-plan", a doua „abonamentele sunt atașate". Confundate
/// într-un singur bool, un eveniment de identitate sosit cât aplicația e în
/// fundal (reîmprospătarea tokenului vine la ~55 min, garantat) reatașa
/// abonamentele în fundal, iar un `start()` de la revenire putea pretinde că
/// rulează ceva fără să existe vreo identitate.
class LiveSync {
  LiveSync._();
  static final instance = LiveSync._();

  StreamSubscription<User?>? _identitySub;

  /// Uid-ul pentru care abonamentele sunt (sau erau ultima dată) atașate.
  /// `null` când nu există identitate — curățat la delogare, altfel relogarea
  /// pe ACELAȘI cont cădea pe ieșirea scurtă din [_applyIdentity] și nu mai
  /// pornea niciodată nimic.
  String? _startedForUid;

  /// „Abonamentele sunt atașate acum." Mișcat DOAR de [_startSubs]/[_stopSubs].
  bool _running = false;

  /// „Aplicația e în prim-plan." Presupus la pornire (Flutter nu livrează
  /// starea inițială de ciclu de viață). Mișcat de [start]/[stop].
  bool _foreground = true;

  // ─── Cusături de test ────────────────────────────────────────────────────
  // Implicit: serviciile reale. `test/live_sync_test.dart` le înlocuiește prin
  // [resetForTest] ca să verifice mașina de stări fără Firebase. API-ul public
  // (attachToIdentity / start / stop) rămâne neschimbat.
  void Function() _onStartSubs = _startAllServices;
  void Function() _onStopSubs = _stopAllServices;
  String Function() _readUid = _currentUidFromSingleton;

  /// Toate abonamentele live, într-un singur loc. Serviciile noi se adaugă
  /// aici, nu în [start]/[stop] — acelea sunt mașina de stări, asta e lista.
  static void _startAllServices() {
    CloudSyncService.instance.startLive();
    PlayerProfileService.instance.startLive();
    NotificationService.instance.startLive();
    ModerationService.instance.startLive();
    instance._startFriendWatchers();
  }

  static void _stopAllServices() {
    CloudSyncService.instance.stopLive();
    PlayerProfileService.instance.stopLive();
    NotificationService.instance.stopLive();
    ModerationService.instance.stopLive();
    instance._stopFriendWatchers();
  }

  // ─── Mesajele necitite și cererile de prietenie, live ────────────────────
  //
  // Bulina de pe clopoțel nu se aprindea niciodată cât stăteai în meniu, iar
  // ecranul de Prieteni era o poză făcută la intrare. Aici stau abonamentele
  // care le mișcă live.
  //
  // COSTUL E O CONDIȚIE, NU UN DETALIU: niciun eveniment de aici nu ajunge la
  // `NotificationService.refreshUnread()` (aceea cheamă `fetchLive()` =
  // `2 + N` citiri Firestore pentru un singur mesaj). Se folosește
  // [NotificationService.setLiveUnread], care actualizează bulina din
  // snapshot-urile deja primite, fără nicio citire nouă.
  //
  // Sursele sunt injectabile (cusături de test) ca resincronizarea, anularea
  // și filtrarea de blocare să fie verificabile fără Firebase — vezi
  // `test/live_sync_test.dart`.

  Stream<List<String>> Function() _friendUidsSource = _realFriendUids;
  Stream<List<String>> Function() _requestUidsSource = _realRequestUids;
  Stream<FriendChatSummary?> Function(String uid) _summarySource = _realSummary;
  bool Function(String uid) _isBlocked = _realIsBlocked;
  void Function(int pending, int unread) _liveUnreadSink = _realLiveUnreadSink;
  void Function() Function(VoidCallback onChange) _blockedChangesSource = _realBlockedChanges;

  static Stream<List<String>> _realFriendUids() => PlayerProfileService.instance.watchFriendUids();
  static Stream<List<String>> _realRequestUids() =>
      PlayerProfileService.instance.watchIncomingRequestFromUids();
  static Stream<FriendChatSummary?> _realSummary(String uid) =>
      FriendChatService.instance.watchSummary(uid);
  static bool _realIsBlocked(String uid) => ModerationService.instance.isBlocked(uid);
  static void _realLiveUnreadSink(int pending, int unread) =>
      NotificationService.instance.setLiveUnread(pendingRequests: pending, unreadThreads: unread);
  static void Function() _realBlockedChanges(VoidCallback onChange) {
    final n = ModerationService.instance.blockedIds;
    n.addListener(onChange);
    return () => n.removeListener(onChange);
  }

  StreamSubscription<List<String>>? _requestsSub;
  StreamSubscription<List<String>>? _friendsListSub;

  /// uid prieten → abonamentul pe firul lui. Un abonament pe DOCUMENT per fir,
  /// nu o interogare pe colecție (ar fi respinsă de reguli — vezi
  /// `FriendChatService.watchSummary`).
  final Map<String, StreamSubscription<FriendChatSummary?>> _threadSubs = {};

  /// Cum se opresc abonamentele pe lista de blocați (`blockedIds` e un
  /// `ValueNotifier` care se schimbă sub noi când cineva blochează pe cineva).
  void Function()? _stopBlockedWatch;

  /// Stare BRUTĂ, nefiltrată: expeditorii cererilor primite și prietenii cu
  /// mesaj necitit. Filtrarea de blocare se aplică la împingere ([_pushUnread]),
  /// nu aici — altfel o schimbare a listei de blocați n-ar recalcula bulina.
  List<String> _requestFromUids = const [];
  final Set<String> _unreadThreadUids = {};

  /// uid prieten → capul firului lui, cel mai recent snapshot. Ecranul de
  /// Prieteni ascultă asta ca să-și miște rândurile de chat la ORICE schimbare
  /// de fir — inclusiv al doilea mesaj de la același prieten, care nu mișcă
  /// numărul agregat din bulină — fără să recitească nimic din Firestore.
  final ValueNotifier<Map<String, FriendChatSummary>> friendSummaries =
      ValueNotifier<Map<String, FriendChatSummary>>(const {});

  /// Uid-urile cererilor de prietenie primite, deja filtrate de blocare.
  /// Ecranul de Prieteni ascultă asta ca să-și reîncarce lista de cereri când
  /// una nouă sosește cât stai pe ecran — înainte, semnalul venea indirect
  /// prin `unreadCount`; de când ecranul ascultă doar rezumatele firelor,
  /// cererile aveau nevoie de un canal propriu.
  final ValueNotifier<List<String>> incomingRequestUids =
      ValueNotifier<List<String>>(const []);

  void _startFriendWatchers() {
    // Aliniat cu `NotificationService.startLive` etc.: curăță întâi, ca un al
    // doilea apelant să nu lase abonamente agățate.
    _stopFriendWatchers();
    final me = _readUid();
    if (me.isEmpty) return;
    _stopBlockedWatch = _blockedChangesSource(_pushUnread);
    // `onError:` prinde doar erorile stream-ului Firestore; corpul `listen` are
    // propriul try/catch pentru orice altceva (tiparul din
    // `PlayerProfileService.startLive`).
    _requestsSub = _requestUidsSource().listen(
      (uids) {
        try {
          _requestFromUids = uids;
          _pushUnread();
        } catch (e) {
          debugPrint('LiveSync._requestsSub a esuat: $e');
        }
      },
      onError: (Object e) => debugPrint('LiveSync._requestsSub a esuat: $e'),
    );
    // Lista de prieteni se schimbă (prieten adăugat/șters) → abonamentele per
    // fir se refac. Aflăm prin acest abonament pe subcolecția `friends`, nu
    // recitind-o periodic.
    _friendsListSub = _friendUidsSource().listen(
      (uids) {
        try {
          _resyncThreadSubs(uids.toSet(), me);
        } catch (e) {
          debugPrint('LiveSync._friendsListSub a esuat: $e');
        }
      },
      onError: (Object e) => debugPrint('LiveSync._friendsListSub a esuat: $e'),
    );
  }

  void _resyncThreadSubs(Set<String> friendUids, String me) {
    // Prieteni dispăruți: ANULEAZĂ firul (nu doar scoate-l din hartă) și curăță
    // starea de necitit + rezumatul.
    for (final uid in _threadSubs.keys.toList()) {
      if (!friendUids.contains(uid)) {
        _threadSubs.remove(uid)?.cancel();
        _unreadThreadUids.remove(uid);
        _writeSummary(uid, null);
      }
    }
    // Prieteni noi: un abonament pe firul fiecăruia.
    for (final uid in friendUids) {
      if (_threadSubs.containsKey(uid)) continue;
      _threadSubs[uid] = _summarySource(uid).listen(
        (summary) {
          try {
            // `hasUnreadFor` e deja scrisă și testată (friend_chat.dart:65) —
            // știe că lipsa lui readAt[me] NU înseamnă „citit".
            if (summary != null && summary.hasUnreadFor(me)) {
              _unreadThreadUids.add(uid);
            } else {
              _unreadThreadUids.remove(uid);
            }
            _writeSummary(uid, summary);
            _pushUnread();
          } catch (e) {
            debugPrint('LiveSync.watchSummary a esuat: $e');
          }
        },
        onError: (Object e) => debugPrint('LiveSync.watchSummary a esuat: $e'),
      );
    }
    _pushUnread();
  }

  void _writeSummary(String uid, FriendChatSummary? summary) {
    final next = Map<String, FriendChatSummary>.from(friendSummaries.value);
    if (summary == null) {
      if (next.remove(uid) == null) return;
    } else {
      next[uid] = summary;
    }
    friendSummaries.value = next;
  }

  void _stopFriendWatchers() {
    _stopBlockedWatch?.call();
    _stopBlockedWatch = null;
    _requestsSub?.cancel();
    _requestsSub = null;
    _friendsListSub?.cancel();
    _friendsListSub = null;
    // Sunt N abonamente pe fire, nu unul — se anulează toate.
    for (final sub in _threadSubs.values) {
      sub.cancel();
    }
    _threadSubs.clear();
    _unreadThreadUids.clear();
    _requestFromUids = const [];
    // [friendSummaries] și [incomingRequestUids] NU se golesc aici: la trecerea
    // în FUNDAL (singurul alt apelant în afară de o schimbare de identitate)
    // ecranul de Prieteni, dacă e montat, ar face un `_load()` întreg (~2N
    // citiri) fix în clipa în care aplicația pleacă, iar previzualizările ar
    // dispărea vizibil ca să reapară la revenire. Golirea aparține schimbării
    // de identitate — se face în [_applyIdentity].
  }

  /// Recalculează, din starea BRUTĂ deja adunată din snapshot-uri, tot ce
  /// depinde de ea: uid-urile cererilor filtrate (pentru ecranul de Prieteni)
  /// și cele două cifre ale bulinei. Fără nicio citire Firestore. Jucătorii
  /// blocați sunt săriți din AMBELE surse, la fel ca [NotificationService.fetchLive]:
  /// altfel cineva blocat ar putea aprinde clopoțelul sau apărea în lista de
  /// cereri, exact canalul pe care blocarea trebuie să-l închidă. Filtrarea e
  /// aici, nu la primire, ca o schimbare a listei de blocați să recalculeze.
  void _pushUnread() {
    final pendingUids = _requestFromUids.where((u) => !_isBlocked(u)).toList();
    final unread = _unreadThreadUids.where((u) => !_isBlocked(u)).length;
    if (!listEquals(incomingRequestUids.value, pendingUids)) {
      incomingRequestUids.value = pendingUids;
    }
    _liveUnreadSink(pendingUids.length, unread);
  }

  static String _currentUidFromSingleton() {
    // Aceeași cale ca `CloudSyncService._uid`. `currentPlayerId` atinge
    // `FirebaseAuth.instance`, care aruncă sincron fără Firebase — de aceea
    // try/catch aici, NU garda `Firebase.apps.isEmpty`: [start] se cheamă din
    // ciclul de viață, unde garda aia lipsește.
    try {
      return MultiplayerService.instance.currentPlayerId;
    } catch (e) {
      debugPrint('LiveSync._currentUidFromSingleton a esuat: $e');
      return '';
    }
  }

  /// Se cheamă O SINGURĂ DATĂ, din `_GuessItAppState.initState`. Flutter nu
  /// livrează starea inițială de ciclu de viață prin
  /// `didChangeAppLifecycleState`, deci prima pornire nu poate veni de acolo.
  void attachToIdentity() {
    // Fără gardă, `test/widget_test.dart` — care montează aplicația direct,
    // fără `Firebase.initializeApp` — ar arunca la simpla atingere a lui
    // FirebaseAuth.instance. Vezi precedentul din main.dart.
    if (Firebase.apps.isEmpty) return;
    // Idempotent: dacă abonamentul pe identitate există deja, nu-l dublăm.
    if (_identitySub != null) return;
    try {
      _identitySub = FirebaseAuth.instance.userChanges().listen(_onIdentityChanged);
    } catch (e) {
      debugPrint('LiveSync.attachToIdentity a esuat: $e');
    }
  }

  void _onIdentityChanged(User? user) => _applyIdentity(user?.uid ?? '');

  void _applyIdentity(String uid) {
    // ACEEAȘI identitate? Nu e o schimbare de cont, e doar un eveniment de la
    // Firebase pe același uid (ex. `updateProfile` după legarea unui cont
    // Google, sau reîmprospătarea tokenului — aceea vine la ~55 min, garantat).
    //
    // Se calculează SEPARAT de `_running`: în FUNDAL `_running` e false (l-a
    // stins [stop]), așa că un eveniment de token pe același uid nu ieșea pe
    // scurtătura de mai jos, ajungea până la goliri și ștergea rezumatele +
    // cererile fix cât aplicația era minimizată. Un `FriendsScreen` montat
    // vedea previzualizările dispărând și pornea un `_load()` de ~2N citiri.
    final sameIdentity = uid.isNotEmpty && uid == _startedForUid;
    // Abonamentele sunt deja atașate pe exact acest uid: nimic de făcut.
    if (_running && sameIdentity) return;
    // NECONDIȚIONAT, înainte de orice altă decizie: dacă identitatea s-a
    // schimbat sau a dispărut, abonamentele vechi n-au voie să supraviețuiască
    // nicio clipă (vezi doc-ul clasei — `_discardAnonymousIdentity`).
    _stopSubs();
    // SCHIMBARE DE IDENTITATE (delogare sau alt cont): datele afișate aparțineau
    // identității de dinainte, n-au ce căuta pe ecran. Trecerea în FUNDAL NU
    // trece pe aici (o face [stop]), deci acolo previzualizările și cererile
    // rămân afișate — corect din punctul de vedere al utilizatorului: minimizezi
    // și revii, ecranul arată ce arăta. Nici un eveniment pe ACELAȘI uid nu
    // golește (de asta e condiția pe [sameIdentity], nu pe `_running`).
    if (!sameIdentity) {
      friendSummaries.value = const {};
      incomingRequestUids.value = const [];
    }
    // Curățat mereu: un uid rămas de la un cont delogat făcea ca relogarea pe
    // ACELAȘI cont să cadă pe ieșirea scurtă de mai sus și să nu mai pornească
    // niciodată abonamentele.
    _startedForUid = uid.isEmpty ? null : uid;
    if (uid.isEmpty) {
      // DELOGARE: bulina nu mai are voie să arate numărul contului anterior.
      // Fundalul lasă bulina pe ecran (dezirabil); împingerea explicită a lui
      // zero DOAR aici distinge cele două cazuri.
      _liveUnreadSink(0, 0);
    }
    // În fundal doar reținem noul uid; reatașarea o face [start] la revenire.
    if (uid.isEmpty || !_foreground) return;
    _startSubs();
  }

  /// Prim-plan. Chemat din `didChangeAppLifecycleState` (`resumed`) și o dată
  /// la pornire nu e nevoie — [attachToIdentity] pornește singur prima oară.
  /// Sigur de chemat de mai multe ori.
  void start() {
    _foreground = true;
    final uid = _readUid();
    // `_running` deja true: abonamentele sunt atașate, nimic de făcut.
    // uid gol: nicio identitate (ex. delogat) — nu pretindem că rulează ceva.
    // `_foreground` e acum true, deci următorul eveniment de identitate
    // pornește abonamentele.
    if (_running || uid.isEmpty) return;
    _startedForUid = uid;
    _startSubs();
  }

  /// Fundal. Chemat din `didChangeAppLifecycleState`
  /// (`paused`/`detached`/`hidden`). Sigur de chemat oricând, inclusiv când nu
  /// rulează nimic.
  void stop() {
    _foreground = false;
    _stopSubs();
  }

  void _startSubs() {
    if (_running) return;
    _running = true;
    _onStartSubs();
  }

  void _stopSubs() {
    if (!_running) return;
    _running = false;
    _onStopSubs();
  }

  // ─── Doar pentru test/live_sync_test.dart ───────────────────────────────

  /// Injectează un eveniment de identitate fără a construi un `User` Firebase.
  @visibleForTesting
  void applyIdentityForTest(String uid) => _applyIdentity(uid);

  @visibleForTesting
  bool get subscriptionsAttachedForTest => _running;

  @visibleForTesting
  String? get startedForUidForTest => _startedForUid;

  @visibleForTesting
  void resetForTest({
    void Function()? onStartSubs,
    void Function()? onStopSubs,
    String Function()? readUid,
    Stream<List<String>> Function()? friendUidsSource,
    Stream<List<String>> Function()? requestUidsSource,
    Stream<FriendChatSummary?> Function(String uid)? summarySource,
    bool Function(String uid)? isBlocked,
    void Function(int pending, int unread)? liveUnreadSink,
    void Function() Function(VoidCallback onChange)? blockedChangesSource,
  }) {
    _identitySub?.cancel();
    _identitySub = null;
    _stopFriendWatchers();
    _running = false;
    _foreground = true;
    _startedForUid = null;
    _onStartSubs = onStartSubs ?? _startAllServices;
    _onStopSubs = onStopSubs ?? _stopAllServices;
    _readUid = readUid ?? _currentUidFromSingleton;
    _friendUidsSource = friendUidsSource ?? _realFriendUids;
    _requestUidsSource = requestUidsSource ?? _realRequestUids;
    _summarySource = summarySource ?? _realSummary;
    _isBlocked = isBlocked ?? _realIsBlocked;
    _liveUnreadSink = liveUnreadSink ?? _realLiveUnreadSink;
    _blockedChangesSource = blockedChangesSource ?? _realBlockedChanges;
  }

  @visibleForTesting
  void startFriendWatchersForTest() => _startFriendWatchers();

  @visibleForTesting
  void stopFriendWatchersForTest() => _stopFriendWatchers();

  @visibleForTesting
  int get threadWatcherCountForTest => _threadSubs.length;
}
