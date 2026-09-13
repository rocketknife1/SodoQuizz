import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/bot_brain.dart';
import '../core/game_helpers.dart';
import '../core/multiplayer_round.dart';
import '../core/obby.dart';
import '../core/powerups.dart';
import '../core/rock_paper_scissors.dart';
import '../core/stable_hash.dart';
import '../core/tanks.dart';
import '../core/electric_chair.dart';
import '../models/multiplayer_models.dart';
import '../models/question.dart';
import 'culture_questions.dart';
import 'local_firestore.dart';
import 'multiplayer_service.dart';
import 'questions.dart';

/// Ce a ales jucătorul înainte de un meci cu boți.
class BotMatchSettings {
  final MatchGameMode mode;
  final int botCount;
  final int difficulty;
  const BotMatchSettings({required this.mode, required this.botCount, required this.difficulty});
}

/// Modurile jucabile cu boți. Higher & Lower are deja modul lui solo
/// (higher_lower_screen.dart), deci nu apare aici.
const List<MatchGameMode> botMatchModes = [
  MatchGameMode.classic,
  MatchGameMode.rockPaperScissors,
  MatchGameMode.quizzTanks,
  MatchGameMode.electricChair,
  MatchGameMode.obby,
];

/// Un meci multiplayer jucat singur, contra boților, fără internet.
///
/// Ecranele de meci și regulile modurilor sunt EXACT cele din multiplayer: se
/// schimbă doar baza de date (una din memorie, [LocalFirestore]) și
/// cine stă la masă. Fiecare bot are propriul [MultiplayerService.local] peste
/// aceeași bază, deci trimite răspunsuri/ținte prin aceleași metode ca un
/// telefon real. Ecranul jucătorului rămâne cel care închide fazele și
/// avansează rundele, ca în orice meci.
///
/// Nimic de aici nu ajunge în Firestore-ul real, în clasament, în rating sau
/// la reconectare — vezi [MultiplayerService.isLocal].
class BotMatch {
  BotMatch._(this.settings, this.service, this.matchId, this._bots, this._rnd);

  static const humanId = 'jucator';

  final BotMatchSettings settings;
  final MultiplayerService service;
  final String matchId;
  final List<MultiplayerService> _bots;
  final Random _rnd;

  final List<StreamSubscription<Object?>> _subs = [];
  final List<Timer> _timers = [];
  final Set<String> _scheduled = {};
  final Map<String, int> _humanRps = {};
  int _rpsCountedRound = -1;
  MatchInfo? _info;
  List<MatchPlayer> _players = const [];
  bool _disposed = false;

  bool get isDisposed => _disposed;

  static Future<BotMatch> start(
    BotMatchSettings settings, {
    required String displayName,
    String? photoUrl,
    String avatarStyle = '',
  }) async {
    final db = LocalFirestore();
    final rnd = Random();
    final me = MultiplayerService.local(db: db, playerId: humanId);
    final room = await me.createRoom(
      displayName: displayName,
      photoUrl: photoUrl,
      avatarStyle: avatarStyle,
      gameMode: settings.mode,
    );
    final count = settings.botCount.clamp(botMinCount, botMaxCount);
    final names = botNames(count, rnd);
    final bots = <MultiplayerService>[];
    for (var i = 0; i < count; i++) {
      final bot = MultiplayerService.local(db: db, playerId: 'bot_${i + 1}');
      await bot.joinRoomById(matchId: room.id, displayName: names[i]);
      bots.add(bot);
    }
    await me.startMatch(room.id);
    final match = BotMatch._(settings, me, room.id, bots, rnd);
    match._run();
    return match;
  }

  void _run() {
    _subs.add(service.watchMatch(matchId).listen((info) {
      _info = info;
      _react();
    }));
    _subs.add(service.watchPlayers(matchId).listen((players) {
      _players = players;
      // Jucătorul a ieșit (înapoi din meci sau ecranul de rezultate a făcut
      // curat) — boții nu mai au pentru cine juca.
      if (players.isNotEmpty && !players.any((p) => p.id == humanId)) {
        dispose();
        return;
      }
      _react();
    }));
    _timers.add(Timer.periodic(MultiplayerService.matchHeartbeatInterval, (_) {
      for (final b in _bots) {
        b.matchHeartbeat(matchId);
      }
    }));
    if (settings.mode == MatchGameMode.classic) _runClassic();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final t in _timers) {
      t.cancel();
    }
    for (final s in _subs) {
      s.cancel();
    }
  }

  // ─── Modurile cu rundă sincronizată ────────────────────────────────────

  // Aceleași pool-uri ca ecranele (multiplayer_tanks_screen.dart etc.), ca botul
  // să răspundă la întrebarea pe care o vede și jucătorul.
  late final List<CultureQuestion> _pool = _shuffledQuestions(stableHash(matchId));
  late final List<CultureQuestion> _chairPool = _shuffledQuestions(stableHash('$matchId#chair'));

  static List<CultureQuestion> _shuffledQuestions(int seed) {
    final pool = List.of(cultureQuestions);
    stableShuffle(pool, seed);
    return pool;
  }

  CultureQuestion _questionFor(int roundIndex) => _pool[roundIndex % _pool.length];

  MatchPlayer? _player(String id) {
    for (final p in _players) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// O singură acțiune per bot per (rundă, fază): [key] o identifică, iar
  /// timerul verifică din nou, la declanșare, că faza e tot aceea.
  void _act(MultiplayerService bot, String phaseKey, int roundSeconds, Future<void> Function(MatchInfo info) action) {
    final key = '${bot.currentPlayerId}#$phaseKey';
    if (!_scheduled.add(key)) return;
    final delay = botThinkTime(difficulty: settings.difficulty, roundSeconds: roundSeconds, rnd: _rnd);
    _timers.add(Timer(delay, () async {
      final info = _info;
      if (_disposed || info == null || info.status != MatchStatus.playing) return;
      if ('${info.roundIndex}#${info.roundPhase.name}' != phaseKey) return;
      try {
        await action(info);
      } catch (e) {
        debugPrint('BotMatch: actiunea botului ${bot.currentPlayerId} a esuat: $e');
      }
    }));
  }

  void _react() {
    final info = _info;
    if (_disposed || info == null || info.status != MatchStatus.playing || _players.isEmpty) return;
    final phaseKey = '${info.roundIndex}#${info.roundPhase.name}';
    switch (settings.mode) {
      case MatchGameMode.rockPaperScissors:
        _reactRps(info, phaseKey);
      case MatchGameMode.quizzTanks:
        _reactTanks(info, phaseKey);
      case MatchGameMode.obby:
        _reactObby(info, phaseKey);
      case MatchGameMode.electricChair:
        _reactChair(info, phaseKey);
      case MatchGameMode.classic:
      case MatchGameMode.higherLower:
        break;
    }
  }

  void _reactRps(MatchInfo info, String phaseKey) {
    if (info.roundPhase == RoundPhase.revealed && _rpsCountedRound != info.roundIndex) {
      _rpsCountedRound = info.roundIndex;
      final mine = info.roundAnswers[humanId];
      if (mine != null && mine.isNotEmpty) _humanRps[mine] = (_humanRps[mine] ?? 0) + 1;
    }
    if (info.roundPhase != RoundPhase.answering) return;
    for (final bot in _bots) {
      if (info.roundAnswers.containsKey(bot.currentPlayerId)) continue;
      _act(bot, phaseKey, rpsRoundSeconds, (_) => bot.submitRoundAnswer(
            matchId: matchId,
            answer: botPickRps(humanHistory: _humanRps, difficulty: settings.difficulty, rnd: _rnd),
          ));
    }
  }

  Future<void> _answerQuestion(MultiplayerService bot, MatchInfo info) {
    final q = _questionFor(info.roundIndex);
    return bot.submitRoundAnswer(
      matchId: matchId,
      answer: botPickAnswer(correct: q.answer, choices: q.choices, difficulty: settings.difficulty, rnd: _rnd),
    );
  }

  void _reactTanks(MatchInfo info, String phaseKey) {
    for (final bot in _bots) {
      final id = bot.currentPlayerId;
      final me = _player(id);
      if (me == null || me.eliminated) continue;
      if (info.roundPhase == RoundPhase.answering && !info.roundAnswers.containsKey(id)) {
        _act(bot, phaseKey, sharedRoundAnswerSeconds, (i) => _answerQuestion(bot, i));
      } else if (info.roundPhase == RoundPhase.targeting &&
          info.roundWinnerIds.contains(id) &&
          !info.roundTargets.containsKey(id)) {
        _act(bot, phaseKey, tanksTargetSeconds, (_) async {
          final target = botPickTarget(
            hpById: {for (final p in _players) if (p.id != id && !p.eliminated) p.id: p.hp},
            difficulty: settings.difficulty,
            rnd: _rnd,
          );
          if (target != null) await bot.submitTanksTarget(matchId: matchId, targetId: target);
        });
      }
    }
  }

  void _reactObby(MatchInfo info, String phaseKey) {
    for (final bot in _bots) {
      final id = bot.currentPlayerId;
      final me = _player(id);
      if (me == null || me.obstaclesCleared >= obbyObstacleCount) continue;
      if (info.roundPhase == RoundPhase.answering && !info.roundAnswers.containsKey(id)) {
        _act(bot, phaseKey, obbyRoundSeconds, (i) => _answerQuestion(bot, i));
      } else if (info.roundPhase == RoundPhase.choosing &&
          info.roundWinnerIds.contains(id) &&
          !info.roundPlatformChoices.containsKey(id)) {
        _act(bot, phaseKey, obbyChoiceSeconds, (i) {
          final storm = roundEventFor(matchId: matchId, roundIndex: i.roundIndex, gameModeId: 'obby') ==
              RoundEvent.asteroidStorm;
          final safe = storm
              ? {obbyStormSafePlatformIndex(matchId: matchId, roundIndex: i.roundIndex, playerId: id)}
              : {
                  for (var p = 0; p < obbyPlatformChoiceCount; p++)
                    if (p != obbyFakePlatformIndex(matchId: matchId, roundIndex: i.roundIndex, playerId: id)) p,
                };
          return bot.submitObbyChoice(
            matchId: matchId,
            platformIndex: botPickPlatform(
              platformCount: obbyPlatformChoiceCount,
              safeIndices: safe,
              difficulty: settings.difficulty,
              rnd: _rnd,
            ),
          );
        });
      }
    }
  }

  void _reactChair(MatchInfo info, String phaseKey) {
    for (final bot in _bots) {
      final id = bot.currentPlayerId;
      final me = _player(id);
      if (me == null || me.eliminated) continue;
      if (info.roundPhase == RoundPhase.answering && !info.roundAnswers.containsKey(id)) {
        _act(bot, phaseKey, electricChairAnswerSeconds, (i) => _answerQuestion(bot, i));
      } else if (info.roundPhase == RoundPhase.targeting &&
          info.roundWinnerIds.contains(id) &&
          !info.roundChairChoices.containsKey(id)) {
        _act(bot, phaseKey, electricChairTargetSeconds, (_) async {
          final target = botPickTarget(
            hpById: {for (final p in _players) if (p.id != id && !p.eliminated) p.id: p.lives},
            difficulty: settings.difficulty,
            rnd: _rnd,
          );
          if (target == null) return;
          await bot.submitElectricChairChoice(
            matchId: matchId,
            targetId: target,
            questionIndex: _rnd.nextInt(electricChairCandidateCount),
          );
        });
      } else if (info.roundPhase == RoundPhase.chair &&
          info.roundChairAssignments.containsKey(id) &&
          !info.roundChairAnswers.containsKey(id)) {
        _act(bot, phaseKey, electricChairSeconds, (i) {
          final assignment = i.roundChairAssignments[id]!;
          final start = stableHash('$matchId#${i.roundIndex}#${assignment.sourceAttackerId}') % _chairPool.length;
          final q = _chairPool[(start + assignment.questionIndex) % _chairPool.length];
          return bot.submitChairAnswer(
            matchId: matchId,
            answer: botPickAnswer(correct: q.answer, choices: q.choices, difficulty: settings.difficulty, rnd: _rnd),
          );
        });
      }
    }
  }

  // ─── Clasic: cursa de un minut ─────────────────────────────────────────

  /// La Clasic nu există rundă comună: fiecare merge în ritmul lui prin
  /// același șir de întrebări. Botul „joacă" minutul în gând — timp de
  /// gândire, corect/greșit, punctele reale ale întrebării — și publică
  /// scorul exact cum face ecranul: o dată la jumătate, o dată la final.
  Future<void> _runClassic() async {
    final questions = List<Question>.of(await loadAllQuestions());
    stableShuffle(questions, stableHash(matchId));
    if (_disposed || questions.isEmpty) return;
    final start = DateTime.now();
    const total = Duration(seconds: multiplayerMatchSeconds);
    for (final bot in _bots) {
      var elapsed = Duration.zero;
      var score = 0;
      var halfScore = 0;
      var halfTaken = false;
      for (var i = 0; i < questions.length; i++) {
        elapsed += botThinkTime(difficulty: settings.difficulty, roundSeconds: 9, rnd: _rnd) +
            const Duration(milliseconds: 700);
        if (elapsed >= total) break;
        if (!halfTaken && elapsed >= total ~/ 2) {
          halfScore = score;
          halfTaken = true;
        }
        final q = questions[i];
        final correct = _rnd.nextDouble() < botAccuracy(settings.difficulty);
        score += correct ? q.maxPoints : -multiplayerWrongPenalty(q.maxPoints);
      }
      if (!halfTaken) halfScore = score;
      final finalScore = score;
      final mid = halfScore;
      _timers.add(Timer(start.add(total ~/ 2).difference(DateTime.now()), () {
        if (!_disposed) bot.updateScore(matchId: matchId, score: mid);
      }));
      _timers.add(Timer(start.add(total).difference(DateTime.now()), () {
        if (!_disposed) bot.finishWithScore(matchId: matchId, score: finalScore);
      }));
    }
  }
}
