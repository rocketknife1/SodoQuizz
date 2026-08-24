import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/electric_chair.dart';

/// Cât stă masa pe loc între două runde la Scaunul Electric — aceeași idee
/// ca la Quizz Tanks (vezi tanks_reveal_pacing_test.dart): dacă nimeni n-a
/// fost pus pe scaun runda asta, n-are ce se anima, deci pauza trebuie să
/// rămână scurtă.
void main() {
  group('pauza dintre runde la Scaunul Electric', () {
    test('runda cu cineva pe scaun primeste bugetul intreg', () {
      expect(electricChairRevealSecondsFor(anyoneTested: true), electricChairRevealSeconds);
    });

    test('runda fara nimeni pe scaun nu tine masa pe loc degeaba', () {
      expect(electricChairRevealSecondsFor(anyoneTested: false), electricChairEmptyRevealSeconds);
      expect(electricChairEmptyRevealSeconds, lessThan(electricChairRevealSeconds));
    });

    test('pauza scurta ramane totusi cat sa se citeasca raspunsul corect', () {
      expect(electricChairEmptyRevealSeconds, greaterThanOrEqualTo(2));
      expect(electricChairEmptyRevealSeconds, lessThanOrEqualTo(4));
    });

    test('toti clientii calculeaza aceeasi valoare din aceleasi date', () {
      for (final anyoneTested in [true, false]) {
        expect(
          electricChairRevealSecondsFor(anyoneTested: anyoneTested),
          electricChairRevealSecondsFor(anyoneTested: anyoneTested),
        );
      }
    });
  });

  /// Cerința modului (aleasă explicit de user): "ultimul rămas în viață"
  /// trebuie să iasă pe primul loc în clasamentul final. `score` rămâne
  /// mic (bun pentru XP) — clasamentul se face după [electricChairRankKey]
  /// (vezi MultiplayerResultsScreen._rankValue), NU după `score` brut.
  ///
  /// PRIMA încercare (dovedită greșită la revizuire) acorda puncte de
  /// supraviețuire direct în `score`, în fiecare rundă, mizând pe faptul că
  /// ponderea per-rundă domina orice punct de acțiune POSIBIL ÎNTR-O
  /// RUNDĂ. Asta nu ajunge: diferența trebuie să domine orice sumă
  /// acumulată pe TOT meciul, altfel un jucător foarte activ, eliminat CU O
  /// RUNDĂ MAI DEVREME, tot poate prinde din urmă pe cineva care a
  /// supraviețuit doar puțin mai mult — vezi contraexemplul din testul de
  /// mai jos, care ar fi PICAT cu vechea abordare.
  group('electricChairRankKey garanteaza ordinea "ultimul ramas in viata"', () {
    test('cine a rezistat mai mult claseaza mereu mai sus, indiferent de scorul de actiune', () {
      // A e eliminat la runda 10, dar a strans scorul de actiune maxim
      // posibil in FIECARE din cele 10 runde (raspuns + soc + aparare, caci
      // poate fi si atacator si victima in aceeasi runda).
      final scoreA = 10 * electricChairMaxActionPointsPerRound;
      final keyA = electricChairRankKey(eliminated: true, eliminatedAtRound: 10, score: scoreA);

      // B rezista DOAR O SINGURA runda in plus (eliminat la runda 11), dar
      // n-a actionat niciodata (scor 0). Contraexemplul exact care ar fi
      // picat cu o pondere per-runda fixa si mica (ex. 10): 13*10=130 vs
      // 11*10=110 — A ar fi iesit inaintea lui B, gresit.
      final keyB = electricChairRankKey(eliminated: true, eliminatedAtRound: 11, score: 0);

      expect(keyB, greaterThan(keyA));
    });

    test('cine e inca in viata la finalul meciului claseaza mereu peste cineva eliminat', () {
      final eliminated = electricChairRankKey(
        eliminated: true,
        eliminatedAtRound: electricChairMaxRounds - 1, // eliminat cat mai tarziu posibil
        score: electricChairMaxRounds * electricChairMaxActionPointsPerRound, // scor maxim posibil
      );
      final survivor = electricChairRankKey(eliminated: false, eliminatedAtRound: -1, score: 0);
      expect(survivor, greaterThan(eliminated));
    });

    test('la aceeasi runda de eliminare, scorul de actiune departajeaza', () {
      final higherAction = electricChairRankKey(eliminated: true, eliminatedAtRound: 7, score: 5);
      final lowerAction = electricChairRankKey(eliminated: true, eliminatedAtRound: 7, score: 2);
      expect(higherAction, greaterThan(lowerAction));
    });

    test('ponderea rundei domina orice scor acumulabil pe tot meciul', () {
      final maxScoreEverPossible = electricChairMaxRounds * electricChairMaxActionPointsPerRound;
      expect(electricChairRankKeyRoundWeight, greaterThan(maxScoreEverPossible));
    });

    test('e pura: aceleasi intrari dau mereu aceeasi iesire', () {
      final a = electricChairRankKey(eliminated: true, eliminatedAtRound: 4, score: 3);
      final b = electricChairRankKey(eliminated: true, eliminatedAtRound: 4, score: 3);
      expect(a, b);
    });
  });
}
