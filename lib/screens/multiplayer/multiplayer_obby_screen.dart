import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../core/admin_reveal.dart';
import '../../core/audio.dart';
import '../../core/lang.dart';
import '../../core/obby.dart';
import '../../core/powerup_ui.dart';
import '../../core/powerups.dart';
import '../../core/stable_hash.dart';
import '../../core/theme.dart';
import '../../data/culture_questions.dart';
import '../../data/bot_match.dart';
import '../../data/multiplayer_service.dart';
import '../../data/storage_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/match_overlay.dart';
import '../../widgets/coin_reward_overlay.dart';
import '../../widgets/countdown_ring.dart';
import '../../widgets/obby_board.dart';
import '../../widgets/powerup_inventory.dart';
import '../../widgets/round_event_banner.dart';
import 'multiplayer_results_screen.dart';
import '../../core/breadcrumbs.dart';

/// **Obby** — cursă de obstacole tip Roblox, de la 2 la [obbyMaxPlayers]
/// personaje pe aceeași pistă (vezi core/obby.dart): ecranul nu decide nimic, citește
/// rezultatul rundei din Firestore și îl animează. ORICE client poate cere
/// rezolvarea rundei.
///
/// Diferența e doar vizuală: în [RoundPhase.answering] fiecare jucător își
/// vede propriul personaj într-un colț, așteptând; în [RoundPhase.revealed]
/// tabla 2D arată toată cursa,
/// cu personajele care au răspuns corect sărind peste obstacolul din față.
class MultiplayerObbyScreen extends StatefulWidget {
  final String matchId;
  /// Meci cu boți (data/bot_match.dart) — null într-un meci online normal.
  final BotMatch? bot;
  const MultiplayerObbyScreen({super.key, required this.matchId, this.bot});

  @override
  State<MultiplayerObbyScreen> createState() => _MultiplayerObbyScreenState();
}

class _MultiplayerObbyScreenState extends State<MultiplayerObbyScreen> {
  MultiplayerService get _mp => widget.bot?.service ?? MultiplayerService.instance;

  late final List<CultureQuestion> _pool = _buildPool();

  late final Stream<MatchInfo> _matchStream = _mp.watchMatch(widget.matchId);
  late final Stream<List<MatchPlayer>> _playersStream = _mp.watchPlayers(widget.matchId);

  MatchInfo? _latestInfo;

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
  Timer? _lateSfxTimer;
  DateTime? _revealedAtLocal;

  bool _playedRevealSfx = false;

  List<String>? _cachedChoices;
  int _cachedChoicesRound = -1;

  /// Recompensa imediată din planul de viitor (punctul 4): cât s-a adunat în
  /// meciul ăsta din monedele instant acordate la fiecare răspuns corect
  /// (vezi [_selectAnswer]) — separată de miza/premiile meciului, doar
  /// pentru pastila din bara de sus. Balanța reală (StorageService) e deja
  /// actualizată în clipa apăsării, nu la final.
  int _instantCoinsThisMatch = 0;
  final GlobalKey _coinPillKey = GlobalKey();

  /// Inventarul de puteri (core/powerups.dart) — acordate direct în
  /// [_selectAnswer] cu răspuns corect, nu prin [_onData]: apelul e din
  /// tap-ul jucătorului, deci nu rulează în timpul unui build ca la
  /// celelalte moduri, iar `info.roundAnswers` deja împiedică o a doua
  /// acordare pe aceeași rundă.
  ///
  /// LISTĂ, nu un singur slot: până la recenzia asta, o putere nouă venită
  /// cât încă aveai una nefolosită o ștergea în tăcere — exact bug-ul
  /// reparat la Quizz Tanks în 2026-09-01 (vezi widgets/powerup_inventory.dart),
  /// dar rămas nereparat aici.
  List<PowerUp> _myPowerUps = [];

  /// Runda în care s-a folosit deja o putere — regula rămâne „una pe rundă"
  /// (vezi widgets/powerup_inventory.dart), acum explicită și aici.
  int? _powerUpUsedRound;
  Set<String> _hiddenChoices = const {};

  /// uid → nume, reîmprospătat la fiecare [_onData] — pentru [PowerUp.peek].
  final Map<String, String> _playerNames = {};

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
    Breadcrumbs.drop('ecran: Meci Obby');
    // Reconectare: daca aplicatia moare in mijlocul meciului, butonul
    // de reconectare stie unde sa te intoarca (vezi MultiplayerService).
    _mp.markActiveMatch(widget.matchId, MatchGameMode.obby);
    // Sunetele modului se încarcă abia acum, nu la pornirea aplicației —
    // vezi ObbySfx pentru de ce.
    ObbySfx.preload();
    // O dată pe secundă ajunge: cronometrele sunt în secunde, iar tabla
    // (widgets/obby_board.dart) își animă singură deznodământul.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _heartbeatTimer = Timer.periodic(MultiplayerService.matchHeartbeatInterval, (_) {
      _mp.matchHeartbeat(widget.matchId);
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _revealDelayTimer?.cancel();
    _advanceTimer?.cancel();
    _heartbeatTimer?.cancel();
    _lateSfxTimer?.cancel();
    super.dispose();
  }

  int get _roundTotalSeconds => obbyRoundSeconds;

  int _secondsLeftFor(MatchInfo info) {
    final started = info.roundStartedAt?.toDate();
    if (started == null) return _roundTotalSeconds;
    final elapsed = DateTime.now().difference(started).inSeconds;
    return (_roundTotalSeconds - elapsed).clamp(0, _roundTotalSeconds);
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
      await _mp.leaveMatch(widget.matchId);
    } catch (e) {
      debugPrint('MultiplayerObbyScreen._leave: leaveMatch a esuat: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  void _selectAnswer(MatchInfo info, MatchPlayer? myPlayer, List<MatchPlayer> players, String answer) {
    if (info.roundPhase != RoundPhase.answering) return;
    if (myPlayer == null || myPlayer.obstaclesCleared >= obbyObstacleCount) return;
    final me = _mp.currentPlayerId;
    if (info.roundAnswers.containsKey(me)) return;
    _mp.submitRoundAnswer(matchId: widget.matchId, roundIndex: info.roundIndex, answer: answer);

    // Recompensa imediată (punctul 4 din planul de viitor): corectitudinea
    // se știe PE LOC — întrebarea și răspunsul corect sunt deja pe telefon
    // (vezi _questionFor), nu vin de la server. Nu se așteaptă rezolvarea
    // rundei (asta poate dura până la [obbyRoundSeconds]s), altfel
    // recompensa n-ar mai fi "imediată", ar fi tot una cu premiul de final.
    final correct = answer == _questionFor(info.roundIndex).answer;
    // „Ploaie de Power-Up": primește și cine a greșit (vezi grantsPowerUp).
    if (!correct && roundEventFor(matchId: widget.matchId, roundIndex: info.roundIndex, gameModeId: 'obby') == RoundEvent.powerUpRain) {
      _maybeGrantPowerUp(info, players, me);
    }
    if (correct) {
      // Cu boți nu: ar fi o fermă de monede fără plafon (recompensa lor e doar
      // cea de la final, vezi core/bot_brain.dart#botMatchReward).
      if (widget.bot == null) {
        StorageService.addCoins(obbyInstantCoinsPerCorrect);
        setState(() => _instantCoinsThisMatch += obbyInstantCoinsPerCorrect);
        if (mounted) {
          CoinRewardOverlay.show(
            context,
            amount: obbyInstantCoinsPerCorrect,
            targetKey: _coinPillKey,
          );
        }
      }
      _maybeGrantPowerUp(info, players, me);
    }
  }

  /// Vezi core/powerups.dart — acordat cui a răspuns corect, cu șansă mai
  /// mare pentru cine e mai în urmă la obstacole trecute.
  void _maybeGrantPowerUp(MatchInfo info, List<MatchPlayer> players, String me) {
    final ranked = List.of(players)..sort((a, b) => b.obstaclesCleared.compareTo(a.obstaclesCleared));
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
      event: roundEventFor(matchId: widget.matchId, roundIndex: info.roundIndex, gameModeId: 'obby'),
    );
    if (!granted) return;
    final picked = powerUpFor(
      matchId: widget.matchId,
      roundIndex: info.roundIndex,
      playerId: me,
      gameModeId: 'obby',
      livePlayers: players.where((p) => !p.eliminated).length,
    );
    setState(() => _myPowerUps = [..._myPowerUps, picked]);
    Sfx.rewardPop();
    announcePowerUp(context, picked);
  }

  /// Consumă puterea [p] din inventar. [PowerUp.jetpack] și [PowerUp.sabotage]
  /// se scriu pe Firestore ([MultiplayerService.submitObbyPowerUp]/
  /// [MultiplayerService.useObbySabotage]) — [resolveObbyChoices] le
  /// citește de-acolo la calculul plăcilor, la fel ca mega rachetă/scut la
  /// Quizz Tanks și Scaunul Electric.
  Future<void> _usePowerUp(MatchInfo info, PowerUp p) async {
    if (p == PowerUp.none || !_myPowerUps.contains(p)) return;
    if (!powerUpUsableInPhase(p, info.roundPhase.name)) {
      notifyPowerUpTooLate(context);
      return; // păstrează puterea — nu o consuma pe o scriere care se pierde
    }
    if (_powerUpUsedRound == info.roundIndex) {
      notifyPowerUpAlreadyUsed(context);
      return;
    }
    Sfx.tileSelect();
    // Scrierile care afectează rezolvarea rundei verifică ÎN tranzacție, pe
    // server, că runda n-a trecut deja — `applied=false` = „prea târziu",
    // puterea rămâne în inventar (vezi [MultiplayerService._submitRoundPowerUp]).
    var applied = true;
    switch (p) {
      case PowerUp.fiftyFifty:
        if (info.roundPhase == RoundPhase.answering) {
          final q = _questionFor(info.roundIndex);
          final wrong = q.choices.where((c) => c != q.answer).toList();
          stableShuffle(wrong, stableHash('${widget.matchId}#${info.roundIndex}#5050'));
          setState(() => _hiddenChoices = wrong.take(max(0, wrong.length - 1)).toSet());
        }
      case PowerUp.jetpack:
        applied = await _mp.submitObbyPowerUp(matchId: widget.matchId, roundIndex: info.roundIndex, powerUp: p);
        if (!applied && mounted) notifyPowerUpTooLate(context);
      case PowerUp.sabotage:
        final victimId = await _mp.useObbySabotage(matchId: widget.matchId, roundIndex: info.roundIndex);
        applied = victimId != null;
        if (!applied) {
          if (mounted) notifySabotageNoTarget(context);
        } else if (mounted) {
          notifySabotageApplied(context, _playerNames[victimId] ?? '?');
        }
      case PowerUp.peek:
        showPeekResults(context, info, myId: _mp.currentPlayerId, playerNames: _playerNames);
      default:
        break;
    }
    if (!applied) return; // păstrează puterea — mesajul de motiv a fost deja arătat
    if (!mounted) return;
    setState(() {
      _myPowerUps = _myPowerUps.where((x) => x != p).toList();
      _powerUpUsedRound = info.roundIndex;
    });
  }

  /// Închide faza de răspuns. Nu mai acordă progres direct: cine a răspuns
  /// corect intră în faza de alegere a plăcii (vezi [_tryResolveChoices]).
  Future<void> _tryResolve(MatchInfo info) async {
    if (_resolving) return;
    _resolving = true;
    try {
      await _mp.closeObbyAnswering(
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
      await _mp.resolveObbyChoices(
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
    final me = _mp.currentPlayerId;
    if (!info.roundWinnerIds.contains(me)) return;
    if (info.roundPlatformChoices.containsKey(me)) return;
    // Confirmarea se aude ACUM, nu când vine snapshot-ul înapoi din
    // Firestore: la o conexiune slabă, un „toc" întârziat cu o secundă se
    // simte ca o apăsare care n-a fost înregistrată.
    ObbySfx.pick();
    _mp.submitObbyChoice(matchId: widget.matchId, roundIndex: info.roundIndex, platformIndex: index);
  }

  void _onPlatformChosenFromGame(int index) {
    final info = _latestInfo;
    if (info != null) _choosePlatform(info, index);
  }

  /// Tabla 2D pentru snapshot-ul curent.
  Widget _buildBoard(MatchInfo info, List<MatchPlayer> players) {
    final me = _mp.currentPlayerId;
    final revealing = info.roundPhase == RoundPhase.revealed;
    final racers = [
      for (final p in players)
        ObbyRacerData(
          id: p.id,
          name: p.name,
          color: pickAvatarColor(p.avatarSeed),
          progress: (p.obstaclesCleared / obbyObstacleCount).clamp(0.0, 1.0),
          isMe: p.id == me,
          outcome: revealing ? _outcomeFor(info, p.id) : ObbyRoundOutcome.none,
        ),
    ];
    // Scena de grup se vede TOT TIMPUL (cerință explicită a userului): toți
    // jucătorii, unul lângă altul în galaxie, în același cadru comun.
    // Singura excepție e faza de alegere a plăcii, unde fiecare își vede
    // propriile trei plăci — acolo cadrul chiar TREBUIE să fie individual.
    // În rest, [ObbyPhase.waiting] reutilizează scena de pistă cu toți pe
    // [ObbyRoundOutcome.none], deci stau pur și simplu pe loc.
    final phase = switch (info.roundPhase) {
      RoundPhase.choosing => _iAmChoosing(info) ? ObbyPhase.choosing : ObbyPhase.waiting,
      RoundPhase.revealed => ObbyPhase.revealed,
      _ => ObbyPhase.waiting,
    };
    final elapsed = _revealedAtLocal == null ? 0.0 : DateTime.now().difference(_revealedAtLocal!).inMilliseconds / 1000.0;
    final revealT = (elapsed / _revealSpanSeconds).clamp(0.0, 1.0);
    return ObbyBoard(
      phase: phase,
      racers: racers,
      myChoice: info.roundPlatformChoices[me],
      revealT: revealT,
      revealDuration: Duration(milliseconds: (_revealSpanSeconds * 1000).round()),
      onPlatformChosen: _onPlatformChosenFromGame,
    );
  }

  bool _iAmChoosing(MatchInfo info) {
    final me = _mp.currentPlayerId;
    return info.roundPhase == RoundPhase.choosing && info.roundWinnerIds.contains(me);
  }

  /// Sunetele deznodământului — o singură dată pe rundă (garda
  /// [_playedRevealSfx], resetată la schimbarea rundei), fiindcă metoda e
  /// chemată din [_onData], adică la fiecare snapshot Firestore.
  ///
  /// Se aude DOAR ce mi se întâmplă mie: cu până la șase alergători pe pistă,
  /// un sunet per personaj ar fi fost o hărmălaie din care n-aș fi înțeles ce
  /// am pățit eu — exact greșeala evitată și la Quizz Tanks, unde exploziile
  /// se adună într-una singură.
  void _playRevealSfx(MatchInfo info, List<MatchPlayer> players) {
    if (_playedRevealSfx) return;
    _playedRevealSfx = true;
    final me = _mp.currentPlayerId;
    switch (_outcomeFor(info, me)) {
      case ObbyRoundOutcome.jumped:
        var myCleared = 0;
        for (final p in players) {
          if (p.id == me) myCleared = p.obstaclesCleared;
        }
        // Ultima săritură are propriul sunet, în locul celui obișnuit. Se
        // pornește pe loc, nu după o pauză: trecerea ultimului obstacol
        // termină meciul, iar ecranul sare la clasament în aceeași clipă —
        // un timer ar fi fost anulat de dispose înainte să apuce să sune.
        // Sunetul deja pornit continuă peste ecranul de clasament, ceea ce e
        // exact ce trebuie: fanfara aparține momentului, nu ecranului.
        if (myCleared >= obbyObstacleCount) {
          ObbySfx.finish();
        } else {
          ObbySfx.jump();
        }
      case ObbyRoundOutcome.fell:
        // Sincronizat cu clipa în care placa cedează în scenă, nu cu
        // începutul deznodământului — vezi [obbyFallDelayFraction].
        final delayMs = (obbyFallDelayFraction * _revealSpanSeconds * 1000).round();
        _lateSfxTimer = Timer(Duration(milliseconds: delayMs), ObbySfx.fall);
      case ObbyRoundOutcome.none:
        break;
    }
  }

  /// Cât durează animația de deznodământ, în secunde — puțin mai scurtă decât
  /// [obbyRevealSeconds], ca mișcarea să se termine înainte să înceapă runda
  /// următoare, nu exact odată cu ea.
  double get _revealSpanSeconds => max(obbyRevealSeconds - 0.6, 0.4);

  /// Ce se vede în scenă pentru jucătorul [id] în deznodământul rundei.
  ///
  /// Cine n-a răspuns corect nu apare nici sărind, nici căzând: n-a ajuns
  /// niciodată în fața plăcilor, deci rămâne pur și simplu pe loc. Cădere
  /// înseamnă „a avut dreptul să aleagă și n-a ieșit bine" — fie a nimerit
  /// placa falsă, fie n-a ales nimic la timp (regula din core/obby.dart le
  /// tratează identic).
  ObbyRoundOutcome _outcomeFor(MatchInfo info, String id) {
    if (!info.roundWinnerIds.contains(id)) return ObbyRoundOutcome.none;
    return _advancedThisRound(info, id) ? ObbyRoundOutcome.jumped : ObbyRoundOutcome.fell;
  }

  void _onData(MatchInfo info, List<MatchPlayer> players) {
    _latestInfo = info;
    for (final p in players) {
      _playerNames[p.id] = p.name;
    }
    if (info.roundIndex != _lastRoundIndex) {
      _lastRoundIndex = info.roundIndex;
      _showAdvance = false;
      _revealedAtLocal = null;
      _playedRevealSfx = false;
      _hiddenChoices = const {};
      _lateSfxTimer?.cancel();
      _lateSfxTimer = null;
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
      _playRevealSfx(info, players);
      _revealDelayTimer ??= Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _showAdvance = true);
      });
      // Doar dacă meciul CONTINUĂ: la ultima rundă, o cerere de avansare ar
      // porni degeaba o rundă nouă într-un meci deja încheiat, exact în clipa
      // în care toată lumea pleacă spre clasament (aceeași gardă ca la Quizz
      // Tanks).
      if (info.status != MatchStatus.finished) {
        _advanceTimer ??= Timer(const Duration(seconds: obbyRevealSeconds), () {
          _mp.advanceObbyRound(matchId: widget.matchId, roundIndex: info.roundIndex);
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
            builder: (_) => MultiplayerResultsScreen(bot: widget.bot,matchId: widget.matchId, gameMode: MatchGameMode.obby),
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
                  final me = _mp.currentPlayerId;
                  MatchPlayer? myPlayer;
                  for (final p in players) {
                    if (p.id == me) {
                      myPlayer = p;
                      break;
                    }
                  }
                  final iAnswered = info.roundAnswers.containsKey(me);
                  return Column(
                    children: [
                      _buildTopBar(info),
                      Expanded(
                        // Tabla 2D e MEREU vizibilă — inclusiv sub întrebare.
                        child: ClipRect(
                          child: Stack(
                            children: [
                              Positioned.fill(child: _buildBoard(info, players)),
                              Positioned.fill(
                                child: switch (info.roundPhase) {
                                  RoundPhase.revealed => _buildRaceScene(info, players, myPlayer),
                                  RoundPhase.choosing when _iAmChoosing(info) => _buildChoosingScene(info),
                                  RoundPhase.choosing => _buildWaitingCaption(
                                      tr('Ceilalți își aleg placa...', 'The others are picking their platform...')),
                                  RoundPhase.answering when iAnswered => _buildWaitingCaption(
                                      tr('✓ Ai răspuns! Aștepți ceilalți concurenți...', '✓ You answered! Waiting for the other racers...')),
                                  _ => _buildAnsweringScene(info, myPlayer, players),
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Jos, nu sus (unde acoperea textul întrebării pe
                      // telefoane mici) — cerință directă a userului. `X`
                      // pe puterile care n-au fereastră ACUM în faza curentă
                      // (vezi powerUpUsableInPhase).
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: PowerUpBar(
                          powerUps: _myPowerUps,
                          usedThisRound: _powerUpUsedRound == info.roundIndex,
                          usableNow: (p) => powerUpUsableInPhase(p, info.roundPhase.name),
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
    );
  }

  Widget _buildTopBar(MatchInfo info) {
    final doubleRound = obbyIsDoubleRound(matchId: widget.matchId, roundIndex: info.roundIndex);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 20, 4),
          child: Row(
            children: [
              IconButton(onPressed: _leave, icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70)),
              const SizedBox(width: 4),
              const Text('Obby', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              // Pastila de monede instant — ținta zborului de monede din
              // CoinRewardOverlay (vezi _selectAnswer). Balanța reală s-a
              // schimbat deja; cifra de-aici e doar contorul VIZIBIL al
              // meciului curent.
              Container(
                key: _coinPillKey,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.coin.withAlpha(40), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.monetization_on_rounded, color: AppColors.coin, size: 13),
                    const SizedBox(width: 3),
                    Text('+$_instantCoinsThisMatch', style: const TextStyle(color: AppColors.coin, fontSize: 12, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const Spacer(),
              const SizedBox(width: 8),
              Text(
                tr('Runda ${(info.roundIndex + 1).clamp(1, obbyObstacleCount)}/$obbyObstacleCount',
                    'Round ${(info.roundIndex + 1).clamp(1, obbyObstacleCount)}/$obbyObstacleCount'),
                style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        RoundEventBanner(
          event: roundEventFor(matchId: widget.matchId, roundIndex: info.roundIndex, gameModeId: 'obby'),
          compact: true,
        ),
        if (doubleRound)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFFB020)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tr('🔥 Rundă Dublă — placa bună trece DOUĂ obstacole!', '🔥 Double Round — the good platform clears TWO obstacles!'),
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Faza de răspuns: întrebarea PESTE scena cu toți jucătorii ──────────
  //
  // Nu mai ascunde scena (cerință explicită a userului): întrebarea și
  // variantele plutesc peste imaginea comună, jos, ca personajele să rămână
  // vizibile deasupra lor. Personajul din colț a dispărut — n-are rost, îți
  // vezi propriul astronaut chiar în scenă, marcat cu un triunghi alb
  // deasupra capului (vezi _RunnerComponent.render).

  Widget _buildAnsweringScene(MatchInfo info, MatchPlayer? myPlayer, List<MatchPlayer> players) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildQuestion(info),
            const SizedBox(height: 10),
            _buildActionArea(info, myPlayer, players),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion(MatchInfo info) {
    final question = _questionFor(info.roundIndex);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // Opac ca textul să rămână lizibil peste stele/personaje, dar NU pe
        // tot ecranul — scena se vede în continuare deasupra panoului.
        color: Colors.black.withAlpha(170),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24, width: 1.4),
      ),
      child: Column(
        children: [
          CountdownRing(secondsLeft: _secondsLeftFor(info), totalSeconds: _roundTotalSeconds, size: 36),
          const SizedBox(height: 8),
          Text(
            question.question,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
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

    // Odată ce am răspuns, ecranul ăsta nu se mai vede deloc — camera trece
    // pe tabla 2D (vezi switch-ul din [build] + [_buildWaitingCaption]),
    // deci nu mai e nevoie de un mesaj "ai răspuns" aici.
    final me = _mp.currentPlayerId;

    // Bonusul câștigat în runda trecută se vede ABIA aici: două variante în
    // loc de patru. Până acum, câmpul era scris și stins corect în Firestore,
    // dar niciun ecran nu-l citea, deci mesajul „Bonus la întrebarea
    // următoare" din deznodământ nu se întâmpla niciodată.
    final bonus = myPlayer.nextQuestionBonus;
    final choices = bonus
        ? obbyBonusChoices(
            choices: _choicesFor(info.roundIndex),
            correctAnswer: _questionFor(info.roundIndex).answer,
            matchId: widget.matchId,
            roundIndex: info.roundIndex,
            playerId: me,
          )
        : _choicesFor(info.roundIndex);
    final visible = choices.where((c) => !_hiddenChoices.contains(c)).toList();
    final correct = _questionFor(info.roundIndex).answer;
    return Column(
      children: [
        if (bonus)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              tr('⚡ Bonus: două variante eliminate', '⚡ Bonus: two options removed'),
              style: const TextStyle(color: AppColors.play, fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
          ),
        for (var i = 0; i < visible.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(child: _choiceButton(visible[i], visible[i] == correct, () => _selectAnswer(info, myPlayer, players, visible[i]))),
                if (i + 1 < visible.length) ...[
                  const SizedBox(width: 10),
                  Expanded(child: _choiceButton(visible[i + 1], visible[i + 1] == correct, () => _selectAnswer(info, myPlayer, players, visible[i + 1]))),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _choiceButton(String label, bool isCorrect, VoidCallback onTap) {
    // Toggle-ul de admin „vezi răspunsul corect" (core/admin_reveal.dart) —
    // conturează varianta corectă cu chihlimbar. Pur vizual.
    final adminHint = adminAnswerRevealOn && isCorrect;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: (adminHint ? adminRevealColor : AppColors.teal).withAlpha(adminHint ? 45 : 35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: adminHint ? adminRevealColor : AppColors.teal, width: adminHint ? 2.4 : 1.4),
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

  /// Legenda mică din partea de sus a ecranului cât camera stă pe mine, dar
  /// nu sunt eu cel care acționează chiar acum — cerută explicit de user, ca
  /// să nu mai acopere tabla 2D cu un text centrat, opac, pe tot
  /// ecranul (asta era comportamentul vechi cât alții alegeau placa).
  Widget _buildWaitingCaption(String text) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: Colors.black.withAlpha(130), borderRadius: BorderRadius.circular(14)),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  // ─── Faza de alegere a pătratului (↖ ▲ ↗, pe tabla 2D) ──────────────────

  /// Apelată DOAR când eu sunt cel care alege (vezi switch-ul din [build]) —
  /// cazul "nu sunt eu cel care alege" arată acum legenda scurtă de sub
  /// tabla 2D, vezi [_buildWaitingCaption].
  Widget _buildChoosingScene(MatchInfo info) {
    final me = _mp.currentPlayerId;
    final myChoice = info.roundPlatformChoices[me];

    return Stack(
      children: [
        // tabla 2D (pătratul meu + cele 3 din față) e montată o
        // singură dată, mai sus în build — aici doar suprapunem UI-ul.
        Positioned(
          left: 16,
          right: 16,
          top: 8,
          child: Column(
            children: [
              CountdownRing(secondsLeft: _choiceSecondsLeftFor(info), totalSeconds: obbyChoiceSeconds, size: 40),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.black.withAlpha(120), borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    Text(
                      tr('Ai răspuns corect! Pe ce pătrat sari?', 'Correct! Which square do you jump to?'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr('Unul din ele e fals și cazi prin el. Apasă ↖ ▲ sau ↗.',
                          'One of them is fake and you fall through. Tap ↖ ▲ or ↗.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (myChoice != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 60,
            child: Center(
              child: Text(
                tr('✓ Ai sărit! Se așteaptă ceilalți...', '✓ You jumped! Waiting for the others...'),
                style: const TextStyle(color: AppColors.play, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Faza de reveal: tabla comună ───────────────────

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
    final me = _mp.currentPlayerId;
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
    return Stack(
      children: [
        // tabla (widgets/obby_board.dart) e montată o singură dată mai sus în build.
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


