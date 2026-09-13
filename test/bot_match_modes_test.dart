import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/electric_chair.dart';
import 'package:guess_it/core/stable_hash.dart';
import 'package:guess_it/core/tanks.dart';
import 'package:guess_it/data/bot_match.dart';
import 'package:guess_it/data/culture_questions.dart';
import 'package:guess_it/models/multiplayer_models.dart';

/// Rulează un meci cu boți fără ecran: bucla de mai jos face ce fac ecranele
/// (închide fazele la timp, avansează rundele), jucătorul nu răspunde nimic.
/// Verifică faptul că boții chiar acționează în fiecare fază și că meciul
/// progresează — nu echilibrul.
void main() {
  List<CultureQuestion> pool(String seed) {
    final p = List.of(cultureQuestions);
    stableShuffle(p, stableHash(seed));
    return p;
  }

  test('Scaunul Electric: boții aleg victime, răspund pe scaun, se pierd vieți', () async {
    final match = await BotMatch.start(
      const BotMatchSettings(mode: MatchGameMode.electricChair, botCount: 3, difficulty: 5),
      displayName: 'Eu',
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
    while (DateTime.now().isBefore(deadline) && !livesLost) {
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
          livesLost = players.any((p) => p.lives < electricChairMaxLives);
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
}
