import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/game_helpers.dart';

void main() {
  group('game helpers', () {
    test('hint penalty stays proportional and within cap', () {
      expect(calculateHintPenalty(200, 200), 40);
      expect(calculateHintPenalty(100, 200), 20);
      expect(calculateHintPenalty(50, 200), 10);
      expect(calculateHintPenalty(1000, 200), 80);
    });

    test('earned points use the same penalty calculation as the score', () {
      expect(calculateAwardedPoints(200, 1, 200), 160);
      expect(calculateAwardedPoints(200, 2, 200), 120);
      expect(calculateAwardedPoints(120, 1, 120), 96);
    });
  });
}
