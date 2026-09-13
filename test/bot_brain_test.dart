import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/bot_brain.dart';
import 'package:guess_it/core/rock_paper_scissors.dart';

void main() {
  test('acuratetea creste cu dificultatea si nu e niciodata perfecta', () {
    for (var d = botMinDifficulty; d < botMaxDifficulty; d++) {
      expect(botAccuracy(d + 1), greaterThan(botAccuracy(d)));
    }
    expect(botAccuracy(botMaxDifficulty), lessThan(1));
  });

  test('botPickAnswer respecta aproximativ acuratetea', () {
    final rnd = Random(1);
    const choices = ['a', 'b', 'c', 'd'];
    for (var d = botMinDifficulty; d <= botMaxDifficulty; d++) {
      var hits = 0;
      for (var i = 0; i < 4000; i++) {
        if (botPickAnswer(correct: 'a', choices: choices, difficulty: d, rnd: rnd) == 'a') hits++;
      }
      expect(hits / 4000, closeTo(botAccuracy(d), 0.04));
    }
  });

  test('timpul de gandire ramane in runda si scade cu dificultatea', () {
    final rnd = Random(2);
    double avg(int d) {
      var total = 0;
      for (var i = 0; i < 500; i++) {
        final t = botThinkTime(difficulty: d, roundSeconds: 15, rnd: rnd).inMilliseconds;
        expect(t, inInclusiveRange(600, 13500));
        total += t;
      }
      return total / 500;
    }
    expect(avg(5), lessThan(avg(1)));
  });

  test('tinta: nivelul maxim vaneaza mai des tancul slabit', () {
    final rnd = Random(3);
    const hp = {'x': 90, 'y': 12, 'z': 70};
    int weakHits(int d) => List.generate(2000, (_) => botPickTarget(hpById: hp, difficulty: d, rnd: rnd))
        .where((t) => t == 'y')
        .length;
    expect(weakHits(5), greaterThan(weakHits(1) + 600));
    expect(botPickTarget(hpById: const {}, difficulty: 3, rnd: rnd), isNull);
  });

  test('placa: nivelul maxim evita mai des placa falsa', () {
    final rnd = Random(4);
    int falls(int d) => List.generate(3000,
        (_) => botPickPlatform(platformCount: 3, safeIndices: const {0, 2}, difficulty: d, rnd: rnd)).where((p) => p == 1).length;
    expect(falls(5), lessThan(falls(1) - 500));
  });

  test('RPS: mereu o mana valida', () {
    final rnd = Random(5);
    for (var i = 0; i < 200; i++) {
      expect([rpsRock, rpsPaper, rpsScissors],
          contains(botPickRps(humanHistory: const {rpsRock: 3}, difficulty: 5, rnd: rnd)));
    }
  });

  test('nume de bot: marcat vizibil, cate trebuie', () {
    final names = botNames(6, Random(6));
    expect(names, hasLength(6));
    expect(names.every((n) => n.endsWith(' 🤖') && !n.startsWith('🤖')), isTrue);
    expect(names.toSet(), hasLength(6));
  });

  test('recompensa: primul > al doilea > ultimul, crescatoare cu dificultatea', () {
    final first = botMatchReward(place: 0, totalPlayers: 4, difficulty: 3, botCount: 3);
    final second = botMatchReward(place: 1, totalPlayers: 4, difficulty: 3, botCount: 3);
    final last = botMatchReward(place: 3, totalPlayers: 4, difficulty: 3, botCount: 3);
    expect(first.coins, greaterThan(second.coins));
    expect(last.coins, 0);
    expect(botMatchReward(place: 0, totalPlayers: 2, difficulty: 5, botCount: 1).coins,
        greaterThan(botMatchReward(place: 0, totalPlayers: 2, difficulty: 1, botCount: 1).coins));
    // plafon de sanatate pentru economie
    expect(botMatchReward(place: 0, totalPlayers: 7, difficulty: 5, botCount: 6).coins, lessThanOrEqualTo(30));
  });
}
