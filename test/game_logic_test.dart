import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/betting.dart';
import 'package:guess_it/core/game_helpers.dart';
import 'package:guess_it/core/progression.dart';
import 'package:guess_it/data/shop.dart';

void main() {
  group('costul hint-ului', () {
    test('scaleaza cu averea, intre plafoane', () {
      expect(hintCoinCost(0), 0); // nu poti plati mai mult decat ai
      expect(hintCoinCost(150), hintCostMin); // sub pragul de ~162 -> minimul
      expect(hintCoinCost(200), 7);
      expect(hintCoinCost(1000), 37);
      expect(hintCoinCost(100000), hintCostMax);
    });

    test('nu te lasa niciodata in pagubă: minimul e sub reward-ul unei intrebari', () {
      // cea mai ieftina intrebare (200p) plateste 12 monede; hint-ul minim 6.
      expect(hintCostMin, lessThan(coinsForCorrectAnswer(200)));
    });

    test('nu poate depasi niciodata averea curenta', () {
      for (final coins in [0, 1, 5, 6, 7, 50, 161, 162, 163]) {
        expect(hintCoinCost(coins), lessThanOrEqualTo(coins),
            reason: 'cu $coins monede');
      }
    });
  });

  group('recompensa unui raspuns corect', () {
    test('XP-ul nu mai e egal cu punctele intrebarii', () {
      expect(xpForCorrectAnswer(200), 11);
      expect(xpForCorrectAnswer(400), 17);
      expect(xpForCorrectAnswer(700), 27);
    });

    test('monedele cresc cu dificultatea', () {
      expect(coinsForCorrectAnswer(200), 12);
      expect(coinsForCorrectAnswer(400), 20);
      expect(coinsForCorrectAnswer(700), 33);
    });

    test('multiplicatorul de serie e in trepte', () {
      expect(streakMultiplier(1), 1.0);
      expect(streakMultiplier(3), 1.17);
      expect(streakMultiplier(5), 1.34);
      expect(streakMultiplier(8), 1.58);
      expect(streakMultiplier(30), 1.79);
    });
  });

  group('curba de nivel', () {
    test('nivelul 5 nu se mai atinge in 16 raspunsuri corecte', () {
      final answersToLevel5 = cumulativeXpForLevel(5) / xpForCorrectAnswer(200);
      expect(answersToLevel5, greaterThan(200));
    });

    test('e strict crescatoare si consistenta cu levelForXp', () {
      for (var level = 1; level < 20; level++) {
        expect(xpForLevel(level + 1), greaterThan(xpForLevel(level)));
        expect(levelForXp(cumulativeXpForLevel(level)), level);
        expect(levelForXp(cumulativeXpForLevel(level) - 1), level - 1 == 0 ? 1 : level - 1);
      }
    });
  });

  group('taxa de intrare in categorie', () {
    test('scaleaza cu averea, intre plafoane', () {
      expect(categoryEntryFee(0), categoryEntryFeeMin);
      expect(categoryEntryFee(5000), 105);
      expect(categoryEntryFee(1000000), categoryEntryFeeMax);
    });

    test('recompensa la iesire e in 4 trepte, raportate la taxa platita', () {
      expect(categoryExitReward(0, 100), 0);
      expect(categoryExitReward(3, 100), 0);
      expect(categoryExitReward(4, 100), 60);
      expect(categoryExitReward(8, 100), 100);
      expect(categoryExitReward(15, 100), 130);
    });
  });

  group('quest-uri', () {
    test('gems doar la quest-urile medii si grele, crescator', () {
      // Ținta: o săptămână de joc adună cât costă o categorie noua (34 gems),
      // nu o categorie pe zi — de-aia cele ușoare nu mai dau gems deloc.
      for (final q in allQuests) {
        expect(
          q.gemReward,
          q.tier == QuestTier.easy ? 0 : greaterThan(0),
          reason: q.id,
        );
      }
      final perTier = {
        for (final tier in QuestTier.values)
          tier: allQuests.firstWhere((q) => q.tier == tier).gemReward
      };
      expect(perTier[QuestTier.medium], greaterThan(perTier[QuestTier.easy]!));
      expect(perTier[QuestTier.hard], greaterThan(perTier[QuestTier.medium]!));
    });

    test('o saptamana de quest-uri ajunge pentru o categorie noua, nu pentru un tier intreg', () {
      // 2026-08-03 e o luni; suma peste toate cele 7 zile din rotație.
      final weekly = List.generate(7, (i) => DateTime(2026, 8, 3 + i))
          .expand(todaysQuests)
          .fold<int>(0, (sum, q) => sum + q.gemReward);
      // Maximul TEORETIC (absolut toate cele 88 terminate) trebuie să fie
      // peste prețul unei categorii, dar sub prețul cumulat al primelor trei
      // — altfel s-ar debloca tot arborele într-o săptămână.
      //
      // Plafonul a urcat de la 2× la 3× odată cu trecerea la 12-14 quest-uri
      // pe zi cu ținte de o zi întreagă (questTargetScale). Nu înseamnă gems
      // mai ieftini: "toate quest-urile unei săptămâni" e acum un scenariu
      // mult mai extrem decât era la 71 de quest-uri cu ținte de câteva
      // minute. Ce contează pentru ritmul real e plafonul zilnic
      // (dailyQuestGemCap), verificat separat în quest_rotation_test.
      expect(weekly, greaterThan(questionUnlockGemsPrice(1)));
      expect(
          weekly,
          lessThan(questionUnlockGemsPrice(1) +
              questionUnlockGemsPrice(2) +
              questionUnlockGemsPrice(3)));
    });

    test('toate metricile de quest sunt distincte de id doar unde trebuie', () {
      // regresie: quest-uri ca wheel_spin_1 aveau metricKey implicit egal cu
      // id-ul, dar nimeni nu bumpa acel metric — erau imposibil de terminat.
      const bumpedMetrics = {
        'wheel_spin', 'culture_quiz_correct', 'daily_challenge_done',
        'culture_quiz_batches', 'question_batch_unlocked', 'shop_spend',
        'clippy_done', 'clippy_perfect', 'modes_played', 'hints_used',
        'answer_count', 'correct_count', 'coins_earned', 'no_hint_correct',
        'streak_hit_3', 'streak_hit_5', 'streak_hit_8', 'streak_hit_10',
        'level_reward_claimed', 'daily_lives_claimed', 'heart_bought',
        'hint_pack_bought', 'quests_claimed_today',
        'mp_bet_played', 'mp_win',
        // Planeta hologramelor (a înlocuit Quiz Nelimitat, deci
        // 'unlimited_quiz_correct' a ieșit din listă odată cu ecranul lui)
        'planet_run', 'planet_correct', 'planet_survived',
        'planet_good_run', 'planet_great_run', 'planet_perfect',
      };
      for (final q in allQuests) {
        expect(bumpedMetrics.contains(q.metricKey), isTrue,
            reason: '${q.id} foloseste metricul "${q.metricKey}", pe care nu-l bumpa nimeni');
      }
    });
  });

  group('mizele multiplayer', () {
    test('in doi, castigatorul ia tot ce ramane dupa comision', () {
      // Cazul care conteaza cel mai mult: Join Online e mereu 1 vs 1. Cu
      // premiile impartite intre amandoi, o victorie in duel ar fi adus un
      // plus derizoriu fata de cat s-a riscat.
      final prizes = matchPrizes(stake: 150, players: 2);
      expect(prizes[1], 0);
      expect(prizes[0], matchPrizePool(stake: 150, players: 2));
      // comisionul chiar iese din joc - nu se imparte tot ce s-a pus pe masa
      expect(prizes[0], lessThan(matchPot(stake: 150, players: 2)));
    });

    test('premiile nu inventeaza si nu pierd monede', () {
      // 11 = capacitatea unei camere private (matchPlayerCount din
      // multiplayer_service.dart, scris aici ca literal ca testul sa nu
      // tarasca dupa el importurile de Firebase).
      for (final stake in matchStakeOptions) {
        for (var n = 2; n <= 11; n++) {
          final prizes = matchPrizes(stake: stake, players: n);
          final total = prizes.fold<int>(0, (s, v) => s + v);
          expect(total, matchPrizePool(stake: stake, players: n),
              reason: '$n jucatori, miza $stake');
          expect(total, lessThan(matchPot(stake: stake, players: n)),
              reason: 'comisionul la $n jucatori, miza $stake');
        }
      }
    });

    test('doar jumatatea de sus a clasamentului ia premiu', () {
      expect(paidPlaceCount(2), 1);
      expect(paidPlaceCount(3), 2);
      expect(paidPlaceCount(4), 2);
      expect(paidPlaceCount(11), 6);
    });

    test('fiecare loc platit ia jumatate din cat ia cel dinaintea lui', () {
      // Regula pe care o citeste jucatorul in dialog. Daca se strica aici, tot
      // ce scrie in interfata devine minciuna.
      for (var n = 2; n <= 11; n++) {
        final prizes = matchPrizes(stake: 150, players: n);
        final paid = paidPlaceCount(n);
        for (var i = 1; i < paid; i++) {
          expect(prizes[i] / prizes[i - 1], closeTo(0.5, 0.03),
              reason: 'locul ${i + 1} la $n jucatori');
        }
        for (var i = paid; i < n; i++) {
          expect(prizes[i], 0, reason: 'locul ${i + 1} e in jumatatea de jos');
        }
      }
    });

    test('locul 1 iese mereu pe plus, ultimul mereu pe minus', () {
      for (final stake in matchStakeOptions) {
        for (var n = 2; n <= 11; n++) {
          final prizes = matchPrizes(stake: stake, players: n);
          expect(prizes.first, greaterThan(stake),
              reason: 'castigatorul la $n jucatori, miza $stake');
          expect(prizes.last, lessThan(stake),
              reason: 'ultimul la $n jucatori, miza $stake');
        }
      }
    });

    test('la egalitate se imparte, nu ia unul tot', () {
      // Fara asta, o remiza intr-un duel l-ar fi lasat pe unul cu toata
      // gramada si pe celalalt cu zero, dupa cum s-a nimerit sortarea.
      final draw = matchPrizesForRanking(stake: 150, sortedScores: [900, 900]);
      expect(draw[0], draw[1]);
      expect(draw[0] + draw[1], matchPrizePool(stake: 150, players: 2));
    });

    test('egalitatea partiala atinge doar premiile celor egali', () {
      final base = matchPrizes(stake: 500, players: 4);
      final tied = matchPrizesForRanking(stake: 500, sortedScores: [900, 300, 300, 100]);
      expect(tied[0], base[0]);
      expect(tied[3], base[3]);
      expect(tied[1], tied[2]);
      expect(tied[1] + tied[2], base[1] + base[2]);
    });

    test('un meci ramas cu un singur jucator returneaza miza intreaga', () {
      expect(matchPrizes(stake: 500, players: 1), [500]);
    });

    test('Join Online nu poate fi cel mai scump drum din joc', () {
      // E singurul loc unde jucatorul NU alege miza, deci nu are voie sa fie
      // si cel care il costa cel mai mult.
      final cheapest = matchStakeOptions.reduce((a, b) => a < b ? a : b);
      expect(publicMatchStake, cheapest);
      expect(minMatchStake, cheapest);
    });

    test('fiecare miza are un nume afisabil', () {
      expect(matchStakeLabels.length, matchStakeOptions.length);
      for (final stake in matchStakeOptions) {
        expect(matchStakeLabel(stake), isNotEmpty);
      }
      expect(matchStakeLabel(1234), isEmpty);
      expect(matchStakeOptions.contains(defaultMatchStake), isTrue);
    });
  });

  group('multiplayer clasic', () {
    test('ghicitul orb pierde puncte, hint-ul plus ghicit nu', () {
      // Calibrarea penalizarilor: bataia la nimereala pe 4 variante trebuie sa
      // aiba valoare asteptata negativa, iar hint-ul (care lasa 2 variante) sa
      // scoata jucatorul din minus. Verificat pe toate valorile reale de
      // intrebare din joc.
      for (final maxPoints in [200, 300, 400, 700, 1000]) {
        final hint = multiplayerHintPenalty(maxPoints);
        final wrong = multiplayerWrongPenalty(maxPoints);

        final blindGuess = 0.25 * maxPoints - 0.75 * wrong;
        expect(blindGuess, lessThan(0), reason: 'ghicit orb la ${maxPoints}p');

        final afterHint = 0.5 * (maxPoints - hint) - 0.5 * (hint + wrong);
        expect(afterHint, greaterThan(0), reason: 'hint + ghicit la ${maxPoints}p');

        // cine STIE raspunsul nu are ce castiga dintr-un hint
        expect(maxPoints - hint, lessThan(maxPoints));
      }
    });

    test('un meci prost nu poate sterge XP castigat aiurea', () {
      expect(multiplayerXpForScore(-5000, won: false),
          greaterThanOrEqualTo(multiplayerParticipationXpBonus));
      expect(multiplayerXpForScore(0, won: false), multiplayerParticipationXpBonus);
    });
  });
}
