import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:guess_it/data/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    StorageService.balanceRevision.value = 0;
  });

  test('fiecare scriere de balanta creste contorul', () async {
    final start = StorageService.balanceRevision.value;
    await StorageService.addCoins(10);
    expect(StorageService.balanceRevision.value, greaterThan(start),
        reason: 'addCoins trebuie sa anunte ecranele');

    final afterCoins = StorageService.balanceRevision.value;
    await StorageService.addGems(1);
    expect(StorageService.balanceRevision.value, greaterThan(afterCoins));

    final afterGems = StorageService.balanceRevision.value;
    await StorageService.spendHint();
    expect(StorageService.balanceRevision.value, greaterThan(afterGems),
        reason: 'un hint consumat schimba ce vede jucatorul');
  });

  test('golirea si reimportul cresc contorul, desi nu ating chei literale', () async {
    await StorageService.addCoins(500);

    var before = StorageService.balanceRevision.value;
    await StorageService.resetToStartingBalance();
    expect(StorageService.balanceRevision.value, greaterThan(before),
        reason: 'resetul de admin schimba balanta prin prefs.clear(), fara setInt');

    before = StorageService.balanceRevision.value;
    await StorageService.resetAll();
    expect(StorageService.balanceRevision.value, greaterThan(before),
        reason: 'stergerea totala din Profil schimba tot');

    before = StorageService.balanceRevision.value;
    await StorageService.importAll({'coins': 999});
    expect(StorageService.balanceRevision.value, greaterThan(before),
        reason: 'cloud-ul care coboara la logare schimba balanta');
  });

  test('pauza pe notificari: scrierile nu bump-uie pana la release, apoi UNA singura', () async {
    var seen = 0;
    void bump() => seen++;
    StorageService.balanceRevision.addListener(bump);
    addTearDown(() => StorageService.balanceRevision.removeListener(bump));

    StorageService.holdBalanceNotifications();
    await StorageService.addCoins(10);
    await StorageService.addXp(5);
    await StorageService.addHints(1);
    expect(seen, 0, reason: 'cat tine pauza, niciun bump');

    StorageService.releaseBalanceNotifications();
    expect(seen, 1, reason: 'la release, exact UN bump pentru tot ce s-a acumulat');
  });

  test('notifyBalanceChanged forteaza bump chiar si sub pauza', () async {
    var seen = 0;
    void bump() => seen++;
    StorageService.balanceRevision.addListener(bump);
    addTearDown(() => StorageService.balanceRevision.removeListener(bump));

    StorageService.holdBalanceNotifications();
    await StorageService.addCoins(10);
    StorageService.notifyBalanceChanged();
    expect(seen, 1, reason: 'bump fortat la impact, chiar sub pauza');
    StorageService.releaseBalanceNotifications();
    expect(seen, 1, reason: 'release nu mai are ce bump-ui, notifyBalanceChanged a golit pending');
  });

}
