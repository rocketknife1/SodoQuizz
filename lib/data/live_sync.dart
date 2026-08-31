import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'cloud_sync_service.dart';

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
/// [_onIdentityChanged] anulează tot NECONDIȚIONAT, înainte de orice
/// verificare, și abia apoi decide dacă repornește.
///
/// `userChanges()`, nu `authStateChanges()`: la legarea unui cont Google
/// peste identitatea anonimă uid-ul NU se schimbă, deci `authStateChanges`
/// poate să nu emită deloc — dar numele afișat se schimbă, iar de el depinde
/// ce se vede în joc.
class LiveSync {
  LiveSync._();
  static final instance = LiveSync._();

  StreamSubscription<User?>? _identitySub;
  String? _startedForUid;
  bool _running = false;

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

  void _onIdentityChanged(User? user) {
    final uid = user?.uid ?? '';
    // Un eveniment care nu schimbă uid-ul (ex. `updateProfile` după legarea
    // unui cont Google) nu are de ce să reconstruiască abonamentele.
    if (_running && uid.isNotEmpty && uid == _startedForUid) return;
    stop();
    if (uid.isEmpty) return;
    _startedForUid = uid;
    start();
  }

  /// Pornește abonamentele. Sigur de chemat de mai multe ori.
  void start() {
    if (_running) return;
    _running = true;
    CloudSyncService.instance.startLive();
  }

  /// Le oprește pe toate. Sigur de chemat oricând, inclusiv când nu rulează
  /// nimic — se cheamă și la trecerea în fundal, și la fiecare schimbare de
  /// identitate.
  void stop() {
    if (!_running) return;
    _running = false;
    CloudSyncService.instance.stopLive();
  }
}
