import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/audio.dart';
import '../../core/powerup_ui.dart';
import '../../core/powerups.dart';
import '../../core/stable_hash.dart';
import '../../core/lang.dart';
import '../../core/theme.dart';
import '../../data/higher_lower_data.dart';
import '../../data/multiplayer_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/match_overlay.dart';
import '../../widgets/powerup_inventory.dart';
import '../../widgets/avatar.dart';
import '../../widgets/countdown_ring.dart';
import '../../widgets/round_event_banner.dart';
import 'multiplayer_results_screen.dart';

/// Varianta multiplayer a mini-jocului solo Higher or Lower
/// (higher_lower_screen.dart): toți jucătorii din cameră văd aceeași
/// pereche campion/provocator pe rundă (aceeași ordine determinist
/// amestecată din higherLowerItems, seed = stableHash(matchId) — la fel ca
/// pool-ul comun de întrebări din modul Clasic) și votează în secret.
///
/// Amestecarea trece OBLIGATORIU prin core/stable_hash.dart, nu prin
/// `shuffle(Random(matchId.hashCode))`: runda se rezolvă cu perechea văzută
/// de clientul care apucă primul tranzacția, deci dacă pool-ul diferă între
/// platforme (și `String.hashCode` chiar diferă), ceilalți primesc "greșit"
/// pe un răspuns corect.
///
/// Rezolvarea rundei (cine a ghicit, cine primește o "pâine", cine e
/// eliminat) se întâmplă printr-o tranzacție Firestore pe care O POATE
/// ÎNCERCA orice client (vezi [MultiplayerService.resolveHigherLowerRound])
/// — nu doar hostul — ca meciul să nu rămână blocat dacă hostul pleacă.
/// Aceeași idee pentru trecerea la runda următoare
/// ([MultiplayerService.advanceHigherLowerRound]).
class MultiplayerHigherLowerScreen extends StatefulWidget {
  final String matchId;
  const MultiplayerHigherLowerScreen({super.key, required this.matchId});

  @override
  State<MultiplayerHigherLowerScreen> createState() => _MultiplayerHigherLowerScreenState();
}

class _MultiplayerHigherLowerScreenState extends State<MultiplayerHigherLowerScreen> {
  late final List<HigherLowerItem> _pool = _buildPool();

  // O singură dată per ecran: create în build, se abonau din nou la fiecare
  // tick de o secundă (un ascultător Firestore nou, citiri facturate în plus).
  late final Stream<MatchInfo> _matchStream = MultiplayerService.instance.watchMatch(widget.matchId);
  late final Stream<List<MatchPlayer>> _playersStream = MultiplayerService.instance.watchPlayers(widget.matchId);

  List<HigherLowerItem> _buildPool() {
    final pool = List.of(higherLowerItems);
    stableShuffle(pool, stableHash(widget.matchId));
    return pool;
  }

  int _lastRoundIndex = -1;
  bool _showWinners = false;

  /// Cât se derulează cifra provocatorului la dezvăluire. Ștampila și
  /// câștigătorii apar abia după, ca verdictul să vină după număr, nu înainte.
  static const int _rollMs = 1100;
  bool _resolving = false;
  bool _navigatedToResults = false;
  bool _left = false;
  Timer? _revealDelayTimer;
  Timer? _advanceTimer;
  Timer? _tickTimer;
  Timer? _heartbeatTimer;
  final Set<String> _announcedEliminated = {};

  /// Cache de nume + id-urile văzute la ultima citire, doar pentru
  /// [_detectPlayersWhoLeft] — spre deosebire de `_announcedEliminated`
  /// (jucătorul rămâne în listă, doar `eliminated=true`), cine PLEACĂ din
  /// meci dispare complet din `players` ([MultiplayerService.leaveMatch]
  /// îi șterge documentul), deci numele trebuie ținut minte dinainte.
  final Map<String, String> _playerNamesCache = {};
  Set<String> _seenPlayerIds = const {};
  final Set<String> _announcedLeftIds = {};

  /// Vezi omologul din MultiplayerTanksScreen/MultiplayerElectricChairScreen
  /// — bug raportat live de pe telefon (2026-09-09), mai vizibil la 1v1.
  void _detectPlayersWhoLeft(MatchInfo info, List<MatchPlayer> players) {
    for (final p in players) {
      _playerNamesCache[p.id] = p.name;
    }
    final currentIds = players.map((p) => p.id).toSet();
    if (_seenPlayerIds.isNotEmpty && info.status == MatchStatus.playing) {
      for (final id in _seenPlayerIds.difference(currentIds)) {
        // Propria plecare nu se anunță — documentul meu dispare chiar când ies.
        if (id == MultiplayerService.instance.currentPlayerId) continue;
        if (_announcedLeftIds.add(id)) {
          final name = _playerNamesCache[id] ?? '?';
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) notifyPlayerLeft(context, name);
          });
        }
      }
    }
    _seenPlayerIds = currentIds;
  }

  /// Power-up câștigat pentru runda anterioară — vezi core/powerups.dart.
  /// [_powerUpRolledRound] ține minte pentru ce rundă s-a tras deja, ca
  /// rebuild-urile din StreamBuilder (fără schimbare de rundă) să nu tragă
  /// zarurile din nou.
  PowerUp _myPowerUp = PowerUp.none;
  int? _powerUpRolledRound;

  /// Efectul lui [PowerUp.fiftyFifty] aici: arată popularitatea
  /// provocatorului mai devreme, înainte de reveal — n-are cum să elimine
  /// variante, sunt doar două (higher/lower).
  bool _peekActive = false;


  HigherLowerItem _championFor(int roundIndex) => _pool[roundIndex % _pool.length];
  HigherLowerItem _challengerFor(int roundIndex) => _pool[(roundIndex + 1) % _pool.length];

  @override
  void initState() {
    super.initState();
    // Reconectare: daca aplicatia moare in mijlocul meciului, butonul
    // de reconectare stie unde sa te intoarca (vezi MultiplayerService).
    MultiplayerService.instance.markActiveMatch(widget.matchId, MatchGameMode.higherLower);
    // Nicio actualizare Firestore nu vine "din ceas" - dar CountdownRing
    // trebuie să scadă vizual în fiecare secundă cât suntem în faza
    // "answering", la fel ca la modul solo (higher_lower_screen.dart).
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

  int get _roundTotalSeconds => higherLowerRoundSeconds;

  int _secondsLeftFor(MatchInfo info) {
    final started = info.roundStartedAt?.toDate();
    if (started == null) return _roundTotalSeconds;
    final elapsed = DateTime.now().difference(started).inSeconds;
    return (_roundTotalSeconds - elapsed).clamp(0, _roundTotalSeconds);
  }

  /// [p] doar ca semnătură comună cu [PowerUpBar.onUse] — Higher & Lower are
  /// un singur power-up posibil ([PowerUp.fiftyFifty]), n-are sens un
  /// parametru neutilizat de tip `void Function()`.
  ///
  /// ÎNAINTE: puterea se ștergea oricum după `revealed` — apăsată prea
  /// târziu, n-avea niciun efect (numărul e deja arătat) și niciun mesaj.
  /// Acum se păstrează pentru runda următoare, la fel ca la celelalte
  /// moduri.
  void _usePowerUp(MatchInfo info, PowerUp p) {
    if (p == PowerUp.none || p != _myPowerUp) return;
    if (info.roundPhase != RoundPhase.answering) {
      notifyPowerUpNoEffect(context);
      return;
    }
    Sfx.tileSelect();
    setState(() {
      switch (p) {
        case PowerUp.fiftyFifty:
          _peekActive = true;
        default:
          break;
      }
      _myPowerUp = PowerUp.none;
    });
  }

  /// Vezi core/powerups.dart — acordat cui a câștigat runda tocmai încheiată,
  /// cu șansă mai mare pentru cine e mai jos în clasamentul de „pâini".
  void _maybeGrantPowerUp(MatchInfo info, List<MatchPlayer> players) {
    if (_powerUpRolledRound == info.roundIndex) return;
    _powerUpRolledRound = info.roundIndex;
    final me = MultiplayerService.instance.currentPlayerId;
    if (!info.roundWinnerIds.contains(me)) return;
    // Rangul se ia din `score`, NU din `breads`: pâinile sunt greșeli
    // acumulate spre eliminare (mai multe = mai rău), scorul e cel care
    // arată cine conduce cu adevărat — vezi resolveHigherLowerRound.
    final active = List.of(players.where((p) => !p.eliminated))..sort((a, b) => b.score.compareTo(a.score));
    final total = active.isEmpty ? 1 : active.length;
    var rank = active.indexWhere((p) => p.id == me);
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
    final picked = powerUpFor(
      matchId: widget.matchId,
      roundIndex: info.roundIndex,
      playerId: me,
      gameModeId: 'higherLower',
      livePlayers: players.where((p) => !p.eliminated).length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _myPowerUp = picked);
      Sfx.rewardPop();
    });
  }

  Future<void> _leave() async {
    if (_left) return;
    _left = true;
    try {
      await MultiplayerService.instance.leaveMatch(widget.matchId, abandoned: true);
    } catch (e) {
      debugPrint('MultiplayerHigherLowerScreen._leave: leaveMatch a esuat: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  void _selectGuess(MatchInfo info, String guess) {
    if (info.roundPhase != RoundPhase.answering) return;
    final me = MultiplayerService.instance.currentPlayerId;
    if (info.roundAnswers.containsKey(me)) return;
    MultiplayerService.instance.submitRoundAnswer(matchId: widget.matchId, roundIndex: info.roundIndex, answer: guess);
  }

  Future<void> _tryResolve(MatchInfo info) async {
    if (_resolving) return;
    _resolving = true;
    final champion = _championFor(info.roundIndex);
    final challenger = _challengerFor(info.roundIndex);
    String? correctGuess;
    if (challenger.popularity > champion.popularity) {
      correctGuess = 'higher';
    } else if (challenger.popularity < champion.popularity) {
      correctGuess = 'lower';
    }
    try {
      await MultiplayerService.instance.resolveHigherLowerRound(
        matchId: widget.matchId,
        roundIndex: info.roundIndex,
        correctGuess: correctGuess,
      );
    } finally {
      _resolving = false;
    }
  }

  /// Efecte secundare (tranzacții Firestore, timere, SnackBar-uri,
  /// navigare) derivate din datele live — apelat din build(), la fel ca
  /// RoomLobbyScreen._maybeNavigateToMatch.
  void _onData(MatchInfo info, List<MatchPlayer> players) {
    _detectPlayersWhoLeft(info, players);
    if (info.roundIndex != _lastRoundIndex) {
      _lastRoundIndex = info.roundIndex;
      _showWinners = false;
      _peekActive = false;
      _revealDelayTimer?.cancel();
      _revealDelayTimer = null;
      _advanceTimer?.cancel();
      _advanceTimer = null;
    }

    if (info.roundPhase == RoundPhase.answering) {
      final activeIds = players.where((p) => !p.eliminated).map((p) => p.id).toSet();
      final allAnswered = activeIds.isNotEmpty && activeIds.every(info.roundAnswers.containsKey);
      final timedOut = _secondsLeftFor(info) <= 0;
      if (allAnswered || timedOut) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryResolve(info));
      }
    } else if (info.roundPhase == RoundPhase.revealed) {
      _revealDelayTimer ??= Timer(const Duration(milliseconds: _rollMs + 150), () {
        if (mounted) setState(() => _showWinners = true);
      });
      _advanceTimer ??= Timer(const Duration(seconds: higherLowerRevealSeconds), () {
        MultiplayerService.instance.advanceSyncRound(matchId: widget.matchId, roundIndex: info.roundIndex);
      });
      _maybeGrantPowerUp(info, players);
    }

    for (final p in players) {
      if (p.eliminated && _announcedEliminated.add(p.id)) {
        final me = MultiplayerService.instance.currentPlayerId;
        final text = p.id == me
            ? tr('Ai fost eliminat! Ești spectator.', 'You are out! You are now a spectator.')
            : tr('${p.name} a fost eliminat!', '${p.name} is out!');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
        });
      }
    }

    if (info.status == MatchStatus.finished && !_navigatedToResults) {
      _navigatedToResults = true;
      // Ultima rundă se rezolvă în aceeași scriere care încheie meciul: fără
      // pauza asta, cifra decisivă nu s-ar mai derula niciodată.
      Future.delayed(const Duration(seconds: higherLowerRevealSeconds), () {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MultiplayerResultsScreen(matchId: widget.matchId, gameMode: MatchGameMode.higherLower),
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
        floatingActionButton: MatchOverlay(matchId: widget.matchId),
        floatingActionButtonLocation: matchOverlayLocation,
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.spaceGradient),
          child: SafeArea(
            child: StreamBuilder<MatchInfo>(
              stream: _matchStream,
              builder: (context, matchSnap) {
                final info = matchSnap.data;
                if (info == null) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.blue));
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
                    final participatedThisRound = info.roundAnswers.containsKey(me);
                    final revealed = info.roundPhase == RoundPhase.revealed;
                    return Column(
                      children: [
                        _buildTopBar(),
                        _buildPlayersRow(info, players),
                        const SizedBox(height: 4),
                        Text(tr('Runda ${info.roundIndex + 1}', 'Round ${info.roundIndex + 1}'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        RoundEventBanner(
                          event: roundEventFor(matchId: widget.matchId, roundIndex: info.roundIndex, gameModeId: 'higherLower'),
                          compact: true,
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                            child: Column(
                              children: [
                                _buildCard(_championFor(info.roundIndex), revealedNumber: true, resultBorder: null),
                                _buildMiddle(info),
                                Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    _buildCard(
                                      _challengerFor(info.roundIndex),
                                      revealedNumber: revealed || _peekActive,
                                      // la dezvăluire cifra se derulează de la zero; la
                                      // „Trage cu ochiul" apare direct, e doar o privire
                                      rollKey: revealed ? info.roundIndex : null,
                                      resultBorder: revealed && participatedThisRound && _showWinners
                                          ? info.roundWinnerIds.contains(me)
                                          : null,
                                    ),
                                    if (revealed && participatedThisRound && _showWinners)
                                      Positioned(
                                        right: 6,
                                        top: 0,
                                        child: _ResultStamp(correct: info.roundWinnerIds.contains(me)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildActionArea(info, myPlayer, players),
                              ],
                            ),
                          ),
                        ),
                        // Jos, nu sus (unde concura cu titlul modului) —
                        // decizie de design.
                        if (_myPowerUp != PowerUp.none)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: PowerUpBar(
                              powerUps: [_myPowerUp],
                              usedThisRound: false,
                              usableNow: (_) => info.roundPhase == RoundPhase.answering,
                              onUse: (p) => _usePowerUp(info, p),
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

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 4),
      child: Row(
        children: [
          IconButton(onPressed: _leave, icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70)),
          const SizedBox(width: 4),
          const Text('Higher & Lower', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildPlayersRow(MatchInfo info, List<MatchPlayer> players) {
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: players.map((p) {
          final voted = info.roundAnswers.containsKey(p.id);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Opacity(
              opacity: p.eliminated ? 0.4 : 1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Avatar(size: 48, label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?', accentColor: pickAvatarColor(p.avatarSeed), photoUrl: p.photoUrl, style: avatarStyleFromId(p.avatarStyle)),
                      if (voted && !p.eliminated && info.roundPhase == RoundPhase.answering)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(color: AppColors.play, shape: BoxShape.circle),
                            child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    width: 56,
                    child: Text(p.name, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  ),
                  if (p.breads > 0) Text('🍞' * p.breads.clamp(0, higherLowerMaxBreads), style: const TextStyle(fontSize: 10)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMiddle(MatchInfo info) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Colors.white12, height: 1)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: AppColors.bg, shape: BoxShape.circle),
            child: info.roundPhase == RoundPhase.answering
                ? CountdownRing(secondsLeft: _secondsLeftFor(info), totalSeconds: _roundTotalSeconds, size: 44)
                : const Icon(Icons.emoji_events_rounded, color: AppColors.coin, size: 32),
          ),
          const Expanded(child: Divider(color: Colors.white12, height: 1)),
        ],
      ),
    );
  }

  Widget _buildCard(HigherLowerItem item, {required bool revealedNumber, required bool? resultBorder, int? rollKey}) {
    final borderColor = switch (resultBorder) {
      true => AppColors.play,
      false => AppColors.danger,
      null => Colors.white24,
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(16),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: resultBorder == null ? 1.4 : 2.2),
        boxShadow: resultBorder != null ? [BoxShadow(color: borderColor.withAlpha(90), blurRadius: 16, spreadRadius: -2)] : null,
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.emoji, style: const TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text(
            item.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: revealedNumber
                ? Container(
                    key: const ValueKey('revealed'),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.coin.withAlpha(40), borderRadius: BorderRadius.circular(14)),
                    child: rollKey == null
                        ? Text(formatSearchVolume(item.popularity), style: const TextStyle(color: AppColors.coin, fontSize: 14, fontWeight: FontWeight.w800))
                        // Contorul care se derulează — suspansul „mai mult sau
                        // mai puțin?" ține cât urcă cifra, nu se rezolvă dintr-o
                        // clipire.
                        : TweenAnimationBuilder<double>(
                            key: ValueKey('roll-$rollKey'),
                            tween: Tween(begin: 0, end: item.popularity),
                            duration: const Duration(milliseconds: _rollMs),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) => Text(
                              formatSearchVolume(v),
                              style: const TextStyle(color: AppColors.coin, fontSize: 18, fontWeight: FontWeight.w900),
                            ),
                          ),
                  )
                : const Text('❓ ❓ ❓', key: ValueKey('hidden'), style: TextStyle(color: Colors.white38, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 3)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionArea(MatchInfo info, MatchPlayer? myPlayer, List<MatchPlayer> players) {
    if (myPlayer == null) return const SizedBox(height: 90);

    if (myPlayer.eliminated) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(color: Colors.white.withAlpha(14), borderRadius: BorderRadius.circular(16)),
        child: Text(
          tr('🍞 Ai fost eliminat — ești spectator. Poți urmări meciul până la final.',
              '🍞 You are out — now a spectator. You can watch the match to the end.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
    }

    if (info.roundPhase == RoundPhase.revealed) {
      if (!_showWinners) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
              const SizedBox(height: 8),
              Text(tr('Se numără voturile…', 'Counting the votes…'), style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        );
      }
      final winnerNames = players.where((p) => info.roundWinnerIds.contains(p.id)).map((p) => p.name).join(', ');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          winnerNames.isEmpty
              ? tr('Niciun câștigător de data asta!', 'No winner this time!')
              : tr('Câștigători: $winnerNames', 'Winners: $winnerNames'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
        ),
      );
    }

    final me = MultiplayerService.instance.currentPlayerId;
    if (info.roundAnswers.containsKey(me)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(tr('✓ Ai votat! Aștepți ceilalți jucători…', '✓ Voted! Waiting for the others…'),
            style: const TextStyle(color: AppColors.play, fontSize: 14, fontWeight: FontWeight.w700)),
      );
    }

    return Row(
      children: [
        Expanded(child: _arrowButton(label: tr('MAI PUȚIN', 'LOWER'), icon: Icons.arrow_downward_rounded, color: AppColors.danger, onTap: () => _selectGuess(info, 'lower'))),
        const SizedBox(width: 12),
        Expanded(child: _arrowButton(label: tr('MAI MULT', 'HIGHER'), icon: Icons.arrow_upward_rounded, color: AppColors.play, onTap: () => _selectGuess(info, 'higher'))),
      ],
    );
  }

  Widget _arrowButton({required String label, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: color.withAlpha(45), borderRadius: BorderRadius.circular(18), border: Border.all(color: color, width: 1.6)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// Ștampila de verdict pe cardul provocatorului: cade de sus, puțin
/// strâmbă, cu un pocnet elastic — „CORECT!" verde sau „GREȘIT" roșu.
class _ResultStamp extends StatelessWidget {
  final bool correct;
  const _ResultStamp({required this.correct});

  @override
  Widget build(BuildContext context) {
    final color = correct ? AppColors.play : AppColors.danger;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 550),
      curve: Curves.elasticOut,
      builder: (context, k, child) => Transform.rotate(
        angle: -0.18,
        child: Transform.scale(scale: 2.2 - 1.2 * k, child: Opacity(opacity: k.clamp(0.0, 1.0), child: child)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(40),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 2.5),
        ),
        child: Text(
          correct ? tr('CORECT!', 'CORRECT!') : tr('GREȘIT', 'WRONG'),
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5),
        ),
      ),
    );
  }
}
