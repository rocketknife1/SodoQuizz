import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/electric_chair.dart';
import 'package:guess_it/core/stable_hash.dart';
import 'package:guess_it/core/tanks.dart';
import 'package:guess_it/core/unknown_game.dart';
import 'package:guess_it/core/flash_game.dart';
import 'package:guess_it/core/impostor_game.dart';
import 'package:guess_it/data/questions.dart';
import 'package:guess_it/data/bot_match.dart';
import 'package:guess_it/data/culture_questions.dart';
import 'package:guess_it/models/multiplayer_models.dart';

/// Rulează un meci cu boți fără ecran: bucla de mai jos face ce fac ecranele
/// (închide fazele la timp, avansează rundele), jucătorul nu răspunde nimic.
/// Verifică faptul că boții chiar acționează în fiecare fază și că meciul
/// progresează — nu echilibrul.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<CultureQuestion> pool(String seed) {
    final p = List.of(cultureQuestions);
    stableShuffle(p, stableHash(seed));
    return p;
  }

  test('Scaunul Electric: boții aleg victime, răspund pe scaun, se pierd vieți', () async {
    final match = await BotMatch.start(
      // Seed fix + dificultatea 3: altfel „nimeni n-a pierdut vreo viață" pica
      // din noroc (victimele nimereau toate răspunsurile), nu din vreun bug.
      const BotMatchSettings(mode: MatchGameMode.electricChair, botCount: 3, difficulty: 3),
      displayName: 'Eu',
      random: Random(7),
    );
    final svc = match.service;
    final id = match.matchId;
    final q = pool(id);
    final chairPool = pool('$id#chair');
    var sawTargeting = false, sawChair = false, sawChoices = false, sawChairAnswers = false;
    var lastRound = -1;
    DateTime? revealAt;

    final deadline = DateTime.now().add(const Duration(seconds: 70));
    var livesLost = false;
    // Până se văd AMBELE: o viață pierdută poate veni și de la jucătorul uman
    // pus pe scaun (în test nu răspunde niciodată), înainte ca vreun bot să
    // fi răspuns pe scaun — oprirea doar pe `livesLost` rata a doua verificare.
    while (DateTime.now().isBefore(deadline) && !(livesLost && sawChairAnswers)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final info = await svc.watchMatch(id).first;
      final players = await svc.watchPlayers(id).first;
      if (info.status == MatchStatus.finished) break;
      if (info.roundIndex != lastRound) {
        lastRound = info.roundIndex;
        revealAt = null;
      }
      final elapsed = DateTime.now().difference(info.roundStartedAt!.toDate()).inSeconds;
      final alive = players.where((p) => !p.eliminated).map((p) => p.id).toSet();
      final present = players.map((p) => p.id).toSet();
      switch (info.roundPhase) {
        case RoundPhase.answering:
          final allBots = alive.where((p) => p != 'jucator').every(info.roundAnswers.containsKey);
          if (allBots || elapsed >= electricChairAnswerSeconds) {
            await svc.closeElectricChairAnswering(
                matchId: id, roundIndex: info.roundIndex, correctAnswer: q[info.roundIndex % q.length].answer);
          }
        case RoundPhase.targeting:
          sawTargeting = true;
          if (info.roundChairChoices.isNotEmpty) sawChoices = true;
          final attackers = info.roundWinnerIds.where(present.contains);
          if (attackers.every(info.roundChairChoices.containsKey) || elapsed >= electricChairTargetSeconds) {
            await svc.resolveElectricChairTargeting(matchId: id, roundIndex: info.roundIndex);
          }
        case RoundPhase.chair:
          sawChair = true;
          if (info.roundChairAnswers.isNotEmpty) sawChairAnswers = true;
          final victims = info.roundChairAssignments.keys.where((v) => v != 'jucator' && present.contains(v));
          if (victims.every(info.roundChairAnswers.containsKey) || elapsed >= electricChairSeconds) {
            final correct = {
              for (final e in info.roundChairAssignments.entries)
                e.key: () {
                  final start = stableHash('$id#${info.roundIndex}#${e.value.sourceAttackerId}') % chairPool.length;
                  return chairPool[(start + e.value.questionIndex) % chairPool.length].answer;
                }(),
            };
            await svc.resolveElectricChairRound(matchId: id, roundIndex: info.roundIndex, correctAnswers: correct);
          }
        case RoundPhase.revealed:
          revealAt ??= DateTime.now();
          livesLost = livesLost || players.any((p) => p.lives < electricChairMaxLives);
          if (DateTime.now().difference(revealAt) > const Duration(seconds: 1)) {
            await svc.advanceElectricChairRound(matchId: id, roundIndex: info.roundIndex);
          }
        default:
          break;
      }
    }
    match.dispose();
    expect(sawTargeting, isTrue, reason: 'nimeni n-a nimerit întrebarea în 70s');
    expect(sawChoices, isTrue, reason: 'boții n-au ales victimă');
    expect(sawChair, isTrue, reason: 'faza de scaun n-a pornit');
    expect(sawChairAnswers, isTrue, reason: 'boții n-au răspuns pe scaun');
    expect(livesLost, isTrue, reason: 'nimeni n-a pierdut vreo viață');
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('Quizz Tanks: boții trag și scad HP', () async {
    final match = await BotMatch.start(
      const BotMatchSettings(mode: MatchGameMode.quizzTanks, botCount: 3, difficulty: 5),
      displayName: 'Eu',
    );
    final svc = match.service;
    final id = match.matchId;
    final q = pool(id);
    var damaged = false;
    var lastRound = -1;
    DateTime? revealAt;
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline) && !damaged) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final info = await svc.watchMatch(id).first;
      final players = await svc.watchPlayers(id).first;
      if (info.roundIndex != lastRound) {
        lastRound = info.roundIndex;
        revealAt = null;
      }
      final elapsed = DateTime.now().difference(info.roundStartedAt!.toDate()).inSeconds;
      final aliveBots = players.where((p) => !p.eliminated && p.id != 'jucator').map((p) => p.id);
      switch (info.roundPhase) {
        case RoundPhase.answering:
          if (aliveBots.every(info.roundAnswers.containsKey) || elapsed >= tanksRoundSeconds) {
            await svc.closeTanksAnswering(
                matchId: id, roundIndex: info.roundIndex, correctAnswer: q[info.roundIndex % q.length].answer);
          }
        case RoundPhase.targeting:
          if (info.roundWinnerIds.every(info.roundTargets.containsKey) || elapsed >= tanksTargetSeconds) {
            await svc.resolveTanksRound(matchId: id, roundIndex: info.roundIndex);
          }
        case RoundPhase.revealed:
          revealAt ??= DateTime.now();
          damaged = players.any((p) => p.hp < tanksMaxHp);
          if (DateTime.now().difference(revealAt) > const Duration(seconds: 1)) {
            await svc.advanceSyncRound(matchId: id, roundIndex: info.roundIndex);
          }
        default:
          break;
      }
    }
    match.dispose();
    expect(damaged, isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('Unknown: boții răspund, aleg la cufăr/magazin, iar cursa avansează', () async {
    final match = await BotMatch.start(
      const BotMatchSettings(mode: MatchGameMode.unknown, botCount: 3, difficulty: 5),
      displayName: 'Eu',
    );
    final svc = match.service;
    final id = match.matchId;
    final q = pool(id);
    var lastRound = -1;
    var botsAnswered = false;
    var choiceMade = false;
    DateTime? revealAt;
    final deadline = DateTime.now().add(const Duration(seconds: 80));
    while (DateTime.now().isBefore(deadline) && !(botsAnswered && choiceMade)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final info = await svc.watchMatch(id).first;
      if (info.status == MatchStatus.finished) break;
      if (info.roundIndex != lastRound) {
        lastRound = info.roundIndex;
        revealAt = null;
      }
      final elapsed = DateTime.now().difference(info.roundStartedAt!.toDate()).inSeconds;
      final bots = ['bot_1', 'bot_2', 'bot_3'];
      switch (info.roundPhase) {
        case RoundPhase.answering:
          if (bots.every(info.roundAnswers.containsKey)) botsAnswered = true;
          if (bots.every(info.roundAnswers.containsKey) || elapsed >= unknownQuestionSeconds) {
            await svc.closeUnknownRound(
                matchId: id, roundIndex: info.roundIndex, correctAnswer: q[info.roundIndex % q.length].answer);
          }
        case RoundPhase.revealed:
          revealAt ??= DateTime.now();
          final game = UnknownGame.fromJson(info.unknownState!);
          final botOffers = game.pendingOffers.keys.where(bots.contains).toList();
          if (botOffers.isNotEmpty && botOffers.every(info.roundChoices.containsKey)) choiceMade = true;
          // Cât așteaptă și ecranul alegerea: până la 10 s.
          final waitChoices = botOffers.isNotEmpty && !botOffers.every(info.roundChoices.containsKey);
          if (DateTime.now().difference(revealAt) > Duration(seconds: waitChoices ? 10 : 1)) {
            await svc.advanceSyncRound(matchId: id, roundIndex: info.roundIndex);
          }
        default:
          break;
      }
    }
    final info = await svc.watchMatch(id).first;
    match.dispose();
    expect(botsAnswered, isTrue);
    expect(choiceMade || info.status == MatchStatus.finished, isTrue, reason: 'niciun bot n-a apucat să aleagă');
    expect(UnknownGame.fromJson(info.unknownState!).players.any((p) => p.pos > 0), isTrue);
  }, timeout: const Timeout(Duration(seconds: 100)));

  test('Fulgerul: boții memorează grila și răspund singuri', () async {
    final match = await BotMatch.start(
      const BotMatchSettings(mode: MatchGameMode.flash, botCount: 3, difficulty: 5),
      displayName: 'Eu',
    );
    final svc = match.service;
    final id = match.matchId;
    final pics = flashPicsFrom(await imagePool());
    final bots = ['bot_1', 'bot_2', 'bot_3'];
    var botsAnswered = false;
    var advanced = false;
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline) && !(botsAnswered && advanced)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final info = await svc.watchMatch(id).first;
      if (info.status == MatchStatus.finished) break;
      final elapsed = DateTime.now().difference(info.roundStartedAt!.toDate()).inMilliseconds;
      switch (info.roundPhase) {
        case RoundPhase.answering:
          if (bots.every(info.roundAnswers.containsKey)) botsAnswered = true;
          final revealMs = flashRevealMsFor(info.roundIndex);
          if (bots.every(info.roundAnswers.containsKey) || elapsed >= revealMs + flashAnswerSeconds * 1000) {
            final grid = const FlashGame().gridFor(pool: pics, seed: stableHash(id), round: info.roundIndex);
            await svc.closeFlashRound(
                matchId: id, roundIndex: info.roundIndex, correctIndex: grid.targetIndex, points: flashPointsFor(info.roundIndex));
          }
        case RoundPhase.revealed:
          advanced = true;
          await svc.advanceSyncRound(matchId: id, roundIndex: info.roundIndex);
        default:
          break;
      }
    }
    match.dispose();
    expect(botsAnswered, isTrue);
    expect(advanced, isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('Impostorul: boții aleg indicii și votează singuri', () async {
    final match = await BotMatch.start(
      const BotMatchSettings(mode: MatchGameMode.impostor, botCount: 3, difficulty: 5),
      displayName: 'Eu',
    );
    final svc = match.service;
    final id = match.matchId;
    final bots = ['bot_1', 'bot_2', 'bot_3'];
    var cluesGiven = false;
    var votesGiven = false;
    var advanced = false;
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline) && !(cluesGiven && votesGiven && advanced)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final info = await svc.watchMatch(id).first;
      if (info.status == MatchStatus.finished) break;
      final elapsed = DateTime.now().difference(info.roundStartedAt!.toDate()).inSeconds;
      switch (info.roundPhase) {
        case RoundPhase.answering:
          if (bots.every(info.roundAnswers.containsKey)) cluesGiven = true;
          if (bots.every(info.roundAnswers.containsKey) || elapsed >= impostorClueSeconds) {
            await svc.closeImpostorClues(matchId: id, roundIndex: info.roundIndex);
          }
        case RoundPhase.voting:
          final impostorId = const ImpostorGame().impostorFor(info.playerIds, stableHash(id), info.roundIndex);
          final votingBots = bots.where((b) => b != impostorId).toList();
          if (votingBots.every(info.roundVotes.containsKey)) votesGiven = true;
          if (votingBots.every(info.roundVotes.containsKey) || elapsed >= impostorVoteSeconds) {
            await svc.closeImpostorVoting(matchId: id, roundIndex: info.roundIndex, impostorId: impostorId);
          }
        case RoundPhase.revealed:
          advanced = true;
          await svc.advanceSyncRound(matchId: id, roundIndex: info.roundIndex);
        default:
          break;
      }
    }
    match.dispose();
    expect(cluesGiven, isTrue);
    expect(votesGiven, isTrue);
    expect(advanced, isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
