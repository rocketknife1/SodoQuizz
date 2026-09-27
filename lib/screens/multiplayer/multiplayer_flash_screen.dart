import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio.dart';
import '../../core/flash_game.dart';
import '../../core/lang.dart';
import '../../core/stable_hash.dart';
import '../../core/theme.dart';
import '../../data/bot_match.dart';
import '../../data/multiplayer_service.dart';
import '../../data/questions.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/avatar.dart';
import '../../widgets/match_overlay.dart';
import 'multiplayer_results_screen.dart';

/// **Fulgerul** — memorie, nu cunoștințe (regulile: core/flash_game.dart).
/// O grilă de poze apare pentru o clipă, apoi se acoperă; întrebarea e
/// „Unde era X?" și răspunzi atingând căsuța unde ai văzut-o. Grila crește
/// și timpul de afișare scade rundă de rundă.
///
/// CE FACE ECRANUL ĂSTA ȘI CE NU: grila fiecărei runde e calculată LOCAL,
/// identic pe orice telefon (același pool de poze + aceeași sămânță — vezi
/// [FlashGame.gridFor]); rezolvarea (cine a nimerit) o face orice client prin
/// [MultiplayerService.closeFlashRound], care primește indexul corect deja
/// calculat, exact ca [MultiplayerService.closeTanksAnswering].
class MultiplayerFlashScreen extends StatefulWidget {
  final String matchId;

  /// Meci cu boți (data/bot_match.dart) — null într-un meci online normal.
  final BotMatch? bot;

  const MultiplayerFlashScreen({super.key, required this.matchId, this.bot});

  @override
  State<MultiplayerFlashScreen> createState() => _MultiplayerFlashScreenState();
}

class _MultiplayerFlashScreenState extends State<MultiplayerFlashScreen> {
  MultiplayerService get _mp => widget.bot?.service ?? MultiplayerService.instance;

  late final Stream<MatchInfo> _matchStream = _mp.watchMatch(widget.matchId);
  late final Stream<List<MatchPlayer>> _playersStream = _mp.watchPlayers(widget.matchId);

  List<FlashPic> _pics = const [];
  bool _ready = false;

  FlashRound? _cachedRound;
  int _cachedRoundIndex = -1;

  int _lastRoundIndex = -1;
  bool _resolving = false;
  bool _navigatedToResults = false;
  bool _left = false;
  bool _revealedSoundPlayed = false;
  Timer? _tickTimer;
  Timer? _advanceTimer;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _mp.markActiveMatch(widget.matchId, MatchGameMode.flash);
    _tickTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
    _heartbeatTimer = Timer.periodic(MultiplayerService.matchHeartbeatInterval, (_) {
      _mp.matchHeartbeat(widget.matchId);
    });
    _load();
  }

  Future<void> _load() async {
    final pool = flashPicsFrom(await imagePool());
    if (!mounted) return;
    setState(() {
      _pics = pool;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _advanceTimer?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  FlashRound _roundFor(int round) {
    if (_cachedRoundIndex == round && _cachedRound != null) return _cachedRound!;
    final r = const FlashGame().gridFor(pool: _pics, seed: stableHash(widget.matchId), round: round);
    _cachedRound = r;
    _cachedRoundIndex = round;
    return r;
  }

  int _elapsedMs(MatchInfo info) {
    final started = info.roundStartedAt?.toDate();
    if (started == null) return 0;
    return DateTime.now().difference(started).inMilliseconds;
  }

  Future<void> _leave() async {
    if (_left) return;
    _left = true;
    try {
      await _mp.leaveMatch(widget.matchId, abandoned: true);
    } catch (e) {
      debugPrint('MultiplayerFlashScreen._leave: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  void _tap(MatchInfo info, int index) {
    final me = _mp.currentPlayerId;
    if (info.roundAnswers.containsKey(me)) return;
    final revealMs = flashRevealMsFor(info.roundIndex);
    if (_elapsedMs(info) < revealMs) return; // grila încă vizibilă, nu se poate răspunde
    Sfx.tileSelect();
    _mp.submitRoundAnswer(matchId: widget.matchId, roundIndex: info.roundIndex, answer: '$index');
  }

  Future<void> _tryResolve(MatchInfo info) async {
    if (_resolving) return;
    _resolving = true;
    try {
      final round = _roundFor(info.roundIndex);
      await _mp.closeFlashRound(
        matchId: widget.matchId,
        roundIndex: info.roundIndex,
        correctIndex: round.targetIndex,
        points: flashPointsFor(info.roundIndex),
      );
    } finally {
      _resolving = false;
    }
  }

  void _onData(MatchInfo info, List<MatchPlayer> players) {
    if (info.roundIndex != _lastRoundIndex) {
      _lastRoundIndex = info.roundIndex;
      _advanceTimer?.cancel();
      _advanceTimer = null;
      _revealedSoundPlayed = false;
    }
    if (!_ready) return;

    if (info.roundPhase == RoundPhase.answering) {
      final revealMs = flashRevealMsFor(info.roundIndex);
      final elapsed = _elapsedMs(info);
      if (elapsed >= revealMs && !_revealedSoundPlayed) {
        _revealedSoundPlayed = true;
        Sfx.next();
      }
      final ids = players.map((p) => p.id).toSet();
      final allAnswered = ids.isNotEmpty && ids.every(info.roundAnswers.containsKey);
      final expired = elapsed >= revealMs + flashAnswerSeconds * 1000;
      if (allAnswered || expired) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryResolve(info));
      }
    }

    if (info.roundPhase == RoundPhase.revealed && info.status != MatchStatus.finished) {
      _advanceTimer ??= Timer(const Duration(milliseconds: 2200), () {
        _mp.advanceSyncRound(matchId: widget.matchId, roundIndex: info.roundIndex);
      });
    }

    if (info.status == MatchStatus.finished && !_navigatedToResults) {
      _navigatedToResults = true;
      Future.delayed(const Duration(milliseconds: 2200), () {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MultiplayerResultsScreen(bot: widget.bot, matchId: widget.matchId, gameMode: MatchGameMode.flash),
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
        floatingActionButton: widget.bot == null ? MatchOverlay(matchId: widget.matchId) : null,
        floatingActionButtonLocation: matchOverlayLocation,
        body: SafeArea(
          child: !_ready
              ? const Center(child: CircularProgressIndicator(color: AppColors.coin))
              : StreamBuilder<MatchInfo>(
                  stream: _matchStream,
                  builder: (context, matchSnap) {
                    final info = matchSnap.data;
                    if (info == null) return const Center(child: CircularProgressIndicator(color: AppColors.coin));
                    return StreamBuilder<List<MatchPlayer>>(
                      stream: _playersStream,
                      builder: (context, playersSnap) {
                        final players = playersSnap.data ?? const <MatchPlayer>[];
                        _onData(info, players);
                        return _body(info, players);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _body(MatchInfo info, List<MatchPlayer> players) {
    _lastInfoCache = info;
    final me = _mp.currentPlayerId;
    final round = _roundFor(info.roundIndex);
    final revealMs = flashRevealMsFor(info.roundIndex);
    final elapsed = _elapsedMs(info);
    final revealed = info.roundPhase == RoundPhase.revealed;
    final showingGrid = !revealed && elapsed < revealMs;
    final guessSecondsLeft =
        revealed ? 0 : ((revealMs + flashAnswerSeconds * 1000 - elapsed) / 1000).ceil().clamp(0, flashAnswerSeconds);
    final myAnswer = info.roundAnswers[me];
    final sorted = List.of(players)..sort((a, b) => b.score.compareTo(a.score));
    final topScore = sorted.isEmpty ? 0 : sorted.first.score;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 16, 4),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70), onPressed: _leave),
              const Expanded(
                child: Text('⚡ Fulgerul', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              Text(tr('Runda ${info.roundIndex + 1} din $flashRounds', 'Round ${info.roundIndex + 1} of $flashRounds'),
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            showingGrid
                ? flashRoundTitle(info.roundIndex)
                : revealed
                    ? flashQuestionFor(round.target.answer)
                    : myAnswer == null
                        ? flashQuestionFor(round.target.answer)
                        : tr('Ai răspuns. Aștepți ceilalți…', 'Locked in. Waiting for others…'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 8),
        if (!showingGrid && !revealed)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: guessSecondsLeft <= 2 ? AppColors.danger : AppColors.play, width: 3),
              ),
              child: Text('$guessSecondsLeft', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _grid(round, showingGrid, revealed, myAnswer),
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        SizedBox(
          height: 190,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final p = sorted[i];
              final answered = info.roundAnswers.containsKey(p.id);
              final correct = revealed && info.roundWinnerIds.contains(p.id);
              return ListTile(
                dense: true,
                leading: Avatar(
                  size: 30,
                  label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                  accentColor: pickAvatarColor(p.avatarSeed),
                  photoUrl: p.photoUrl,
                  style: avatarStyleFromId(p.avatarStyle),
                ),
                title: Text(p.name + (p.id == me ? tr(' (tu)', ' (you)') : ''),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (revealed)
                      Icon(correct ? Icons.check_circle : Icons.cancel, size: 16, color: correct ? AppColors.play : AppColors.danger)
                    else if (answered)
                      const Icon(Icons.check_circle, color: AppColors.play, size: 16),
                    const SizedBox(width: 8),
                    Text('${p.score}',
                        style: TextStyle(
                          color: p.score == topScore && topScore > 0 ? AppColors.coin : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        )),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _grid(FlashRound round, bool showingGrid, bool revealed, String? myAnswer) {
    final n = round.pics.length;
    final cols = n <= 4 ? 2 : 3;
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: n,
      itemBuilder: (context, i) {
        final pic = round.pics[i];
        final myPick = myAnswer != null && int.tryParse(myAnswer) == i;
        final isTarget = i == round.targetIndex;
        Color border = Colors.white24;
        if (revealed && isTarget) border = AppColors.play;
        if (revealed && myPick && !isTarget) border = AppColors.danger;
        if (!revealed && myPick) border = AppColors.blue;
        return GestureDetector(
          onTap: showingGrid ? null : () => _tap(_lastInfoCache!, i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: myPick || (revealed && isTarget) ? 3 : 1.5),
              color: Colors.white.withAlpha(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: showingGrid
                ? Image.asset(pic.imagePath, fit: BoxFit.cover)
                : Center(
                    child: Text(revealed && isTarget ? '✓' : '${i + 1}',
                        style: TextStyle(
                          color: revealed && isTarget ? AppColors.play : Colors.white38,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        )),
                  ),
          ),
        );
      },
    );
  }

  // `_tap` are nevoie de `info` curent, dar `_grid` nu-l primește ca să nu
  // reconstruim toată grila la fiecare tick de secundă — ținut aici, scris o
  // dată pe `build`.
  MatchInfo? _lastInfoCache;
}
