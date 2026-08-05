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

  group('pariuri multiplayer', () {
    test('pariul respecta procentul, minimul si averea', () {
      expect(betAmountFor(coins: 40, percent: 0.5), 0); // sub pragul de intrare
      expect(betAmountFor(coins: 1000, percent: 0.10), 96);
      expect(betAmountFor(coins: 100, percent: 0.05), minBetAmount);
    });

    test('la masa echilibrata, primul castiga si ultimul pierde', () {
      final entries = [
        for (var i = 0; i < 7; i++)
          BetEntry(
            playerId: 'p$i',
            bet: 300,
            betPercent: 0.3,
            performance: 1 - i / 6,
            place: i + 1,
          ),
      ];
      final result = BetPayouts.compute(entries);
      expect(result.payouts['p0']!, greaterThan(300));
      expect(result.payouts['p6']!, lessThan(300));
      // suma platilor nu poate depasi pool-ul net (rake-ul chiar iese din joc)
      final total = result.payouts.values.fold<int>(0, (s, v) => s + v);
      expect(total, lessThanOrEqualTo(result.poolNet + entries.length));
      expect(result.poolNet, lessThan(result.pool));
    });

    test('plafonul mesei retează pariul unui jucător bogat si îi returnează restul', () {
      final bets = [6000, 40, 300, 300, 300, 300, 300];
      final entries = [
        // bogatul termina ULTIMUL, micul termina PRIMUL
        BetEntry(playerId: 'mic', bet: 40, betPercent: 0.10, performance: 1.0, place: 1),
        for (var i = 0; i < 5; i++)
          BetEntry(
            playerId: 'mid$i',
            bet: 300,
            betPercent: 0.3,
            performance: 0.8 - i * 0.12,
            place: i + 2,
          ),
        BetEntry(playerId: 'bogat', bet: 6000, betPercent: 0.6, performance: 0.0, place: 7),
      ];
      final cap = BetPayouts.tableCapFor(bets);
      final result = BetPayouts.compute(entries);

      expect(result.effectiveBets['bogat'], cap);
      expect(result.refunds['bogat'], 6000 - cap);
      // bogatul pierde o parte reala din miza efectiva...
      expect(result.payouts['bogat']!, lessThan(cap));
      // ...iar micul, care a rezistat pana la final, pleaca cu de cateva ori
      // miza lui — exact redistribuirea pentru care exista potul de loc.
      expect(result.payouts['mic']!, greaterThan(40 * 3));
    });

    test('a paria enorm la o masa mica e prost chiar si cand castigi', () {
      List<BetEntry> table({required double whalePerf}) => [
            BetEntry(playerId: 'bogat', bet: 6000, betPercent: 0.6, performance: whalePerf, place: whalePerf > 0.5 ? 1 : 7),
            for (var i = 0; i < 5; i++)
              BetEntry(playerId: 'mid$i', bet: 300, betPercent: 0.3, performance: 0.5, place: i + 2),
            BetEntry(playerId: 'mic', bet: 40, betPercent: 0.10, performance: 0.2, place: 7),
          ];
      final won = BetPayouts.compute(table(whalePerf: 1.0));
      final effective = won.effectiveBets['bogat']!;
      final profit = won.payouts['bogat']! - effective;
      // castiga, dar marginal — nu poate "aspira" masa
      expect(profit, greaterThan(0));
      expect(profit / effective, lessThan(0.25));
    });

    test('sub 2 jucatori nu exista pool — miza se intoarce', () {
      final result = BetPayouts.compute([
        const BetEntry(playerId: 'solo', bet: 500, betPercent: 0.4, performance: 1, place: 1),
      ]);
      expect(result.payouts['solo'], 500);
    });

    test('cotele potului de loc insumeaza 1 pentru orice numar de jucatori', () {
      for (var n = 2; n <= 20; n++) {
        final sum = placementShares(n).fold<double>(0, (s, v) => s + v);
        expect(sum, closeTo(1.0, 1e-9), reason: '$n jucatori');
      }
    });

    test('fiecare loc valoreaza strict mai putin decat cel dinaintea lui', () {
      // Inainte, orice loc de la al 8-lea incolo primea aceeasi cota plata
      // (0,01), deci intr-o camera plina nu mai exista niciun motiv sa lupti
      // pentru locul 9 in loc de 11.
      // 11 = capacitatea unei camere private (matchPlayerCount din
      // multiplayer_service.dart, scris aici ca literal ca testul sa nu tarasca
      // dupa el importurile de Firebase).
      final shares = placementShares(11);
      for (var i = 1; i < shares.length; i++) {
        expect(shares[i], lessThan(shares[i - 1]), reason: 'locul ${i + 1}');
      }
    });

    test('la masa mare, mijlocul plutonului nu mai sangereaza ca inainte', () {
      // Cota potului de loc scade cu marimea mesei tocmai ca jumatatea de jos
      // sa nu plateasca sistematic varful la fiecare meci.
      List<BetEntry> table(int n) => [
            for (var i = 0; i < n; i++)
              BetEntry(
                playerId: 'p$i',
                bet: 300,
                betPercent: 0.23,
                performance: n > 1 ? (n - 1 - i) / (n - 1) : 1.0,
                place: i + 1,
              ),
          ];
      final big = BetPayouts.compute(table(20));
      final median = big.payouts['p10']!;
      final winner = big.payouts['p0']!;
      expect(median / 300, greaterThan(0.85), reason: 'mijlocul mesei');
      expect(winner / 300, greaterThan(1.8), reason: 'locul 1 ramane atractiv');
    });

    test('performanta ramane ordonata chiar si cu scoruri negative', () {
      final perfs = classicPerformances([2006, 1584, 372, -121]);
      expect(perfs.first, 1.0);
      expect(perfs.last, 0.0);
      for (var i = 1; i < perfs.length; i++) {
        expect(perfs[i], lessThan(perfs[i - 1]));
      }
    });

    test('o masa fara scoruri negative se comporta exact ca inainte', () {
      // Translatia nu trebuie sa se atinga de mesele "normale": aici raportul
      // simplu scor/scorMaxim e si el raspunsul corect.
      final perfs = classicPerformances([2000, 1900, 1850]);
      expect(perfs[1], closeTo(0.95, 1e-9));
      expect(perfs[2], closeTo(0.925, 1e-9));
    });

    test('toti la egalitate nu inseamna performanta zero pentru nimeni', () {
      expect(classicPerformances([0, 0, 0]), everyElement(1.0));
      expect(classicPerformances([-140, -140]), everyElement(1.0));
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
