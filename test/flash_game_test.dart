import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/flash_game.dart';

List<FlashPic> _pool(int n) => [for (var i = 0; i < n; i++) FlashPic(id: 'p$i', answer: 'POZA$i', imagePath: 'x/$i.webp')];

void main() {
  const game = FlashGame();

  test('grila crește cu runda, apoi rămâne la 9', () {
    expect(flashGridSize(0), 4);
    expect(flashGridSize(2), 6);
    expect(flashGridSize(4), 9);
    expect(flashGridSize(20), 9);
  });

  test('timpul de afișare scade cu runda', () {
    for (var r = 1; r < 6; r++) {
      expect(flashRevealMsFor(r), lessThan(flashRevealMsFor(r - 1)));
    }
  });

  test('aceeași sămânță și rundă → aceeași grilă', () {
    final pool = _pool(20);
    final a = game.gridFor(pool: pool, seed: 7, round: 2);
    final b = game.gridFor(pool: pool, seed: 7, round: 2);
    expect(a.pics.map((p) => p.id), b.pics.map((p) => p.id));
    expect(a.targetIndex, b.targetIndex);
  });

  test('sămânță diferită → grilă diferită (aproape mereu)', () {
    final pool = _pool(20);
    final a = game.gridFor(pool: pool, seed: 1, round: 0);
    final b = game.gridFor(pool: pool, seed: 2, round: 0);
    expect(a.pics.map((p) => p.id).toList(), isNot(b.pics.map((p) => p.id).toList()));
  });

  test('nicio poză nu se repetă în aceeași grilă', () {
    final pool = _pool(30);
    for (var round = 0; round < 6; round++) {
      final r = game.gridFor(pool: pool, seed: 42, round: round);
      expect(r.pics.map((p) => p.id).toSet().length, r.pics.length);
    }
  });

  test('un pool mai mic decât grila nu explodează', () {
    final pool = _pool(3);
    final r = game.gridFor(pool: pool, seed: 1, round: 4); // grilă cerută = 9
    expect(r.pics.length, 3);
    expect(r.targetIndex, lessThan(3));
  });

  test('acuratețea botului scade cu grila mai mare', () {
    expect(flashBotAccuracy(4), greaterThan(flashBotAccuracy(6)));
    expect(flashBotAccuracy(6), greaterThan(flashBotAccuracy(9)));
  });

  test('botul ghicește corect cu rata așteptată, pe termen lung', () {
    final pool = _pool(9);
    final round = game.gridFor(pool: pool, seed: 3, round: 0);
    final rnd = Random(9);
    var correct = 0;
    const trials = 2000;
    for (var i = 0; i < trials; i++) {
      if (flashBotGuess(round, rnd) == round.targetIndex) correct++;
    }
    expect(correct / trials, closeTo(flashBotAccuracy(round.pics.length), 0.05));
  });
}
