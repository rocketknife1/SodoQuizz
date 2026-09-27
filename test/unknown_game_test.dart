import 'dart:convert';
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
        case UnknownLandingKind.potion:
          if (m.landing.potionOffers.isNotEmpty && rnd.nextBool()) {
            final effect = m.landing.potionOffers[rnd.nextInt(m.landing.potionOffers.length)];
            switch (effect) {
              case UnknownPotionEffect.deadly:
                p.pos = max(1, p.pos - unknownPotionDeadlySetback);
              case UnknownPotionEffect.sleep:
                p.skipNext = true;
              case UnknownPotionEffect.setback:
                p.pos = max(1, p.pos - unknownPotionSetback);
              case UnknownPotionEffect.karma:
                p.pos = max(1, p.pos - 1);
            }
          }
        case UnknownLandingKind.none:
          break;
      }
    }
    g.endRound();
  }
  return g;
}

/// Joacă un meci întreg prin [UnknownGame.resolveRound] — exact drumul din
/// multiplayer: alegerile și obiectele boților se trimit ca ale unui om, iar
/// jocul se poate salva/restaura între runde ([saveEvery]).
String _playRounds(int seed, int players, {int? saveEvery}) {
  final rnd = Random(seed);
  var g = _game(seed: seed, players: players);
  var choices = <String, UnknownChoice>{};
  while (!g.isOver) {
    final arms = <String, UnknownItem>{
      for (final p in g.players)
        if (unknownBotArmChoice(g, p) case final item?) p.id: item,
    };
    final answers = {
      for (final p in g.players) p.id: UnknownAnswer(correct: rnd.nextDouble() < 0.6, ms: rnd.nextInt(9000)),
    };
    g.resolveRound(answers, arms: arms, choices: choices);
    choices = {for (final e in g.pendingOffers.entries) e.key: unknownBotChoice(g.player(e.key), e.value)};
    if (saveEvery != null && g.round % saveEvery == 0) {
      g = UnknownGame.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>);
    }
  }
  return [for (final p in g.players) '${p.pos}/${p.coins}/${p.relics}/${p.items}/${p.finishOrder}'].join('|');
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

  group('toți deodată (multiplayer)', () {
    test('duelul se decide la următoarea întrebare', () {
      final g = _game();
      g.player('p0').coins = 10;
      g.player('p1').coins = 10;
      g.pendingDuels.add(('p0', 'p1'));
      final log = g.resolveRound({
        'p0': const UnknownAnswer(correct: false, ms: 500),
        'p1': const UnknownAnswer(correct: true, ms: 4000),
        'p2': const UnknownAnswer(correct: false, ms: 1000),
      });
      expect(log.duels.single.winnerId, 'p1');
      expect(g.pendingDuels.where((d) => d == ('p0', 'p1')), isEmpty);
      expect(g.player('p1').duelsWon, 1);
    });

    test('întrebarea de aur: corect la următoarea întrebare = +4', () {
      final g = _game();
      g.player('p0').pos = 28;
      g.pendingGolden.add('p0');
      final log = g.resolveRound(_all(g, correct: true));
      expect(log.golden['p0'], isTrue);
      expect(log.prelude['p0']![0], 32);
    });

    test('alegerea din cufăr se aplică la runda următoare; una inventată e ignorată', () {
      final g = _game();
      g.pendingOffers['p0'] = const UnknownOffer(chest: true, relics: [UnknownRelic.onFire, UnknownRelic.echo]);
      g.pendingOffers['p1'] = const UnknownOffer(chest: true, relics: [UnknownRelic.magnet]);
      final log = g.resolveRound(_all(g, correct: false), choices: {
        'p0': const UnknownChoice(take: 'echo'),
        'p1': const UnknownChoice(take: 'goldLadder'),
      });
      expect(g.player('p0').relics, [UnknownRelic.echo]);
      expect(g.player('p1').relics, isEmpty);
      expect(log.choices.firstWhere((c) => c.playerId == 'p0').relic, UnknownRelic.echo);
    });

    test('cu 3 artefacte, fără să spui pe care îl lași, nu se schimbă nimic', () {
      final g = _game();
      final p = g.player('p0')..relics.addAll([UnknownRelic.scholar, UnknownRelic.magnet, UnknownRelic.echo]);
      g.pendingOffers['p0'] = const UnknownOffer(chest: true, relics: [UnknownRelic.onFire]);
      g.resolveRound(_all(g, correct: false), choices: {'p0': const UnknownChoice(take: 'onFire')});
      expect(p.relics, [UnknownRelic.scholar, UnknownRelic.magnet, UnknownRelic.echo]);
    });

    test('magazinul: obiectul se plătește la runda următoare', () {
      final g = _game();
      final p = g.player('p0')..coins = 20;
      g.pendingOffers['p0'] = const UnknownOffer(chest: false, items: [UnknownItem.shield, UnknownItem.swap]);
      g.resolveRound(_all(g, correct: false), choices: {'p0': const UnknownChoice(take: 'shield')});
      expect(p.items, contains(UnknownItem.shield));
    });

    test('cuferele de acum devin oferte în așteptare', () {
      // De pe câmpul 1, un zar de 4 duce pe cufărul de pe 5; căutăm o sămânță
      // care dă 4 (totul e determinist, deci testul nu e aleator).
      for (var seed = 0; seed < 200; seed++) {
        final h = _game(seed: seed)..player('p0').pos = 1;
        final log = h.resolveRound(_all(h, correct: false));
        final mine = log.moves.firstWhere((m) => m.roll.playerId == 'p0');
        if (mine.move.landing.kind == UnknownLandingKind.chest) {
          expect(h.pendingOffers['p0']?.chest, isTrue);
          expect(h.pendingOffers['p0']!.relics.length, 3);
          return;
        }
      }
      fail('niciun zar n-a dus pe cufăr în 200 de semințe');
    });

    test('cine pleacă nu se mai mută, iar singur la masă meciul se termină', () {
      final g = _game(players: 2);
      g.player('p1').left = true;
      expect(g.moveOrder(_all(g, correct: true)), ['p0']);
      expect(g.isOver, isTrue);
    });

    test('cheia de clasament dă aceeași ordine ca standings()', () {
      final g = _game(players: 4);
      g.player('p0').pos = 30;
      g.player('p1')
        ..pos = unknownFinish
        ..finishOrder = 1;
      g.player('p2')
        ..pos = unknownFinish
        ..finishOrder = 0;
      g.player('p3')
        ..pos = 30
        ..coins = 50;
      final byKey = List.of(g.players)..sort((a, b) => unknownRankKey(b).compareTo(unknownRankKey(a)));
      expect([for (final p in byKey) p.id], [for (final p in g.standings()) p.id]);
      expect(g.standings().map((p) => p.id), ['p2', 'p1', 'p3', 'p0']);
    });

    test('starea și jurnalul nu conțin liste direct în liste (Firestore le refuză)', () {
      void check(Object? v, String where, {bool inList = false}) {
        if (v is List) {
          expect(inList, isFalse, reason: 'listă în listă la $where');
          for (final x in v) {
            check(x, where, inList: true);
          }
        } else if (v is Map) {
          v.forEach((k, x) => check(x, '$where.$k'));
        }
      }

      for (final seed in [1, 2, 3, 4, 5, 6, 7, 8]) {
        final rnd = Random(seed);
        final g = _game(seed: seed, players: 5);
        var choices = <String, UnknownChoice>{};
        while (!g.isOver) {
          final log = g.resolveRound({
            for (final p in g.players) p.id: UnknownAnswer(correct: rnd.nextBool(), ms: rnd.nextInt(9000)),
          }, choices: choices);
          choices = {for (final e in g.pendingOffers.entries) e.key: unknownBotChoice(g.player(e.key), e.value)};
          check(g.toJson(), 'stare');
          check(log.toJson(), 'jurnal');
        }
      }
    });

    test('jurnalul rundei trece prin JSON fără să piardă nimic', () {
      final g = _game(players: 4);
      for (var i = 0; i < 5; i++) {
        final log = g.resolveRound(_all(g, correct: i.isEven));
        final json = jsonDecode(jsonEncode(log.toJson())) as Map<String, dynamic>;
        expect(UnknownRoundLog.fromJson(json).toJson(), log.toJson());
      }
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

    test('drumul multiplayer (resolveRound) e determinist', () {
      expect(_playRounds(5, 4), _playRounds(5, 4));
      expect(_playRounds(5, 4), isNot(_playRounds(6, 4)));
    });

    test('salvat și restaurat prin JSON la fiecare rundă = același meci ca fără pauză', () {
      for (final seed in [1, 2, 3, 17, 99]) {
        expect(_playRounds(seed, 4, saveEvery: 1), _playRounds(seed, 4), reason: 'seed $seed');
        expect(_playRounds(seed, 6, saveEvery: 3), _playRounds(seed, 6), reason: 'seed $seed');
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

  group('catapultă', () {
    test('16 și 48 sunt catapultă pe tablă', () {
      expect(unknownTileAt(16), UnknownTile.catapult);
      expect(unknownTileAt(48), UnknownTile.catapult);
    });

    test('lansează înainte, în intervalul configurat, o singură dată (fără lanț)', () {
      final g = _game(players: 2);
      final p = g.players[0];
      p.pos = 15;
      final m = g.move(p, _roll(p, 1));
      expect(p.pos, inInclusiveRange(16 + unknownCatapultMin, 16 + unknownCatapultMax));
      expect(m.hops.last.kind, UnknownHopKind.catapult);
      expect(m.landing.note, UnknownNote.catapult);
    });

    test('nu trece de finish direct din catapultă', () {
      final g = _game(players: 2);
      final p = g.players[0];
      p.pos = 47;
      final m = g.move(p, _roll(p, 1));
      expect(p.pos, lessThan(unknownFinish));
      expect(m.landing.note, UnknownNote.catapult);
    });

    test('aceeași sămânță → aceeași distanță de catapultare', () {
      int landedAt(int seed) {
        final g = UnknownGame(seed: seed, players: [UnknownPlayer(id: 'a', name: 'A', isBot: false, colorIndex: 0)]);
        final p = g.players[0];
        p.pos = 15;
        g.move(p, _roll(p, 1));
        return p.pos;
      }

      expect(landedAt(9), landedAt(9));
    });
  });

  group('coliziune (jucător pe jucător)', () {
    test('a picat pe cineva încă pe drum → declanșează coliziune, indiferent de tipul câmpului', () {
      final g = _game(players: 2);
      final a = g.players[0];
      final b = g.players[1];
      b.pos = 21; // coins — coliziunea trebuie să coexiste cu monedele
      a.pos = 19;
      final m = g.move(a, _roll(a, 2));
      expect(a.pos, 21);
      expect(m.landing.collisionOpponentId, b.id);
      expect(a.coins, greaterThan(unknownStartCoins)); // tot a luat monedele câmpului
    });

    test('nu se declanșează pe START sau pe câmpul liber', () {
      final g = _game(players: 2);
      final a = g.players[0];
      final b = g.players[1];
      b.pos = 40;
      a.pos = 1;
      final m = g.move(a, _roll(a, 1));
      expect(m.landing.collisionOpponentId, isNull);
    });

    test('cine ajunge sau a plecat nu mai declanșează coliziune', () {
      final g = _game(players: 2);
      final a = g.players[0];
      final b = g.players[1];
      b.pos = 21;
      b.left = true;
      a.pos = 19;
      final m = g.move(a, _roll(a, 2));
      expect(m.landing.collisionOpponentId, isNull);
    });

    test('resolveCollision: învinsul pierde pași, nu monede', () {
      final g = _game(players: 2);
      final a = g.players[0]..pos = 20;
      final b = g.players[1]..pos = 20;
      final coinsBefore = (a.coins, b.coins);
      final res = g.resolveCollision(
        a,
        b,
        const UnknownAnswer(correct: true, ms: 500),
        const UnknownAnswer(correct: false, ms: 999),
      );
      expect(res.winnerId, a.id);
      expect(b.pos, 20 - unknownCollisionPushback);
      expect(a.pos, 20);
      expect((a.coins, b.coins), coinsBefore);
    });

    test('resolveCollision: amândoi greșit → fără efect', () {
      final g = _game(players: 2);
      final a = g.players[0]..pos = 20;
      final b = g.players[1]..pos = 20;
      const miss = UnknownAnswer(correct: false, ms: 1 << 30);
      final res = g.resolveCollision(a, b, miss, miss);
      expect(res.winnerId, isNull);
      expect(a.pos, 20);
      expect(b.pos, 20);
    });

    test('o coliziune în așteptare se rezolvă la resolveRound și se golește', () {
      final g = _game(players: 2);
      final a = g.players[0]..pos = 20;
      final b = g.players[1]..pos = 20;
      g.pendingCollisions.add((a.id, b.id));
      final log = g.resolveRound({a.id: const UnknownAnswer(correct: true, ms: 100), b.id: const UnknownAnswer(correct: false, ms: 100)});
      expect(log.collisions, isNotEmpty);
      expect(log.collisions.first.winnerId, a.id);
      expect(g.pendingCollisions, isEmpty);
    });
  });

  group('vraja de stun', () {
    test('stunul prinde la runda VIITOARE, nu la asta — indiferent de ordinea din players', () {
      final g = _game(players: 2);
      final user = g.players[0];
      final target = g.players[1]..pos = 5;
      user.pos = 1;
      user.items.add(UnknownItem.stun);
      g.arm(user, UnknownItem.stun);
      final r1 = g.resolveAnswers(_all(g, correct: true));
      expect(r1.rolls[target.id]!.skipped, isFalse, reason: 'ținta se mișcă normal chiar în runda în care a fost stunată');
      expect(target.skipNext, isTrue);
      final r2 = g.resolveAnswers(_all(g, correct: true));
      expect(r2.rolls[target.id]!.skipped, isTrue);
      expect(target.skipNext, isFalse);
    });

    test('fără nimeni în față: obiectul se întoarce în inventar, nu se pierde', () {
      final g = _game(players: 2);
      final leader = g.players[0]..pos = 50;
      g.players[1].pos = 5;
      leader.items.add(UnknownItem.stun);
      g.arm(leader, UnknownItem.stun);
      g.resolveAnswers(_all(g, correct: true));
      expect(leader.items, contains(UnknownItem.stun));
      expect(leader.armed, isNull);
    });
  });

  group('poțiuni misterioase', () {
    test('33 și 56 sunt poțiune pe tablă; oferă 2 efecte diferite din cele 4', () {
      expect(unknownTileAt(33), UnknownTile.potion);
      expect(unknownTileAt(56), UnknownTile.potion);
      final g = _game(players: 2);
      final p = g.players[0]..pos = 32;
      final m = g.move(p, _roll(p, 1));
      expect(m.landing.kind, UnknownLandingKind.potion);
      expect(m.landing.potionOffers.length, 2);
      expect(m.landing.potionOffers[0], isNot(m.landing.potionOffers[1]));
    });

    test('aceeași sămânță → aceleași 2 poțiuni oferite', () {
      List<UnknownPotionEffect> offersFor(int seed) {
        final g = UnknownGame(seed: seed, players: [UnknownPlayer(id: 'a', name: 'A', isBot: false, colorIndex: 0)]);
        final p = g.players[0]..pos = 32;
        return g.move(p, _roll(p, 1)).landing.potionOffers;
      }

      expect(offersFor(11), offersFor(11));
    });

    test('efectul sleep: stă o tură; oferta se golește după alegere', () {
      final g = _game(players: 2);
      final p = g.players[0];
      g.pendingPotions[p.id] = const [UnknownPotionEffect.sleep, UnknownPotionEffect.setback];
      final log = g.resolveRound(_all(g, correct: true), choices: {p.id: const UnknownChoice(take: '0')});
      expect(g.pendingPotions, isEmpty);
      final applied = log.choices.firstWhere((c) => c.playerId == p.id);
      expect(applied.potion, UnknownPotionEffect.sleep);
      expect(log.moves.firstWhere((m) => m.roll.playerId == p.id).roll.skipped, isTrue);
    });

    test('efectul setback: câțiva pași înapoi', () {
      // Verificat pe `prelude` (poziția imediat după poțiune, înainte de
      // mutarea propriu-zisă a rundei) — zarul care urmează e tot aleator.
      final g = _game(players: 2);
      final p = g.players[0]..pos = 20;
      g.pendingPotions[p.id] = const [UnknownPotionEffect.setback, UnknownPotionEffect.sleep];
      final log = g.resolveRound(_all(g, correct: false), choices: {p.id: const UnknownChoice(take: '0')});
      expect(log.prelude[p.id]![0], 20 - unknownPotionSetback);
    });

    test('efectul deadly: mult înapoi', () {
      final g = _game(players: 2);
      final p = g.players[0]..pos = 30;
      g.pendingPotions[p.id] = const [UnknownPotionEffect.deadly, UnknownPotionEffect.sleep];
      final log = g.resolveRound(_all(g, correct: false), choices: {p.id: const UnknownChoice(take: '0')});
      expect(log.prelude[p.id]![0], 30 - unknownPotionDeadlySetback);
    });

    test('nu bea nimic → fără efect, dar oferta se consumă', () {
      final g = _game(players: 2);
      final p = g.players[0]..pos = 20;
      g.pendingPotions[p.id] = const [UnknownPotionEffect.deadly, UnknownPotionEffect.sleep];
      final log = g.resolveRound(_all(g, correct: false), choices: {p.id: UnknownChoice.none});
      expect(g.pendingPotions, isEmpty);
      final applied = log.choices.firstWhere((c) => c.playerId == p.id);
      expect(applied.potion, isNull);
      expect(p.skipNext, isFalse);
      expect(log.prelude[p.id]![0], 20, reason: 'fără poțiune, poziția nu s-a schimbat înainte de mutare');
    });

    test('karma: avans mic sau fără avans → efect blând (nu te teleportează)', () {
      final g = _game(players: 2);
      final p = g.players[0]..pos = 10;
      g.players[1].pos = 8; // avans mic, sub prag
      g.pendingPotions[p.id] = const [UnknownPotionEffect.karma, UnknownPotionEffect.sleep];
      final log = g.resolveRound(_all(g, correct: false), choices: {p.id: const UnknownChoice(take: '0')});
      expect(log.prelude[p.id]![0], 9);
    });

    test('karma: lider cu avans mare → teleportat lângă locul 2', () {
      final g = _game(players: 3);
      final p = g.players[0]..pos = 30;
      g.players[1].pos = 10;
      g.players[2].pos = 5;
      g.pendingPotions[p.id] = const [UnknownPotionEffect.karma, UnknownPotionEffect.sleep];
      final log = g.resolveRound(_all(g, correct: false), choices: {p.id: const UnknownChoice(take: '0')});
      expect(log.prelude[p.id]![0], 9); // lângă locul 2 (10 - 1)
    });

    test('karma: nu ești lider → efect blând, chiar cu diferență mare', () {
      final g = _game(players: 2);
      final p = g.players[0]..pos = 5;
      g.players[1].pos = 40; // celălalt e mult în față — p NU e lider
      g.pendingPotions[p.id] = const [UnknownPotionEffect.karma, UnknownPotionEffect.sleep];
      final log = g.resolveRound(_all(g, correct: false), choices: {p.id: const UnknownChoice(take: '0')});
      expect(log.prelude[p.id]![0], 4);
    });
  });
}
