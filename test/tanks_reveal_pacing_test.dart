import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/tanks.dart';

/// Cât stă masa pe loc între două întrebări, la Quizz Tanks.
///
/// Bugetul mare ([tanksRevealSeconds]) e dimensionat pentru coregrafia
/// completă de după rundă — încărcare, zbor, impact, bare care scad, epave
/// care explodează. Problema raportată: când NIMENI n-a nimerit răspunsul,
/// runda ajunge tot în faza de reveal (vezi
/// MultiplayerService.closeTanksAnswering, care sare direct acolo cu
/// `roundShots` gol), dar nu zboară niciun proiectil — și toți jucătorii
/// stăteau bugetul întreg uitându-se la o arenă în care nu se întâmpla nimic.
///
/// Testul păzește exact raportul ăsta, nu valorile în sine: dacă cineva umblă
/// la constante, pauza scurtă trebuie să rămână SCURTĂ și strict sub cea
/// lungă, altfel bug-ul se întoarce fără ca nimic să pice.
void main() {
  group('pauza dintre runde la Quizz Tanks', () {
    test('runda cu foc trasa primeste bugetul intreg de coregrafie', () {
      expect(tanksRevealSecondsFor(anyShots: true), tanksRevealSeconds);
    });

    test('runda fara niciun foc nu mai tine masa pe loc degeaba', () {
      expect(tanksRevealSecondsFor(anyShots: false), tanksEmptyRevealSeconds);
      expect(tanksEmptyRevealSeconds, lessThan(tanksRevealSeconds));
    });

    test('pauza scurta ramane totusi cat sa se citeasca raspunsul corect', () {
      // Sub 2 secunde raspunsul corect ar clipi si ar disparea; peste 4 ar
      // redeveni exact timpul mort pentru care a fost facuta schimbarea.
      expect(tanksEmptyRevealSeconds, greaterThanOrEqualTo(2));
      expect(tanksEmptyRevealSeconds, lessThanOrEqualTo(4));
    });

    test('toti clientii calculeaza aceeasi valoare din aceleasi date', () {
      // Fiecare client isi porneste singur cronometrul de avansare a rundei,
      // din `roundShots` citit din acelasi document. Functia trebuie sa fie
      // pura — doua apeluri cu aceeasi intrare nu au voie sa difere, altfel
      // un client ar cere runda urmatoare peste altul care inca animeaza.
      for (final anyShots in [true, false]) {
        expect(
          tanksRevealSecondsFor(anyShots: anyShots),
          tanksRevealSecondsFor(anyShots: anyShots),
        );
      }
    });
  });
}
