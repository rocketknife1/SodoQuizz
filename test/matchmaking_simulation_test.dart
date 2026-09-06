import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/elo.dart';
import 'package:guess_it/core/matchmaking.dart';

// Simulare cu jucatori generati, ca sa NU asteptam oameni reali ca sa vedem
// daca matchmaking-ul pe rating + ratingul Elo chiar functioneaza impreuna.
//
// Fiecare jucator are un `skill` ascuns, fix. Ratingul porneste de la 1000 si
// se misca DOAR prin `eloDelta` (codul real). Perechile se fac DOAR prin
// `pickOpponentsByRating` (codul real). Rezultatul unui meci vine din skill +
// zgomot. Dupa cateva zeci de runde verificam:
//   1. ratingul ajunge sa reflecte skill-ul (jucatorii buni urca)
//   2. matchmaking-ul pe rating chiar apropie adversarii (fata de la intamplare)
//   3. nimic nu explodeaza (ratingul ramane in limite, media sta la ~1000)

class _P {
  final int id;
  final double skill;
  int rating = eloStartRating;
  int matches = 0;
  _P(this.id, this.skill);
}

class _Result {
  final List<_P> players;
  final double avgMatchGap; // |rating diferenta| mediu in meciurile formate
  final double meanRating;
  final int minRating;
  final int maxRating;
  final double concordance; // fractia de perechi unde rating si skill sunt de acord
  _Result(this.players, this.avgMatchGap, this.meanRating, this.minRating,
      this.maxRating, this.concordance);
}

/// N(0,1) aproximativ — suma a 12 uniforme minus 6 (varianta = 1).
double _gauss(Random r) {
  var s = 0.0;
  for (var i = 0; i < 12; i++) {
    s += r.nextDouble();
  }
  return s - 6.0;
}

double _uniform(Random r, double a, double b) => a + r.nextDouble() * (b - a);

void _playMatch(List<_P> lobby, Random r) {
  // Performanta in meciul asta = skill + zgomot. Cine are performanta mai mare
  // termina mai sus. Zgomotul e destul cat un underdog sa castige uneori.
  final perf = <int, double>{
    for (final p in lobby) p.id: p.skill + _uniform(r, -140, 140),
  };
  lobby.sort((a, b) => perf[b.id]!.compareTo(perf[a.id]!)); // cel mai bun primul

  // Ratingurile se citesc TOATE inainte de update (ca in tranzactia reala).
  final snapshot = {for (final p in lobby) p.id: p.rating};
  for (var i = 0; i < lobby.length; i++) {
    final me = lobby[i];
    final oppRatings = <int>[];
    final beat = <bool>[];
    for (var j = 0; j < lobby.length; j++) {
      if (i == j) continue;
      oppRatings.add(snapshot[lobby[j].id]!);
      beat.add(i < j); // am terminat peste j daca sunt mai sus in ordine
    }
    final d = eloDelta(
        myRating: snapshot[me.id]!, opponentRatings: oppRatings, beat: beat);
    me.rating = max(0, me.rating + d); // podeaua din player_profile_service
    me.matches++;
  }
}

double _concordance(List<_P> ps, Random r) {
  var correct = 0, total = 0;
  for (var k = 0; k < 8000; k++) {
    final a = ps[r.nextInt(ps.length)];
    final b = ps[r.nextInt(ps.length)];
    if (a.id == b.id || (a.skill - b.skill).abs() < 1) continue;
    total++;
    if ((a.rating > b.rating) == (a.skill > b.skill)) correct++;
  }
  return correct / total;
}

_Result _run({
  required int seed,
  required int playerCount,
  required int rounds,
  required int lobbySize,
  required bool ratingMatchmaking,
}) {
  // Acelasi seed de skill indiferent de tipul de matchmaking, ca sa comparam
  // corect cele doua rulari.
  final skillRng = Random(seed);
  final players = [
    for (var i = 0; i < playerCount; i++)
      _P(i, (1000 + _gauss(skillRng) * 260).clamp(380, 1750)),
  ];

  final rng = Random(seed * 7 + (ratingMatchmaking ? 1 : 2));
  var gapSum = 0.0;
  var gapCount = 0;

  for (var round = 0; round < rounds; round++) {
    final queue = List.of(players)..shuffle(rng); // ordinea de intrare in coada
    while (queue.length >= lobbySize) {
      final head = queue.removeAt(0);
      final List<_P> chosen;
      if (ratingMatchmaking) {
        final picked = pickOpponentsByRating(
          myRating: head.rating,
          candidateRatings: [for (final p in queue) p.rating],
          count: lobbySize - 1,
        );
        chosen = [for (final i in picked) queue[i]];
        for (final i in picked.toList()..sort((a, b) => b - a)) {
          queue.removeAt(i);
        }
      } else {
        // control: primii din coada (deja amestecata) = pereche la intamplare
        chosen = [for (var k = 0; k < lobbySize - 1; k++) queue.removeAt(0)];
      }
      for (final c in chosen) {
        gapSum += (head.rating - c.rating).abs();
        gapCount++;
      }
      _playMatch([head, ...chosen], rng);
    }
  }

  final ratings = [for (final p in players) p.rating];
  return _Result(
    players,
    gapSum / gapCount,
    ratings.reduce((a, b) => a + b) / ratings.length,
    ratings.reduce(min),
    ratings.reduce(max),
    _concordance(players, Random(seed * 13)),
  );
}

void main() {
  group('simulare matchmaking + Elo cu jucatori generati', () {
    test('1v1: ratingul ajunge sa reflecte skill-ul, sistemul e stabil', () {
      final res = _run(
        seed: 42,
        playerCount: 240,
        rounds: 80,
        lobbySize: 2,
        ratingMatchmaking: true,
      );

      // Ratingul „stie" cine e mai bun in ~4 din 5 perechi.
      expect(res.concordance, greaterThan(0.78),
          reason: 'ratingul nu urmareste skill-ul: ${res.concordance}');

      // Media nu deriveaza (Elo e ~zero-sum pe pereche; doar podeaua la 0 ar
      // injecta puncte, si nu ajunge nimeni acolo cu skill-ul minim 380).
      expect(res.meanRating, closeTo(1000, 12),
          reason: 'media ratingului a derivat: ${res.meanRating}');

      // Nimic nu explodeaza.
      expect(res.maxRating, lessThan(1550));
      expect(res.minRating, greaterThanOrEqualTo(0));

      // Toata lumea a jucat de multe ori (coada nu infometeaza pe nimeni).
      final minMatches = res.players.map((p) => p.matches).reduce(min);
      expect(minMatches, greaterThan(50),
          reason: 'cineva a jucat prea putin: $minMatches');
    });

    test('matchmaking pe rating apropie adversarii fata de la intamplare', () {
      final byRating = _run(
        seed: 42,
        playerCount: 240,
        rounds: 80,
        lobbySize: 2,
        ratingMatchmaking: true,
      );
      final random = _run(
        seed: 42,
        playerCount: 240,
        rounds: 80,
        lobbySize: 2,
        ratingMatchmaking: false,
      );

      // Diferenta medie de rating in meciurile formate trebuie sa fie mult mai
      // mica cu matchmaking pe rating.
      expect(byRating.avgMatchGap, lessThan(random.avgMatchGap * 0.5),
          reason: 'gap rating: ${byRating.avgMatchGap.toStringAsFixed(1)} '
              'vs random ${random.avgMatchGap.toStringAsFixed(1)}');

      // Iar meciurile mai echilibrate nu strica invatarea ratingului.
      expect(byRating.concordance,
          greaterThanOrEqualTo(random.concordance - 0.05));
    });

    test('FFA lobby de 4: media impartita la nr. adversari tine ratingul stabil',
        () {
      final res = _run(
        seed: 7,
        playerCount: 200,
        rounds: 90,
        lobbySize: 4,
        ratingMatchmaking: true,
      );

      expect(res.concordance, greaterThan(0.75));
      expect(res.meanRating, closeTo(1000, 15));
      expect(res.maxRating, lessThan(1550));
      // Un meci FFA de 4 nu misca ratingul mai mult decat unul 1v1 (media / n).
      // Peste 90 de runde, nimeni nu ajunge la extreme absurde.
      expect(res.minRating, greaterThan(400));
    });

    test('rulare determinista: acelasi seed -> acelasi rezultat', () {
      _Result a = _run(
          seed: 99,
          playerCount: 120,
          rounds: 40,
          lobbySize: 2,
          ratingMatchmaking: true);
      _Result b = _run(
          seed: 99,
          playerCount: 120,
          rounds: 40,
          lobbySize: 2,
          ratingMatchmaking: true);
      expect([for (final p in a.players) p.rating],
          [for (final p in b.players) p.rating]);
    });

    test('raport lizibil (ruleaza mereu, ca sa se vada cifrele)', () {
      final res = _run(
        seed: 2026,
        playerCount: 240,
        rounds: 80,
        lobbySize: 2,
        ratingMatchmaking: true,
      );
      final bySkill = List.of(res.players)
        ..sort((a, b) => b.skill.compareTo(a.skill));
      final byRating = List.of(res.players)
        ..sort((a, b) => b.rating.compareTo(a.rating));

      final sb = StringBuffer()
        ..writeln('--- SIMULARE MATCHMAKING + ELO (240 jucatori, 80 runde) ---')
        ..writeln('concordanta rating<->skill : '
            '${(res.concordance * 100).toStringAsFixed(1)}%')
        ..writeln('media ratingului           : '
            '${res.meanRating.toStringAsFixed(1)} (start 1000)')
        ..writeln('rating min / max           : ${res.minRating} / ${res.maxRating}')
        ..writeln('gap mediu in meci          : '
            '${res.avgMatchGap.toStringAsFixed(1)} puncte')
        ..writeln('')
        ..writeln('TOP 8 dupa RATING (si locul lor real dupa SKILL):');
      for (var i = 0; i < 8; i++) {
        final p = byRating[i];
        final skillRank = bySkill.indexWhere((x) => x.id == p.id) + 1;
        sb.writeln('  #${i + 1}  rating ${p.rating}  '
            'skill ${p.skill.toStringAsFixed(0)}  (loc real dupa skill: #$skillRank)');
      }
      // ignore: avoid_print
      print(sb.toString());

      expect(res.concordance, greaterThan(0.78));
    });
  });
}
