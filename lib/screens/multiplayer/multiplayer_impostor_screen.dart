import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio.dart';
import '../../core/impostor_game.dart';
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

/// **Impostorul** — deducție socială (regulile: core/impostor_game.dart).
/// Toți primesc același cuvânt de ghicit, în afară de unul; fiecare alege un
/// indiciu adevărat despre cuvântul lui, apoi toată masa votează cine crede
/// că are alt cuvânt.
///
/// CE FACE ECRANUL ĂSTA ȘI CE NU: cine e impostorul și ce cuvinte sunt în
/// joc se calculează LOCAL, identic pe orice telefon (din `matchId` +
/// rundă + [MatchInfo.playerIds] — vezi [ImpostorGame.impostorFor] și
/// [ImpostorGame.wordsFor], ambele pe [StableRandom]). Rezolvarea (cine a
/// nimerit votul) o face orice client prin [MultiplayerService.closeImpostorVoting].
class MultiplayerImpostorScreen extends StatefulWidget {
  final String matchId;

  /// Meci cu boți (data/bot_match.dart) — null într-un meci online normal.
  final BotMatch? bot;

  const MultiplayerImpostorScreen({super.key, required this.matchId, this.bot});

  @override
  State<MultiplayerImpostorScreen> createState() => _MultiplayerImpostorScreenState();
}

class _MultiplayerImpostorScreenState extends State<MultiplayerImpostorScreen> {
  MultiplayerService get _mp => widget.bot?.service ?? MultiplayerService.instance;

  late final Stream<MatchInfo> _matchStream = _mp.watchMatch(widget.matchId);
  late final Stream<List<MatchPlayer>> _playersStream = _mp.watchPlayers(widget.matchId);

  Map<String, List<ImpostorPic>> _byCategory = const {};
  bool _ready = false;

  int _lastRoundIndex = -1;
  bool _resolvingClues = false;
  bool _resolvingVotes = false;
  bool _navigatedToResults = false;
  bool _left = false;
  Timer? _tickTimer;
  Timer? _advanceTimer;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _mp.markActiveMatch(widget.matchId, MatchGameMode.impostor);
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _heartbeatTimer = Timer.periodic(MultiplayerService.matchHeartbeatInterval, (_) {
      _mp.matchHeartbeat(widget.matchId);
    });
    _load();
  }

  Future<void> _load() async {
    final byCat = impostorPicsByCategory(await imagePool());
    if (!mounted) return;
    setState(() {
      _byCategory = byCat;
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

  int _seed() => stableHash(widget.matchId);

  String _impostorFor(MatchInfo info) => const ImpostorGame().impostorFor(info.playerIds, _seed(), info.roundIndex);

  (ImpostorPic real, ImpostorPic impostor) _wordsFor(int round) =>
      const ImpostorGame().wordsFor(byCategory: _byCategory, seed: _seed(), round: round);

  String _myWord(MatchInfo info) {
    final (real, impostor) = _wordsFor(info.roundIndex);
    return _mp.currentPlayerId == _impostorFor(info) ? impostor.answer : real.answer;
  }

  int _secondsLeft(MatchInfo info, int total) {
    final started = info.roundStartedAt?.toDate();
    if (started == null) return total;
    final elapsed = DateTime.now().difference(started).inSeconds;
    return (total - elapsed).clamp(0, total);
  }

  Future<void> _leave() async {
    if (_left) return;
    _left = true;
    try {
      await _mp.leaveMatch(widget.matchId, abandoned: true);
    } catch (e) {
      debugPrint('MultiplayerImpostorScreen._leave: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  void _pickClue(MatchInfo info, ImpostorClue clue) {
    final me = _mp.currentPlayerId;
    if (info.roundAnswers.containsKey(me)) return;
    Sfx.tileSelect();
    _mp.submitRoundAnswer(matchId: widget.matchId, roundIndex: info.roundIndex, answer: clue.encode());
  }

  void _vote(MatchInfo info, String accusedId) {
    final me = _mp.currentPlayerId;
    if (info.roundVotes.containsKey(me)) return;
    Sfx.tileSelect();
    _mp.submitImpostorVote(matchId: widget.matchId, roundIndex: info.roundIndex, accusedId: accusedId);
  }

  Future<void> _tryCloseClues(MatchInfo info) async {
    if (_resolvingClues) return;
    _resolvingClues = true;
    try {
      await _mp.closeImpostorClues(matchId: widget.matchId, roundIndex: info.roundIndex);
    } finally {
      _resolvingClues = false;
    }
  }

  Future<void> _tryCloseVoting(MatchInfo info) async {
    if (_resolvingVotes) return;
    _resolvingVotes = true;
    try {
      await _mp.closeImpostorVoting(matchId: widget.matchId, roundIndex: info.roundIndex, impostorId: _impostorFor(info));
    } finally {
      _resolvingVotes = false;
    }
  }

  void _onData(MatchInfo info, List<MatchPlayer> players) {
    if (info.roundIndex != _lastRoundIndex) {
      _lastRoundIndex = info.roundIndex;
      _advanceTimer?.cancel();
      _advanceTimer = null;
    }
    if (!_ready) return;
    final ids = players.map((p) => p.id).toSet();

    if (info.roundPhase == RoundPhase.answering) {
      final allAnswered = ids.isNotEmpty && ids.every(info.roundAnswers.containsKey);
      if (allAnswered || _secondsLeft(info, impostorClueSeconds) <= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryCloseClues(info));
      }
    } else if (info.roundPhase == RoundPhase.voting) {
      final allVoted = ids.isNotEmpty && ids.every(info.roundVotes.containsKey);
      if (allVoted || _secondsLeft(info, impostorVoteSeconds) <= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryCloseVoting(info));
      }
    }

    if (info.roundPhase == RoundPhase.revealed && info.status != MatchStatus.finished) {
      _advanceTimer ??= Timer(const Duration(milliseconds: 3200), () {
        _mp.advanceSyncRound(matchId: widget.matchId, roundIndex: info.roundIndex);
      });
    }

    if (info.status == MatchStatus.finished && !_navigatedToResults) {
      _navigatedToResults = true;
      Future.delayed(const Duration(milliseconds: 3200), () {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                MultiplayerResultsScreen(bot: widget.bot, matchId: widget.matchId, gameMode: MatchGameMode.impostor),
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
              ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
              : StreamBuilder<MatchInfo>(
                  stream: _matchStream,
                  builder: (context, matchSnap) {
                    final info = matchSnap.data;
                    if (info == null) return const Center(child: CircularProgressIndicator(color: AppColors.purple));
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

  Widget _header(MatchInfo info) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 16, 4),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70), onPressed: _leave),
          const Expanded(
            child: Text('🎭 Impostorul', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Text(tr('Runda ${info.roundIndex + 1} din $impostorRounds', 'Round ${info.roundIndex + 1} of $impostorRounds'),
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _scoreList(MatchInfo info, List<MatchPlayer> players, {Set<String> highlight = const {}}) {
    final me = _mp.currentPlayerId;
    final sorted = List.of(players)..sort((a, b) => b.score.compareTo(a.score));
    final topScore = sorted.isEmpty ? 0 : sorted.first.score;
    return SizedBox(
      height: 170,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: sorted.length,
        itemBuilder: (context, i) {
          final p = sorted[i];
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
                style: TextStyle(
                  color: highlight.contains(p.id) ? AppColors.coin : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                )),
            trailing: Text('${p.score}',
                style: TextStyle(
                  color: p.score == topScore && topScore > 0 ? AppColors.coin : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                )),
          );
        },
      ),
    );
  }

  Widget _body(MatchInfo info, List<MatchPlayer> players) {
    return switch (info.roundPhase) {
      RoundPhase.voting => _votingPhase(info, players),
      RoundPhase.revealed => _revealedPhase(info, players),
      _ => _cluePhase(info, players),
    };
  }

  Widget _cluePhase(MatchInfo info, List<MatchPlayer> players) {
    final me = _mp.currentPlayerId;
    final myWord = _myWord(info);
    final clues = impostorCluesFor(myWord);
    final myClue = info.roundAnswers[me];
    final seconds = _secondsLeft(info, impostorClueSeconds);
    return Column(
      children: [
        _header(info),
        const SizedBox(height: 8),
        Text(tr('Cuvântul tău', 'Your word'), style: const TextStyle(color: Colors.white54, fontSize: 12.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(myWord, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(height: 10),
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: seconds <= 3 ? AppColors.danger : AppColors.play, width: 3)),
          child: Text('$seconds', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 12),
        Text(
          myClue == null
              ? tr('Alege un indiciu ADEVĂRAT despre cuvântul tău', 'Pick a TRUE clue about your word')
              : tr('Ai ales. Aștepți ceilalți…', 'Locked in. Waiting for others…'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13.5),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in clues)
                  _ClueChip(
                    text: impostorClueText(c),
                    selected: myClue == c.encode(),
                    dimmed: myClue != null && myClue != c.encode(),
                    onTap: myClue == null ? () => _pickClue(info, c) : null,
                  ),
              ],
            ),
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        _scoreList(info, players),
      ],
    );
  }

  Widget _votingPhase(MatchInfo info, List<MatchPlayer> players) {
    final me = _mp.currentPlayerId;
    final myVote = info.roundVotes[me];
    final seconds = _secondsLeft(info, impostorVoteSeconds);
    final others = players.where((p) => p.id != me).toList();
    return Column(
      children: [
        _header(info),
        const SizedBox(height: 4),
        Text(tr('Cine crezi că e impostorul?', 'Who do you think is the impostor?'),
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: seconds <= 3 ? AppColors.danger : AppColors.play, width: 3)),
          child: Text('$seconds', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: others.length,
            itemBuilder: (context, i) {
              final p = others[i];
              final rawClue = info.roundAnswers[p.id];
              final clueText = rawClue == null || rawClue.isEmpty
                  ? tr('(n-a apucat să aleagă)', "(didn't get to pick)")
                  : impostorClueText(ImpostorClue.decode(rawClue));
              final selected = myVote == p.id;
              return GestureDetector(
                onTap: myVote == null ? () => _vote(info, p.id) : null,
                child: Opacity(
                  opacity: myVote != null && !selected ? 0.5 : 1,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.purple.withAlpha(60) : Colors.white.withAlpha(14),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: selected ? AppColors.purple : Colors.white24, width: selected ? 2 : 1),
                    ),
                    child: Row(
                      children: [
                        Avatar(
                          size: 36,
                          label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                          accentColor: pickAvatarColor(p.avatarSeed),
                          photoUrl: p.photoUrl,
                          style: avatarStyleFromId(p.avatarStyle),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(clueText, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        if (selected) const Icon(Icons.check_circle, color: AppColors.purple),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _revealedPhase(MatchInfo info, List<MatchPlayer> players) {
    final impostorId = _impostorFor(info);
    final impostorName = players.where((p) => p.id == impostorId).map((p) => p.name).firstOrNull ?? '?';
    final me = _mp.currentPlayerId;
    // `roundWinnerIds` = cine a votat corect, DOAR când impostorul a fost
    // prins (vezi MultiplayerService.closeImpostorVoting) — deci nevidă
    // înseamnă mereu „prins".
    final caught = info.roundWinnerIds.isNotEmpty;
    final iAmImpostor = me == impostorId;
    return Column(
      children: [
        _header(info),
        const SizedBox(height: 18),
        Text(caught ? '🎉' : '🕵️', style: const TextStyle(fontSize: 48)),
        const SizedBox(height: 8),
        Text(
          iAmImpostor
              ? (caught ? tr('Te-au prins!', 'You got caught!') : tr('Ai scăpat!', 'You got away with it!'))
              : (caught ? tr('Impostorul a fost prins!', 'The impostor was caught!') : tr('Impostorul a scăpat…', 'The impostor got away…')),
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(tr('Impostorul era $impostorName', 'The impostor was $impostorName'),
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 20),
        const Divider(color: Colors.white12, height: 1),
        _scoreList(info, players, highlight: {impostorId}),
      ],
    );
  }
}

class _ClueChip extends StatelessWidget {
  const _ClueChip({required this.text, required this.selected, required this.dimmed, required this.onTap});

  final String text;
  final bool selected;
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: dimmed ? 0.4 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.purple.withAlpha(70) : Colors.white.withAlpha(14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.purple : Colors.white24, width: selected ? 2 : 1),
          ),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
