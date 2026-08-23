import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/obby.dart';

/// Logica pură din spatele plăcilor de la Obby. Contează să fie testată aici
/// fiindcă e SINGURA parte din mecanică pe care nimeni n-o scrie nicăieri:
/// care placă e falsă nu ajunge niciodată în Firestore, fiecare telefon o
/// recalculează singur. Dacă doi clienți ar ajunge la răspunsuri diferite,
/// unul ar anima o cădere iar celălalt o săritură reușită, pentru același
/// jucător — exact clasa de bug pe care core/stable_hash.dart a fost scris
/// s-o prevină.
void main() {
  group('obbyFakePlatformIndex', () {
    test('e determinist: aceleași date dau mereu același rezultat', () {
      for (var round = 0; round < obbyObstacleCount; round++) {
        final first = obbyFakePlatformIndex(matchId: 'meci123', roundIndex: round, playerId: 'jucatorA');
        final second = obbyFakePlatformIndex(matchId: 'meci123', roundIndex: round, playerId: 'jucatorA');
        expect(second, first);
      }
    });

    test('rămâne mereu un index valid de placă', () {
      for (var round = 0; round < 50; round++) {
        for (final player in ['a', 'jucator-cu-nume-lung', 'ZZZ', '0']) {
          final index = obbyFakePlatformIndex(matchId: 'm$round', roundIndex: round, playerId: player);
          expect(index, greaterThanOrEqualTo(0));
          expect(index, lessThan(obbyPlatformChoiceCount));
        }
      }
    });

    test('diferă între jucători — fiecare își riscă propriile plăci', () {
      // Nu cerem ca TOȚI să difere într-o rundă dată (ar fi imposibil cu 3
      // plăci și 6 jucători), ci ca layout-ul să nu fie același pentru toată
      // lumea tot timpul — altfel ar fi de fapt un layout comun pe masă.
      var roundsWhereTwoPlayersDiffer = 0;
      for (var round = 0; round < 20; round++) {
        final a = obbyFakePlatformIndex(matchId: 'meci', roundIndex: round, playerId: 'jucatorA');
        final b = obbyFakePlatformIndex(matchId: 'meci', roundIndex: round, playerId: 'jucatorB');
        if (a != b) roundsWhereTwoPlayersDiffer++;
      }
      expect(roundsWhereTwoPlayersDiffer, greaterThan(0));
    });

    test('diferă între runde — nu poți învăța placa bună o dată și gata', () {
      final perRound = {
        for (var round = 0; round < 20; round++)
          round: obbyFakePlatformIndex(matchId: 'meci', roundIndex: round, playerId: 'jucator'),
      };
      expect(perRound.values.toSet().length, greaterThan(1));
    });

    test('folosește toate plăcile, rezonabil de echilibrat', () {
      // Cu 1 placă falsă din 3, fiecare ar trebui să iasă în ~1/3 din cazuri.
      // Prag larg intenționat (>10%): testăm că nicio placă nu e practic
      // niciodată falsă, nu că hash-ul e un generator statistic perfect.
      final counts = <int, int>{};
      const samples = 900;
      for (var i = 0; i < samples; i++) {
        final index = obbyFakePlatformIndex(matchId: 'meci', roundIndex: i, playerId: 'jucator$i');
        counts[index] = (counts[index] ?? 0) + 1;
      }
      expect(counts.length, obbyPlatformChoiceCount);
      for (final count in counts.values) {
        expect(count, greaterThan(samples * 0.10));
      }
    });
  });

  group('obbyChoiceIsSafe', () {
    test('orice placă în afară de cea falsă te ține', () {
      for (var fake = 0; fake < obbyPlatformChoiceCount; fake++) {
        for (var chosen = 0; chosen < obbyPlatformChoiceCount; chosen++) {
          expect(
            obbyChoiceIsSafe(chosenIndex: chosen, fakeIndex: fake),
            chosen != fake,
          );
        }
      }
    });

    test('cine n-a ales deloc cade — la fel ca cine răspunde greșit', () {
      expect(obbyChoiceIsSafe(chosenIndex: null, fakeIndex: 0), isFalse);
    });

    test('un index în afara intervalului nu poate păcăli verificarea', () {
      // fakeIndex e mereu 0..2, deci un -1 sau 99 ar trece de un simplu
      // „chosen != fake" și ar da progres pe gratis.
      expect(obbyChoiceIsSafe(chosenIndex: -1, fakeIndex: 0), isFalse);
      expect(obbyChoiceIsSafe(chosenIndex: obbyPlatformChoiceCount, fakeIndex: 0), isFalse);
      expect(obbyChoiceIsSafe(chosenIndex: 999, fakeIndex: 1), isFalse);
    });
  });

  group('obbyMatchIsOver', () {
    test('se termină când cineva trece de ultimul obstacol', () {
      expect(
        obbyMatchIsOver(roundIndex: 0, obstaclesClearedPerPlayer: [obbyObstacleCount, 1]),
        isTrue,
      );
    });

    test('se termină la epuizarea rundelor, chiar dacă n-a terminat nimeni', () {
      expect(
        obbyMatchIsOver(roundIndex: obbyObstacleCount - 1, obstaclesClearedPerPlayer: [0, 1]),
        isTrue,
      );
    });

    test('continuă cât timp mai sunt runde și n-a ajuns nimeni la final', () {
      expect(
        obbyMatchIsOver(roundIndex: 0, obstaclesClearedPerPlayer: [0, 1]),
        isFalse,
      );
      expect(
        obbyMatchIsOver(roundIndex: obbyObstacleCount - 2, obstaclesClearedPerPlayer: [1, 2]),
        isFalse,
      );
    });

    test('o masă goală nu blochează meciul la nesfârșit', () {
      expect(
        obbyMatchIsOver(roundIndex: obbyObstacleCount - 1, obstaclesClearedPerPlayer: const []),
        isTrue,
      );
    });
  });

  group('constantele modului', () {
    test('sunt mai multe plăci decât plăci false', () {
      expect(obbyFakePlatformCount, lessThan(obbyPlatformChoiceCount));
      expect(obbyFakePlatformCount, greaterThan(0));
    });

    test('un meci întreg rămâne sub trei minute', () {
      // răspuns + alegere + deznodământ, per rundă
      final perRound = obbyRoundSeconds + obbyChoiceSeconds + obbyRevealSeconds;
      expect(perRound * obbyObstacleCount, lessThan(180));
    });
  });

  group('obbyBonusChoices', () {
    const choices = ['Amperul', 'Ohmul', 'Wattul', 'Voltul'];

    test('lasa exact doua variante, una fiind cea corecta', () {
      final kept = obbyBonusChoices(
        choices: choices,
        correctAnswer: 'Amperul',
        matchId: 'm1',
        roundIndex: 2,
        playerId: 'p1',
      );
      expect(kept, hasLength(2));
      expect(kept, contains('Amperul'));
    });

    test('e determinist: acelasi jucator vede mereu aceleasi doua variante', () {
      List<String> run() => obbyBonusChoices(
            choices: choices,
            correctAnswer: 'Amperul',
            matchId: 'm1',
            roundIndex: 2,
            playerId: 'p1',
          );
      expect(run(), equals(run()));
    });

    test('doi jucatori nu primesc neaparat aceeasi varianta gresita', () {
      // Ancorarea pe playerId e ce impiedica doi jucatori cu bonus sa afle
      // raspunsul comparand ecranele. Cu 3 variante gresite si multi jucatori
      // incercati, macar doi trebuie sa difere.
      final seen = <String>{};
      for (var i = 0; i < 12; i++) {
        final kept = obbyBonusChoices(
          choices: choices,
          correctAnswer: 'Amperul',
          matchId: 'm1',
          roundIndex: 2,
          playerId: 'p$i',
        );
        seen.add(kept.firstWhere((c) => c != 'Amperul'));
      }
      expect(seen.length, greaterThan(1));
    });

    test('raspunsul corect nu sta mereu pe acelasi loc', () {
      final positions = <int>{};
      for (var i = 0; i < 12; i++) {
        final kept = obbyBonusChoices(
          choices: choices,
          correctAnswer: 'Amperul',
          matchId: 'm$i',
          roundIndex: 0,
          playerId: 'p1',
        );
        positions.add(kept.indexOf('Amperul'));
      }
      expect(positions, containsAll(<int>[0, 1]));
    });

    test('daca raspunsul corect lipseste din lista, nu se elimina nimic', () {
      final kept = obbyBonusChoices(
        choices: choices,
        correctAnswer: 'Newtonul',
        matchId: 'm1',
        roundIndex: 0,
        playerId: 'p1',
      );
      expect(kept, equals(choices));
    });
  });

  group('obbyIsDoubleRound', () {
    test('niciodata pe prima runda, indiferent de meci', () {
      for (var i = 0; i < 20; i++) {
        expect(obbyIsDoubleRound(matchId: 'm$i', roundIndex: 0), isFalse);
      }
    });

    test('niciodata pe ultimele doua runde (penultima + finala)', () {
      for (var i = 0; i < 20; i++) {
        expect(obbyIsDoubleRound(matchId: 'm$i', roundIndex: obbyObstacleCount - 2), isFalse);
        expect(obbyIsDoubleRound(matchId: 'm$i', roundIndex: obbyObstacleCount - 1), isFalse);
      }
    });

    test('e determinist: acelasi meci si runda dau mereu acelasi rezultat', () {
      for (var round = 1; round < obbyObstacleCount - 2; round++) {
        final first = obbyIsDoubleRound(matchId: 'meciX', roundIndex: round);
        final second = obbyIsDoubleRound(matchId: 'meciX', roundIndex: round);
        expect(second, first);
      }
    });

    test('se intampla la unele meciuri, nu la toate — nu e nici mereu true, nici mereu false', () {
      final results = <bool>{};
      for (var i = 0; i < 30; i++) {
        results.add(obbyIsDoubleRound(matchId: 'meci$i', roundIndex: 2));
      }
      expect(results, containsAll(<bool>[true, false]));
    });
  });

  group('obbyIsComebackRound', () {
    test('e adevarat DOAR la penultima runda', () {
      for (var round = 0; round < obbyObstacleCount; round++) {
        expect(obbyIsComebackRound(roundIndex: round), round == obbyObstacleCount - 2);
      }
    });
  });

  group('obbyLastPlaceIds', () {
    test('intoarce jucatorul cu cel mai putin progres', () {
      final ids = obbyLastPlaceIds([('a', 3), ('b', 1), ('c', 5)]);
      expect(ids, ['b']);
    });

    test('intoarce toti jucatorii legati la egalitate pe ultimul loc', () {
      final ids = obbyLastPlaceIds([('a', 2), ('b', 2), ('c', 5)]);
      expect(ids.toSet(), {'a', 'b'});
    });

    test('ignora jucatorii deja terminati (obstaclesCleared >= obbyObstacleCount)', () {
      final ids = obbyLastPlaceIds([('a', obbyObstacleCount), ('b', 3)]);
      expect(ids, ['b']);
    });

    test('lista goala daca toata lumea a terminat sau nimeni nu e activ', () {
      expect(obbyLastPlaceIds([('a', obbyObstacleCount)]), isEmpty);
      expect(obbyLastPlaceIds(const []), isEmpty);
    });
  });
}
