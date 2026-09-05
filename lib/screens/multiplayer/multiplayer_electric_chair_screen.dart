import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../core/admin_reveal.dart';
import '../../core/audio.dart';
import '../../core/electric_chair.dart';
import '../../core/lang.dart';
import '../../core/powerup_ui.dart';
import '../../core/powerups.dart';
import '../../core/stable_hash.dart';
import '../../core/theme.dart';
import '../../data/culture_questions.dart';
import '../../data/multiplayer_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/player_badge.dart';
import '../../widgets/round_event_banner.dart';
import '../../widgets/space_background.dart';
import 'multiplayer_results_screen.dart';
import '../../core/breadcrumbs.dart';

/// **Scaunul Electric** — până la [electricChairPlayerCount] jucători,
/// [electricChairMaxLives] vieți fiecare. Cine răspunde corect la propria
/// întrebare capătă dreptul să pună pe altcineva pe scaun, alegându-i și
/// întrebarea din patru oferite. Victima care greșește pierde o viață; la
/// zero e eliminată, dar rămâne la masă ca spectator.
/// Regulile și toate cifrele stau în core/electric_chair.dart, rezolvarea
/// rundei în MultiplayerService (closeElectricChairAnswering →
/// resolveElectricChairTargeting → resolveElectricChairRound).
///
/// CE FACE ECRANUL ĂSTA ȘI CE NU: la fel ca Quizz Tanks, nu decide nimic.
/// Întrebările — atât cea proprie a rundei, cât și cele patru candidate
/// pentru scaun — se derivă determinist local (vezi core/stable_hash.dart),
/// iar rezultatul rundei se CITEȘTE din Firestore. Orice client poate cere
/// închiderea unei faze; meciul nu are voie să se blocheze dacă pleacă
/// tocmai cel care ar fi trebuit s-o facă.
class MultiplayerElectricChairScreen extends StatefulWidget {
  final String matchId;
  const MultiplayerElectricChairScreen({super.key, required this.matchId});

  @override
  State<MultiplayerElectricChairScreen> createState() => _MultiplayerElectricChairScreenState();
}

class _MultiplayerElectricChairScreenState extends State<MultiplayerElectricChairScreen>
    with SingleTickerProviderStateMixin {
  late final Stream<MatchInfo> _matchStream = MultiplayerService.instance.watchMatch(widget.matchId);
  late final Stream<List<MatchPlayer>> _playersStream = MultiplayerService.instance.watchPlayers(widget.matchId);

  /// Pool-ul întrebărilor PROPRII de rundă — aceeași idee ca la Quizz Tanks:
  /// amestecat o singură dată, determinist din matchId, ca toți clienții să
  /// vadă aceeași întrebare la aceeași rundă.
  late final List<CultureQuestion> _pool = _buildPool();

  /// Pool separat pentru candidatele de scaun — amestecat cu o sămânță
  /// diferită ('#chair'), ca cele patru oferite unui atacator să nu fie pur
  /// și simplu următoarele din pool-ul întrebării proprii.
  late final List<CultureQuestion> _chairPool = _buildChairPool();

  Timer? _tick;
  Timer? _advanceTimer;
  Timer? _heartbeatTimer;
  int _lastRoundIndex = -1;
  bool _resolving = false;
  DateTime? _lastResolveAttempt;
  bool _navigatedToResults = false;
  bool _left = false;

  /// Alegerea LOCALĂ (nu încă trimisă) a atacatorului curent, în faza de
  /// alegere: victima aleasă primul pas, întrebarea al doilea. Resetate la
  /// fiecare rundă nouă.
  String? _pendingTargetId;

  List<String>? _cachedChoices;
  int _cachedChoicesRound = -1;

  /// Ordinea variantelor de răspuns pentru fiecare victimă de pe scaun,
  /// amestecată determinist o singură dată pe rundă.
  final Map<String, List<String>> _chairChoiceCache = {};
  int _chairChoiceCacheRound = -1;

  /// Eveniment/power-up determinist (core/powerups.dart), la fel ca-n
  /// celelalte moduri deja cablate. Vezi [_maybeGrantPowerUp]/[_usePowerUp].
  PowerUp _myPowerUp = PowerUp.none;
  int? _powerUpRolledRound;
  Set<String> _hiddenChoices = const {};

  /// uid → nume, reîmprospătat la fiecare [_onData] — pentru banner-ul de la
  /// [PowerUp.peek].
  final Map<String, String> _playerNames = {};

  List<CultureQuestion> _buildPool() {
    final pool = List.of(cultureQuestions);
    stableShuffle(pool, stableHash(widget.matchId));
    return pool;
  }

  List<CultureQuestion> _buildChairPool() {
    final pool = List.of(cultureQuestions);
    stableShuffle(pool, stableHash('${widget.matchId}#chair'));
    return pool;
  }

  CultureQuestion _questionFor(int roundIndex) => _pool[roundIndex % _pool.length];

  List<String> _choicesFor(int roundIndex) {
    if (_cachedChoicesRound == roundIndex && _cachedChoices != null) return _cachedChoices!;
    final choices = List.of(_questionFor(roundIndex).choices);
    stableShuffle(choices, stableHash('${widget.matchId}#$roundIndex'));
    _cachedChoices = choices;
    _cachedChoicesRound = roundIndex;
    return choices;
  }

  /// Cele [electricChairCandidateCount] întrebări oferite unui atacator, din
  /// care alege UNA pentru victima lui. Depind doar de cine atacă, nu și de
  /// cine e ținta — un atacator vede mereu aceleași patru opțiuni într-o
  /// rundă, indiferent pe cine alege.
  List<CultureQuestion> _chairCandidatesFor(int roundIndex, String attackerId) {
    final start = stableHash('${widget.matchId}#$roundIndex#$attackerId') % _chairPool.length;
    return List.generate(electricChairCandidateCount, (i) => _chairPool[(start + i) % _chairPool.length]);
  }

  CultureQuestion _chairQuestionFor(int roundIndex, ChairAssignment assignment) =>
      _chairCandidatesFor(roundIndex, assignment.sourceAttackerId)[assignment.questionIndex];

  List<String> _chairChoicesFor(int roundIndex, String victimId, CultureQuestion question) {
    if (_chairChoiceCacheRound != roundIndex) {
      _chairChoiceCache.clear();
      _chairChoiceCacheRound = roundIndex;
    }
    final cached = _chairChoiceCache[victimId];
    if (cached != null) return cached;
    final choices = List.of(question.choices);
    stableShuffle(choices, stableHash('${widget.matchId}#$roundIndex#chairAnswer#$victimId'));
    _chairChoiceCache[victimId] = choices;
    return choices;
  }

  String get _myId => MultiplayerService.instance.currentPlayerId;

  @override
  void initState() {
    super.initState();
    Breadcrumbs.drop('ecran: Meci Scaunul Electric');
    // Reconectare: daca aplicatia moare in mijlocul meciului, butonul
    // de reconectare stie unde sa te intoarca (vezi MultiplayerService).
    MultiplayerService.instance.markActiveMatch(widget.matchId, MatchGameMode.electricChair);
    // O data pe secunda, NU la 250ms. Nimic din ecranul asta nu se schimba mai des de o data pe secunda:
    // singurul consumator de timp e cronometrul, care numara in secunde.
    // Tick-ul asta exista doar pentru cronometru; la 250ms reconstruia tot
    // ecranul (lista de jucatori, avatare, tot) de patru ori pe secunda
    // degeaba. Verificarea de expirare a rundei ramane corecta — ruleaza in
    // continuare o data pe secunda.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _heartbeatTimer = Timer.periodic(MultiplayerService.matchHeartbeatInterval, (_) {
      MultiplayerService.instance.matchHeartbeat(widget.matchId);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _advanceTimer?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  int _secondsLeft(MatchInfo info, int total) {
    final started = info.roundStartedAt?.toDate();
    if (started == null) return total;
    final elapsed = DateTime.now().difference(started).inSeconds;
    return (total - elapsed).clamp(0, total);
  }

  int get _answerTotalSeconds => electricChairAnswerSeconds;
  int _answerSecondsLeftFor(MatchInfo info) => _secondsLeft(info, _answerTotalSeconds);
  int _targetSecondsLeftFor(MatchInfo info) => _secondsLeft(info, electricChairTargetSeconds);
  int _chairSecondsLeftFor(MatchInfo info) => _secondsLeft(info, electricChairSeconds);

  Future<void> _leave() async {
    if (_left) return;
    _left = true;
    try {
      await MultiplayerService.instance.leaveMatch(widget.matchId);
    } catch (e) {
      debugPrint('MultiplayerElectricChairScreen._leave: leaveMatch a esuat: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  void _answerOwnQuestion(MatchInfo info, String choice) {
    if (info.roundPhase != RoundPhase.answering) return;
    if (info.roundAnswers.containsKey(_myId)) return;
    Sfx.tileSelect();
    MultiplayerService.instance.submitRoundAnswer(matchId: widget.matchId, answer: choice);
  }

  void _pickTarget(MatchInfo info, String targetId) {
    if (info.roundPhase != RoundPhase.targeting) return;
    if (!info.roundWinnerIds.contains(_myId) || info.roundChairChoices.containsKey(_myId)) return;
    Sfx.tileSelect();
    setState(() => _pendingTargetId = targetId);
  }

  void _pickQuestion(MatchInfo info, int roundIndex, int questionIndex) {
    if (info.roundPhase != RoundPhase.targeting) return;
    final target = _pendingTargetId;
    if (target == null) return;
    if (!info.roundWinnerIds.contains(_myId) || info.roundChairChoices.containsKey(_myId)) return;
    Sfx.tileSelect();
    MultiplayerService.instance.submitElectricChairChoice(
      matchId: widget.matchId,
      targetId: target,
      questionIndex: questionIndex,
    );
  }

  /// Consumă power-up-ul curent. Efectele de scaun (scut, reflect, sabotaj
  /// pe atac) vin la trecerea de polish — aici doar [PowerUp.fiftyFifty]
  /// (pe propria întrebare) are efect local, instant.
  /// [PowerUp.shield]/[PowerUp.piercingShock] se scriu pe `roundPowerUps` —
  /// [resolveElectricChairRound] le citește de-acolo la deznodământ, ca la
  /// mega rachetă/scut din Quizz Tanks. [PowerUp.allyShield] apără automat
  /// cel mai slăbit coechipier ([MultiplayerService.useElectricChairAllyShield]).
  /// [PowerUp.reflect] se scrie pe `roundPowerUps` și întoarce șocul spre
  /// atacatori la [MultiplayerService.resolveElectricChairRound].
  /// [PowerUp.peek] e efect local — arată ce au răspuns ceilalți.
  void _usePowerUp(MatchInfo info) {
    final p = _myPowerUp;
    if (p == PowerUp.none) return;
    if (!powerUpUsableInPhase(p, info.roundPhase.name)) {
      notifyPowerUpTooLate(context);
      return; // păstrează puterea — nu o consuma pe o scriere care se pierde
    }
    Sfx.tileSelect();
    switch (p) {
      case PowerUp.fiftyFifty:
        if (info.roundPhase == RoundPhase.answering && !info.roundAnswers.containsKey(_myId)) {
          final q = _questionFor(info.roundIndex);
          final wrong = q.choices.where((c) => c != q.answer).toList();
          stableShuffle(wrong, stableHash('${widget.matchId}#${info.roundIndex}#5050'));
          setState(() => _hiddenChoices = wrong.take(max(0, wrong.length - 1)).toSet());
        }
      case PowerUp.shield:
      case PowerUp.piercingShock:
      case PowerUp.reflect:
        MultiplayerService.instance.submitElectricChairPowerUp(matchId: widget.matchId, powerUp: p);
      case PowerUp.allyShield:
        MultiplayerService.instance.useElectricChairAllyShield(matchId: widget.matchId, roundIndex: info.roundIndex);
      case PowerUp.peek:
        showPeekResults(context, info, myId: _myId, playerNames: _playerNames);
      default:
        break;
    }
    setState(() => _myPowerUp = PowerUp.none);
  }

  /// Vezi core/powerups.dart — acordat cui a răspuns corect la propria
  /// întrebare (adică e în `roundWinnerIds`), cu șansă mai mare pentru cine
  /// are mai puține vieți.
  void _maybeGrantPowerUp(MatchInfo info, List<MatchPlayer> players) {
    if (_powerUpRolledRound == info.roundIndex) return;
    _powerUpRolledRound = info.roundIndex;
    final me = _myId;
    if (!info.roundWinnerIds.contains(me)) return;
    final ranked = List.of(players)..sort((a, b) => b.lives.compareTo(a.lives));
    final total = ranked.isEmpty ? 1 : ranked.length;
    var rank = ranked.indexWhere((p) => p.id == me);
    if (rank < 0) rank = 0;
    final granted = grantsPowerUp(
      matchId: widget.matchId,
      roundIndex: info.roundIndex,
      playerId: me,
      wonRound: true,
      myRank: rank,
      totalPlayers: total,
    );
    if (!granted) return;
    final picked = powerUpFor(matchId: widget.matchId, roundIndex: info.roundIndex, playerId: me, gameModeId: 'electricChair');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _myPowerUp = picked);
      Sfx.rewardPop();
      announcePowerUp(context, picked);
    });
  }

  void _answerChairQuestion(MatchInfo info, String choice) {
    if (info.roundPhase != RoundPhase.chair) return;
    if (!info.roundChairAssignments.containsKey(_myId)) return;
    if (info.roundChairAnswers.containsKey(_myId)) return;
    Sfx.tileSelect();
    MultiplayerService.instance.submitChairAnswer(matchId: widget.matchId, answer: choice);
  }

  /// Aceeași frână ca la Quizz Tanks: `build` rulează de câteva ori pe
  /// secundă cât cronometrul e la zero, deci fiecare cerere de închidere a
  /// fazei trebuie ferită de coliziune cu ea însăși.
  Future<void> _advancePhase(MatchInfo info) async {
    if (_resolving) return;
    final now = DateTime.now();
    if (_lastResolveAttempt != null && now.difference(_lastResolveAttempt!) < const Duration(milliseconds: 900)) {
      return;
    }
    _lastResolveAttempt = now;
    _resolving = true;
    try {
      if (info.roundPhase == RoundPhase.answering) {
        await MultiplayerService.instance.closeElectricChairAnswering(
          matchId: widget.matchId,
          roundIndex: info.roundIndex,
          correctAnswer: _questionFor(info.roundIndex).answer,
        );
      } else if (info.roundPhase == RoundPhase.targeting) {
        await MultiplayerService.instance.resolveElectricChairTargeting(
          matchId: widget.matchId,
          roundIndex: info.roundIndex,
        );
      } else if (info.roundPhase == RoundPhase.chair) {
        final correctAnswers = {
          for (final entry in info.roundChairAssignments.entries)
            entry.key: _chairQuestionFor(info.roundIndex, entry.value).answer,
        };
        await MultiplayerService.instance.resolveElectricChairRound(
          matchId: widget.matchId,
          roundIndex: info.roundIndex,
          correctAnswers: correctAnswers,
        );
      }
    } finally {
      _resolving = false;
    }
  }

  void _onData(MatchInfo info, List<MatchPlayer> players) {
    for (final p in players) {
      _playerNames[p.id] = p.name;
    }
    if (info.roundIndex != _lastRoundIndex) {
      _lastRoundIndex = info.roundIndex;
      _pendingTargetId = null;
      _lastResolveAttempt = null;
      _hiddenChoices = const {};
      _advanceTimer?.cancel();
      _advanceTimer = null;
    }

    final present = players.map((p) => p.id).toSet();

    if (info.roundPhase == RoundPhase.answering) {
      final aliveIds = players.where((p) => !p.eliminated).map((p) => p.id).toSet();
      final allAnswered = aliveIds.isNotEmpty && aliveIds.every(info.roundAnswers.containsKey);
      if (allAnswered || _answerSecondsLeftFor(info) <= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _advancePhase(info));
      }
    } else if (info.roundPhase == RoundPhase.targeting) {
      // roundWinnerIds e cunoscut din clipa asta — de-aia power-up-ul se
      // acordă aici, nu în faza de răspuns.
      _maybeGrantPowerUp(info, players);
      final attackers = info.roundWinnerIds.where(present.contains);
      final allPicked = attackers.isNotEmpty && attackers.every(info.roundChairChoices.containsKey);
      if (allPicked || _targetSecondsLeftFor(info) <= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _advancePhase(info));
      }
    } else if (info.roundPhase == RoundPhase.chair) {
      final victims = info.roundChairAssignments.keys.where(present.contains);
      final allAnswered = victims.isNotEmpty && victims.every(info.roundChairAnswers.containsKey);
      if (allAnswered || _chairSecondsLeftFor(info) <= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _advancePhase(info));
      }
    } else if (info.roundPhase == RoundPhase.revealed && info.status != MatchStatus.finished) {
      _advanceTimer ??= Timer(
        Duration(seconds: electricChairRevealSecondsFor(anyoneTested: info.roundChairOutcomes.isNotEmpty)),
        () {
          MultiplayerService.instance.advanceElectricChairRound(matchId: widget.matchId, roundIndex: info.roundIndex);
        },
      );
    }

    if (info.status == MatchStatus.finished && !_navigatedToResults) {
      _navigatedToResults = true;
      Future.delayed(
        Duration(seconds: electricChairRevealSecondsFor(anyoneTested: info.roundChairOutcomes.isNotEmpty)),
        () {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MultiplayerResultsScreen(matchId: widget.matchId, gameMode: MatchGameMode.electricChair),
            ),
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SpaceBackground(
          child: SafeArea(
            child: StreamBuilder<MatchInfo>(
              stream: _matchStream,
              builder: (context, matchSnap) {
                final info = matchSnap.data;
                if (info == null) return const Center(child: CircularProgressIndicator(color: AppColors.coin));
                return StreamBuilder<List<MatchPlayer>>(
                  stream: _playersStream,
                  builder: (context, playersSnap) {
                    final players = List.of(playersSnap.data ?? const <MatchPlayer>[])..sort((a, b) => a.id.compareTo(b.id));
                    _onData(info, players);
                    return Column(
                      children: [
                        _buildTopBar(info),
                        _buildPlayerStrip(players),
                        Expanded(child: _buildPhaseContent(info, players)),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(MatchInfo info) {
    return Column(
      // Fără mainAxisSize.min, acest Column (necuprins într-un Expanded)
      // pretinde toată înălțimea disponibilă de la Column-ul din build(),
      // împingând _buildPlayerStrip și restul ecranului spre zero — exact
      // bug-ul confirmat live la Obby, evitat aici din start.
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 16, 4),
          child: Row(
            children: [
              IconButton(onPressed: _leave, icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70)),
              const Icon(Icons.electric_bolt_rounded, color: AppColors.coin, size: 20),
              const SizedBox(width: 6),
              const Text('SCAUNUL ELECTRIC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 0.8, fontSize: 14)),
              const Spacer(),
              PowerUpChip(powerUp: _myPowerUp, onTap: () => _usePowerUp(info)),
              const SizedBox(width: 8),
              Text('Runda ${info.roundIndex + 1}', style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        RoundEventBanner(
          event: roundEventFor(matchId: widget.matchId, roundIndex: info.roundIndex, gameModeId: 'electricChair'),
          compact: true,
        ),
      ],
    );
  }

  Widget _buildPlayerStrip(List<MatchPlayer> players) {
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final p in players)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Opacity(
                opacity: p.eliminated ? 0.35 : 1,
                child: PlayerBadge(
                  name: p.name,
                  photoUrl: p.photoUrl,
                  avatarSeed: p.avatarSeed,
                  avatarStyle: p.avatarStyle,
                  size: 46,
                  ringColor: p.id == _myId ? AppColors.blue : (p.isHost ? AppColors.coin : null),
                  scoreChip: _livesChip(p),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _livesChip(MatchPlayer p) {
    if (p.eliminated) {
      return const Text('💀', style: TextStyle(fontSize: 12));
    }
    final color = p.lives <= 2 ? AppColors.danger : (p.lives <= 4 ? AppColors.orange : AppColors.play);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bolt_rounded, color: color, size: 11),
        Text(' ${p.lives}', style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _buildPhaseContent(MatchInfo info, List<MatchPlayer> players) {
    switch (info.roundPhase) {
      case RoundPhase.answering:
        return _buildAnsweringPhase(info, players);
      case RoundPhase.targeting:
        return _buildTargetingPhase(info, players);
      case RoundPhase.chair:
        return _buildChairPhase(info, players);
      case RoundPhase.revealed:
        return _buildRevealedPhase(info, players);
      case RoundPhase.choosing:
        return const SizedBox.shrink(); // fază care nu aparține acestui mod
    }
  }

  // ─── Faza 1: răspuns propriu ───────────────────────────────────────────

  Widget _buildAnsweringPhase(MatchInfo info, List<MatchPlayer> players) {
    final me = _myId;
    final iAmEliminated = players.where((p) => p.id == me).firstOrNull?.eliminated ?? false;
    if (iAmEliminated) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility_rounded, color: Colors.white38, size: 28),
              const SizedBox(height: 10),
              Text(tr('Ești eliminat — rămâi la masă ca spectator.', 'You are eliminated — you stay at the table as a spectator.'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }
    final question = _questionFor(info.roundIndex);
    final choices = _choicesFor(info.roundIndex).where((c) => !_hiddenChoices.contains(c)).toList();
    final answered = info.roundAnswers.containsKey(me);
    final seconds = _answerSecondsLeftFor(info);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CountdownBar(seconds: seconds, total: _answerTotalSeconds, color: AppColors.coin),
          const SizedBox(height: 14),
          Text(
            tr('Cine răspunde corect alege pe cineva pentru scaun.', 'Whoever answers right gets to pick someone for the chair.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          _QuestionCard(text: question.question, accent: AppColors.coin),
          const SizedBox(height: 16),
          for (final c in choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AnswerButton(
                text: c,
                onTap: answered ? null : () => _answerOwnQuestion(info, c),
                selected: info.roundAnswers[me] == c,
                adminHint: !answered && adminAnswerRevealOn && c == question.answer,
              ),
            ),
          if (answered)
            Text(tr('Ai răspuns — aștept ceilalți jucători...', 'You answered — waiting for the others...'),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }

  // ─── Faza 2: alegere victimă + întrebare ───────────────────────────────

  Widget _buildTargetingPhase(MatchInfo info, List<MatchPlayer> players) {
    final me = _myId;
    final qualifies = info.roundWinnerIds.contains(me);
    final alreadyPicked = info.roundChairChoices.containsKey(me);
    if (!qualifies) {
      return _buildTargetingWaiting(info);
    }
    if (alreadyPicked) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Text(
            tr('Ai ales — aștept ceilalți...', 'You picked — waiting for the others...'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    final seconds = _targetSecondsLeftFor(info);
    final targets = players.where((p) => p.id != me && !p.eliminated).toList();

    if (_pendingTargetId == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CountdownBar(seconds: seconds, total: electricChairTargetSeconds, color: AppColors.danger),
            const SizedBox(height: 10),
            Text(tr('⚡ Ai răspuns corect! Pe cine pui pe scaun?', '⚡ Correct! Who goes on the chair?'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                children: [
                  for (final t in targets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TargetTile(player: t, onTap: () => _pickTarget(info, t.id)),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final target = players.firstWhere((p) => p.id == _pendingTargetId, orElse: () => targets.first);
    final candidates = _chairCandidatesFor(info.roundIndex, me);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CountdownBar(seconds: seconds, total: electricChairTargetSeconds, color: AppColors.danger),
          const SizedBox(height: 10),
          Text(tr('Ce întrebare îi dai lui ${target.name}?', 'What question do you give ${target.name}?'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => setState(() => _pendingTargetId = null),
            child: Text(tr('‹ schimbă ținta', '‹ change target'), style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < candidates.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _QuestionPickTile(text: candidates[i].question, onTap: () => _pickQuestion(info, info.roundIndex, i)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetingWaiting(MatchInfo info) {
    final me = _myId;
    final myAnswer = info.roundAnswers[me];
    final correct = _questionFor(info.roundIndex).answer;
    final gotItRight = myAnswer == correct;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(gotItRight ? Icons.hourglass_top_rounded : Icons.close_rounded,
                color: gotItRight ? Colors.white38 : AppColors.danger, size: 30),
            const SizedBox(height: 10),
            Text(
              gotItRight
                  ? tr('Ai răspuns corect, dar altcineva a fost mai rapid la alegere.', 'You got it right, but someone else picked faster.')
                  : tr('Ai greșit — nu alegi de data asta.', 'You got it wrong — no pick this time.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(tr('Răspunsul corect era: $correct', 'The correct answer was: $correct'),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }

  // ─── Faza 3: scaunul ────────────────────────────────────────────────────

  Widget _buildChairPhase(MatchInfo info, List<MatchPlayer> players) {
    final me = _myId;
    final myAssignment = info.roundChairAssignments[me];
    if (myAssignment == null) {
      return _buildChairSpectator(info, players);
    }
    final answered = info.roundChairAnswers.containsKey(me);
    final question = _chairQuestionFor(info.roundIndex, myAssignment);
    final choices = _chairChoicesFor(info.roundIndex, me, question);
    final seconds = _chairSecondsLeftFor(info);
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.danger.withAlpha(40), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CountdownBar(seconds: seconds, total: electricChairSeconds, color: AppColors.danger),
            const SizedBox(height: 10),
            Text('⚡ ${tr('EȘTI PE SCAUN!', 'YOU ARE ON THE CHAIR!')} ⚡',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(tr('Răspunde corect ca să scapi.', 'Answer correctly to survive.'),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
            const SizedBox(height: 12),
            _QuestionCard(text: question.question, accent: AppColors.danger),
            const SizedBox(height: 16),
            for (final c in choices)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AnswerButton(
                  text: c,
                  onTap: answered ? null : () => _answerChairQuestion(info, c),
                  selected: info.roundChairAnswers[me] == c,
                  danger: true,
                  adminHint: !answered && adminAnswerRevealOn && c == question.answer,
                ),
              ),
            if (answered)
              Text(tr('Ai răspuns — se decide soarta ta...', 'You answered — your fate is being decided...'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildChairSpectator(MatchInfo info, List<MatchPlayer> players) {
    final me = _myId;
    final myPlayer = players.where((p) => p.id == me).firstOrNull;
    final assignments = info.roundChairAssignments;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility_rounded, color: Colors.white38, size: 28),
            const SizedBox(height: 10),
            if (assignments.isEmpty)
              Text(tr('Nimeni pe scaun runda asta.', 'Nobody on the chair this round.'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600))
            else ...[
              Text(tr('Pe scaun acum:', 'On the chair now:'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              for (final id in assignments.keys)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    players.where((p) => p.id == id).firstOrNull?.name ?? '?',
                    style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
            ],
            if (myPlayer?.eliminated == true) ...[
              const SizedBox(height: 16),
              Text(tr('Ești eliminat — rămâi la masă ca spectator.', 'You are eliminated — you stay at the table as a spectator.'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Faza 4: deznodământ ────────────────────────────────────────────────

  Widget _buildRevealedPhase(MatchInfo info, List<MatchPlayer> players) {
    final outcomes = info.roundChairOutcomes;
    if (outcomes.isEmpty) {
      final correct = _questionFor(info.roundIndex).answer;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('😴', style: TextStyle(fontSize: 32)),
              const SizedBox(height: 10),
              Text(tr('Nimeni n-a nimerit — nimeni pe scaun runda asta.', 'Nobody got it — nobody on the chair this round.'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(tr('Răspunsul corect era: $correct', 'The correct answer was: $correct'),
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: ListView(
        children: [
          for (final entry in outcomes.entries)
            Builder(builder: (context) {
              final player = players.where((p) => p.id == entry.key).firstOrNull;
              final assignment = info.roundChairAssignments[entry.key];
              final question = assignment == null ? null : _chairQuestionFor(info.roundIndex, assignment);
              final survived = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: (survived ? AppColors.play : AppColors.danger).withAlpha(30),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: (survived ? AppColors.play : AppColors.danger).withAlpha(140)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(survived ? '✅' : '⚡', style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(player?.name ?? '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                        ),
                        Text(
                          survived ? tr('A SCĂPAT', 'SURVIVED') : tr('-1 VIAȚĂ', '-1 LIFE'),
                          style: TextStyle(
                              color: survived ? AppColors.play : AppColors.danger, fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ],
                    ),
                    if (question != null) ...[
                      const SizedBox(height: 6),
                      Text('${question.question}  →  ${question.answer}',
                          style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _CountdownBar extends StatelessWidget {
  final int seconds;
  final int total;
  final Color color;
  const _CountdownBar({required this.seconds, required this.total, required this.color});

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : (seconds / total).clamp(0, 1).toDouble();
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: Colors.white.withAlpha(20),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('${seconds}s', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
      ],
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final String text;
  final Color accent;
  const _QuestionCard({required this.text, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withAlpha(120)),
      ),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.3)),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool selected;
  final bool danger;
  /// Toggle-ul de admin „vezi răspunsul corect" — conturează varianta corectă
  /// cu chihlimbar. Pur vizual (core/admin_reveal.dart).
  final bool adminHint;
  const _AnswerButton({required this.text, required this.onTap, this.selected = false, this.danger = false, this.adminHint = false});

  @override
  Widget build(BuildContext context) {
    final accent = adminHint && !selected ? adminRevealColor : (danger ? AppColors.danger : AppColors.coin);
    final showAccent = selected || adminHint;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: showAccent ? accent.withAlpha(60) : Colors.white.withAlpha(15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: showAccent ? accent : Colors.white24, width: adminHint && !selected ? 2.2 : 1),
          ),
          child: Text(text, style: TextStyle(color: onTap == null && !selected ? Colors.white38 : Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ),
    );
  }
}

class _TargetTile extends StatelessWidget {
  final MatchPlayer player;
  final VoidCallback onTap;
  const _TargetTile({required this.player, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.danger.withAlpha(100)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(player.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              Icon(Icons.bolt_rounded, color: AppColors.danger, size: 14),
              Text(' ${player.lives}', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionPickTile extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _QuestionPickTile({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.coin.withAlpha(110)),
          ),
          child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13, height: 1.25)),
        ),
      ),
    );
  }
}
