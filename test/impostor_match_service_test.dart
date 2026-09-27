import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/impostor_game.dart';
import 'package:guess_it/core/stable_hash.dart';
import 'package:guess_it/data/local_firestore.dart';
import 'package:guess_it/data/multiplayer_service.dart';
import 'package:guess_it/data/questions.dart';
import 'package:guess_it/models/multiplayer_models.dart';

/// Un meci de Impostorul jucat cap-coadă prin MultiplayerService, pe baza
/// din memorie — fiecare „telefon" recalculează local impostorul și
/// cuvintele (exact ca MultiplayerImpostorScreen), niciodată citite dintr-un
/// loc comun, ca în meciul real.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Impostorul: meci întreg cu 4 jucători, fără blocaje, scoruri corecte', () async {
    final byCat = impostorPicsByCategory(await imagePool());
    final db = LocalFirestore();
    final a = MultiplayerService.local(db: db, playerId: 'ana');
    final b = MultiplayerService.local(db: db, playerId: 'bogdan');
    final c = MultiplayerService.local(db: db, playerId: 'cici');
    final d = MultiplayerService.local(db: db, playerId: 'dan');
    final all = [a, b, c, d];

    final room = await a.createRoom(displayName: 'Ana', gameMode: MatchGameMode.impostor);
    await b.joinRoomById(matchId: room.id, displayName: 'Bogdan');
    await c.joinRoomById(matchId: room.id, displayName: 'Cici');
    await d.joinRoomById(matchId: room.id, displayName: 'Dan');
    await a.startMatch(room.id);

    var guard = 0;
    MatchInfo info = await a.watchMatch(room.id).first;
    while (info.status != MatchStatus.finished) {
      expect(guard++, lessThan(impostorRounds + 2), reason: 'meciul trebuia să se termine la $impostorRounds runde');
      final round = info.roundIndex;
      final seed = stableHash(room.id);
      final impostorId = const ImpostorGame().impostorFor(info.playerIds, seed, round);
      final (real, fake) = const ImpostorGame().wordsFor(byCategory: byCat, seed: seed, round: round);
      expect(info.playerIds, contains(impostorId));
      expect(real.answer, isNot(fake.answer));

      // Faza de indicii: fiecare alege primul indiciu al cuvântului lui.
      for (final s in all) {
        final myWord = s.currentPlayerId == impostorId ? fake.answer : real.answer;
        final clue = impostorCluesFor(myWord).first;
        await s.submitRoundAnswer(matchId: room.id, roundIndex: round, answer: clue.encode());
      }
      await a.closeImpostorClues(matchId: room.id, roundIndex: round);
      await b.closeImpostorClues(matchId: room.id, roundIndex: round); // no-op
      info = await a.watchMatch(room.id).first;
      expect(info.roundPhase, RoundPhase.voting);

      // Votul: toți votează corect pe impostor (verifică drumul „prins").
      for (final s in all) {
        if (s.currentPlayerId == impostorId) continue;
        await s.submitImpostorVote(matchId: room.id, roundIndex: round, accusedId: impostorId);
      }
      await a.closeImpostorVoting(matchId: room.id, roundIndex: round, impostorId: impostorId);
      info = await a.watchMatch(room.id).first;
      expect(info.roundPhase, RoundPhase.revealed);
      expect(info.roundWinnerIds, isNotEmpty, reason: 'impostorul a fost prins de toți — trebuia să apară în roundWinnerIds');

      if (info.status == MatchStatus.finished) break;
      await a.advanceSyncRound(matchId: room.id, roundIndex: round);
      info = await a.watchMatch(room.id).first;
      expect(info.roundIndex, round + 1);
      expect(info.roundPhase, RoundPhase.answering);
      expect(info.roundVotes, isEmpty, reason: 'voturile rundei trecute trebuiau golite la avansare');
    }

    final players = await a.watchPlayers(room.id).first;
    // Fiecare a fost impostor cel puțin o dată prins peste 8 runde? Nu
    // garantat, dar toată lumea trebuie să fi punctat ceva (fie ca votant
    // corect, fie ca impostor prins — consolarea tot dă 1 punct).
    expect(players.every((p) => p.score > 0), isTrue);
  });

  test('impostorul care scapă (nimeni nu-l votează) ia punctele de supraviețuire', () async {
    final db = LocalFirestore();
    final a = MultiplayerService.local(db: db, playerId: 'ana');
    final b = MultiplayerService.local(db: db, playerId: 'bogdan');
    final c = MultiplayerService.local(db: db, playerId: 'cici');
    final room = await a.createRoom(displayName: 'Ana', gameMode: MatchGameMode.impostor);
    await b.joinRoomById(matchId: room.id, displayName: 'Bogdan');
    await c.joinRoomById(matchId: room.id, displayName: 'Cici');
    await a.startMatch(room.id);

    final info0 = await a.watchMatch(room.id).first;
    final seed = stableHash(room.id);
    final impostorId = const ImpostorGame().impostorFor(info0.playerIds, seed, 0);

    for (final s in [a, b, c]) {
      await s.submitRoundAnswer(matchId: room.id, roundIndex: 0, answer: 'startsWith:X');
    }
    await a.closeImpostorClues(matchId: room.id, roundIndex: 0);
    // Nimeni nu votează (toți expiră) — impostorul trebuie să scape.
    await a.closeImpostorVoting(matchId: room.id, roundIndex: 0, impostorId: impostorId);

    final players = await a.watchPlayers(room.id).first;
    final impostorScore = players.firstWhere((p) => p.id == impostorId).score;
    expect(impostorScore, impostorSurvivePoints);
  });
}
