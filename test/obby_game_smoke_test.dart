import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/widgets/obby_game.dart';

/// Verifică că scena Flame chiar se montează și randează, în toate fazele —
/// exact partea pe care testele pure nu o ating și care a picat tăcut în
/// browser (un ecran gri + „Another exception was thrown", fără mesaj).
void main() {
  const racers = [
    ObbyRacerData(id: 'a', name: 'A', color: Colors.blue, progress: 0, isMe: true),
    ObbyRacerData(id: 'b', name: 'B', color: Colors.orange, progress: 0.3, isMe: false),
  ];

  testWidgets('scena de alegere se monteaza fara exceptii', (tester) async {
    final game = ObbyGame(onPlatformChosen: (_) {});
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    game.applyRoundState(phase: ObbyPhase.choosing, racers: racers, myId: 'a');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  testWidgets('scena de reveal se monteaza fara exceptii', (tester) async {
    final game = ObbyGame(onPlatformChosen: (_) {});
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    game.applyRoundState(phase: ObbyPhase.revealed, racers: racers, myId: 'a', revealT: 0.5);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  /// Căderea are propriul cod de randare (rotire, estompare, umbră scoasă,
  /// poziție scrisă direct în loc de lerp), deci nu e acoperită de testul de
  /// mai sus — acolo toată lumea are outcome-ul implicit [none].
  testWidgets('caderea prin placa falsa se randeaza fara exceptii', (tester) async {
    final game = ObbyGame(onPlatformChosen: (_) {});
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    const fallers = [
      ObbyRacerData(id: 'a', name: 'A', color: Colors.blue, progress: 0.14, isMe: true, outcome: ObbyRoundOutcome.fell),
      ObbyRacerData(id: 'b', name: 'B', color: Colors.orange, progress: 0.43, isMe: false, outcome: ObbyRoundOutcome.jumped),
    ];

    // Toată animația, pas cu pas: începutul (încă pe placă), mijlocul
    // căderii și sfârșitul ei, unde personajul e aproape complet estompat.
    for (final t in [0.0, 0.2, 0.5, 0.8, 1.0]) {
      game.applyRoundState(phase: ObbyPhase.revealed, racers: fallers, myId: 'a', revealT: t);
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
  });

  /// Un meci întreg trece de mai multe ori prin ciclul răspuns → alegere →
  /// deznodământ, iar scena e demontată și remontată la fiecare pas. Testul
  /// păzește exact drumul ăsta, plus faptul că un snapshot nou cu ACELEAȘI
  /// date (Firestore trimite mai multe pe rundă) nu strică nimic.
  testWidgets('doua runde la rand, cu demontari intre ele', (tester) async {
    final game = ObbyGame(onPlatformChosen: (_) {});
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    const afterRound1 = [
      ObbyRacerData(id: 'a', name: 'A', color: Colors.blue, progress: 1 / 7, isMe: true, outcome: ObbyRoundOutcome.jumped),
      ObbyRacerData(id: 'b', name: 'B', color: Colors.orange, progress: 0.3, isMe: false),
    ];
    const afterRound2 = [
      ObbyRacerData(id: 'a', name: 'A', color: Colors.blue, progress: 2 / 7, isMe: true, outcome: ObbyRoundOutcome.jumped),
      ObbyRacerData(id: 'b', name: 'B', color: Colors.orange, progress: 0.3, isMe: false),
    ];

    Future<void> playRound(List<ObbyRacerData> result) async {
      game.applyRoundState(phase: ObbyPhase.idle, racers: racers, myId: 'a');
      await tester.pump(const Duration(milliseconds: 100));
      game.applyRoundState(phase: ObbyPhase.choosing, racers: racers, myId: 'a', myChoice: 1);
      await tester.pump(const Duration(milliseconds: 100));
      for (final t in [0.0, 0.4, 0.4, 1.0]) {
        game.applyRoundState(phase: ObbyPhase.revealed, racers: result, myId: 'a', revealT: t);
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await playRound(afterRound1);
    await playRound(afterRound2);

    expect(tester.takeException(), isNull);
  });

  /// [ObbyPhase.waiting] — camera pe mine cât aștept rezultatul, cerută
  /// explicit de user, ca răspunsul propriu să nu mai fie singurul moment
  /// din meci fără cameră 3rd-person. Reutilizează scena de reveal
  /// (vezi ObbyGame._rebuildScene), dar cu toți alergătorii pe
  /// [ObbyRoundOutcome.none] — nimeni n-are voie să sară/cadă aici.
  testWidgets('scena de asteptare (camera pe mine) se monteaza fara exceptii', (tester) async {
    final game = ObbyGame(onPlatformChosen: (_) {});
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    game.applyRoundState(phase: ObbyPhase.waiting, racers: racers, myId: 'a');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  /// Drumul real al unei runde, din perspectiva userului: n-am răspuns încă
  /// (idle, ecranul de întrebare) → am răspuns, camera trece pe mine
  /// (waiting) → runda se rezolvă (revealed). Fiecare tranziție demontează
  /// și remontează scena Flame (vezi rosterChanged/phase!=this.phase din
  /// ObbyGame.applyRoundState) — testul păzește exact înlănțuirea asta.
  testWidgets('idle -> waiting -> revealed nu arunca nimic la tranzitii', (tester) async {
    final game = ObbyGame(onPlatformChosen: (_) {});
    await tester.pumpWidget(MaterialApp(home: GameWidget(game: game)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    game.applyRoundState(phase: ObbyPhase.idle, racers: racers, myId: 'a');
    await tester.pump(const Duration(milliseconds: 100));

    game.applyRoundState(phase: ObbyPhase.waiting, racers: racers, myId: 'a');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    const result = [
      ObbyRacerData(id: 'a', name: 'A', color: Colors.blue, progress: 1 / 7, isMe: true, outcome: ObbyRoundOutcome.jumped),
      ObbyRacerData(id: 'b', name: 'B', color: Colors.orange, progress: 0.3, isMe: false, outcome: ObbyRoundOutcome.fell),
    ];
    for (final t in [0.0, 0.3, 0.7, 1.0]) {
      game.applyRoundState(phase: ObbyPhase.revealed, racers: result, myId: 'a', revealT: t);
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
  });
}
