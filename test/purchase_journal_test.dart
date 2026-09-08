import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/data/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Jurnalul achizitiilor cu bani reali trebuie sa aplice EXACT O DATA, oricat
/// de urat ar muri aplicatia intre pasi.
///
/// Testele simuleaza aplicarea unui grant („da-i 130 gems si 10 vieti") si
/// omoara procesul dupa fiecare pas posibil, apoi reiau de la zero exact cum
/// ar face PurchaseService la urmatoarea pornire. Soldul final trebuie sa fie
/// acelasi in toate scenariile.
///
/// DE CE conteaza atat: tiparul de la `admin_grants` sterge documentul INAINTE
/// de aplicare si accepta pierderea unui cadou. Pentru o plata reala,
/// prejudecata e pe dos — se aplica intai, se sterge dupa — iar singurul lucru
/// care opreste dublarea e jurnalul asta.
void main() {
  const grantId = 'abc123';

  /// Un „sold" fals, ca sa nu depindem de economia reala.
  late Map<String, int> sold;

  /// Aplicarea, exact ca in PurchaseService: pentru fiecare componenta
  /// neaplicata inca, scrie in sold si abia apoi marcheaza pasul.
  /// [moareLa] simuleaza o intrerupere INAINTE de pasul cu indicele dat.
  Future<bool> aplica(Map<String, int> payload, {int moareLa = -1}) async {
    if (await StorageService.isPurchaseApplied(grantId)) return true;
    await StorageService.beginPurchaseJournal(grantId);
    final facuti = await StorageService.journalSteps(grantId);
    var i = 0;
    for (final e in payload.entries) {
      if (i == moareLa) return false; // procesul moare aici
      i++;
      if (facuti.contains(e.key)) continue;
      sold[e.key] = (sold[e.key] ?? 0) + e.value;
      await StorageService.markJournalStep(grantId, e.key);
    }
    if (moareLa == payload.length) return false; // moare inainte de inchidere
    await StorageService.endPurchaseJournal(grantId);
    return true;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sold = {};
  });

  test('aplicare completa, fara intreruperi', () async {
    expect(await aplica({'gems': 130, 'hearts': 10}), isTrue);
    expect(sold, {'gems': 130, 'hearts': 10});
    expect(await StorageService.isPurchaseApplied(grantId), isTrue);
    expect(await StorageService.unfinishedPurchaseJournals(), isEmpty);
  });

  test('reluarea unei achizitii deja aplicate nu dubleaza nimic', () async {
    await aplica({'gems': 130, 'hearts': 10});
    await aplica({'gems': 130, 'hearts': 10});
    await aplica({'gems': 130, 'hearts': 10});
    expect(sold, {'gems': 130, 'hearts': 10});
  });

  test('moarte inainte de fiecare pas -> reluarea da acelasi sold', () async {
    final payload = {'gems': 130, 'hearts': 10, 'hints': 25};
    for (var k = 0; k <= payload.length; k++) {
      SharedPreferences.setMockInitialValues({});
      sold = {};

      expect(await aplica(payload, moareLa: k), isFalse,
          reason: 'scenariul $k trebuia sa fie intrerupt');
      // ...aplicatia porneste din nou si reia jurnalul neterminat
      expect(await StorageService.unfinishedPurchaseJournals(), [grantId]);
      expect(await aplica(payload), isTrue);

      expect(sold, {'gems': 130, 'hearts': 10, 'hints': 25},
          reason: 'sold gresit dupa intrerupere la pasul $k');
      expect(await StorageService.isPurchaseApplied(grantId), isTrue);
      expect(await StorageService.unfinishedPurchaseJournals(), isEmpty);
    }
  });

  test('doua achizitii diferite nu se incurca', () async {
    await StorageService.beginPurchaseJournal('unu');
    await StorageService.markJournalStep('unu', 'gems');
    await StorageService.beginPurchaseJournal('doi');

    expect(await StorageService.journalSteps('unu'), {'gems'});
    expect(await StorageService.journalSteps('doi'), isEmpty);
    expect(
      (await StorageService.unfinishedPurchaseJournals()).toSet(),
      {'unu', 'doi'},
    );

    await StorageService.endPurchaseJournal('unu');
    expect(await StorageService.isPurchaseApplied('unu'), isTrue);
    expect(await StorageService.isPurchaseApplied('doi'), isFalse);
    expect(await StorageService.unfinishedPurchaseJournals(), ['doi']);
  });

  test('lista de aplicate nu creste la nesfarsit', () async {
    for (var i = 0; i < 80; i++) {
      await StorageService.endPurchaseJournal('grant$i');
    }
    final prefs = await SharedPreferences.getInstance();
    final applied = prefs.getStringList('iap_applied')!;
    expect(applied.length, lessThanOrEqualTo(60));
    // FIFO: cele mai noi raman, cele mai vechi cad.
    expect(applied.contains('grant79'), isTrue);
    expect(applied.contains('grant0'), isFalse);
  });

  test('un reset de admin NU sterge lista de aplicate', () async {
    // Altfel fiecare cumparatura inca nesearsa din cutia postala s-ar aplica
    // a doua oara la urmatoarea pornire.
    await StorageService.endPurchaseJournal(grantId);
    await StorageService.resetToStartingBalance();
    expect(await StorageService.isPurchaseApplied(grantId), isTrue);
  });

  test('un reset de admin NU sterge drepturile cumparate', () async {
    await StorageService.setNoAdsForever();
    await StorageService.setStarterPackBought();
    await StorageService.resetToStartingBalance();
    expect(await StorageService.getNoAdsForever(), isTrue);
    expect(await StorageService.getStarterPackBought(), isTrue);
  });
}
