import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../core/audio.dart';
import '../../core/lang.dart';
import '../../core/rock_paper_scissors.dart';
import '../../core/theme.dart';
import '../../data/bot_match.dart';
import '../../data/multiplayer_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/match_overlay.dart';
import '../../widgets/avatar.dart';
import '../../widgets/countdown_ring.dart';
import 'multiplayer_results_screen.dart';

/// Modul Piatră-Hârtie-Foarfecă — cel mai simplu mod multiplayer: nicio
/// întrebare, nicio poză. Fiecare rundă, toți jucătorii aleg în secret una
/// din trei (în [rpsRoundSeconds] secunde), apoi se dezvăluie simultan.
/// Fiecare primește `+1` pentru fiecare adversar bătut; după [rpsRounds]
/// runde (~3 minute) câștigă cine are scorul cel mai mare.
///
/// Structura urmează Higher & Lower (rundă sincronă, alegere secretă,
/// rezolvare prin tranzacție pe care o poate încerca orice client — vezi
/// [MultiplayerService.resolveRockPaperScissorsRound]), doar fără eliminare
/// și fără power-up-uri.
class MultiplayerRockPaperScissorsScreen extends StatefulWidget {
  final String matchId;
  /// Meci cu boți (data/bot_match.dart) — null într-un meci online normal.
  final BotMatch? bot;
  const MultiplayerRockPaperScissorsScreen({super.key, required this.matchId, this.bot});

  @override
  State<MultiplayerRockPaperScissorsScreen> createState() =>
      _MultiplayerRockPaperScissorsScreenState();
}

class _MultiplayerRockPaperScissorsScreenState
    extends State<MultiplayerRockPaperScissorsScreen> with SingleTickerProviderStateMixin {
  MultiplayerService get _mp => widget.bot?.service ?? MultiplayerService.instance;

  // O singură dată per ecran: create în build, se abonau din nou la fiecare
  // tick de o secundă (un ascultător Firestore nou, citiri facturate în plus).
  late final Stream<MatchInfo> _matchStream = _mp.watchMatch(widget.matchId);
  late final Stream<List<MatchPlayer>> _playersStream = _mp.watchPlayers(widget.matchId);

  int _lastRoundIndex = -1;
  bool _resolving = false;
  bool _navigatedToResults = false;
  bool _left = false;
  Timer? _advanceTimer;
  Timer? _tickTimer;
  Timer? _heartbeatTimer;

  static const _emoji = {rpsRock: '✊', rpsPaper: '✋', rpsScissors: '✌️'};

  /// Ceasul dezvăluirii: pumnii bat de trei ori, apoi se deschid toți
  /// deodată — vezi [_RpsRevealStage]. Pornește când sosește runda rezolvată.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(seconds: rpsRevealSeconds),
  );
  int _revealedRound = -1;
  final Set<int> _pumpSounds = {};

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
    _mp.markActiveMatch(widget.matchId, MatchGameMode.rockPaperScissors);
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _heartbeatTimer = Timer.periodic(MultiplayerService.matchHeartbeatInterval, (_) {
      _mp.matchHeartbeat(widget.matchId);
    });
    _reveal.addListener(_onRevealTick);
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _advanceTimer?.cancel();
    _heartbeatTimer?.cancel();
    _reveal.removeListener(_onRevealTick);
    _reveal.dispose();
    super.dispose();
  }

  /// Sunetele dezvăluirii, legate de ceasul ei: câte un bătut pentru fiecare
  /// „Piatră… Hârtie… Foarfecă", apoi pocnetul la deschiderea mâinilor.
  void _onRevealTick() {
    final t = _reveal.value * rpsRevealSeconds;
    for (var k = 0; k < 4; k++) {
      if (t >= k * _RpsRevealStage.pumpSeconds && _pumpSounds.add(k)) {
        k < 3 ? Sfx.tileSelect() : Sfx.rewardPop();
      }
    }
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
      await _mp.leaveMatch(widget.matchId, abandoned: true);
    } catch (e) {
      debugPrint('MultiplayerRockPaperScissorsScreen._leave: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  void _choose(MatchInfo info, String choice) {
    if (info.roundPhase != RoundPhase.answering) return;
    final me = _mp.currentPlayerId;
    if (info.roundAnswers.containsKey(me)) return;
    Sfx.tileSelect();
    _mp.submitRoundAnswer(matchId: widget.matchId, roundIndex: info.roundIndex, answer: choice);
  }

  Future<void> _tryResolve(MatchInfo info) async {
    if (_resolving) return;
    _resolving = true;
    try {
      await _mp.resolveRockPaperScissorsRound(
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
    }

    if (info.roundPhase == RoundPhase.revealed && _revealedRound != info.roundIndex) {
      _revealedRound = info.roundIndex;
      _pumpSounds.clear();
      // post-frame: _onData rulează în timpul build-ului
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reveal.forward(from: 0);
      });
    }

    if (info.roundPhase == RoundPhase.revealed && info.status != MatchStatus.finished) {
      _advanceTimer ??= Timer(const Duration(seconds: rpsRevealSeconds), () {
        _mp
            .advanceSyncRound(matchId: widget.matchId, roundIndex: info.roundIndex);
      });
    }

    if (info.status == MatchStatus.finished && !_navigatedToResults) {
      _navigatedToResults = true;
      // Meciul se termină în aceeași scriere care rezolvă ultima rundă: fără
      // pauza asta, runda decisivă nu s-ar vedea — ecranul sărea la clasament
      // exact când trebuiau să se deschidă mâinile.
      Future.delayed(const Duration(seconds: rpsRevealSeconds), () {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MultiplayerResultsScreen(
                bot: widget.bot,
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
        floatingActionButton: widget.bot == null ? MatchOverlay(matchId: widget.matchId) : null,
        floatingActionButtonLocation: matchOverlayLocation,
        body: SafeArea(
          child: StreamBuilder<MatchInfo>(
            stream: _matchStream,
            builder: (context, matchSnap) {
              final info = matchSnap.data;
              if (info == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return StreamBuilder<List<MatchPlayer>>(
                stream: _playersStream,
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
    final me = _mp.currentPlayerId;
    final answering = info.roundPhase == RoundPhase.answering;
    final myChoice = info.roundAnswers[me];
    final secondsLeft = _secondsLeftFor(info);
    final sorted = List.of(players)..sort((a, b) => b.score.compareTo(a.score));
    final topScore = sorted.isEmpty ? 0 : sorted.first.score;

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
                tr('Runda ${min(info.roundIndex + 1, rpsRounds)} din $rpsRounds',
                    'Round ${min(info.roundIndex + 1, rpsRounds)} of $rpsRounds'),
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
          AnimatedBuilder(
            animation: _reveal,
            builder: (context, _) => _RpsRevealStage(
              time: _reveal.value * rpsRevealSeconds,
              info: info,
              players: players,
              myId: me,
              emoji: _emoji,
              labelFor: _labelFor,
            ),
          ),
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
                    // scorul urcă cifră cu cifră, după ce s-au deschis mâinile
                    TweenAnimationBuilder<int>(
                      tween: IntTween(end: p.score),
                      duration: const Duration(milliseconds: 700),
                      builder: (context, v, _) => Text(
                        '$v',
                        style: TextStyle(
                          // cine conduce e auriu, ca să se vadă cursa
                          color: p.score == topScore && topScore > 0 ? AppColors.coin : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
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

/// **Dezvăluirea**: toți pumnii bat de trei ori pe „Piatră… Hârtie…
/// Foarfecă!", apoi se deschid în aceeași clipă. Cine a bătut pe cineva
/// strălucește auriu și primește „+N"; cine a fost bătut se stinge. Timpul
/// vine din controlerul ecranului, deci totul e o funcție de [time] —
/// nicio stare proprie.
class _RpsRevealStage extends StatelessWidget {
  final double time;
  final MatchInfo info;
  final List<MatchPlayer> players;
  final String myId;
  final Map<String, String> emoji;
  final String Function(String) labelFor;
  const _RpsRevealStage({
    required this.time,
    required this.info,
    required this.players,
    required this.myId,
    required this.emoji,
    required this.labelFor,
  });

  /// Un „bătut" de pumn. Trei bătăi, apoi deschiderea la 3 × [pumpSeconds].
  static const double pumpSeconds = 0.34;
  static const double openAt = pumpSeconds * 3;

  @override
  Widget build(BuildContext context) {
    final gains = rpsRoundScores({for (final p in players) p.id: info.roundAnswers[p.id] ?? ''});
    final open = time >= openAt;
    final sinceOpen = time - openAt;
    final words = [tr('PIATRĂ…', 'ROCK…'), tr('HÂRTIE…', 'PAPER…'), tr('FOARFECĂ!', 'SCISSORS!')];
    final pump = (time / pumpSeconds).floor().clamp(0, 2);
    final myGain = gains[myId] ?? 0;

    // bătaia: pumnul urcă și coboară o dată pe fiecare cuvânt
    final phase = (time % pumpSeconds) / pumpSeconds;
    final lift = open ? 0.0 : -sin(phase * pi) * 16;

    final String headline;
    final Color headColor;
    if (!open) {
      headline = words[pump];
      headColor = Colors.white;
    } else if (myGain > 0) {
      headline = myGain == 1 ? tr('+1 PUNCT!', '+1 POINT!') : tr('+$myGain PUNCTE!', '+$myGain POINTS!');
      headColor = AppColors.coin;
    } else if (players.every((p) => (gains[p.id] ?? 0) == 0)) {
      headline = tr('EGALITATE', 'DRAW');
      headColor = Colors.white70;
    } else {
      headline = tr('NIMIC RUNDA ASTA', 'NOTHING THIS ROUND');
      headColor = Colors.white54;
    }
    final headPop = open ? Curves.elasticOut.transform((sinceOpen / 0.6).clamp(0.0, 1.0)) : 1.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: open ? 0.6 + 0.4 * headPop : 1.0 + (1 - phase) * 0.12,
          child: Text(
            headline,
            style: TextStyle(
              color: headColor,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 10)],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 12,
          children: [for (final p in players) _card(p, gains, open, sinceOpen, lift)],
        ),
      ],
    );
  }

  Widget _card(MatchPlayer p, Map<String, int> gains, bool open, double sinceOpen, double lift) {
    final choice = info.roundAnswers[p.id] ?? '';
    final gain = gains[p.id] ?? 0;
    final beaten = open && gain == 0 && gains.values.any((g) => g > 0);
    final isMe = p.id == myId;
    // deschiderea: un pocnet elastic, fiecare carte cu o fracțiune de
    // întârziere față de vecina ei, ca să se simtă ca un val
    final order = players.indexOf(p);
    final pop = open ? Curves.elasticOut.transform(((sinceOpen - order * 0.03) / 0.5).clamp(0.0, 1.0)) : 1.0;
    final glow = open && gain > 0 ? ((sinceOpen - 0.2) / 0.3).clamp(0.0, 1.0) : 0.0;
    final dim = beaten ? ((sinceOpen - 0.2) / 0.3).clamp(0.0, 1.0) : 0.0;
    final plusT = ((sinceOpen - 0.35) / 1.2).clamp(0.0, 1.0);

    return SizedBox(
      width: 78,
      height: 118,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Opacity(
            opacity: 1 - 0.55 * dim,
            child: Container(
              width: 78,
              height: 104,
              decoration: BoxDecoration(
                color: Color.lerp(Colors.white.withAlpha(14), AppColors.coin.withAlpha(46), glow),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Color.lerp(isMe ? AppColors.purple : Colors.white24, AppColors.coin, glow)!,
                  width: isMe || glow > 0 ? 2 : 1,
                ),
                boxShadow: glow > 0
                    ? [BoxShadow(color: AppColors.coin.withAlpha((110 * glow).round()), blurRadius: 18, spreadRadius: -4)]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.translate(
                    offset: Offset(0, lift),
                    child: Transform.scale(
                      scale: open ? 0.5 + 0.5 * pop : 1.0,
                      child: Text(open ? (emoji[choice] ?? '❔') : '✊', style: const TextStyle(fontSize: 36)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    open ? (choice.isEmpty ? tr('nimic', 'nothing') : labelFor(choice)) : '',
                    style: const TextStyle(color: Colors.white60, fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    width: 70,
                    child: Text(
                      isMe ? tr('TU', 'YOU') : p.name,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isMe ? AppColors.purple : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open && gain > 0 && plusT > 0 && plusT < 1)
            Positioned(
              top: -8 - plusT * 34,
              child: Opacity(
                opacity: plusT < 0.7 ? 1 : 1 - (plusT - 0.7) / 0.3,
                child: Text(
                  '+$gain',
                  style: const TextStyle(
                    color: AppColors.coin,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
