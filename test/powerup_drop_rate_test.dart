import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/powerups.dart';

void main() {
  test('cat de des pica un power-up cand raspunzi corect', () {
    // Simulam 200 de runde castigate, cu 4 jucatori, pe pozitii diferite.
    for (final rank in [0, 1, 2, 3]) {
      var drops = 0;
      for (var r = 0; r < 200; r++) {
        if (grantsPowerUp(
          matchId: 'meci-test-$rank', roundIndex: r, playerId: 'jucator',
          wonRound: true, myRank: rank, totalPlayers: 4,
        )) drops++;
      }
      // ignore: avoid_print
      print('  locul ${rank + 1}/4 -> $drops din 200 runde castigate '
            '(${(drops / 2).toStringAsFixed(0)}%)');
      expect(drops, greaterThan(0), reason: 'trebuie sa pice uneori');
    }
  });

  test('cine NU castiga runda nu primeste niciodata', () {
    for (var r = 0; r < 50; r++) {
      expect(grantsPowerUp(
        matchId: 'm', roundIndex: r, playerId: 'p',
        wonRound: false, myRank: 3, totalPlayers: 4,
      ), isFalse);
    }
  });
}
