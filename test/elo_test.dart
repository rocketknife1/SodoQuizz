import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/elo.dart';

void main() {
  test('fara adversari sau lungimi diferite -> 0', () {
    expect(eloDelta(myRating: 1000, opponentRatings: [], beat: []), 0);
    expect(eloDelta(myRating: 1000, opponentRatings: [1000], beat: []), 0);
  });

  test('bati un egal -> creste; pierzi cu un egal -> scade, simetric', () {
    final up = eloDelta(myRating: 1000, opponentRatings: [1000], beat: [true]);
    final down = eloDelta(myRating: 1000, opponentRatings: [1000], beat: [false]);
    expect(up, greaterThan(0));
    expect(down, lessThan(0));
    expect(up, -down); // simetric la rating egal
  });

  test('bati pe cineva mult mai bun -> castig mai mare decat vs egal', () {
    final vsEqual = eloDelta(myRating: 1000, opponentRatings: [1000], beat: [true]);
    final vsBetter = eloDelta(myRating: 1000, opponentRatings: [1400], beat: [true]);
    expect(vsBetter, greaterThan(vsEqual));
  });

  test('pierzi cu cineva mult mai slab -> pierdere mai mare decat vs egal', () {
    final vsEqual = eloDelta(myRating: 1000, opponentRatings: [1000], beat: [false]);
    final vsWorse = eloDelta(myRating: 1000, opponentRatings: [600], beat: [false]);
    expect(vsWorse, lessThan(vsEqual));
  });

  test('un meci nu poate misca ratingul cu mai mult de K', () {
    final huge = eloDelta(myRating: 100, opponentRatings: [3000, 3000, 3000], beat: [true, true, true]);
    expect(huge, lessThanOrEqualTo(24));
    final crash = eloDelta(myRating: 3000, opponentRatings: [100, 100, 100], beat: [false, false, false]);
    expect(crash, greaterThanOrEqualTo(-24));
  });

  test('lobby de 5: locul din mijloc (bati 2, pierzi cu 2) ~ neutru', () {
    final d = eloDelta(
      myRating: 1000,
      opponentRatings: [1000, 1000, 1000, 1000],
      beat: [true, true, false, false],
    );
    expect(d.abs(), lessThanOrEqualTo(2));
  });
}
