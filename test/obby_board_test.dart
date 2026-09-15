import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/widgets/obby_board.dart';

void main() {
  const racers = [
    ObbyRacerData(id: 'a', name: 'Ana', color: Colors.blue, progress: 2 / 7, isMe: true),
    ObbyRacerData(id: 'b', name: 'Bot', color: Colors.orange, progress: 3 / 7, isMe: false, outcome: ObbyRoundOutcome.fell),
  ];

  Widget host(ObbyPhase phase, {int? choice, ValueChanged<int>? onPick, List<ObbyRacerData> list = racers}) => MaterialApp(
        home: Scaffold(
          body: ObbyBoard(
            phase: phase,
            racers: list,
            myChoice: choice,
            revealDuration: const Duration(milliseconds: 500),
            onPlatformChosen: onPick ?? (_) {},
          ),
        ),
      );

  testWidgets('alegerea arată ↖ ▲ ↗ și trimite indexul apăsat', (tester) async {
    int? picked;
    await tester.pumpWidget(host(ObbyPhase.choosing, onPick: (i) => picked = i));
    expect(find.text('↖'), findsOneWidget);
    expect(find.text('▲'), findsOneWidget);
    expect(find.text('↗'), findsOneWidget);
    await tester.tap(find.text('↗'));
    expect(picked, 2);
  });

  testWidgets('după alegere, pătratele nu mai acceptă alt tap', (tester) async {
    int? picked;
    await tester.pumpWidget(host(ObbyPhase.choosing, choice: 1, onPick: (i) => picked = i));
    await tester.tap(find.text('↖'));
    expect(picked, isNull);
  });

  testWidgets('tabla comună și deznodământul se desenează fără excepții', (tester) async {
    await tester.pumpWidget(host(ObbyPhase.waiting));
    await tester.pumpWidget(host(ObbyPhase.revealed, list: const [
      ObbyRacerData(id: 'a', name: 'Ana', color: Colors.blue, progress: 3 / 7, isMe: true, outcome: ObbyRoundOutcome.jumped),
      ObbyRacerData(id: 'b', name: '', color: Colors.orange, progress: 3 / 7, isMe: false, outcome: ObbyRoundOutcome.fell),
    ]));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  });
}
