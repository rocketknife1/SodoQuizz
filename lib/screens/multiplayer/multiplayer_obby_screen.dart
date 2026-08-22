import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../core/obby.dart';
import '../../core/stable_hash.dart';
import '../../core/theme.dart';
import '../../data/culture_questions.dart';
import '../../data/multiplayer_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/countdown_ring.dart';
import 'multiplayer_results_screen.dart';

/// **Obby** — cursă de obstacole tip Roblox, de la 2 la 6 personaje pe
/// aceeași pistă. Aceeași arhitectură de sincronizare ca Astro Sodo (vezi
/// MultiplayerAstroSodoScreen și core/obby.dart): ecranul nu decide nimic,
/// citește rezultatul rundei din Firestore și îl animează. ORICE client
/// poate cere rezolvarea rundei.
///
/// Diferența e doar vizuală: în [RoundPhase.answering] fiecare jucător își
/// vede propriul personaj într-un colț, așteptând; în [RoundPhase.revealed]
/// camera trece la 3rd-person (ca CJ din San Andreas) și arată toată pista,
/// cu personajele care au răspuns corect sărind peste obstacolul din față.
class MultiplayerObbyScreen extends StatefulWidget {
  final String matchId;
  const MultiplayerObbyScreen({super.key, required this.matchId});

  @override
  State<MultiplayerObbyScreen> createState() => _MultiplayerObbyScreenState();
}

class _MultiplayerObbyScreenState extends State<MultiplayerObbyScreen> with SingleTickerProviderStateMixin {
  late final List<CultureQuestion> _pool = _buildPool();

  late final Stream<MatchInfo> _matchStream = MultiplayerService.instance.watchMatch(widget.matchId);
  late final Stream<List<MatchPlayer>> _playersStream = MultiplayerService.instance.watchPlayers(widget.matchId);

  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  int _lastRoundIndex = -1;
  bool _showAdvance = false;
  bool _resolving = false;
  bool _resolvingChoices = false;
  bool _navigatedToResults = false;
  bool _left = false;
  Timer? _revealDelayTimer;
  Timer? _advanceTimer;
  Timer? _tickTimer;
  Timer? _heartbeatTimer;
  DateTime? _revealedAtLocal;

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
    _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
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
    _anim.dispose();
    super.dispose();
  }

  int _secondsLeftFor(MatchInfo info) {
    final started = info.roundStartedAt?.toDate();
    if (started == null) return obbyRoundSeconds;
    final elapsed = DateTime.now().difference(started).inSeconds;
    return (obbyRoundSeconds - elapsed).clamp(0, obbyRoundSeconds);
  }

  /// Cronometrul fazei de alegere. `roundStartedAt` e REPORNIT de
  /// [MultiplayerService.closeObbyAnswering] când începe faza, deci se măsoară
  /// de acolo, nu de la începutul rundei — la fel ca faza de țintire de la
  /// Quizz Tanks.
  int _choiceSecondsLeftFor(MatchInfo info) {
    final started = info.roundStartedAt?.toDate();
    if (started == null) return obbyChoiceSeconds;
    final elapsed = DateTime.now().difference(started).inSeconds;
    return (obbyChoiceSeconds - elapsed).clamp(0, obbyChoiceSeconds);
  }

  Future<void> _leave() async {
    if (_left) return;
    _left = true;
    try {
      await MultiplayerService.instance.leaveMatch(widget.matchId);
    } catch (e) {
      debugPrint('MultiplayerObbyScreen._leave: leaveMatch a esuat: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  void _selectAnswer(MatchInfo info, MatchPlayer? myPlayer, String answer) {
    if (info.roundPhase != RoundPhase.answering) return;
    if (myPlayer == null || myPlayer.obstaclesCleared >= obbyObstacleCount) return;
    final me = MultiplayerService.instance.currentPlayerId;
    if (info.roundAnswers.containsKey(me)) return;
    MultiplayerService.instance.submitRoundAnswer(matchId: widget.matchId, answer: answer);
  }

  /// Închide faza de răspuns. Nu mai acordă progres direct: cine a răspuns
  /// corect intră în faza de alegere a plăcii (vezi [_tryResolveChoices]).
  Future<void> _tryResolve(MatchInfo info) async {
    if (_resolving) return;
    _resolving = true;
    try {
      await MultiplayerService.instance.closeObbyAnswering(
        matchId: widget.matchId,
        roundIndex: info.roundIndex,
        correctAnswer: _questionFor(info.roundIndex).answer,
      );
    } finally {
      _resolving = false;
    }
  }

  /// Închide faza de alegere — abia aici se acordă (sau nu) progresul.
  Future<void> _tryResolveChoices(MatchInfo info) async {
    if (_resolvingChoices) return;
    _resolvingChoices = true;
    try {
      await MultiplayerService.instance.resolveObbyChoices(
        matchId: widget.matchId,
        roundIndex: info.roundIndex,
      );
    } finally {
      _resolvingChoices = false;
    }
  }

  /// Placa aleasă de mine. O singură dată pe rundă — a doua apăsare nu mai
  /// trimite nimic, la fel ca la alegerea țintei din Quizz Tanks.
  void _choosePlatform(MatchInfo info, int index) {
    if (info.roundPhase != RoundPhase.choosing) return;
    final me = MultiplayerService.instance.currentPlayerId;
    if (!info.roundWinnerIds.contains(me)) return;
    if (info.roundPlatformChoices.containsKey(me)) return;
    MultiplayerService.instance.submitObbyChoice(matchId: widget.matchId, platformIndex: index);
  }

  void _onData(MatchInfo info, List<MatchPlayer> players) {
    if (info.roundIndex != _lastRoundIndex) {
      _lastRoundIndex = info.roundIndex;
      _showAdvance = false;
      _revealedAtLocal = null;
      _revealDelayTimer?.cancel();
      _revealDelayTimer = null;
      _advanceTimer?.cancel();
      _advanceTimer = null;
    }

    if (info.roundPhase == RoundPhase.answering) {
      final activeIds = players.where((p) => p.obstaclesCleared < obbyObstacleCount).map((p) => p.id).toSet();
      final allAnswered = activeIds.isNotEmpty && activeIds.every(info.roundAnswers.containsKey);
      final timedOut = _secondsLeftFor(info) <= 0;
      if (allAnswered || timedOut) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryResolve(info));
      }
    } else if (info.roundPhase == RoundPhase.choosing) {
      // Aceeași regulă ca la răspuns: se închide fie când au ales toți cei
      // care aveau dreptul, fie când li s-a scurs timpul. Cine a plecat din
      // meci între timp nu blochează runda — se numără doar cei încă la
      // masă, exact ca la țintirea din Quizz Tanks.
      final present = players.map((p) => p.id).toSet();
      final choosers = info.roundWinnerIds.where(present.contains);
      final allChose = choosers.isNotEmpty && choosers.every(info.roundPlatformChoices.containsKey);
      if (allChose || _choiceSecondsLeftFor(info) <= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryResolveChoices(info));
      }
    } else if (info.roundPhase == RoundPhase.revealed) {
      _revealedAtLocal ??= DateTime.now();
      _revealDelayTimer ??= Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _showAdvance = true);
      });
      // Doar dacă meciul CONTINUĂ: la ultima rundă, o cerere de avansare ar
      // porni degeaba o rundă nouă într-un meci deja încheiat, exact în clipa
      // în care toată lumea pleacă spre clasament (aceeași gardă ca la Quizz
      // Tanks).
      if (info.status != MatchStatus.finished) {
        _advanceTimer ??= Timer(const Duration(seconds: obbyRevealSeconds), () {
          MultiplayerService.instance.advanceObbyRound(matchId: widget.matchId, roundIndex: info.roundIndex);
        });
      }
    }

    if (info.status == MatchStatus.finished && !_navigatedToResults) {
      _navigatedToResults = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MultiplayerResultsScreen(matchId: widget.matchId, gameMode: MatchGameMode.obby),
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
        body: SafeArea(
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
                  return Column(
                    children: [
                      _buildTopBar(info),
                      Expanded(
                        child: switch (info.roundPhase) {
                          RoundPhase.revealed => _buildRaceScene(info, players, myPlayer),
                          RoundPhase.choosing => _buildChoosingScene(info),
                          _ => _buildAnsweringScene(info, myPlayer, players),
                        },
                      ),
                    ],
                  );
                },
              );
            },
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
          const Text('Obby', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text(
            tr('Runda ${(info.roundIndex + 1).clamp(1, obbyObstacleCount)}/$obbyObstacleCount',
                'Round ${(info.roundIndex + 1).clamp(1, obbyObstacleCount)}/$obbyObstacleCount'),
            style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // ─── Faza de răspuns: întrebare + propriul personaj într-un colț ────────

  Widget _buildAnsweringScene(MatchInfo info, MatchPlayer? myPlayer, List<MatchPlayer> players) {
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              children: [
                const SizedBox(height: 96),
                _buildQuestion(info),
                const SizedBox(height: 14),
                _buildActionArea(info, myPlayer, players),
              ],
            ),
          ),
        ),
        if (myPlayer != null)
          Positioned(
            top: 4,
            right: 12,
            child: AnimatedBuilder(
              animation: _anim,
              builder: (context, _) => _CornerCharacter(
                color: pickAvatarColor(myPlayer.avatarSeed),
                bob: sin(_anim.value * 2 * pi),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildQuestion(MatchInfo info) {
    final question = _questionFor(info.roundIndex);
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
          CountdownRing(secondsLeft: _secondsLeftFor(info), totalSeconds: obbyRoundSeconds, size: 40),
          const SizedBox(height: 10),
          Text(
            question.question,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildActionArea(MatchInfo info, MatchPlayer? myPlayer, List<MatchPlayer> players) {
    if (myPlayer == null) return const SizedBox(height: 90);

    if (myPlayer.obstaclesCleared >= obbyObstacleCount) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(color: Colors.white.withAlpha(14), borderRadius: BorderRadius.circular(16)),
        child: Text(
          tr('🏁 Personajul tău a ajuns la final! Aștepți restul cursei.',
              '🏁 Your character reached the finish! Waiting for the rest of the race.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
    }

    final me = MultiplayerService.instance.currentPlayerId;
    if (info.roundAnswers.containsKey(me)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('✓ Ai răspuns! Se așteaptă ceilalți concurenți...', style: TextStyle(color: AppColors.play, fontSize: 14, fontWeight: FontWeight.w700)),
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

  // ─── Faza de alegere a plăcii ───────────────────────────────────────────
  // PROVIZORIU (etapa 1): butoane simple. Se înlocuiesc cu plăci desenate în
  // scena Flame + joystick la etapa 3, dar rămân ca variantă de rezervă
  // (tap direct), nu se aruncă.

  Widget _buildChoosingScene(MatchInfo info) {
    final me = MultiplayerService.instance.currentPlayerId;
    final amChooser = info.roundWinnerIds.contains(me);
    final myChoice = info.roundPlatformChoices[me];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        children: [
          CountdownRing(
            secondsLeft: _choiceSecondsLeftFor(info),
            totalSeconds: obbyChoiceSeconds,
            size: 40,
          ),
          const SizedBox(height: 16),
          Text(
            amChooser
                ? tr('Ai răspuns corect! Pe ce placă sari?', 'Correct! Which platform do you jump on?')
                : tr('Ceilalți își aleg placa...', 'The others are picking their platform...'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (amChooser)
            Text(
              tr('Una din ele e falsă și cazi prin ea. Nimerești bine → la întrebarea următoare vezi doar 2 variante.',
                  'One of them is fake and you fall through. Land safely → next question shows only 2 options.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.35),
            ),
          const SizedBox(height: 22),
          if (amChooser)
            Row(
              children: [
                for (var i = 0; i < obbyPlatformChoiceCount; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: _platformButton(
                      index: i,
                      selected: myChoice == i,
                      locked: myChoice != null,
                      onTap: () => _choosePlatform(info, i),
                    ),
                  ),
                ],
              ],
            ),
          if (amChooser && myChoice != null) ...[
            const SizedBox(height: 16),
            Text(
              tr('✓ Ai sărit! Se așteaptă ceilalți...', '✓ You jumped! Waiting for the others...'),
              style: const TextStyle(color: AppColors.play, fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _platformButton({
    required int index,
    required bool selected,
    required bool locked,
    required VoidCallback onTap,
  }) {
    // stânga/centru/dreapta, în ordinea în care vor sta și plăcile în scenă
    const labels = ['◀', '▲', '▶'];
    final color = selected ? AppColors.play : AppColors.teal;
    return GestureDetector(
      onTap: locked ? null : onTap,
      child: Opacity(
        opacity: locked && !selected ? 0.35 : 1,
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            color: color.withAlpha(selected ? 60 : 30),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color, width: selected ? 2.4 : 1.4),
          ),
          alignment: Alignment.center,
          child: Text(
            labels[index % labels.length],
            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  // ─── Faza de reveal: cameră 3rd-person pe toată pista ───────────────────

  /// A trecut jucătorul [id] obstacolul în runda tocmai încheiată?
  ///
  /// NU e totuna cu „e în [MatchInfo.roundWinnerIds]": lista aia înseamnă
  /// acum doar „a răspuns corect, deci a avut dreptul să aleagă o placă".
  /// Cine a nimerit placa falsă (sau n-a ales deloc) e tot acolo, dar a
  /// căzut. Se recalculează local, identic pe toate telefoanele — de-asta nu
  /// e nevoie de niciun câmp în plus în Firestore, vezi core/obby.dart.
  bool _advancedThisRound(MatchInfo info, String id) {
    if (!info.roundWinnerIds.contains(id)) return false;
    return obbyChoiceIsSafe(
      chosenIndex: info.roundPlatformChoices[id],
      fakeIndex: obbyFakePlatformIndex(
        matchId: widget.matchId,
        roundIndex: info.roundIndex,
        playerId: id,
      ),
    );
  }

  /// Textul de sub scenă: întâi ce am pățit EU (ăsta e ce caută ochiul), apoi
  /// cine a mai trecut obstacolul.
  String _revealSummary(MatchInfo info, List<MatchPlayer> players) {
    final me = MultiplayerService.instance.currentPlayerId;
    if (info.roundWinnerIds.contains(me)) {
      if (_advancedThisRound(info, me)) {
        return tr('✓ Placa a ținut! Bonus la întrebarea următoare.',
            '✓ The platform held! Bonus on the next question.');
      }
      return info.roundPlatformChoices.containsKey(me)
          ? tr('✗ Placa era falsă — ai căzut prin ea.', '✗ That platform was fake — you fell through.')
          : tr('✗ N-ai ales nicio placă la timp.', "✗ You didn't pick a platform in time.");
    }

    final advanced = players.where((p) => _advancedThisRound(info, p.id)).map((p) => p.name).toList();
    if (advanced.isEmpty) {
      return tr('Niciun obstacol trecut de data asta!', 'No obstacle cleared this time!');
    }
    return tr('Au trecut: ${advanced.join(', ')}', 'Cleared it: ${advanced.join(', ')}');
  }

  Widget _buildRaceScene(MatchInfo info, List<MatchPlayer> players, MatchPlayer? myPlayer) {
    final elapsed = _revealedAtLocal == null ? 0.0 : DateTime.now().difference(_revealedAtLocal!).inMilliseconds / 1000.0;
    final jumpT = (elapsed / max(obbyRevealSeconds - 0.6, 0.4)).clamp(0.0, 1.0);
    final racers = [
      for (var i = 0; i < players.length; i++)
        _Racer(
          id: players[i].id,
          name: players[i].name,
          color: pickAvatarColor(players[i].avatarSeed),
          progress: (players[i].obstaclesCleared / obbyObstacleCount).clamp(0.0, 1.0),
          lane: players.length <= 1 ? 0.5 : i / (players.length - 1),
          justJumped: _advancedThisRound(info, players[i].id),
          isMe: players[i].id == MultiplayerService.instance.currentPlayerId,
        ),
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _ObbyScenePainter(racers: racers, jumpT: jumpT)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: Center(
            child: !_showAdvance
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(color: Colors.black.withAlpha(140), borderRadius: BorderRadius.circular(14)),
                    child: Text(
                      _revealSummary(info, players),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Datele minime necesare ca [_ObbyScenePainter] să deseneze un personaj pe
/// pistă — extrase din [MatchPlayer] o singură dată per cadru, ca painter-ul
/// să nu depindă de restul modelului.
class _Racer {
  final String id;
  final String name;
  final Color color;
  final double progress; // 0..1, cât din pistă a trecut
  final double lane; // 0..1, poziția lui pe lățimea pistei
  final bool justJumped;
  final bool isMe;

  const _Racer({
    required this.id,
    required this.name,
    required this.color,
    required this.progress,
    required this.lane,
    required this.justJumped,
    required this.isMe,
  });
}

/// Personajul din colțul ecranului, cât timp jucătorul răspunde — o siluetă
/// simplă (cap + corp), care abia se leagănă (idle), ca ecranul să nu pară
/// static în timp ce se așteaptă răspunsul.
class _CornerCharacter extends StatelessWidget {
  final Color color;
  final double bob; // -1..1

  const _CornerCharacter({required this.color, required this.bob});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 92,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(90),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24, width: 1.2),
      ),
      child: CustomPaint(painter: _SilhouettePainter(color: color, bob: bob)),
    );
  }
}

/// Desenul unei siluete simple (cap rotund + corp capsulă + două picioare) —
/// aceeași formă e refolosită atât pentru personajul din colț cât și pentru
/// alergătorii de pe pistă, doar la scări diferite.
void paintObbySilhouette(Canvas canvas, Rect bounds, Color color, {double legSpread = 0, double crouch = 0}) {
  final w = bounds.width;
  final h = bounds.height;
  final cx = bounds.center.dx;
  final top = bounds.top + h * crouch * 0.15;

  final bodyPaint = Paint()..color = color;
  final headR = w * 0.22;
  final headCy = top + headR * 1.1;
  canvas.drawCircle(Offset(cx, headCy), headR, bodyPaint);

  final bodyTop = headCy + headR * 0.75;
  final bodyBottom = bounds.bottom - h * 0.22 + crouch * h * 0.08;
  final bodyRect = RRect.fromRectAndRadius(
    Rect.fromLTRB(cx - w * 0.20, bodyTop, cx + w * 0.20, bodyBottom),
    Radius.circular(w * 0.16),
  );
  canvas.drawRRect(bodyRect, bodyPaint);

  final legPaint = Paint()
    ..color = color
    ..strokeWidth = w * 0.13
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(
    Offset(cx - w * 0.06, bodyBottom - h * 0.02),
    Offset(cx - w * 0.06 - legSpread * w * 0.22, bounds.bottom),
    legPaint,
  );
  canvas.drawLine(
    Offset(cx + w * 0.06, bodyBottom - h * 0.02),
    Offset(cx + w * 0.06 + legSpread * w * 0.22, bounds.bottom),
    legPaint,
  );
}

class _SilhouettePainter extends CustomPainter {
  final Color color;
  final double bob;
  const _SilhouettePainter({required this.color, required this.bob});

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(0, bob.abs() * -2, size.width, size.height - 4);
    paintObbySilhouette(canvas, bounds, color, legSpread: bob * 0.4);
  }

  @override
  bool shouldRepaint(covariant _SilhouettePainter oldDelegate) => oldDelegate.bob != bob || oldDelegate.color != color;
}

/// Scena de 3rd-person a pistei — o pistă în perspectivă, cu linia de sosire
/// la orizont, pe care alergătorii avansează dinspre camera (jos, mare) spre
/// finish (sus, mic). Cine tocmai a răspuns corect ([_Racer.justJumped])
/// sare, cu un arc simplu, peste obstacolul curent.
class _ObbyScenePainter extends CustomPainter {
  final List<_Racer> racers;
  final double jumpT; // 0..1, cât de avansată e animația de săritură a rundei curente

  const _ObbyScenePainter({required this.racers, required this.jumpT});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizon = h * 0.30;

    // cerul
    final skyRect = Rect.fromLTWH(0, 0, w, horizon);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E1330), Color(0xFF232A52), Color(0xFF3E4A82)],
        ).createShader(skyRect),
    );

    // pista în perspectivă: două margini care converg spre punctul de fugă
    final vp = Offset(w / 2, horizon);
    final groundRect = Rect.fromLTRB(0, horizon, w, h);
    canvas.drawRect(
      groundRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C6E5B), Color(0xFF163826)],
        ).createShader(groundRect),
    );

    final railPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withAlpha(70);
    canvas.drawLine(vp, Offset(w * 0.06, h), railPaint);
    canvas.drawLine(vp, Offset(w * 0.94, h), railPaint);

    // marcaje transversale, una pe fiecare obstacol al pistei
    final markPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withAlpha(50);
    for (var i = 1; i <= obbyObstacleCount; i++) {
      final depth = i / obbyObstacleCount;
      final y = horizon + (h - horizon) * (1 - depth) * (1 - depth);
      final spread = 0.06 + (1 - depth) * 0.88;
      canvas.drawLine(Offset(w * (0.5 - spread / 2), y), Offset(w * (0.5 + spread / 2), y), markPaint);
    }

    // linia de sosire, chiar la orizont
    _paintFinishBanner(canvas, size, vp);

    // alergătorii, ordonați ca cei "din spate" (aproape de cameră) să se
    // deseneze peste cei "din față" (spre orizont) — perspectivă corectă.
    final sorted = List.of(racers)..sort((a, b) => a.progress.compareTo(b.progress));
    for (final r in sorted.reversed) {
      _paintRacer(canvas, size, vp, r);
    }
  }

  void _paintFinishBanner(Canvas canvas, Size size, Offset vp) {
    final w = size.width * 0.22;
    final rect = Rect.fromCenter(center: vp - const Offset(0, 6), width: w, height: 10);
    final paint = Paint()..color = Colors.white.withAlpha(230);
    canvas.drawRect(rect, paint);
    const stripes = 8;
    final stripeW = w / stripes;
    final blackPaint = Paint()..color = Colors.black.withAlpha(220);
    for (var i = 0; i < stripes; i++) {
      if (i.isEven) continue;
      canvas.drawRect(Rect.fromLTWH(rect.left + i * stripeW, rect.top, stripeW, rect.height), blackPaint);
    }
  }

  void _paintRacer(Canvas canvas, Size size, Offset vp, _Racer r) {
    final w = size.width;
    final h = size.height;
    // depth: 0 = start (aproape de cameră, jos, mare), 1 = finish (la orizont, mic)
    final depth = Curves.easeOutCubic.transform(r.progress);
    final y = vp.dy + (h - vp.dy) * (1 - depth) * (1 - depth) + (h * 0.02);
    final scale = (1 - depth) * 0.85 + 0.15;
    final laneSpread = w * 0.30 * scale;
    final x = w / 2 + (r.lane - 0.5) * laneSpread * 2 + (vp.dx - w / 2) * depth;

    // arcul de săritură: doar cel/cei care tocmai au răspuns corect
    var jumpLift = 0.0;
    if (r.justJumped) {
      jumpLift = sin(jumpT.clamp(0.0, 1.0) * pi) * scale * 46;
    }

    final bodyW = 40 * scale;
    final bodyH = 58 * scale;
    final bounds = Rect.fromCenter(center: Offset(x, y - bodyH / 2 - jumpLift), width: bodyW, height: bodyH);

    // umbra rămâne pe sol, ca săritura să se vadă că e „în aer", nu doar
    // personajul mutat mai sus.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y), width: bodyW * 0.8, height: bodyW * 0.28),
      Paint()..color = Colors.black.withAlpha((90 * scale).round().clamp(0, 90)),
    );

    paintObbySilhouette(canvas, bounds, r.color, legSpread: jumpLift > 1 ? 0.6 : 0.15);

    if (scale > 0.35) {
      final tp = TextPainter(
        text: TextSpan(
          text: r.name,
          style: TextStyle(color: Colors.white, fontSize: (12 * scale).clamp(8, 12), fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 90);
      tp.paint(canvas, Offset(x - tp.width / 2, bounds.top - tp.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ObbyScenePainter oldDelegate) => true;
}
