import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/tanks.dart';

/// Cât stă masa pe loc între două întrebări, la Quizz Tanks.
///
/// Problema raportată: când NIMENI n-a nimerit răspunsul, runda ajunge tot în
/// faza de reveal (vezi MultiplayerService.closeTanksAnswering, care sare
/// direct acolo cu `roundShots` gol), dar nu zboară niciun proiectil — și toți
/// jucătorii stăteau bugetul întreg uitându-se la o arenă în care nu se
/// întâmpla nimic.
///
/// Testul păzește raportul, nu valorile în sine: pauza fără foc trebuie să
/// rămână SCURTĂ și strict sub orice rundă în care s-a tras.
ResolvedTankShot _shot(String by, String at) => ResolvedTankShot(byId: by, atId: at, hit: true, damage: 10);

void main() {
  group('pauza dintre runde la Quizz Tanks', () {
    test('runda fara niciun foc nu mai tine masa pe loc degeaba', () {
      final empty = buildTankAttackPlan(shots: const []);
      final one = buildTankAttackPlan(shots: [_shot('a', 'b')]);
      expect(empty.revealSeconds, tanksEmptyRevealSeconds);
      expect(empty.revealSeconds, lessThan(one.revealSeconds));
    });

    test('pauza scurta ramane totusi cat sa se citeasca raspunsul corect', () {
      // Sub 2 secunde raspunsul corect ar clipi si ar disparea; peste 4 ar
      // redeveni exact timpul mort pentru care a fost facuta schimbarea.
      expect(tanksEmptyRevealSeconds, greaterThanOrEqualTo(2));
      expect(tanksEmptyRevealSeconds, lessThanOrEqualTo(4));
    });

    test('un 1 la 1 lasa camera de pe obuz sa se termine inainte de runda noua', () {
      final p = buildTankAttackPlan(shots: [_shot('a', 'b')]);
      final impact = p.timings[0]!.impactAt;
      expect(p.revealSeconds, greaterThan(impact + tanksCamAftermathSeconds));
    });
  });
}
