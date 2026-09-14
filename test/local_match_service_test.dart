import 'package:guess_it/data/local_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/data/multiplayer_service.dart';
import 'package:guess_it/models/multiplayer_models.dart';

void main() {
  test('meci local: camera, bot, runda sincronizata, tranzactia de rezolvare', () async {
    final db = LocalFirestore();
    final me = MultiplayerService.local(db: db, playerId: 'eu');
    final bot = MultiplayerService.local(db: db, playerId: 'bot_1');

    final room = await me.createRoom(displayName: 'Eu', gameMode: MatchGameMode.rockPaperScissors);
    await bot.joinRoomById(matchId: room.id, displayName: 'Bot');
    await me.startMatch(room.id);

    final infos = <MatchInfo>[];
    final sub = me.watchMatch(room.id).listen(infos.add);

    await me.submitRoundAnswer(matchId: room.id, roundIndex: 0, answer: 'rock');
    await bot.submitRoundAnswer(matchId: room.id, roundIndex: 0, answer: 'scissors');
    await me.resolveRockPaperScissorsRound(matchId: room.id, roundIndex: 0);
    // al doilea apel pe aceeasi runda trebuie sa fie no-op (garda din tranzactie)
    await bot.resolveRockPaperScissorsRound(matchId: room.id, roundIndex: 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final players = await me.watchPlayers(room.id).first;
    final mine = players.firstWhere((p) => p.id == 'eu');
    final theirs = players.firstWhere((p) => p.id == 'bot_1');
    expect(mine.score, greaterThan(0));
    expect(theirs.score, 0);
    expect(infos.last.roundPhase, RoundPhase.revealed);
    expect(infos.last.roundWinnerIds, ['eu']);
    expect(infos.last.startedAt, isNotNull);

    await me.advanceSyncRound(matchId: room.id, roundIndex: 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(infos.last.roundIndex, 1);
    expect(infos.last.roundPhase, RoundPhase.answering);
    await sub.cancel();
  });

  test('fluxul de jucatori suporta mai multi ascultatori, ca Firestore real', () async {
    final db = LocalFirestore();
    final me = MultiplayerService.local(db: db, playerId: 'eu');
    final room = await me.createRoom(displayName: 'Eu');
    final stream = me.watchPlayers(room.id);
    expect((await stream.first).single.id, 'eu');
    expect((await stream.first).single.id, 'eu');
  });

  test('un raspuns intarziat din runda trecuta nu blocheaza runda noua', () async {
    final db = LocalFirestore();
    final me = MultiplayerService.local(db: db, playerId: 'eu');
    final bot = MultiplayerService.local(db: db, playerId: 'bot_1');
    final room = await me.createRoom(displayName: 'Eu', gameMode: MatchGameMode.rockPaperScissors);
    await bot.joinRoomById(matchId: room.id, displayName: 'Bot');
    await me.startMatch(room.id);
    await me.submitRoundAnswer(matchId: room.id, roundIndex: 0, answer: 'rock');
    await bot.submitRoundAnswer(matchId: room.id, roundIndex: 0, answer: 'paper');
    await me.resolveRockPaperScissorsRound(matchId: room.id, roundIndex: 0);
    await me.advanceSyncRound(matchId: room.id, roundIndex: 0);
    // scrierea botului pentru runda 0 ajunge abia acum, in runda 1
    await bot.submitRoundAnswer(matchId: room.id, roundIndex: 0, answer: 'scissors');
    final info = await me.watchMatch(room.id).first;
    expect(info.roundIndex, 1);
    expect(info.roundAnswers.containsKey('bot_1'), isFalse);
  });
}
