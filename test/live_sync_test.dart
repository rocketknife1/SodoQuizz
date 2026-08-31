import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/data/live_sync.dart';
import 'package:guess_it/data/moderation_service.dart';
import 'package:guess_it/data/player_profile_service.dart';
import 'package:guess_it/models/friend_chat.dart';

/// Mașina de stări din [LiveSync], verificată fără Firebase prin cusăturile de
/// test (`resetForTest` injectează uid-ul și cele două callback-uri care
/// altfel cheamă `CloudSyncService`).
///
/// Cele două Critical din recenzie erau exact ce prinde un test tabelar:
///  - #1 (scenariul 2): un eveniment de identitate sosit în fundal reataşa
///    abonamentele acolo.
///  - #2 (scenariile 3 și 4): `_startedForUid` nu se curăţa la delogare, iar
///    `start()` pretindea că rulează ceva şi pe uid gol → relogarea pe acelaşi
///    cont nu mai pornea niciodată nimic.
/// Scenariile 1 și 5 trec și pe codul dinainte de reparaţie — sunt gărzi pentru
/// căile fericite (pornire→fundal→prim-plan și idempotenţa evenimentelor).
void main() {
  final sync = LiveSync.instance;

  // Model fidel al lui `CloudSyncService.startLive`, care iese pe uid gol:
  // `attached` devine true DOAR dacă exista o identitate când s-au pornit
  // abonamentele.
  late String uid;
  late int startCalls;
  late int stopCalls;
  late bool attached;

  setUp(() {
    uid = '';
    startCalls = 0;
    stopCalls = 0;
    attached = false;
    sync.resetForTest(
      readUid: () => uid,
      onStartSubs: () {
        startCalls++;
        attached = uid.isNotEmpty;
      },
      onStopSubs: () {
        stopCalls++;
        attached = false;
      },
      // Fara Firebase; altfel golirea bulinei la delogare (calea reala) ar
      // atinge NotificationService -> StorageService si ar zgomotui log-ul.
      liveUnreadSink: (_, __) {},
    );
  });

  tearDown(sync.resetForTest);

  test('1. pornire -> logare -> fundal -> prim-plan: abonamente active, o singura data', () {
    uid = 'anon-1';
    sync.applyIdentityForTest('anon-1'); // userChanges emite identitatea initiala
    uid = 'google-1';
    sync.applyIdentityForTest('google-1'); // logare care schimba uid-ul

    sync.stop(); // fundal
    expect(sync.subscriptionsAttachedForTest, isFalse);

    sync.start(); // prim-plan
    expect(sync.subscriptionsAttachedForTest, isTrue);
    expect(attached, isTrue);
    expect(startCalls - stopCalls, 1, reason: 'net exact o atasare activa la final');
  });

  test('2. eveniment de identitate in FUNDAL: abonamentele raman oprite', () {
    uid = 'user-2';
    sync.applyIdentityForTest('user-2');
    expect(sync.subscriptionsAttachedForTest, isTrue);

    sync.stop(); // fundal
    expect(sync.subscriptionsAttachedForTest, isFalse);
    final startsBefore = startCalls;

    // Reimprospatarea tokenului (~55 min, garantat) emite acelasi uid.
    sync.applyIdentityForTest('user-2');

    expect(sync.subscriptionsAttachedForTest, isFalse,
        reason: 'un eveniment de identitate in fundal NU are voie sa reataseze');
    expect(attached, isFalse);
    expect(startCalls, startsBefore);
  });

  test('3. delogare -> fundal -> prim-plan -> relogare pe ACELASI uid: active', () {
    uid = 'user-3';
    sync.applyIdentityForTest('user-3');
    expect(sync.subscriptionsAttachedForTest, isTrue);

    // Delogare: userChanges emite null. Fluxul de login pleaca apoi intr-o
    // Activitate externa, deci produce el insusi paused -> resumed.
    uid = '';
    sync.applyIdentityForTest('');
    expect(sync.subscriptionsAttachedForTest, isFalse);
    expect(sync.startedForUidForTest, isNull,
        reason: 'uid-ul contului delogat trebuie curatat, altfel relogarea cade pe iesirea scurta');

    sync.stop(); // fundal
    sync.start(); // prim-plan, inca delogat
    expect(sync.subscriptionsAttachedForTest, isFalse);

    // Relogare pe ACELASI cont.
    uid = 'user-3';
    sync.applyIdentityForTest('user-3');
    expect(sync.subscriptionsAttachedForTest, isTrue,
        reason: 'relogarea pe acelasi uid trebuie sa reporneasca abonamentele');
    expect(attached, isTrue);
  });

  test('4. resumed cu uid gol: nu porneste nimic; o logare ulterioara porneste', () {
    uid = '';
    sync.start(); // resumed fara identitate
    expect(sync.subscriptionsAttachedForTest, isFalse);
    expect(startCalls, 0, reason: 'fara identitate nu se atinge CloudSyncService');

    uid = 'user-4';
    sync.applyIdentityForTest('user-4');
    expect(sync.subscriptionsAttachedForTest, isTrue);
    expect(attached, isTrue);
  });

  test('5. doua evenimente consecutive cu acelasi uid: o singura atasare', () {
    uid = 'user-5';
    sync.applyIdentityForTest('user-5');
    expect(sync.subscriptionsAttachedForTest, isTrue);
    final startsAfterFirst = startCalls;
    final stopsAfterFirst = stopCalls;

    sync.applyIdentityForTest('user-5');

    expect(startCalls, startsAfterFirst, reason: 'niciun re-attach');
    expect(stopCalls, stopsAfterFirst, reason: 'niciun detach');
    expect(sync.subscriptionsAttachedForTest, isTrue);
  });

  // ─── Abonamentele de prieteni (mesaje necitite + cereri), Sarcina 9 ──────
  //
  // Rulate direct prin `startFriendWatchersForTest`, cu surse injectate — la
  // fel cum scenariile de mai sus rulează mașina de stări cu callback-urile
  // injectate. Fără Firebase.
  group('abonamente de prieteni', () {
    late StreamController<List<String>> friendsCtrl;
    late StreamController<List<String>> requestsCtrl;
    late Map<String, StreamController<FriendChatSummary?>> threadCtrls;
    late List<(int, int)> pushes;

    StreamController<FriendChatSummary?> threadCtrlFor(String uid) =>
        threadCtrls.putIfAbsent(uid, () => StreamController<FriendChatSummary?>());

    FriendChatSummary unreadFrom(String friendUid) => FriendChatSummary(
          lastMessageAt: Timestamp.now(),
          lastSenderId: friendUid,
          lastText: 'salut',
        );

    setUp(() {
      friendsCtrl = StreamController<List<String>>();
      requestsCtrl = StreamController<List<String>>();
      threadCtrls = {};
      pushes = [];
      sync.resetForTest(
        readUid: () => 'me',
        onStartSubs: () {},
        onStopSubs: () {},
        friendUidsSource: () => friendsCtrl.stream,
        requestUidsSource: () => requestsCtrl.stream,
        summarySource: (uid) => threadCtrlFor(uid).stream,
        isBlocked: (uid) => uid == 'bad',
        liveUnreadSink: (p, u) => pushes.add((p, u)),
        blockedChangesSource: (_) => () {},
      );
    });

    tearDown(() {
      sync.stopFriendWatchersForTest();
      friendsCtrl.close();
      requestsCtrl.close();
      for (final c in threadCtrls.values) {
        c.close();
      }
    });

    test('6. prieten adaugat => abonament nou; sters => abonament ANULAT', () async {
      sync.startFriendWatchersForTest();

      friendsCtrl.add(['a', 'b']);
      await pumpEventQueue();
      expect(sync.threadWatcherCountForTest, 2);
      expect(threadCtrls['a']!.hasListener, isTrue);
      expect(threadCtrls['b']!.hasListener, isTrue);

      friendsCtrl.add(['a']); // b scos din prieteni
      await pumpEventQueue();
      expect(sync.threadWatcherCountForTest, 1);
      expect(threadCtrls['b']!.hasListener, isFalse,
          reason: 'abonamentul lui b trebuie ANULAT, nu doar scos din harta');

      friendsCtrl.add(['a', 'c']); // c adaugat
      await pumpEventQueue();
      expect(sync.threadWatcherCountForTest, 2);
      expect(threadCtrls['c']!.hasListener, isTrue);
    });

    test('7. stop() anuleaza TOATE cele N fire, nu doar unul', () async {
      sync.startFriendWatchersForTest();
      friendsCtrl.add(['a', 'b', 'c', 'd', 'e']);
      await pumpEventQueue();
      expect(sync.threadWatcherCountForTest, 5);

      sync.stopFriendWatchersForTest();

      expect(sync.threadWatcherCountForTest, 0);
      for (final entry in threadCtrls.entries) {
        expect(entry.value.hasListener, isFalse, reason: 'firul ${entry.key} a ramas agatat');
      }
    });

    test('10. cerere noua cat ecranul e deschis => incomingRequestUids se schimba; blocatele excluse', () async {
      sync.startFriendWatchersForTest();
      expect(sync.incomingRequestUids.value, isEmpty);

      requestsCtrl.add(['bad', 'good']);
      await pumpEventQueue();
      expect(sync.incomingRequestUids.value, ['good'],
          reason: 'expeditorul blocat nu are voie sa apara in semnalul catre ecranul de Prieteni');

      requestsCtrl.add(const []); // cererea a fost acceptata/refuzata de pe alt telefon
      await pumpEventQueue();
      expect(sync.incomingRequestUids.value, isEmpty);
    });

    test('8. un prieten/expeditor blocat NU intra in numaratoarea bulinei', () async {
      sync.startFriendWatchersForTest();

      requestsCtrl.add(['bad', 'good']);
      await pumpEventQueue();
      expect(pushes.last, (1, 0), reason: 'cererea de la "bad" e sarita');

      friendsCtrl.add(['bad', 'good']);
      await pumpEventQueue();
      threadCtrlFor('bad').add(unreadFrom('bad'));
      threadCtrlFor('good').add(unreadFrom('good'));
      await pumpEventQueue();

      expect(pushes.last, (1, 1), reason: 'firul cu "bad" nu se numara, doar "good"');
    });

    test('11. lista de blocati se schimba in sesiune => recalcul prin cusatura _blockedChangesSource', () async {
      var blocked = <String>{};
      void Function()? fireBlockedChange;
      sync.resetForTest(
        readUid: () => 'me',
        onStartSubs: () {},
        onStopSubs: () {},
        friendUidsSource: () => friendsCtrl.stream,
        requestUidsSource: () => requestsCtrl.stream,
        summarySource: (uid) => threadCtrlFor(uid).stream,
        isBlocked: (uid) => blocked.contains(uid),
        liveUnreadSink: (p, u) => pushes.add((p, u)),
        // `blockedIds` e un ValueNotifier care se schimba sub noi; aici captam
        // callback-ul pe care `_startFriendWatchers` il inregistreaza, ca sa-l
        // putem declansa. Fara acest test, scoaterea liniei
        // `_stopBlockedWatch = _blockedChangesSource(_pushUnread)` ar trece verde.
        blockedChangesSource: (cb) {
          fireBlockedChange = cb;
          return () {};
        },
      );
      sync.startFriendWatchersForTest();

      requestsCtrl.add(['x', 'y']);
      friendsCtrl.add(['x', 'y']);
      await pumpEventQueue();
      threadCtrlFor('x').add(unreadFrom('x'));
      await pumpEventQueue();
      expect(pushes.last, (2, 1));
      expect(sync.incomingRequestUids.value, ['x', 'y']);

      blocked = {'x'};
      fireBlockedChange!();

      expect(pushes.last, (1, 0), reason: 'recalcul fara alt snapshot Firestore');
      expect(sync.incomingRequestUids.value, ['y'], reason: 'cererea de la cel blocat dispare');
    });
  });

  /// Reînnoirea tokenului (`userChanges()` la ~55 min, garantat) emite un
  /// eveniment cu ACELAȘI uid. În FUNDAL `_running` e false, deci vechea gardă
  /// `_running && uid == _startedForUid` nu-l oprea: evenimentul ajungea la
  /// goliri și ștergea rezumatele + cererile cât aplicația era minimizată.
  test('12. token reinnoit in FUNDAL (acelasi uid) NU goleste; alt uid / delogare golesc', () {
    final pushes = <(int, int)>[];
    uid = 'user-12';
    sync.resetForTest(
      readUid: () => uid,
      // Calea REALA de pornire/oprire — ca la testul 9, altfel afirmatiile ar fi vide.
      onStartSubs: () => sync.startFriendWatchersForTest(),
      onStopSubs: () => sync.stopFriendWatchersForTest(),
      friendUidsSource: () => Stream<List<String>>.empty(),
      requestUidsSource: () => Stream<List<String>>.empty(),
      summarySource: (_) => Stream<FriendChatSummary?>.empty(),
      isBlocked: (_) => false,
      liveUnreadSink: (p, u) => pushes.add((p, u)),
      blockedChangesSource: (_) => () {},
    );

    FriendChatSummary summary() =>
        FriendChatSummary(lastMessageAt: Timestamp.now(), lastSenderId: 'f', lastText: 'hi');

    sync.applyIdentityForTest('user-12');
    sync.friendSummaries.value = {'f': summary()};
    sync.incomingRequestUids.value = ['r'];

    sync.stop(); // FUNDAL: `_running` devine false
    expect(sync.subscriptionsAttachedForTest, isFalse);

    // Reinnoirea tokenului: acelasi uid, aplicatia tot in fundal.
    sync.applyIdentityForTest('user-12');
    expect(sync.subscriptionsAttachedForTest, isFalse, reason: 'fundalul nu reataseaza');
    expect(sync.startedForUidForTest, 'user-12');
    expect(pushes, isEmpty, reason: 'un token reinnoit nu stinge bulina');
    expect(sync.friendSummaries.value, isNotEmpty,
        reason: 'token reinnoit pe acelasi uid: previzualizarile raman');
    expect(sync.incomingRequestUids.value, isNotEmpty,
        reason: 'token reinnoit pe acelasi uid: cererile raman');

    // ALT CONT, tot in fundal: acolo golirea TREBUIE sa se faca.
    uid = 'user-99';
    sync.applyIdentityForTest('user-99');
    expect(sync.friendSummaries.value, isEmpty, reason: 'alt cont goleste rezumatele');
    expect(sync.incomingRequestUids.value, isEmpty, reason: 'alt cont goleste cererile');

    // DELOGARE: goleste si stinge bulina, chiar daca tot in fundal suntem.
    sync.friendSummaries.value = {'f': summary()};
    sync.incomingRequestUids.value = ['r'];
    uid = '';
    sync.applyIdentityForTest('');
    expect(sync.friendSummaries.value, isEmpty, reason: 'delogarea goleste rezumatele');
    expect(sync.incomingRequestUids.value, isEmpty, reason: 'delogarea goleste cererile');
    expect(pushes.last, (0, 0), reason: 'delogarea stinge bulina');
    expect(sync.startedForUidForTest, isNull);
  });

  test('9. identitate schimbata goleste rezumatele+cererile; FUNDALUL nu (calea reala de oprire)', () {
    final pushes = <(int, int)>[];
    uid = 'user-9';
    sync.resetForTest(
      readUid: () => uid,
      // Calea REALA de oprire/pornire, nu un stub gol — altfel `_stopFriendWatchers`
      // nu s-ar executa si afirmatia "fundalul nu goleste" ar fi vida.
      onStartSubs: () => sync.startFriendWatchersForTest(),
      onStopSubs: () => sync.stopFriendWatchersForTest(),
      friendUidsSource: () => Stream<List<String>>.empty(),
      requestUidsSource: () => Stream<List<String>>.empty(),
      summarySource: (_) => Stream<FriendChatSummary?>.empty(),
      isBlocked: (_) => false,
      liveUnreadSink: (p, u) => pushes.add((p, u)),
      blockedChangesSource: (_) => () {},
    );

    sync.applyIdentityForTest('user-9'); // porneste abonamentele (calea reala)
    sync.friendSummaries.value = {
      'f': FriendChatSummary(lastMessageAt: Timestamp.now(), lastSenderId: 'f', lastText: 'hi'),
    };
    sync.incomingRequestUids.value = ['r'];

    sync.stop(); // FUNDAL
    expect(pushes, isEmpty, reason: 'fundalul nu are voie sa stinga bulina');
    expect(sync.friendSummaries.value, isNotEmpty, reason: 'fundalul pastreaza previzualizarile de chat');
    expect(sync.incomingRequestUids.value, isNotEmpty, reason: 'fundalul pastreaza lista de cereri');

    sync.start();
    uid = '';
    sync.applyIdentityForTest(''); // DELOGARE (schimbare de identitate)
    expect(pushes.last, (0, 0), reason: 'delogarea goleste bulina');
    expect(sync.friendSummaries.value, isEmpty, reason: 'schimbarea de identitate goleste rezumatele');
    expect(sync.incomingRequestUids.value, isEmpty, reason: 'schimbarea de identitate goleste cererile');
  });

  /// I5: starea per-cont (`amIBanned`, lista de blocați) trebuie să dispară la
  /// SCHIMBAREA de identitate, dar NU la trecerea în fundal.
  ///
  /// Fără asta: un Guest banat care se loghează cu un cont Google curat vedea
  /// ecranul de interdicție peste contul nou până sosea primul snapshot al
  /// noii identități — și invers, porțile stăteau deschise o clipă pe un cont
  /// banat. Golirea NU se poate face în `stopLive`, fiindcă `LiveSync.stop()`
  /// (fundal) trece tot pe acolo.
  test('13. schimbarea de identitate goleste amIBanned si lista de blocati; fundalul NU', () {
    final banned = PlayerProfileService.instance.amIBanned;
    final blocked = ModerationService.instance.blockedIds;

    uid = 'banned-1';
    sync.applyIdentityForTest('banned-1');
    banned.value = true;
    blocked.value = const {'cineva'};

    // FUNDAL: starea contului curent rămâne — altfel, la revenire, chatul ar fi
    // nefiltrat și porțile de ban deschise pentru câteva cadre.
    sync.stop();
    expect(banned.value, isTrue, reason: 'fundalul nu sterge starea de ban');
    expect(blocked.value, isNotEmpty, reason: 'fundalul nu sterge lista de blocati');

    // Acelasi uid (token reinnoit): tot nu goleste.
    sync.applyIdentityForTest('banned-1');
    expect(banned.value, isTrue, reason: 'acelasi uid nu goleste starea de ban');
    expect(blocked.value, isNotEmpty, reason: 'acelasi uid nu goleste lista de blocati');

    // ALT CONT: aici starea contului vechi n-are ce cauta.
    uid = 'curat-1';
    sync.applyIdentityForTest('curat-1');
    expect(banned.value, isFalse, reason: 'contul nou nu mosteneste banul celui vechi');
    expect(blocked.value, isEmpty, reason: 'contul nou nu mosteneste lista de blocati');

    // DELOGARE: la fel.
    banned.value = true;
    blocked.value = const {'altcineva'};
    uid = '';
    sync.applyIdentityForTest('');
    expect(banned.value, isFalse, reason: 'delogarea goleste starea de ban');
    expect(blocked.value, isEmpty, reason: 'delogarea goleste lista de blocati');
  });
}
