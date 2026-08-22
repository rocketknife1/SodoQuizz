import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/astrosodo.dart';
import '../../core/lang.dart';
import '../../core/stable_hash.dart';
import '../../core/theme.dart';
import '../../data/culture_questions.dart';
import '../../data/multiplayer_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/avatar.dart';
import '../../widgets/countdown_ring.dart';
import 'multiplayer_results_screen.dart';

/// **Astro Sodo** — de la 2 la 6 nave, fiecare pe culoarul ei presărat cu
/// [astroSodoObstacleCount] bolovani de asteroid. Toți jucătorii văd
/// aceeași întrebare de cultură generală pe rundă; cine răspunde corect
/// își trece nava peste bolovanul din față. Regulile stau în
/// core/astrosodo.dart, rezolvarea rundei în
/// MultiplayerService.resolveAstroSodoRound.
///
/// Ca la Higher & Lower și Quizz Tanks: ecranul ăsta nu decide nimic. Are
/// local doar pool-ul de întrebări (amestecat determinist din `matchId`,
/// vezi core/stable_hash.dart), citește rezultatul rundei din Firestore și
/// îl animează. ORICE client poate cere rezolvarea rundei — meciul nu are
/// voie să se blocheze dacă pleacă tocmai gazda.
class MultiplayerAstroSodoScreen extends StatefulWidget {
  final String matchId;
  const MultiplayerAstroSodoScreen({super.key, required this.matchId});

  @override
  State<MultiplayerAstroSodoScreen> createState() => _MultiplayerAstroSodoScreenState();
}

class _MultiplayerAstroSodoScreenState extends State<MultiplayerAstroSodoScreen> {
  late final List<CultureQuestion> _pool = _buildPool();

  late final Stream<MatchInfo> _matchStream = MultiplayerService.instance.watchMatch(widget.matchId);
  late final Stream<List<MatchPlayer>> _playersStream = MultiplayerService.instance.watchPlayers(widget.matchId);

  int _lastRoundIndex = -1;
  bool _showAdvance = false;
  bool _resolving = false;
  bool _navigatedToResults = false;
  bool _left = false;
  Timer? _revealDelayTimer;
  Timer? _advanceTimer;
  Timer? _tickTimer;
  Timer? _heartbeatTimer;

  List<String>? _cachedChoices;
  int _cachedChoicesRound = -1;

  List<CultureQuestion> _buildPool() {
    final pool = List.of(cultureQuestions);
    stableShuffle(pool, stableHash(widget.matchId));
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

  @override
  void initState() {
    super.initState();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _heartbeatTimer = Timer.periodic(MultiplayerService.matchHeartbeatInterval, (_) {
      MultiplayerService.instance.matchHeartbeat(widget.matchId);
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _revealDelayTimer?.cancel();
    _advanceTimer?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  int _secondsLeftFor(MatchInfo info) {
    final started = info.roundStartedAt?.toDate();
    if (started == null) return astroSodoRoundSeconds;
    final elapsed = DateTime.now().difference(started).inSeconds;
    return (astroSodoRoundSeconds - elapsed).clamp(0, astroSodoRoundSeconds);
  }

  Future<void> _leave() async {
    if (_left) return;
    _left = true;
    try {
      await MultiplayerService.instance.leaveMatch(widget.matchId);
    } catch (e) {
      debugPrint('MultiplayerAstroSodoScreen._leave: leaveMatch a esuat: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  void _selectAnswer(MatchInfo info, MatchPlayer? myPlayer, String answer) {
    if (info.roundPhase != RoundPhase.answering) return;
    if (myPlayer == null || myPlayer.obstaclesCleared >= astroSodoObstacleCount) return;
    final me = MultiplayerService.instance.currentPlayerId;
    if (info.roundAnswers.containsKey(me)) return;
    MultiplayerService.instance.submitRoundAnswer(matchId: widget.matchId, answer: answer);
  }

  Future<void> _tryResolve(MatchInfo info) async {
    if (_resolving) return;
    _resolving = true;
    try {
      await MultiplayerService.instance.resolveAstroSodoRound(
        matchId: widget.matchId,
        roundIndex: info.roundIndex,
        correctAnswer: _questionFor(info.roundIndex).answer,
      );
    } finally {
      _resolving = false;
    }
  }

  void _onData(MatchInfo info, List<MatchPlayer> players) {
    if (info.roundIndex != _lastRoundIndex) {
      _lastRoundIndex = info.roundIndex;
      _showAdvance = false;
      _revealDelayTimer?.cancel();
      _revealDelayTimer = null;
      _advanceTimer?.cancel();
      _advanceTimer = null;
    }

    if (info.roundPhase == RoundPhase.answering) {
      final activeIds = players.where((p) => p.obstaclesCleared < astroSodoObstacleCount).map((p) => p.id).toSet();
      final allAnswered = activeIds.isNotEmpty && activeIds.every(info.roundAnswers.containsKey);
      final timedOut = _secondsLeftFor(info) <= 0;
      if (allAnswered || timedOut) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryResolve(info));
      }
    } else if (info.roundPhase == RoundPhase.revealed) {
      _revealDelayTimer ??= Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _showAdvance = true);
      });
      _advanceTimer ??= Timer(const Duration(seconds: astroSodoRevealSeconds), () {
        MultiplayerService.instance.advanceSyncRound(matchId: widget.matchId, roundIndex: info.roundIndex);
      });
    }

    if (info.status == MatchStatus.finished && !_navigatedToResults) {
      _navigatedToResults = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MultiplayerResultsScreen(matchId: widget.matchId, gameMode: MatchGameMode.astroSodo),
          ),
        );
      });
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
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.spaceGradient),
          child: SafeArea(
            child: StreamBuilder<MatchInfo>(
              stream: _matchStream,
              builder: (context, matchSnap) {
                final info = matchSnap.data;
                if (info == null) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.teal));
                }
                return StreamBuilder<List<MatchPlayer>>(
                  stream: _playersStream,
                  builder: (context, playersSnap) {
                    final players = playersSnap.data ?? const <MatchPlayer>[];
                    _onData(info, players);
                    final me = MultiplayerService.instance.currentPlayerId;
                    MatchPlayer? myPlayer;
                    for (final p in players) {
                      if (p.id == me) {
                        myPlayer = p;
                        break;
                      }
                    }
                    final revealed = info.roundPhase == RoundPhase.revealed;
                    return Column(
                      children: [
                        _buildTopBar(info),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            child: Column(
                              children: [
                                _buildTrack(players, revealed && _showAdvance ? info.roundWinnerIds : const []),
                                const SizedBox(height: 14),
                                _buildQuestion(info),
                                const SizedBox(height: 14),
                                _buildActionArea(info, myPlayer, players),
                              ],
                            ),
                          ),
                        ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 4),
      child: Row(
        children: [
          IconButton(onPressed: _leave, icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70)),
          const SizedBox(width: 4),
          const Text('Astro Sodo', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text(
            tr('Runda ${(info.roundIndex + 1).clamp(1, astroSodoObstacleCount)}/$astroSodoObstacleCount',
                'Round ${(info.roundIndex + 1).clamp(1, astroSodoObstacleCount)}/$astroSodoObstacleCount'),
            style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  /// Culoarele cursei — un rând pe jucător, cu bolovanii rămași și nava în
  /// poziția ei curentă. [justAdvanced] arată, pentru o clipă, care nave au
  /// trecut peste un bolovan chiar în runda tocmai rezolvată.
  Widget _buildTrack(List<MatchPlayer> players, List<String> justAdvanced) {
    return Column(
      children: [for (final p in players) _buildLane(p, justAdvanced.contains(p.id))],
    );
  }

  Widget _buildLane(MatchPlayer p, bool justAdvanced) {
    final cleared = p.obstaclesCleared.clamp(0, astroSodoObstacleCount);
    final finished = cleared >= astroSodoObstacleCount;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: finished ? AppColors.teal.withAlpha(45) : Colors.white.withAlpha(14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: finished ? AppColors.teal : (justAdvanced ? AppColors.play : Colors.white24)),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Avatar(size: 34, label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?', accentColor: pickAvatarColor(p.avatarSeed), photoUrl: p.photoUrl, style: avatarStyleFromId(p.avatarStyle)),
              if (finished)
                const Positioned(
                  right: -2,
                  bottom: -2,
                  child: Text('🏆', style: TextStyle(fontSize: 14)),
                ),
            ],
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // pozitia navei alunecă între bolovanul de dinainte și cel
                // trecut de curând - AnimatedAlign face avansul o mișcare,
                // nu un salt brusc între cadre.
                final progress = cleared / astroSodoObstacleCount;
                return SizedBox(
                  height: 30,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (var i = 0; i < astroSodoObstacleCount; i++)
                            Opacity(
                              opacity: i < cleared ? 0.25 : 1,
                              child: Text(i < cleared ? '·' : '🪨', style: const TextStyle(fontSize: 13)),
                            ),
                        ],
                      ),
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment(-1 + 2 * progress, 0),
                        child: const Text('🚀', style: TextStyle(fontSize: 20)),
                      ),
                      const Align(alignment: Alignment.centerRight, child: Text('🏁', style: TextStyle(fontSize: 16))),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          Text('$cleared/$astroSodoObstacleCount', style: const TextStyle(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildQuestion(MatchInfo info) {
    final question = _questionFor(info.roundIndex);
    final revealed = info.roundPhase == RoundPhase.revealed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(16),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24, width: 1.4),
      ),
      child: Column(
        children: [
          if (info.roundPhase == RoundPhase.answering)
            CountdownRing(secondsLeft: _secondsLeftFor(info), totalSeconds: astroSodoRoundSeconds, size: 40)
          else
            const Icon(Icons.rocket_launch_rounded, color: AppColors.teal, size: 32),
          const SizedBox(height: 10),
          Text(
            question.question,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          if (revealed) ...[
            const SizedBox(height: 8),
            Text(
              tr('Răspuns corect: ${question.answer}', 'Correct answer: ${question.answer}'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.teal, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionArea(MatchInfo info, MatchPlayer? myPlayer, List<MatchPlayer> players) {
    if (myPlayer == null) return const SizedBox(height: 90);

    if (myPlayer.obstaclesCleared >= astroSodoObstacleCount) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(color: Colors.white.withAlpha(14), borderRadius: BorderRadius.circular(16)),
        child: Text(
          tr('🏁 Nava ta a ajuns la final! Aștepți restul cursei.',
              '🏁 Your ship reached the finish! Waiting for the rest of the race.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
    }

    if (info.roundPhase == RoundPhase.revealed) {
      if (!_showAdvance) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
        );
      }
      final advancedNames = players.where((p) => info.roundWinnerIds.contains(p.id)).map((p) => p.name).join(', ');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          advancedNames.isEmpty
              ? tr('Niciun bolovan trecut de data asta!', 'No boulder cleared this time!')
              : tr('Au avansat: $advancedNames', 'Advanced: $advancedNames'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
        ),
      );
    }

    final me = MultiplayerService.instance.currentPlayerId;
    if (info.roundAnswers.containsKey(me)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('✓ Ai răspuns! Se așteaptă ceilalți piloți...', style: TextStyle(color: AppColors.play, fontSize: 14, fontWeight: FontWeight.w700)),
      );
    }

    final choices = _choicesFor(info.roundIndex);
    return Column(
      children: [
        for (var i = 0; i < choices.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(child: _choiceButton(choices[i], () => _selectAnswer(info, myPlayer, choices[i]))),
                if (i + 1 < choices.length) ...[
                  const SizedBox(width: 10),
                  Expanded(child: _choiceButton(choices[i + 1], () => _selectAnswer(info, myPlayer, choices[i + 1]))),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _choiceButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.teal.withAlpha(35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.teal, width: 1.4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
