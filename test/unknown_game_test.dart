import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/unknown_game.dart';

UnknownGame _game({int players = 3, int seed = 7}) => UnknownGame(
      seed: seed,
      players: [
        for (var i = 0; i < players; i++) UnknownPlayer(id: 'p$i', name: 'P$i', isBot: i > 0, colorIndex: i),
      ],
    );

Map<String, UnknownAnswer> _all(UnknownGame g, {required bool correct}) =>
    {for (final p in g.players) p.id: UnknownAnswer(correct: correct, ms: 1000 + g.players.indexOf(p) * 100)};

UnknownRoll _roll(UnknownPlayer p, int steps) =>
    UnknownRoll(playerId: p.id, dice: [steps], bonus: 0, labels: const [], fastest: false);

/// Joacă un meci întreg cu boți „orbi" și întoarce jocul terminat.
UnknownGame _playOut(int seed, int players, {double accuracy = 0.6}) {
  final rnd = Random(seed);
  final g = _game(seed: seed, players: players);
  while (!g.isOver) {
    for (final p in g.players) {
      unknownBotArm(g, p);
    }
    final answers = {
      for (final p in g.players) p.id: UnknownAnswer(correct: rnd.nextDouble() < accuracy, ms: rnd.nextInt(9000)),
    };
    final rolls = g.resolveAnswers(answers).rolls;
    for (final id in g.moveOrder(answers)) {
      final p = g.player(id);
      final m = g.move(p, rolls[id]!);
      switch (m.landing.kind) {
        case UnknownLandingKind.chest:
          final k = unknownBotPickRelic(p, m.landing.relicOffers);
          g.takeRelic(p, k.take, drop: k.drop);
        case UnknownLandingKind.shop:
          final it = unknownBotPickItem(p, m.landing.itemOffers);
          if (it != null) g.buyItem(p, it);
        case UnknownLandingKind.duel:
          g.resolveDuel(p, g.player(m.landing.opponentId!), UnknownAnswer(correct: rnd.nextBool(), ms: rnd.nextInt(5000)),
              UnknownAnswer(correct: rnd.nextBool(), ms: rnd.nextInt(5000)));
        case UnknownLandingKind.goldenQuestion:
          g.resolveGolden(p, rnd.nextBool());
        case UnknownLandingKind.none:
          break;
      }
    }
    g.endRound();
  }
  return g;
}

void main() {
  group('tabla', () {
    test('scările urcă, șerpii coboară', () {
      unknownLadders.forEach((from, to) => expect(to, greaterThan(from)));
      unknownSnakes.forEach((from, to) => expect(to, lessThan(from)));
    });

    test('scările și șerpii duc pe câmpuri simple (fără reacție în lanț)', () {
      for (final to in [...unknownLadders.values, ...unknownSnakes.values]) {
        expect(unknownTileAt(to), UnknownTile.normal, reason: 'câmpul $to');
      }
    });

    test('niciun câmp nu e și scară și șarpe', () {
      expect(unknownLadders.keys.toSet().intersection(unknownSnakes.keys.toSet()), isEmpty);
    });

    test('finalul e ultimul câmp', () {
      expect(unknownTileAt(unknownFinish), UnknownTile.finish);
    });
  });

  group('zaruri', () {
    test('greșit = un zar, corect = două — greșit tot avansezi', () {
      final g = _game();
      for (final r in g.resolveAnswers(_all(g, correct: false)).rolls.values) {
        expect(r.dice.length, 1);
        expect(r.total, greaterThanOrEqualTo(1));
      }
      for (final r in g.resolveAnswers(_all(g, correct: true)).rolls.values) {
        expect(r.dice.length, 2);
      }
    });

    test('lipsa răspunsului contează ca greșit, nu blochează', () {
      final g = _game();
      final rolls = g.resolveAnswers({}).rolls;
      expect(rolls.length, g.players.length);
      expect(rolls.values.every((r) => r.dice.length == 1), isTrue);
    });

    test('cel mai rapid răspuns corect ia +3 monede', () {
      final g = _game();
      final before = g.player('p1').coins;
      final res = g.resolveAnswers({
        'p0': const UnknownAnswer(correct: false, ms: 100),
        'p1': const UnknownAnswer(correct: true, ms: 900),
        'p2': const UnknownAnswer(correct: true, ms: 1500),
      });
      expect(res.rolls['p1']!.fastest, isTrue);
      expect(g.player('p1').coins, before + 3);
    });

    test('ordinea mutărilor: corecții după viteză, apoi ceilalți', () {
      final g = _game();
      expect(
        g.moveOrder({
          'p0': const UnknownAnswer(correct: false, ms: 100),
          'p1': const UnknownAnswer(correct: true, ms: 900),
          'p2': const UnknownAnswer(correct: true, ms: 500),
        }),
        ['p2', 'p1', 'p0'],
      );
    });

    test('Zarul trucat nu dă niciodată 1', () {
      final g = _game();
      g.players.first.relics.add(UnknownRelic.loadedDie);
      for (var i = 0; i < 200; i++) {
        expect(g.resolveAnswers(_all(g, correct: true)).rolls['p0']!.dice, isNot(contains(1)));
      }
    });

    test('Seria de foc crește cu răspunsurile corecte la rând, max +3', () {
      final g = _game();
      final p = g.players.first..relics.add(UnknownRelic.onFire);
      final bonuses = [for (var i = 0; i < 6; i++) g.resolveAnswers(_all(g, correct: true)).rolls[p.id]!.bonus];
      expect(bonuses.take(4).toList(), [0, 1, 2, 3]);
      expect(bonuses.last, 3);
    });

    test('obiectul pregătit se consumă la mutare', () {
      final g = _game();
      final p = g.players.first..items.add(UnknownItem.extraDie);
      g.arm(p, UnknownItem.extraDie);
      expect(p.items, isEmpty);
      expect(g.resolveAnswers(_all(g, correct: true)).rolls[p.id]!.dice.length, 3);
      expect(p.armed, isNull);
    });

    test('ultimul primește vânt din spate (+2)', () {
      final g = _game()..round = 3;
      g.players[0].pos = 20;
      g.players[1].pos = 5;
      g.players[2].pos = 12;
      final r = g.resolveAnswers(_all(g, correct: false)).rolls;
      expect(r['p1']!.bonus, 2);
      expect(r['p0']!.bonus, 0);
    });
  });

  group('drum', () {
    test('scara te urcă', () {
      final g = _game();
      final p = g.players.first..pos = 1;
      final m = g.move(p, _roll(p, 2)); // 3 → 11
      expect(p.pos, 11);
      expect(m.hops.last.kind, UnknownHopKind.ladder);
    });

    test('șarpele te coboară, dar nu dacă ai imunitate', () {
      final g = _game();
      final p = g.players.first..pos = 15;
      g.move(p, _roll(p, 2)); // 17 → 6
      expect(p.pos, 6);
      p
        ..pos = 15
        ..shielded = true;
      g.move(p, _roll(p, 2));
      expect(p.pos, 17);
      expect(p.shielded, isFalse, reason: 'imunitatea se consumă');
    });

    test('Umbrela: șarpele te duce doar pe jumătate', () {
      final g = _game();
      final p = g.players.first
        ..relics.add(UnknownRelic.umbrella)
        ..pos = 15;
      g.move(p, _roll(p, 2)); // 17 → 6 întreg, 17 → 12 pe jumătate (11 / 2 = 5)
      expect(p.pos, 12);
    });

    test('Scara de aur: +3 peste vârful scării', () {
      final g = _game();
      final p = g.players.first
        ..relics.add(UnknownRelic.goldLadder)
        ..pos = 1;
      g.move(p, _roll(p, 2));
      expect(p.pos, 14);
    });

    test('„înapoi 3"', () {
      final g = _game();
      final p = g.players.first..pos = 13;
      g.move(p, _roll(p, 2)); // 15 → 12
      expect(p.pos, 12);
    });

    test('capcana: stai o tură, apoi te miști iar', () {
      final g = _game();
      final p = g.players.first..pos = 22;
      g.move(p, _roll(p, 1)); // 23 = capcană
      expect(p.skipNext, isTrue);
      final r = g.resolveAnswers(_all(g, correct: true)).rolls[p.id]!;
      expect(r.skipped, isTrue);
      expect(r.total, 0);
      final m = g.move(p, r);
      expect(m.hops, isEmpty);
      expect(p.pos, 23);
      expect(g.resolveAnswers(_all(g, correct: true)).rolls[p.id]!.skipped, isFalse);
    });

    test('trifoiul dă imunitate', () {
      final g = _game();
      final p = g.players.first..pos = 11;
      g.move(p, _roll(p, 1)); // 12 = trifoi
      expect(p.shielded, isTrue);
    });

    test('dacă dai mai mult decât îți trebuie, tot ai ajuns', () {
      final g = _game();
      final p = g.players.first..pos = 58;
      final m = g.move(p, _roll(p, 5));
      expect(p.pos, unknownFinish);
      expect(p.finished, isTrue);
      expect(m.hops.length, 2, reason: 'pionul se oprește pe final');
    });

    test('fix pe final = ai ajuns, meciul se termină după runda asta', () {
      final g = _game();
      final p = g.players.first..pos = 55;
      g.move(p, _roll(p, 5));
      expect(p.finished, isTrue);
      expect(p.finishOrder, 0);
      expect(g.isOver, isFalse, reason: 'ceilalți își termină runda');
      g.endRound();
      expect(g.isOver, isTrue);
      expect(g.standings().first.id, p.id);
    });

    test('cine a ajuns nu se mai mută', () {
      final g = _game();
      g.players.first.pos = unknownFinish;
      expect(g.moveOrder(_all(g, correct: true)), isNot(contains('p0')));
    });

    test('monedele nu scad niciodată sub zero', () {
      final g = _game();
      final p = g.players.first
        ..coins = 1
        ..pos = 52;
      g.move(p, _roll(p, 2)); // 54 = taxă
      expect(p.coins, 0);
    });

    test('Magnetul fură 2 de la cei pe lângă care treci', () {
      final g = _game();
      final p = g.players[0]
        ..relics.add(UnknownRelic.magnet)
        ..pos = 28;
      final q = g.players[1]
        ..coins = 10
        ..pos = 29;
      g.move(p, _roll(p, 2));
      expect(q.coins, 8);
    });

    test('Schimbul te pune în locul celui din față', () {
      final g = _game();
      final p = g.players[0]
        ..pos = 5
        ..items.add(UnknownItem.swap);
      g.players[1].pos = 30;
      g.players[2].pos = 12;
      g.arm(p, UnknownItem.swap);
      g.resolveAnswers(_all(g, correct: true));
      expect(p.pos, 12);
      expect(g.players[2].pos, 5);
    });
  });

  group('decizii', () {
    test('al patrulea artefact scoate unul', () {
      final g = _game();
      final p = g.players.first..relics.addAll([UnknownRelic.scholar, UnknownRelic.magnet, UnknownRelic.echo]);
      g.takeRelic(p, UnknownRelic.onFire, drop: UnknownRelic.magnet);
      expect(p.relics, [UnknownRelic.scholar, UnknownRelic.echo, UnknownRelic.onFire]);
    });

    test('magazinul refuză fără bani sau cu buzunarele pline', () {
      final g = _game();
      final p = g.players.first..coins = 5;
      expect(g.buyItem(p, UnknownItem.extraDie), isFalse);
      p.coins = 100;
      expect(g.buyItem(p, UnknownItem.extraDie), isTrue);
      expect(g.buyItem(p, UnknownItem.bigStep), isTrue);
      expect(g.buyItem(p, UnknownItem.shield), isFalse);
    });

    test('duel: amândoi corecți → câștigă cel mai rapid', () {
      final g = _game();
      final a = g.players[0]..coins = 10;
      final d = g.players[1]..coins = 10;
      final res = g.resolveDuel(a, d, const UnknownAnswer(correct: true, ms: 2000), const UnknownAnswer(correct: true, ms: 1000));
      expect(res.winnerId, d.id);
      expect(d.coins, 16);
      expect(a.coins, 4);
    });

    test('botul schimbă un artefact doar pe unul mai bun', () {
      final p = UnknownPlayer(id: 'b', name: 'B', isBot: true, colorIndex: 0)
        ..relics.addAll([UnknownRelic.goldLadder, UnknownRelic.umbrella, UnknownRelic.onFire]);
      expect(unknownBotPickRelic(p, [UnknownRelic.duelist]).take, isNull);
      p.relics[2] = UnknownRelic.duelist;
      final better = unknownBotPickRelic(p, [UnknownRelic.lightning]);
      expect(better.take, UnknownRelic.lightning);
      expect(better.drop, UnknownRelic.duelist);
    });
  });

  group('meciul întreg', () {
    test('aceeași sămânță → același meci', () {
      String sig(UnknownGame g) => [for (final p in g.players) '${p.pos}/${p.coins}/${p.relics}'].join('|');
      expect(sig(_playOut(42, 4)), sig(_playOut(42, 4)));
      expect(sig(_playOut(42, 4)), isNot(sig(_playOut(43, 4))));
    });

    test('echilibru: un meci ține în medie 7-12 runde și aproape mereu are un câștigător', () {
      for (final n in [2, 4, 6]) {
        var rounds = 0, noWinner = 0;
        const games = 300;
        for (var s = 0; s < games; s++) {
          final g = _playOut(s, n);
          rounds += g.round;
          if (!g.players.any((p) => p.finished)) noWinner++;
        }
        final avg = rounds / games;
        expect(avg, inInclusiveRange(7, 12), reason: '$n jucători: $avg runde');
        expect(noWinner / games, lessThan(0.05), reason: '$n jucători: fără câștigător ${noWinner / games}');
      }
    });

    test('și cine greșește mult tot termină cursa în timp rezonabil', () {
      var finished = 0;
      for (var s = 0; s < 200; s++) {
        final g = _playOut(s, 2, accuracy: 0.2);
        if (g.players.any((p) => p.finished)) finished++;
      }
      expect(finished / 200, greaterThan(0.8));
    });
  });
}
