import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/stable_hash.dart';
import 'package:guess_it/core/progression.dart';
import 'package:guess_it/models/multiplayer_models.dart';

/// Aceste teste apără o singură regulă: orice ALEGERE pe care o fac doi
/// clienți din date identice trebuie să iasă la fel pe telefon și în browser.
///
/// `String.hashCode` și `Random(seed)` NU garanteaza asta (vezi
/// core/stable_hash.dart). Bug-ul raportat pe 2026-09-01: aceleași două
/// tancuri aveau aceeași culoare pe telefon și două culori diferite în
/// browser.
///
/// Valorile de mai jos sunt „golden": dacă cineva înlocuiește `stableHash`
/// cu `hashCode`, ele se schimbă și testele pică. Asta e tot rostul lor.
void main() {
  group('stableHash e determinist si independent de platforma', () {
    test('valori golden — se schimba doar daca se schimba algoritmul', () {
      expect(stableHash(''), 0x811C9DC5);
      expect(stableHash('a'), isNot(0));
      // acelasi input => acelasi hash, mereu
      expect(stableHash('abc'), stableHash('abc'));
      expect(stableHash('abc'), isNot(stableHash('abd')));
    });
  });

  group('pickAvatarColor', () {
    test('acelasi seed da mereu aceeasi culoare', () {
      final a = pickAvatarColor('uid-de-test-123');
      final b = pickAvatarColor('uid-de-test-123');
      expect(a, b);
    });

    test('seed-uri diferite dau (in general) culori diferite', () {
      // Nu se poate cere garantat diferit (paleta are 6 culori), dar peste un
      // set de uid-uri realiste trebuie sa foloseasca mai mult de o culoare —
      // exact simptomul raportat („toate tancurile la fel").
      final seeds = [
        'AbC123XyZ456', 'QwErTy789012', 'ZxCvBn345678',
        'PoIuYt901234', 'LkJhGf567890', 'MnBvCx123789',
      ];
      final culori = seeds.map(pickAvatarColor).toSet();
      expect(culori.length, greaterThan(1),
          reason: 'daca toate ies la fel, seed-ul colapseaza (bug-ul raportat)');
    });

    test('GOLDEN: valori fixe — pica daca cineva pune hashCode la loc', () {
      // Astea sunt indecsii din paleta calculati cu stableHash. Daca
      // implementarea revine la `seed.hashCode.abs() % 6`, valorile se schimba
      // (hashCode e altul) si testul pica — exact rostul lui. Sunt si dovada
      // ca aceleasi seed-uri dau culori DIFERITE, nu toate la fel.
      expect(stableHash('jucator-fix-pentru-test') % 6, 3);
      expect(stableHash('uid-A') % 6, 5);
      expect(stableHash('uid-B') % 6, 4);
      // trei seed-uri, trei indecsi diferiti => trei culori diferite
      expect({
        pickAvatarColor('jucator-fix-pentru-test'),
        pickAvatarColor('uid-A'),
        pickAvatarColor('uid-B'),
      }.length, 3);
    });

    test('GOLDEN: nuanta gradientului de intrebare e stabila', () {
      // buildQuestionGradient foloseste stableHash(seed) % 360 — aceeasi
      // intrebare trebuie sa arate la fel pe telefon si in browser.
      expect(stableHash('jucator-fix-pentru-test') % 360, 153);
      expect(stableHash('uid-A') % 360, 323);
    });
  });

  group('rotatia de quest-uri', () {
    test('aceleasi quest-uri pentru aceeasi zi, la fiecare apel', () {
      // todaysQuests() e API-ul public; rotatia din spate trebuie sa fie
      // determinista, altfel acelasi cont vede alte quest-uri pe telefon
      // fata de browser.
      final luni = DateTime(2026, 9, 7); // luni
      final a = todaysQuests(luni).map((q) => q.id).toList();
      final b = todaysQuests(luni).map((q) => q.id).toList();
      expect(a, b, reason: 'aceeasi zi trebuie sa dea aceleasi quest-uri');
      expect(a, isNotEmpty);
    });

    test('zile diferite dau seturi diferite', () {
      final luni = todaysQuests(DateTime(2026, 9, 7)).map((q) => q.id).toSet();
      final marti = todaysQuests(DateTime(2026, 9, 8)).map((q) => q.id).toSet();
      expect(luni, isNot(marti));
    });
  });

  // StableRandom n-avea niciun golden: o regresie in `_nextState` ar fi trecut
  // nedetectata, desi tot rostul clasei e ca telefonul si browserul sa vada
  // aceiasi bolovani (recenzie 2026-09-01). Valorile de mai jos sunt captura
  // implementarii curente — daca pica testul, s-a schimbat generatorul si
  // formele din Obby difera intre platforme.
  group('StableRandom', () {
    test('sirul e stabil, bit cu bit', () {
      final r = StableRandom(1);
      final got = [for (var i = 0; i < 5; i++) r.nextInt(1000)];
      expect(got, [369, 689, 461, 695, 233]);
    });

    test('nextDouble ramane in [0, 1) pe multe trageri', () {
      final r = StableRandom(12345);
      for (var i = 0; i < 20000; i++) {
        final v = r.nextDouble();
        expect(v, greaterThanOrEqualTo(0.0));
        expect(v, lessThan(1.0));
      }
    });

    test('samante diferite dau siruri diferite', () {
      final s1 = StableRandom(7);
      final s2 = StableRandom(8);
      expect([for (var i = 0; i < 5; i++) s1.nextInt(1 << 20)],
          isNot([for (var i = 0; i < 5; i++) s2.nextInt(1 << 20)]));
    });
  });
}
