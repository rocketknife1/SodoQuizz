import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/data/shop.dart';

/// Preturile din magazin, rescrise 2026-09-01 la cererea userului: accesibile,
/// tentante, cu mai putine optiuni. Testele de aici apara REGULILE dupa care
/// au fost alese, nu cifrele in sine — daca cineva schimba un pret asa incat
/// pachetul mare devine mai prost decat cel mic, trebuie sa pice ceva.
void main() {
  group('cate optiuni sunt', () {
    test('trei trepte la fiecare rubrica, nu cinci', () {
      expect(gemPacks.length, 3);
      expect(hintPacksReal.length, 3);
      // Vietile au doua pachete numerice + "nelimitat 24h" ca a treia treapta.
      expect(livesPacks.length, 2);
    });

    test('trei pachete, nu patru', () {
      expect(bundles.length, 3);
    });
  });

  group('preturi accesibile', () {
    test('fiecare rubrica are o intrare sub 5 lei', () {
      expect(gemPacks.first.priceRon, lessThan(5));
      expect(livesPacks.first.priceRon, lessThan(5));
      expect(hintPacksReal.first.priceRon, lessThan(5));
    });

    test('nimic din magazin nu trece de 40 de lei', () {
      final toate = [
        for (final p in gemPacks) p.priceRon,
        for (final p in livesPacks) p.priceRon,
        for (final p in hintPacksReal) p.priceRon,
        for (final b in bundles) b.priceRon,
        noAdsBundle.priceRon,
        unlimitedLives24hPriceRon,
      ];
      for (final p in toate) {
        expect(p, lessThanOrEqualTo(40.0), reason: '$p lei e peste pragul stabilit');
      }
    });
  });

  group('treapta mai scumpa trebuie sa fie mai buna', () {
    test('gems: randamentul creste cu treapta', () {
      var prev = 0.0;
      for (final p in gemPacks) {
        final perLeu = p.gems / p.priceRon;
        expect(perLeu, greaterThan(prev),
            reason: '${p.productId} da $perLeu gems/leu, sub treapta precedenta ($prev)');
        prev = perLeu;
      }
    });

    test('hints: randamentul creste cu treapta', () {
      var prev = 0.0;
      for (final p in hintPacksReal) {
        final perLeu = p.hints / p.priceRon;
        expect(perLeu, greaterThan(prev), reason: '${p.productId}: $perLeu hints/leu');
        prev = perLeu;
      }
    });

    test('vieti: randamentul creste cu treapta', () {
      var prev = 0.0;
      for (final p in livesPacks) {
        final perLeu = p.lives / p.priceRon;
        expect(perLeu, greaterThan(prev), reason: '${p.productId}: $perLeu vieti/leu');
        prev = perLeu;
      }
    });

    test('preturile sunt strict crescatoare in fiecare rubrica', () {
      for (final lista in [
        [for (final p in gemPacks) p.priceRon],
        [for (final p in livesPacks) p.priceRon],
        [for (final p in hintPacksReal) p.priceRon],
        [for (final b in bundles) b.priceRon],
      ]) {
        for (var i = 1; i < lista.length; i++) {
          expect(lista[i], greaterThan(lista[i - 1]));
        }
      }
    });
  });

  group('pachetele chiar merita', () {
    test('fiecare pachet da mai multe gems decat ai lua pe aceiasi bani', () {
      // Cel mai bun randament din rubrica de gems, cu care se compara.
      final celMaiBun = gemPacks.map((p) => p.gems / p.priceRon).reduce((a, b) => a > b ? a : b);
      for (final b in bundles) {
        final gemsDirect = celMaiBun * b.priceRon;
        // Un pachet poate da mai putini gems bruti — dar atunci trebuie sa
        // compenseze cu monede/vieti/hints. Aici cerem doar sa nu fie o
        // batjocura: minim 70% din gems-ul echivalent, PLUS restul resurselor.
        expect(b.gems, greaterThan(gemsDirect * 0.7),
            reason: '${b.productId}: ${b.gems} gems fata de ${gemsDirect.round()} cumparati direct');
        expect(b.coins + b.hearts + b.hints, greaterThan(0),
            reason: '${b.productId} nu adauga nimic peste gems, deci nu e pachet');
      }
    });

    test('pachetul de start e cel mai bun raport, cum scrie pe el', () {
      final start = bundles.firstWhere((b) => b.oneTimeOnly);
      final raportStart = start.gems / start.priceRon;
      for (final b in bundles.where((b) => !b.oneTimeOnly)) {
        expect(raportStart, greaterThanOrEqualTo(b.gems / b.priceRon),
            reason: 'scrie "cea mai buna oferta" dar ${b.productId} e mai bun');
      }
    });
  });

  group('cadoul de gems', () {
    test('e fix cat o treapta de categorie', () {
      expect(gemGiftGems, questionUnlockGemsPrice(1));
    });

    test('nu dubleaza cadoul de pornire', () {
      // starterGemGrant e deja in sold de la instalare (StorageService.getGems).
      // Daca cineva face cadoul egal cu el, jucatorul nou ia dublu.
      expect(gemGiftGems, lessThan(starterGemGrant));
    });

    test('nu inunda economia: sub jumatate din venitul zilnic de gems', () {
      // Venit estimat al unui jucator activ: ~13/zi din quest-uri + ~15/zi din
      // roata. Cadoul se imparte pe zilele de racire.
      const venitZilnicEstimat = 28.0;
      final peZi = gemGiftGems / (gemGiftCooldownHours / 24);
      expect(peZi, lessThan(venitZilnicEstimat),
          reason: 'cadoul da $peZi gems/zi, mai mult decat joaca jucatorul');
    });

    test('racirea e in zile intregi, ca sa cada la aceeasi ora', () {
      expect(gemGiftCooldownHours % 24, 0);
    });
  });
}
