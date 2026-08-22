import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/widgets/obby_game.dart';

/// Verifică că scena Flame chiar se montează și randează, în ambele faze —
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
}
