import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/rock_paper_scissors.dart';

void main() {
  group('rpsRoundScores', () {
    test('duel simplu: piatra bate foarfeca', () {
      final s = rpsRoundScores({'a': rpsRock, 'b': rpsScissors});
      expect(s, {'a': 1, 'b': 0});
    });

    test('duel: hartie bate piatra', () {
      final s = rpsRoundScores({'a': rpsPaper, 'b': rpsRock});
      expect(s, {'a': 1, 'b': 0});
    });

    test('duel: foarfeca bate hartia', () {
      final s = rpsRoundScores({'a': rpsScissors, 'b': rpsPaper});
      expect(s, {'a': 1, 'b': 0});
    });

    test('aceeasi alegere = 0 puncte pentru ambii (egalitate)', () {
      final s = rpsRoundScores({'a': rpsRock, 'b': rpsRock});
      expect(s, {'a': 0, 'b': 0});
    });

    test('trei jucatori: hartie bate doua pietre, foarfeca bate hartia', () {
      final s = rpsRoundScores({'a': rpsPaper, 'b': rpsRock, 'c': rpsRock});
      // a: bate b si c -> +2 ; b,c: bat nimic (a nu are piatra, unul pe altul e egal)
      expect(s, {'a': 2, 'b': 0, 'c': 0});
    });

    test('cinci jucatori mix', () {
      final s = rpsRoundScores({
        'a': rpsRock, 'b': rpsRock, 'c': rpsScissors, 'd': rpsScissors, 'e': rpsPaper,
      });
      // a: bate c,d (foarfece) -> +2 ; b: la fel -> +2
      // c: bate e (hartie) -> +1 ; d: bate e -> +1
      // e: bate a,b (pietre) -> +2
      expect(s, {'a': 2, 'b': 2, 'c': 1, 'd': 1, 'e': 2});
    });

    test('toti la fel = nimeni nu ia punct', () {
      final s = rpsRoundScores({'a': rpsScissors, 'b': rpsScissors, 'c': rpsScissors});
      expect(s, {'a': 0, 'b': 0, 'c': 0});
    });

    test('alegere lipsa (nu a apasat la timp) = nu bate pe nimeni si e batut de toti', () {
      final s = rpsRoundScores({'a': rpsRock, 'b': ''});
      // a bate b (b n-a ales) ; b nu bate nimic
      expect(s['a'], 1);
      expect(s['b'], 0);
    });

    test('doi fara alegere = egalitate intre ei', () {
      final s = rpsRoundScores({'a': '', 'b': ''});
      expect(s, {'a': 0, 'b': 0});
    });

    test('un singur jucator = 0 (n-are pe cine bate)', () {
      expect(rpsRoundScores({'a': rpsRock}), {'a': 0});
    });
  });

  group('rpsWinnerReached', () {
    test('nimeni sub prag', () {
      expect(rpsWinnerReached({'a': 8, 'b': 5}), isFalse);
    });
    test('unul atinge pragul', () {
      expect(rpsWinnerReached({'a': 10, 'b': 5}), isTrue);
    });
    test('peste prag', () {
      expect(rpsWinnerReached({'a': 12, 'b': 5}), isTrue);
    });
  });
}
