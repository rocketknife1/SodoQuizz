import 'dart:async';
import 'dart:math';

import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import '../../core/audio.dart';
import '../../core/lang.dart';
import '../../core/obby.dart';
import '../../core/stable_hash.dart';
import '../../core/theme.dart';
import '../../data/culture_questions.dart';
import '../../data/multiplayer_service.dart';
import '../../data/storage_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/coin_reward_overlay.dart';
import '../../widgets/countdown_ring.dart';
import '../../widgets/obby_game.dart';
import 'multiplayer_results_screen.dart';

/// **Obby** — cursă de obstacole tip Roblox, de la 2 la [obbyMaxPlayers]
/// personaje pe aceeași pistă (vezi core/obby.dart): ecranul nu decide nimic, citește
/// rezultatul rundei din Firestore și îl animează. ORICE client poate cere
/// rezolvarea rundei.
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

  /// Jocul Flame — o singură instanță pentru tot ecranul, creată o dată și
  /// hrănită cu date noi la fiecare snapshot (vezi [_onData]/[_feedGame]).
  /// NU importă multiplayer_service.dart, primește doar acest callback.
  late final ObbyGame _game = ObbyGame(onPlatformChosen: _onPlatformChosenFromGame);
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
    // Sunetele modului se încarcă abia acum, nu la pornirea aplicației —
    // vezi ObbySfx pentru de ce.
    ObbySfx.preload();
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
    _lateSfxTimer?.cancel();
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

    // Recompensa imediată (punctul 4 din planul de viitor): corectitudinea
    // se știe PE LOC — întrebarea și răspunsul corect sunt deja pe telefon
    // (vezi _questionFor), nu vin de la server. Nu se așteaptă rezolvarea
    // rundei (asta poate dura până la [obbyRoundSeconds]s), altfel
    // recompensa n-ar mai fi "imediată", ar fi tot una cu premiul de final.
    if (answer == _questionFor(info.roundIndex).answer) {
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
    // Confirmarea se aude ACUM, nu când vine snapshot-ul înapoi din
    // Firestore: la o conexiune slabă, un „toc" întârziat cu o secundă se
    // simte ca o apăsare care n-a fost înregistrată.
    ObbySfx.pick();
    MultiplayerService.instance.submitObbyChoice(matchId: widget.matchId, platformIndex: index);
  }

  void _onPlatformChosenFromGame(int index) {
    final info = _latestInfo;
    if (info != null) _choosePlatform(info, index);
  }

  /// Hrănește jocul Flame cu snapshot-ul curent — apelat din [_onData], deci
  /// la fiecare rebuild al StreamBuilder-ului. [ObbyGame.applyRoundState] e
  /// idempotent, deci a-l chema des (inclusiv fără schimbări) e sigur.
  void _feedGame(MatchInfo info, List<MatchPlayer> players) {
    final me = MultiplayerService.instance.currentPlayerId;
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
    _game.applyRoundState(
      phase: phase,
      racers: racers,
      myChoice: info.roundPlatformChoices[me],
      revealT: revealT,
    );
  }

  bool _iAmChoosing(MatchInfo info) {
    final me = MultiplayerService.instance.currentPlayerId;
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
    final me = MultiplayerService.instance.currentPlayerId;
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
    if (info.roundIndex != _lastRoundIndex) {
      _lastRoundIndex = info.roundIndex;
      _showAdvance = false;
      _revealedAtLocal = null;
      _playedRevealSfx = false;
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

    _feedGame(info, players);
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
                  final iAnswered = info.roundAnswers.containsKey(me);
                  return Column(
                    children: [
                      _buildTopBar(info),
                      Expanded(
                        // Scena Flame e MEREU vizibilă acum — inclusiv sub
                        // întrebare. UN SINGUR GameWidget pentru tot ecranul:
                        // două instanțe pe același joc (una per fază) aruncau
                        // la fiecare schimbare de fază.
                        child: Stack(
                          children: [
                            Positioned.fill(child: GameWidget(game: _game)),
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
              Text(
                tr('Runda ${(info.roundIndex + 1).clamp(1, obbyObstacleCount)}/$obbyObstacleCount',
                    'Round ${(info.roundIndex + 1).clamp(1, obbyObstacleCount)}/$obbyObstacleCount'),
                style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
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
          CountdownRing(secondsLeft: _secondsLeftFor(info), totalSeconds: obbyRoundSeconds, size: 36),
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
    // pe scena 3rd-person (vezi switch-ul din [build] + [_buildWaitingCaption]),
    // deci nu mai e nevoie de un mesaj "ai răspuns" aici.
    final me = MultiplayerService.instance.currentPlayerId;

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

  /// Legenda mică din partea de sus a ecranului cât camera stă pe mine, dar
  /// nu sunt eu cel care acționează chiar acum — cerută explicit de user, ca
  /// să nu mai acopere scena 3rd-person cu un text centrat, opac, pe tot
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

  // ─── Faza de alegere a plăcii ───────────────────────────────────────────
  // PROVIZORIU (etapa 1): butoane simple. Se înlocuiesc cu plăci desenate în
  // scena Flame, dar rămân ca variantă de rezervă
  // (tap direct), nu se aruncă.

  /// Apelată DOAR când eu sunt cel care alege (vezi switch-ul din [build]) —
  /// cazul "nu sunt eu cel care alege" arată acum legenda scurtă de sub
  /// scena 3rd-person, vezi [_buildWaitingCaption].
  Widget _buildChoosingScene(MatchInfo info) {
    final me = MultiplayerService.instance.currentPlayerId;
    final myChoice = info.roundPlatformChoices[me];

    return Stack(
      children: [
        // scena Flame (personajul + cele 3 plăci) e montată o
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
                      tr('Ai răspuns corect! Pe ce placă sari?', 'Correct! Which platform do you jump on?'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr('Una din ele e falsă și cazi prin ea. Apasă placa pe care vrei să sari.',
                          'One of them is fake and you fall through. Tap the platform you want to jump on.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // butoane de rezervă — aceeași alegere ca tap-ul direct pe placă din
        // scenă, pentru accesibilitate și pentru cazul rar în care Flame nu
        // randează corect pe un device anume.
        Positioned(
          left: 16,
          right: 16,
          bottom: 220,
          child: Row(
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
    return Stack(
      children: [
        // camera 3rd-person (ObbyGame._buildRevealScene / camera.follow) e
        // montată o singură dată mai sus în build.
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


