import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/data/live_sync.dart';
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
  });

  test('9. delogare goleste bulina live; trecerea in fundal NU', () {
    final pushes = <(int, int)>[];
    uid = 'user-9';
    sync.resetForTest(
      readUid: () => uid,
      onStartSubs: () {},
      onStopSubs: () {},
      liveUnreadSink: (p, u) => pushes.add((p, u)),
    );

    sync.applyIdentityForTest('user-9');
    sync.stop(); // fundal
    expect(pushes, isEmpty, reason: 'trecerea in fundal nu are voie sa stinga bulina');

    sync.start();
    uid = '';
    sync.applyIdentityForTest(''); // delogare
    expect(pushes.last, (0, 0), reason: 'delogarea trebuie sa goleasca bulina live');
  });
}
