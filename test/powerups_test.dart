import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/powerups.dart';

/// Power-up-urile și evenimentele NU se scriu în Firestore: fiecare client le
/// derivă local din matchId + rundă (+ jucător). Dacă determinismul se rupe,
/// doi jucători din același meci văd reguli diferite în aceeași rundă — un
/// bug imposibil de prins cu ochiul, dar care strică meciul complet. De-aia
/// aproape toate testele de aici verifică exact asta.
void main() {
  group('evenimente de runda', () {
    test('e determinist: acelasi meci + aceeasi runda dau acelasi eveniment', () {
      for (var round = 1; round <= 30; round++) {
        final a = roundEventFor(matchId: 'M1', roundIndex: round, gameModeId: 'quizzTanks');
        final b = roundEventFor(matchId: 'M1', roundIndex: round, gameModeId: 'quizzTanks');
        expect(a, b);
      }
    });

    test('prima runda nu are niciodata eveniment', () {
      for (final mode in ['quizzTanks', 'obby', 'electricChair', 'higherLower']) {
        expect(roundEventFor(matchId: 'M1', roundIndex: 0, gameModeId: mode), RoundEvent.none);
      }
    });

    test('un eveniment nu apare niciodata intr-un mod care nu-l suporta', () {
      for (final mode in ['quizzTanks', 'obby', 'electricChair', 'higherLower']) {
        for (var round = 1; round <= 200; round++) {
          final e = roundEventFor(matchId: 'M$round', roundIndex: round, gameModeId: mode);
          if (e == RoundEvent.none) continue;
          expect(roundEventModes[e], contains(mode),
              reason: '$e a aparut in modul $mode, unde nu are voie');
        }
      }
    });

    test('evenimentele sunt rare, nu regula', () {
      var withEvent = 0;
      const total = 400;
      for (var round = 1; round <= total; round++) {
        if (roundEventFor(matchId: 'M', roundIndex: round, gameModeId: 'quizzTanks') != RoundEvent.none) {
          withEvent++;
        }
      }
      // Banda e larga intentionat — testul pazeste ORDINUL de marime (nu
      // fiecare runda, nici o data la 20), nu valoarea exacta.
      final rate = withEvent / total;
      expect(rate, greaterThan(0.10));
      expect(rate, lessThan(0.50));
    });

    test('fiecare eveniment are titlu si descriere in ambele limbi', () {
      for (final e in RoundEvent.values) {
        if (e == RoundEvent.none) continue;
        expect(roundEventTitles[e], isNotNull, reason: '$e nu are titlu');
        expect(roundEventDescriptions[e], isNotNull, reason: '$e nu are descriere');
        expect(roundEventModes[e], isNotNull, reason: '$e nu e alocat niciunui mod');
        expect(roundEventModes[e], isNotEmpty, reason: '$e nu e alocat niciunui mod');
      }
    });
  });

  group('power-up-uri', () {
    test('e determinist: acelasi jucator, aceeasi runda, acelasi power-up', () {
      for (var round = 1; round <= 20; round++) {
        final a = powerUpFor(matchId: 'M1', roundIndex: round, playerId: 'p1', gameModeId: 'obby');
        final b = powerUpFor(matchId: 'M1', roundIndex: round, playerId: 'p1', gameModeId: 'obby');
        expect(a, b);
      }
    });

    test('nu se acorda niciodata unui power-up dintr-un mod strain', () {
      for (final mode in ['quizzTanks', 'obby', 'electricChair', 'higherLower']) {
        for (var round = 1; round <= 60; round++) {
          final p = powerUpFor(matchId: 'M', roundIndex: round, playerId: 'p$round', gameModeId: mode);
          if (p == PowerUp.none) continue;
          expect(powerUpModes[p], contains(mode), reason: '$p a aparut in modul $mode');
        }
      }
    });

    test('cine NU a castigat runda nu primeste nimic, oricat de in urma ar fi', () {
      for (var round = 1; round <= 50; round++) {
        expect(
          grantsPowerUp(
            matchId: 'M', roundIndex: round, playerId: 'p', wonRound: false,
            myRank: 9, totalPlayers: 10, // ultimul din zece
          ),
          isFalse,
        );
      }
    });

    test('puterile de lupta nu se mai pot folosi dupa ce runda s-a rezolvat', () {
      // Bug live 2026-08-25: scrierea pe roundPowerUps ajunge prea tarziu in
      // faza revealed si se pierde in tacere.
      for (final p in [PowerUp.megaRocket, PowerUp.doubleShot, PowerUp.shield,
          PowerUp.piercingShock, PowerUp.allyShield, PowerUp.sabotage, PowerUp.jetpack]) {
        expect(powerUpUsableInPhase(p, 'revealed'), isFalse, reason: '$p in revealed');
        expect(powerUpUsableInPhase(p, 'answering'), isTrue, reason: '$p in answering');
      }
    });

    test('trusa de reparatii se poate folosi in orice faza', () {
      // Singura putere ramasa fara fereastra: recupereaza viata printr-o
      // scriere care merge oricand.
      for (final phase in ['answering', 'targeting', 'choosing', 'chair', 'revealed']) {
        expect(powerUpUsableInPhase(PowerUp.repairKit, phase), isTrue,
            reason: 'repairKit in $phase');
      }
    });

    test('50/50 se poate folosi DOAR cat se raspunde (recenzie 2026-09-01)', () {
      // Testul asta spunea inainte ca 50/50 merge in orice faza — ceea ce era
      // chiar bug-ul: fara fereastra, trecea de garda si se consuma in gol,
      // arzand si dreptul la o putere pe runda aia.
      expect(powerUpUsableInPhase(PowerUp.fiftyFifty, 'answering'), isTrue);
      for (final phase in ['targeting', 'choosing', 'chair', 'revealed']) {
        expect(powerUpUsableInPhase(PowerUp.fiftyFifty, phase), isFalse,
            reason: 'fiftyFifty in $phase');
      }
    });

    test('Timp in Plus e doar la Clasic (recenzie 2026-09-01)', () {
      // In modurile sincrone runda se inchide cand expira cronometrul ORICARUI
      // client, iar secundele in plus erau locale — puterea nu facea nimic.
      expect(powerUpModes[PowerUp.extraTime], {'classic'});
    });

    test('fereastra de folosire e mereu un subset de faze reale', () {
      const realPhases = {'answering', 'targeting', 'choosing', 'revealed', 'chair'};
      for (final entry in powerUpUsablePhases.entries) {
        expect(entry.value, isNotEmpty, reason: '${entry.key} nu are nicio faza');
        expect(realPhases.containsAll(entry.value), isTrue,
            reason: '${entry.key} listeaza o faza inexistenta: ${entry.value}');
      }
    });

    test('fiecare power-up are titlu si descriere in ambele limbi', () {
      for (final p in PowerUp.values) {
        if (p == PowerUp.none) continue;
        expect(powerUpTitles[p], isNotNull, reason: '$p nu are titlu');
        expect(powerUpDescriptions[p], isNotNull, reason: '$p nu are descriere');
        expect(powerUpModes[p], isNotNull, reason: '$p nu e alocat niciunui mod');
        expect(powerUpModes[p], isNotEmpty, reason: '$p nu e alocat niciunui mod');
      }
    });
  });

  /// Handicapul cerut explicit de user: cine e in urma trebuie sa aiba mai
  /// multe SANSE sa intoarca meciul — dar nu puncte gratis.
  group('handicap (catch-up)', () {
    test('liderul nu primeste niciun avantaj', () {
      expect(catchUpBoostFor(myRank: 0, totalPlayers: 10), 1);
      expect(catchUpBoostFor(myRank: 0, totalPlayers: 2), 1);
    });

    test('ultimul primeste avantajul maxim', () {
      expect(catchUpBoostFor(myRank: 9, totalPlayers: 10), closeTo(maxCatchUpMultiplier, 0.0001));
      expect(catchUpBoostFor(myRank: 1, totalPlayers: 2), closeTo(maxCatchUpMultiplier, 0.0001));
    });

    test('creste monoton cu locul: cu cat esti mai in urma, cu atat mai mult', () {
      var previous = 0.0;
      for (var rank = 0; rank < 10; rank++) {
        final boost = catchUpBoostFor(myRank: rank, totalPlayers: 10);
        expect(boost, greaterThanOrEqualTo(previous));
        previous = boost;
      }
    });

    test('un singur jucator la masa nu are pe cine recupera', () {
      expect(catchUpBoostFor(myRank: 0, totalPlayers: 1), 1);
      expect(catchUpBoostFor(myRank: 0, totalPlayers: 0), 1);
    });

    test('handicapul chiar produce mai multe power-up-uri pentru ultimul', () {
      var leaderDrops = 0;
      var lastDrops = 0;
      const rounds = 300;
      for (var round = 1; round <= rounds; round++) {
        if (grantsPowerUp(
            matchId: 'M', roundIndex: round, playerId: 'p', wonRound: true,
            myRank: 0, totalPlayers: 10)) {
          leaderDrops++;
        }
        if (grantsPowerUp(
            matchId: 'M', roundIndex: round, playerId: 'p', wonRound: true,
            myRank: 9, totalPlayers: 10)) {
          lastDrops++;
        }
      }
      expect(lastDrops, greaterThan(leaderDrops),
          reason: 'ultimul din clasament trebuie sa primeasca power-up-uri mai des decat liderul');
    });
  });
}
