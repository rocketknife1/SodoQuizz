import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'cloud_sync_service.dart';
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
  }

  static void _stopAllServices() {
    CloudSyncService.instance.stopLive();
    PlayerProfileService.instance.stopLive();
    NotificationService.instance.stopLive();
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
    // Eveniment care nu schimbă nimic (ex. `updateProfile` după legarea unui
    // cont Google, sau reîmprospătarea tokenului): abonamentele deja atașate
    // pe acest uid rămân cum sunt.
    if (_running && uid.isNotEmpty && uid == _startedForUid) return;
    // NECONDIȚIONAT, înainte de orice altă decizie: dacă identitatea s-a
    // schimbat sau a dispărut, abonamentele vechi n-au voie să supraviețuiască
    // nicio clipă (vezi doc-ul clasei — `_discardAnonymousIdentity`).
    _stopSubs();
    // Curățat mereu: un uid rămas de la un cont delogat făcea ca relogarea pe
    // ACELAȘI cont să cadă pe ieșirea scurtă de mai sus și să nu mai pornească
    // niciodată abonamentele.
    _startedForUid = uid.isEmpty ? null : uid;
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
  }) {
    _identitySub?.cancel();
    _identitySub = null;
    _running = false;
    _foreground = true;
    _startedForUid = null;
    _onStartSubs = onStartSubs ?? _startAllServices;
    _onStopSubs = onStopSubs ?? _stopAllServices;
    _readUid = readUid ?? _currentUidFromSingleton;
  }
}
