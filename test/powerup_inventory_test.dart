import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/powerups.dart';
import 'package:guess_it/widgets/powerup_inventory.dart';

/// Inventarul de puteri din Quizz Tanks. Riscul real al acestei componente nu
/// e logica, ci ASEZAREA: sta intr-o banda ingusta sub tancuri, iar daca
/// patratelele nu incap, Flutter arunca overflow si ecranul de joc se strica
/// exact in mijlocul unui meci.
void main() {
  Future<void> pump(WidgetTester tester, List<PowerUp> p, {bool used = false}) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox()), // tine loc de arena
            PowerUpInventory(powerUps: p, usedThisRound: used, onUse: (_) {}),
            const SizedBox(height: 200), // tine loc de panoul cu intrebarea
          ],
        ),
      ),
    ));
  }

  testWidgets('fara puteri nu ocupa niciun spatiu', (tester) async {
    await pump(tester, const []);
    expect(find.byType(PowerUpInventory), findsOneWidget);
    expect(tester.getSize(find.byType(PowerUpInventory)).height, 0);
  });

  testWidgets('o putere: iconita si nume, fara overflow', (tester) async {
    await pump(tester, const [PowerUp.megaRocket]);
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.rocket_launch_rounded), findsOneWidget);
  });

  testWidgets('OPT puteri incap fara overflow (deruleaza orizontal)', (tester) async {
    // "cate vrei" — userul a cerut explicit sa se poata aduna oricate.
    await pump(tester, const [
      PowerUp.megaRocket, PowerUp.doubleShot, PowerUp.shield, PowerUp.allyShield,
      PowerUp.reflect, PowerUp.fiftyFifty, PowerUp.peek, PowerUp.repairKit,
    ]);
    expect(tester.takeException(), isNull,
        reason: 'un overflow aici ar strica ecranul in mijlocul meciului');
  });

  testWidgets('apasarea trimite exact puterea apasata', (tester) async {
    PowerUp? apasat;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PowerUpInventory(
          powerUps: const [PowerUp.megaRocket, PowerUp.shield],
          usedThisRound: false,
          onUse: (p) => apasat = p,
        ),
      ),
    ));
    await tester.tap(find.byIcon(Icons.shield_rounded));
    expect(apasat, PowerUp.shield);
  });

  testWidgets('dupa ce ai folosit una in runda asta, nu se mai poate apasa', (tester) async {
    PowerUp? apasat;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PowerUpInventory(
          powerUps: const [PowerUp.megaRocket],
          usedThisRound: true,
          onUse: (p) => apasat = p,
        ),
      ),
    ));
    await tester.tap(find.byIcon(Icons.rocket_launch_rounded));
    expect(apasat, isNull, reason: 'regula e UNA pe runda');
  });

  test('numele scurt nu contine emoji-ul din titlu', () {
    final n = powerUpShortName(PowerUp.megaRocket);
    expect(n, isNotEmpty);
    expect(n.contains('🚀'), isFalse, reason: 'patratelul are deja iconita lui');
  });
}
