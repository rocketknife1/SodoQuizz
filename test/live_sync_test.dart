import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/data/live_sync.dart';

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
}
