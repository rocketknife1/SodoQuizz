import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/tanks.dart';

/// Geometria grilei de tancuri (core/tanks.dart, computeTankArenaLayout) —
/// pură, fără Flutter, testabilă direct pentru orice număr de jucători.
///
/// Motivul testului: plafonul de jucători a urcat de la 4 la 10, iar grila
/// nu mai e fixă 2×2 (vezi comentariul din tanks.dart). Genul de bug de aici
/// nu e o eroare de compilare — e o cutie cu lățime/înălțime negativă sau un
/// NaN care apare abia la un anumit număr de jucători sau un anumit ecran,
/// exact ca la test/tank_cinematics_test.dart.
void main() {
  group('computeTankArenaLayout', () {
    test('la 10 jucători (plafonul curent), grila are 2 coloane si 5 randuri', () {
      final layout = computeTankArenaLayout(viewportWidth: 400, viewportHeight: 700, playerCount: tanksPlayerCount);
      expect(layout.cols, 2);
      expect(layout.rows, 5);
      expect(tanksPlayerCount, 10);
    });

    test('cutiile raman cu dimensiuni pozitive, finite, pentru orice numar de jucatori intre 2 si 10', () {
      for (var players = 2; players <= 10; players++) {
        for (final size in [
          (w: 320.0, h: 480.0), // telefon mic
          (w: 400.0, h: 700.0), // telefon obisnuit
          (w: 480.0, h: 320.0), // spatiu foarte scund (orientare stranie/tastatura deschisa)
          (w: 800.0, h: 1200.0), // tableta
        ]) {
          final layout = computeTankArenaLayout(viewportWidth: size.w, viewportHeight: size.h, playerCount: players);
          expect(layout.cellWidth, greaterThan(0), reason: 'players=$players size=$size');
          expect(layout.cellHeight, greaterThan(0), reason: 'players=$players size=$size');
          expect(layout.cellWidth.isFinite, isTrue, reason: 'players=$players size=$size');
          expect(layout.cellHeight.isFinite, isTrue, reason: 'players=$players size=$size');
          expect(layout.contentHeight, greaterThanOrEqualTo(size.h - 0.001), reason: 'players=$players size=$size');
          expect(layout.top, greaterThanOrEqualTo(0), reason: 'players=$players size=$size');
          expect(layout.top.isFinite, isTrue, reason: 'players=$players size=$size');
        }
      }
    });

    test('grila deruleaza cand nu incape pe verticala, si NU deruleaza cand incape', () {
      // O masa plina (10) intr-un spatiu vertical foarte mic trebuie sa
      // deruleze, altfel jumatate din tancuri ar ramane taiate din ecran.
      final cramped = computeTankArenaLayout(viewportWidth: 360, viewportHeight: 200, playerCount: 10);
      expect(cramped.scrolls, isTrue);
      expect(cramped.contentHeight, greaterThan(200));
      expect(cramped.top, 0); // ancorata sus, nu centrata, cand deruleaza

      // O masa mica (2), pe un ecran normal, tot incape fara sa deruleze.
      final roomy = computeTankArenaLayout(viewportWidth: 400, viewportHeight: 700, playerCount: 2);
      expect(roomy.scrolls, isFalse);
      expect(roomy.contentHeight, 700);
    });

    test('continutul care deruleaza contine intreaga grila, nu doar o parte din ea', () {
      const gap = 10.0;
      final layout = computeTankArenaLayout(viewportWidth: 360, viewportHeight: 200, playerCount: 10, gap: gap);
      final actualGridHeight = layout.cellHeight * layout.rows + gap * (layout.rows - 1);
      expect(layout.contentHeight, closeTo(actualGridHeight, 0.001));
    });

    test('e pura: aceleasi intrari dau mereu aceeasi iesire', () {
      final a = computeTankArenaLayout(viewportWidth: 400, viewportHeight: 700, playerCount: 7);
      final b = computeTankArenaLayout(viewportWidth: 400, viewportHeight: 700, playerCount: 7);
      expect(a.cellWidth, b.cellWidth);
      expect(a.cellHeight, b.cellHeight);
      expect(a.rows, b.rows);
      expect(a.scrolls, b.scrolls);
      expect(a.top, b.top);
    });

    test('un singur jucator ramas (masa aproape goala) tot produce o grila valida', () {
      final layout = computeTankArenaLayout(viewportWidth: 400, viewportHeight: 700, playerCount: 1);
      expect(layout.rows, 1);
      expect(layout.cellWidth, greaterThan(0));
      expect(layout.cellHeight, greaterThan(0));
    });
  });
}
