import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/flash_game.dart';
import 'package:guess_it/core/stable_hash.dart';
import 'package:guess_it/data/local_firestore.dart';
import 'package:guess_it/data/multiplayer_service.dart';
import 'package:guess_it/data/questions.dart';
import 'package:guess_it/models/multiplayer_models.dart';

/// Un meci de Fulgerul jucat cap-coadă prin MultiplayerService, pe baza din
/// memorie — grila calculată local trebuie să coincidă cu ce așteaptă
/// [MultiplayerService.closeFlashRound], altfel nimeni n-ar lua niciodată
/// punctaj real.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Fulgerul: meci întreg cu 3 jucători, punctaj corect, fără blocaje', () async {
    final pics = flashPicsFrom(await imagePool());
    final db = LocalFirestore();
    final a = MultiplayerService.local(db: db, playerId: 'ana');
    final b = MultiplayerService.local(db: db, playerId: 'bogdan');
    final c = MultiplayerService.local(db: db, playerId: 'cici');
    final all = [a, b, c];

    final room = await a.createRoom(displayName: 'Ana', gameMode: MatchGameMode.flash);
    await b.joinRoomById(matchId: room.id, displayName: 'Bogdan');
    await c.joinRoomById(matchId: room.id, displayName: 'Cici');
    await a.startMatch(room.id);

    final rnd = Random(3);
    var guard = 0;
    MatchInfo info = await a.watchMatch(room.id).first;
    while (info.status != MatchStatus.finished) {
      expect(guard++, lessThan(flashRounds + 2), reason: 'meciul trebuia să se termine la $flashRounds runde');
      final round = info.roundIndex;
      // Aceeași sămânță pe care o calculează ecranul (stableHash(matchId)) —
      // fiecare „telefon" din test o recalculează independent, ca în meciul
      // real, nu o citește dintr-un loc comun.
      final grid = const FlashGame().gridFor(pool: pics, seed: stableHash(room.id), round: round);
      for (final s in all) {
        final guess = flashBotGuess(grid, rnd);
        await s.submitRoundAnswer(matchId: room.id, roundIndex: round, answer: '$guess');
      }
      await a.closeFlashRound(matchId: room.id, roundIndex: round, correctIndex: grid.targetIndex, points: flashPointsFor(round));
      await b.closeFlashRound(matchId: room.id, roundIndex: round, correctIndex: grid.targetIndex, points: flashPointsFor(round)); // no-op
      info = await a.watchMatch(room.id).first;
      expect(info.roundPhase, RoundPhase.revealed);
      if (info.status == MatchStatus.finished) break;
      await a.advanceSyncRound(matchId: room.id, roundIndex: round);
      info = await a.watchMatch(room.id).first;
      expect(info.roundIndex, round + 1);
      expect(info.roundPhase, RoundPhase.answering);
    }

    final players = await a.watchPlayers(room.id).first;
    expect(players.every((p) => p.score >= 0), isTrue);
    expect(players.map((p) => p.score).reduce((x, y) => x + y), greaterThan(0), reason: 'nimeni n-a nimerit nicio grilă');
  });

  test('un răspuns invalid (index inexistent) nu strică runda — doar nu numără', () async {
    final pics = flashPicsFrom(await imagePool());
    final db = LocalFirestore();
    final a = MultiplayerService.local(db: db, playerId: 'ana');
    final room = await a.createRoom(displayName: 'Ana', gameMode: MatchGameMode.flash);
    await a.startMatch(room.id);
    final grid = const FlashGame().gridFor(pool: pics, seed: stableHash(room.id), round: 0);
    await a.submitRoundAnswer(matchId: room.id, roundIndex: 0, answer: '999');
    await a.closeFlashRound(matchId: room.id, roundIndex: 0, correctIndex: grid.targetIndex, points: 10);
    final players = await a.watchPlayers(room.id).first;
    expect(players.single.score, 0);
  });
}
