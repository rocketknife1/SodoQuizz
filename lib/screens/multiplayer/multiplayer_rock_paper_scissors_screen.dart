import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/audio.dart';
import '../../core/lang.dart';
import '../../core/rock_paper_scissors.dart';
import '../../core/theme.dart';
import '../../data/multiplayer_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/avatar.dart';
import '../../widgets/countdown_ring.dart';
import 'multiplayer_results_screen.dart';

/// Modul Piatră-Hârtie-Foarfecă — cel mai simplu mod multiplayer: nicio
/// întrebare, nicio poză. Fiecare rundă, toți jucătorii aleg în secret una
/// din trei (în [rpsRoundSeconds] secunde), apoi se dezvăluie simultan.
/// Fiecare primește `+1` pentru fiecare adversar bătut; primul la
/// [rpsTargetScore] câștigă meciul.
///
/// Structura urmează Higher & Lower (rundă sincronă, alegere secretă,
/// rezolvare prin tranzacție pe care o poate încerca orice client — vezi
/// [MultiplayerService.resolveRockPaperScissorsRound]), doar fără eliminare
/// și fără power-up-uri.
class MultiplayerRockPaperScissorsScreen extends StatefulWidget {
  final String matchId;
  const MultiplayerRockPaperScissorsScreen({super.key, required this.matchId});

  @override
  State<MultiplayerRockPaperScissorsScreen> createState() =>
      _MultiplayerRockPaperScissorsScreenState();
}

class _MultiplayerRockPaperScissorsScreenState
    extends State<MultiplayerRockPaperScissorsScreen> {
  int _lastRoundIndex = -1;
  bool _resolving = false;
  bool _navigatedToResults = false;
  bool _left = false;
  Timer? _advanceTimer;
  Timer? _tickTimer;
  Timer? _heartbeatTimer;

  static const _emoji = {rpsRock: '✊', rpsPaper: '✋', rpsScissors: '✌️'};

  String _labelFor(String choice) => switch (choice) {
        rpsRock => tr('Piatră', 'Rock'),
        rpsPaper => tr('Hârtie', 'Paper'),
        rpsScissors => tr('Foarfecă', 'Scissors'),
        _ => '—',
      };

  @override
  void initState() {
    super.initState();
    // Reconectare: daca aplicatia moare in mijlocul meciului, butonul
    // de reconectare stie unde sa te intoarca (vezi MultiplayerService).
    MultiplayerService.instance.markActiveMatch(widget.matchId, MatchGameMode.rockPaperScissors);
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
    _advanceTimer?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  int _secondsLeftFor(MatchInfo info) {
    final started = info.roundStartedAt?.toDate();
    if (started == null) return rpsRoundSeconds;
    final elapsed = DateTime.now().difference(started).inSeconds;
    return (rpsRoundSeconds - elapsed).clamp(0, rpsRoundSeconds);
  }

  Future<void> _leave() async {
    if (_left) return;
    _left = true;
    try {
      await MultiplayerService.instance.leaveMatch(widget.matchId);
    } catch (e) {
      debugPrint('MultiplayerRockPaperScissorsScreen._leave: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  void _choose(MatchInfo info, String choice) {
    if (info.roundPhase != RoundPhase.answering) return;
    final me = MultiplayerService.instance.currentPlayerId;
    if (info.roundAnswers.containsKey(me)) return;
    Sfx.tileSelect();
    MultiplayerService.instance.submitRoundAnswer(matchId: widget.matchId, answer: choice);
  }

  Future<void> _tryResolve(MatchInfo info) async {
    if (_resolving) return;
    _resolving = true;
    try {
      await MultiplayerService.instance.resolveRockPaperScissorsRound(
        matchId: widget.matchId,
        roundIndex: info.roundIndex,
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
    }

    if (info.roundPhase == RoundPhase.answering) {
      final ids = players.map((p) => p.id).toSet();
      final allChosen = ids.isNotEmpty && ids.every(info.roundAnswers.containsKey);
      final timedOut = _secondsLeftFor(info) <= 0;
      if (allChosen || timedOut) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryResolve(info));
      }
    } else if (info.roundPhase == RoundPhase.revealed) {
      _advanceTimer ??= Timer(const Duration(seconds: rpsRevealSeconds), () {
        MultiplayerService.instance
            .advanceSyncRound(matchId: widget.matchId, roundIndex: info.roundIndex);
      });
    }

    if (info.status == MatchStatus.finished && !_navigatedToResults) {
      _navigatedToResults = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MultiplayerResultsScreen(
                matchId: widget.matchId, gameMode: MatchGameMode.rockPaperScissors),
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
        backgroundColor: const Color(0xFF0E1230),
        body: SafeArea(
          child: StreamBuilder<MatchInfo>(
            stream: MultiplayerService.instance.watchMatch(widget.matchId),
            builder: (context, matchSnap) {
              final info = matchSnap.data;
              if (info == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return StreamBuilder<List<MatchPlayer>>(
                stream: MultiplayerService.instance.watchPlayers(widget.matchId),
                builder: (context, playersSnap) {
                  final players = playersSnap.data ?? const <MatchPlayer>[];
                  _onData(info, players);
                  return _buildBody(info, players);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(MatchInfo info, List<MatchPlayer> players) {
    final me = MultiplayerService.instance.currentPlayerId;
    final answering = info.roundPhase == RoundPhase.answering;
    final myChoice = info.roundAnswers[me];
    final secondsLeft = _secondsLeftFor(info);
    final sorted = List.of(players)..sort((a, b) => b.score.compareTo(a.score));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: _leave,
              ),
              Expanded(
                child: Text(
                  tr('Piatră-Hârtie-Foarfecă', 'Rock-Paper-Scissors'),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                tr('Primul la $rpsTargetScore', 'First to $rpsTargetScore'),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (answering)
          CountdownRing(
            secondsLeft: secondsLeft,
            totalSeconds: rpsRoundSeconds,
          )
        else
          const SizedBox(height: 8),
        const SizedBox(height: 16),
        Text(
          answering
              ? (myChoice == null
                  ? tr('Alege!', 'Choose!')
                  : tr('Ai ales. Aștepți ceilalți…', 'Locked in. Waiting for others…'))
              : tr('Dezvăluire', 'Reveal'),
          style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        if (answering)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final c in rpsChoices)
                _ChoiceButton(
                  emoji: _emoji[c]!,
                  label: _labelFor(c),
                  selected: myChoice == c,
                  dimmed: myChoice != null && myChoice != c,
                  onTap: myChoice == null ? () => _choose(info, c) : null,
                ),
            ],
          )
        else
          _RevealRow(info: info, players: players, emoji: _emoji, labelFor: _labelFor),
        const SizedBox(height: 24),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final p = sorted[i];
              final chose = info.roundAnswers.containsKey(p.id);
              return ListTile(
                leading: Avatar(
                  size: 34,
                  label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                  accentColor: pickAvatarColor(p.avatarSeed),
                  photoUrl: p.photoUrl,
                  style: avatarStyleFromId(p.avatarStyle),
                ),
                title: Text(
                  p.name + (p.id == me ? tr(' (tu)', ' (you)') : ''),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (answering && chose)
                      const Icon(Icons.check_circle, color: AppColors.play, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '${p.score}',
                      style: TextStyle(
                        color: p.score >= rpsTargetScore ? AppColors.coin : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final bool dimmed;
  final VoidCallback? onTap;
  const _ChoiceButton({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 96,
        height: 116,
        decoration: BoxDecoration(
          color: selected ? AppColors.purple.withAlpha(60) : Colors.white.withAlpha(12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.purple : Colors.white24,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: Opacity(
          opacity: dimmed ? 0.4 : 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 40)),
              const SizedBox(height: 8),
              Text(label,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevealRow extends StatelessWidget {
  final MatchInfo info;
  final List<MatchPlayer> players;
  final Map<String, String> emoji;
  final String Function(String) labelFor;
  const _RevealRow({
    required this.info,
    required this.players,
    required this.emoji,
    required this.labelFor,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 10,
      children: [
        for (final p in players)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                emoji[info.roundAnswers[p.id]] ?? '❔',
                style: const TextStyle(fontSize: 34),
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 72,
                child: Text(
                  p.name,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: info.roundWinnerIds.contains(p.id) ? AppColors.play : Colors.white54,
                    fontSize: 11,
                    fontWeight: info.roundWinnerIds.contains(p.id) ? FontWeight.w800 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
