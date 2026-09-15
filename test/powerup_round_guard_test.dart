import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/powerups.dart';
import 'package:guess_it/data/local_firestore.dart';
import 'package:guess_it/data/multiplayer_service.dart';
import 'package:guess_it/models/multiplayer_models.dart';
import 'package:guess_it/widgets/powerup_inventory.dart';

/// Bug raportat live (2026-09-15): scut folosit la Scaunul Electric, răspuns
/// greșit, viață pierdută oricum — scrierea puterii ajungea după ce runda se
/// rezolvase. Acum scrierea verifică runda+faza în tranzacție și întoarce
/// `false` când e prea târziu, ca ecranul să păstreze puterea.
void main() {
  Future<(MultiplayerService, String, LocalFirestore)> chairMatch() async {
    final db = LocalFirestore();
    final me = MultiplayerService.local(db: db, playerId: 'eu');
    final room = await me.createRoom(displayName: 'Eu', gameMode: MatchGameMode.electricChair);
    for (var i = 1; i <= 2; i++) {
      await MultiplayerService.local(db: db, playerId: 'bot_$i').joinRoomById(matchId: room.id, displayName: 'Bot $i');
    }
    await me.startMatch(room.id);
    return (me, room.id, db);
  }

  test('scutul se aplică cât runda e activă', () async {
    final (me, id, db) = await chairMatch();
    final ok = await me.submitElectricChairPowerUp(matchId: id, roundIndex: 0, powerUp: PowerUp.shield);
    expect(ok, isTrue);
    final data = (await db.collection('matches').doc(id).get()).data()!;
    expect((data['roundPowerUps'] as Map)['eu'], PowerUp.shield.name);
  });

  test('scutul trimis după ce runda a trecut NU se scrie și întoarce false', () async {
    final (me, id, db) = await chairMatch();
    await db.collection('matches').doc(id).update({'roundIndex': 1});
    final ok = await me.submitElectricChairPowerUp(matchId: id, roundIndex: 0, powerUp: PowerUp.shield);
    expect(ok, isFalse);
    final data = (await db.collection('matches').doc(id).get()).data()!;
    expect((data['roundPowerUps'] as Map? ?? const {})['eu'], isNull);
  });

  test('scutul trimis în faza revealed (runda rezolvată) întoarce false', () async {
    final (me, id, db) = await chairMatch();
    await db.collection('matches').doc(id).update({'roundPhase': RoundPhase.revealed.name});
    final ok = await me.submitElectricChairPowerUp(matchId: id, roundIndex: 0, powerUp: PowerUp.shield);
    expect(ok, isFalse);
  });

  testWidgets('bara de puteri: indiciu + X pe puterea blocată acum', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PowerUpBar(
          powerUps: const [PowerUp.shield, PowerUp.fiftyFifty],
          usedThisRound: false,
          usableNow: (p) => p == PowerUp.shield,
          onUse: (_) {},
        ),
      ),
    ));
    expect(find.textContaining('Poți folosi puterile'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget); // doar 50/50 e blocată
  });

  testWidgets('toate blocate: indiciul spune runda următoare', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PowerUpBar(
          powerUps: const [PowerUp.fiftyFifty],
          usedThisRound: false,
          usableNow: (_) => false,
          onUse: (_) {},
        ),
      ),
    ));
    expect(find.textContaining('runda următoare'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
  });

  testWidgets('după folosire: fără indiciu de folosire, fără X', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PowerUpBar(
          powerUps: const [PowerUp.shield],
          usedThisRound: true,
          usableNow: (_) => false,
          onUse: (_) {},
        ),
      ),
    ));
    expect(find.textContaining('Poți folosi puterile'), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });
}
