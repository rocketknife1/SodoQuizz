import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/unknown_game.dart';
import 'package:guess_it/data/local_firestore.dart';
import 'package:guess_it/data/multiplayer_service.dart';
import 'package:guess_it/models/multiplayer_models.dart';

/// Un meci de Unknown jucat cap-coadă prin MultiplayerService, pe baza din
/// memorie — exact drumul unui meci real: răspunsuri cu timp, închiderea
/// rundei (de două ori, ca doi clienți care se calcă), alegeri la cufăr și
/// magazin trimise cât se animă, apoi trecerea la runda următoare.
void main() {
  test('Unknown: meci întreg cu 3 jucători, până la final, fără blocaje', () async {
    final db = LocalFirestore();
    final a = MultiplayerService.local(db: db, playerId: 'ana');
    final b = MultiplayerService.local(db: db, playerId: 'bogdan');
    final c = MultiplayerService.local(db: db, playerId: 'cici');
    final all = [a, b, c];

    final room = await a.createRoom(displayName: 'Ana', gameMode: MatchGameMode.unknown);
    await b.joinRoomById(matchId: room.id, displayName: 'Bogdan');
    await c.joinRoomById(matchId: room.id, displayName: 'Cici');
    await a.startMatch(room.id);

    final rnd = Random(4);
    MatchInfo info = await a.watchMatch(room.id).first;
    var guard = 0;
    while (info.status != MatchStatus.finished) {
      expect(guard++, lessThan(40), reason: 'meciul trebuia să se termine');
      final round = info.roundIndex;
      for (final s in all) {
        await s.submitUnknownAnswer(
          matchId: room.id,
          roundIndex: round,
          answer: rnd.nextDouble() < 0.6 ? 'corect' : 'gresit',
          ms: 1000 + rnd.nextInt(8000),
        );
      }
      await a.closeUnknownRound(matchId: room.id, roundIndex: round, correctAnswer: 'corect');
      await b.closeUnknownRound(matchId: room.id, roundIndex: round, correctAnswer: 'corect'); // no-op
      info = await a.watchMatch(room.id).first;
      expect(info.roundPhase, RoundPhase.revealed);
      expect(info.unknownLog, isNotNull);
      expect((info.unknownLog!['r'] as num).toInt(), round, reason: 'a doua închidere nu are voie să rescrie runda');

      final game = UnknownGame.fromJson(info.unknownState!);
      for (final s in all) {
        final offer = game.pendingOffers[s.currentPlayerId];
        if (offer == null) continue;
        await s.submitUnknownChoice(
          matchId: room.id,
          offerRound: round,
          choice: unknownBotChoice(game.player(s.currentPlayerId), offer),
        );
      }
      if (info.status == MatchStatus.finished) break;
      await a.advanceSyncRound(matchId: room.id, roundIndex: round);
      info = await a.watchMatch(room.id).first;
      expect(info.roundIndex, round + 1);
      expect(info.roundPhase, RoundPhase.answering);
    }

    final game = UnknownGame.fromJson(info.unknownState!);
    expect(game.players.any((p) => p.finished) || game.round >= unknownMaxRounds, isTrue);
    final players = await a.watchPlayers(room.id).first;
    final byRank = List.of(players)..sort((x, y) => y.unknownRank.compareTo(x.unknownRank));
    expect([for (final p in byRank) p.id], [for (final p in game.standings()) p.id]);
    // `score` rămâne mic (poziția), ca XP-ul să nu explodeze.
    expect(players.every((p) => p.score <= unknownFinish), isTrue);
  });

  test('Unknown: cine pleacă nu blochează runda, iar singur la masă meciul se termină', () async {
    final db = LocalFirestore();
    final a = MultiplayerService.local(db: db, playerId: 'ana');
    final b = MultiplayerService.local(db: db, playerId: 'bogdan');
    final room = await a.createRoom(displayName: 'Ana', gameMode: MatchGameMode.unknown);
    await b.joinRoomById(matchId: room.id, displayName: 'Bogdan');
    await a.startMatch(room.id);

    await a.submitUnknownAnswer(matchId: room.id, roundIndex: 0, answer: 'x', ms: 1000);
    await a.closeUnknownRound(matchId: room.id, roundIndex: 0, correctAnswer: 'x');
    await a.advanceSyncRound(matchId: room.id, roundIndex: 0);
    await b.leaveMatch(room.id);
    await a.closeUnknownRound(matchId: room.id, roundIndex: 1, correctAnswer: 'x');

    final info = await a.watchMatch(room.id).first;
    expect(info.status, MatchStatus.finished);
    expect(UnknownGame.fromJson(info.unknownState!).player('bogdan').left, isTrue);
  });
}
