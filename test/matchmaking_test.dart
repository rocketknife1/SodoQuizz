import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/matchmaking.dart';

// Alegerea adversarilor la Meci Rapid. Testată aici, nu pe teren: cu doi
// jucători în coadă „cel mai apropiat ca rating" dă exact același rezultat ca
// „primul venit", iar ca să se vadă diferența ar trebui 3+ oameni reali cu
// ratinguri depărtate — bază de jucători pe care jocul n-o are încă.
void main() {
  group('pickOpponentsByRating', () {
    test('alege cel mai apropiat ca rating, nu pe primul venit', () {
      // Coada, în ordinea intrării: 1500, 995, 1600. Eu am 988.
      final picked = pickOpponentsByRating(
        myRating: 988,
        candidateRatings: [1500, 995, 1600],
        count: 1,
      );
      expect(picked, [1], reason: '995 e la 7 puncte de 988; 1500 e la 512');
    });

    test('la rating egal câștigă cine e mai demult în coadă', () {
      final picked = pickOpponentsByRating(
        myRating: 1000,
        candidateRatings: [1200, 1050, 1050, 900],
        count: 1,
      );
      // 900 e la 100, ambii 1050 sunt la 50 — se ia PRIMUL dintre ei.
      expect(picked, [1]);
    });

    test('ordonează toți candidații, nu doar primul', () {
      final picked = pickOpponentsByRating(
        myRating: 1000,
        candidateRatings: [1400, 1010, 1200, 990],
        count: 3,
      );
      // 1010 şi 990 sunt amândoi la 10 de 1000 — decide vechimea în coadă,
      // deci 1010 (intrat mai devreme) trece înaintea lui 990.
      expect(picked, [1, 3, 2]);
    });

    test('distanța se ia în valoare absolută, în ambele sensuri', () {
      final picked = pickOpponentsByRating(
        myRating: 1000,
        candidateRatings: [1300, 700],
        count: 1,
      );
      expect(picked, [0], reason: '1300 e la 300, 700 e la 300 — egalitate, primul intrat');
    });

    test('cere mai mulți decât are coada: îi dă pe toți, tot ordonați', () {
      final picked = pickOpponentsByRating(
        myRating: 1000,
        candidateRatings: [1500, 1010],
        count: 5,
      );
      expect(picked, [1, 0]);
    });

    test('coadă goală sau count zero: nimeni', () {
      expect(pickOpponentsByRating(myRating: 1000, candidateRatings: [], count: 1), isEmpty);
      expect(pickOpponentsByRating(myRating: 1000, candidateRatings: [1010], count: 0), isEmpty);
    });

    test('nu modifică lista primită', () {
      final ratings = [1500, 995, 1600];
      pickOpponentsByRating(myRating: 988, candidateRatings: ratings, count: 2);
      expect(ratings, [1500, 995, 1600]);
    });
  });
}
