import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../core/audio.dart';
import '../../core/lang.dart';
import '../../core/stable_hash.dart';
import '../../core/tanks.dart';
import '../../core/theme.dart';
import '../../data/culture_questions.dart';
import '../../data/multiplayer_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/avatar.dart';
import '../../widgets/tank_art.dart';
import 'multiplayer_results_screen.dart';

/// **Quizz Tanks** — patru tancuri, întrebări de cultură generală, cinci
/// secunde de răspuns și bare de viață de 100. Cine răspunde corect trage în
/// toți adversarii rămași; cine a răspuns corect e și mai greu de lovit.
/// Regulile și toate cifrele stau în core/tanks.dart, rezolvarea rundei în
/// MultiplayerService.resolveTanksRound.
///
/// CE FACE ECRANUL ĂSTA ȘI CE NU: nu decide nimic. Întrebările le are local
/// (pool comun, amestecat determinist din `matchId` — vezi core/stable_hash.dart
/// pentru de ce NU se poate folosi `shuffle(Random(matchId.hashCode))`), iar
/// rezultatul rundei îl CITEȘTE din Firestore și îl animează. Zarurile se
/// aruncă o singură dată, în tranzacția care rezolvă runda, indiferent care
/// dintre cele patru telefoane apucă s-o facă.
///
/// Ca la Higher & Lower, ORICE client poate cere rezolvarea rundei și
/// trecerea la următoarea — meciul nu are voie să se blocheze dacă pleacă
/// tocmai gazda.
class MultiplayerTanksScreen extends StatefulWidget {
  final String matchId;
  const MultiplayerTanksScreen({super.key, required this.matchId});

  @override
  State<MultiplayerTanksScreen> createState() => _MultiplayerTanksScreenState();
}

class _MultiplayerTanksScreenState extends State<MultiplayerTanksScreen> with SingleTickerProviderStateMixin {
  late final List<CultureQuestion> _pool = _buildPool();

  late final Stream<MatchInfo> _matchStream = MultiplayerService.instance.watchMatch(widget.matchId);
  late final Stream<List<MatchPlayer>> _playersStream = MultiplayerService.instance.watchPlayers(widget.matchId);

  /// Controlerul întregului spectacol de după rundă (tunuri, proiectile,
  /// impacturi, bare care scad, epave). Rulează exact [tanksRevealSeconds],
  /// iar toți timpii de mai jos sunt secunde în interiorul lui.
  late final AnimationController _fire = AnimationController(
    vsync: this,
    duration: const Duration(seconds: tanksRevealSeconds),
  );

  /// Coregrafia fazei de foc, în secunde. Prima jumătate de secundă e
  /// pauza în care se citește „FOC!" și se vede cine trage — fără ea,
  /// proiectilele apar înainte ca ochiul să apuce să găsească tunurile.
  static const double _firstShotAt = 0.45;
  static const double _shotStagger = 0.10;
  static const double _drainDuration = 0.6;

  Timer? _tick;
  Timer? _advanceTimer;
  int _lastRoundIndex = -1;
  bool _resolving = false;
  bool _navigatedToResults = false;

  /// Viața fiecărui tanc la ÎNCEPUTUL rundei curente — reperul din care
  /// coboară „fantoma" barei (vezi TankHpBar). Se ia o singură dată pe
  /// rundă, cât suntem încă în faza de răspuns.
  final Map<String, int> _hpAtRoundStart = {};

  List<ShotFlight> _flights = const [];
  int _flightsBuiltForRound = -1;
  final Set<int> _playedShot = {};
  final Set<int> _playedImpact = {};
  bool _playedAlarm = false;
  bool _playedExplosions = false;

  /// Momentul în care se așază barele de viață și, imediat după, explodează
  /// epavele — calculat din ultimul impact al rundei (vezi [_ensureFlights]).
  double _drainStart = 0;
  int _pendingDestroyed = 0;

  /// Ultima cerere de rezolvare a rundei. Fără ea, `build` rulează de câteva
  /// ori pe secundă cât cronometrul e la zero, iar fiecare rulare ar porni o
  /// citire de jucători + o tranzacție Firestore care oricum nu poate face
  /// nimic (runda e deja rezolvată). Nu e doar un `bool`: dacă o încercare
  /// pică pe rețea, trebuie să existe și o a doua.
  DateTime? _lastResolveAttempt;

  /// Variantele rundei curente, amestecate o singură dată. Amestecarea e
  /// determinist ieftină, dar `build` se execută des — la 60 de cadre pe
  /// secundă cât durează focul, patru amestecări pe cadru sunt muncă
  /// degeaba.
  List<String>? _cachedChoices;
  int _cachedChoicesRound = -1;

  List<CultureQuestion> _buildPool() {
    final pool = List.of(cultureQuestions);
    stableShuffle(pool, stableHash(widget.matchId));
    return pool;
  }

  CultureQuestion _questionFor(int roundIndex) => _pool[roundIndex % _pool.length];

  /// Ordinea variantelor se amestecă și ea determinist, altfel răspunsul
  /// corect ar sta mereu pe aceeași poziție cât timp datele nu se schimbă —
  /// iar la a treia rundă lumea ar apăsa după poziție, nu după conținut.
  /// Sămânța include runda, ca aceeași întrebare să nu arate identic dacă
  /// pool-ul se reia într-un meci foarte lung.
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
    // vezi TankSfx pentru de ce.
    TankSfx.preload();
    _fire.addListener(_onFireTick);
    // Nicio actualizare Firestore nu vine „din ceas", dar cronometrul de 5
    // secunde trebuie să scadă vizibil în fiecare secundă.
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _advanceTimer?.cancel();
    _fire.removeListener(_onFireTick);
    _fire.dispose();
    super.dispose();
  }

  int _secondsLeftFor(MatchInfo info) => _secondsLeft(info, tanksRoundSeconds);

  /// Cronometrul fazei de țintire pornește de la zero: [closeTanksAnswering]
  /// rescrie `roundStartedAt` când intră în fază, tocmai ca secundele de aici
  /// să nu le continue pe cele de răspuns.
  int _targetSecondsLeftFor(MatchInfo info) => _secondsLeft(info, tanksTargetSeconds);

  int _secondsLeft(MatchInfo info, int total) {
    final started = info.roundStartedAt?.toDate();
    if (started == null) return total;
    final elapsed = DateTime.now().difference(started).inSeconds;
    return (total - elapsed).clamp(0, total);
  }

  Future<void> _leave() async {
    try {
      await MultiplayerService.instance.leaveMatch(widget.matchId);
    } catch (e) {
      debugPrint('MultiplayerTanksScreen._leave: leaveMatch a esuat: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  void _answer(MatchInfo info, String choice) {
    if (info.roundPhase != RoundPhase.answering) return;
    final me = MultiplayerService.instance.currentPlayerId;
    if (info.roundAnswers.containsKey(me)) return;
    Sfx.tileSelect();
    MultiplayerService.instance.submitRoundAnswer(matchId: widget.matchId, answer: choice);
  }

  void _pickTarget(MatchInfo info, String targetId) {
    if (info.roundPhase != RoundPhase.targeting) return;
    final me = MultiplayerService.instance.currentPlayerId;
    if (!info.roundWinnerIds.contains(me) || info.roundTargets.containsKey(me)) return;
    TankSfx.lock();
    MultiplayerService.instance.submitTanksTarget(matchId: widget.matchId, targetId: targetId);
  }

  /// Închiderea fazei de răspuns și tragerea propriu-zisă merg prin aceeași
  /// frână: `build` rulează de câteva ori pe secundă cât cronometrul e la
  /// zero, iar fiecare rulare ar porni o citire de jucători + o tranzacție
  /// care oricum n-are ce face (faza s-a schimbat deja). Nu e un simplu
  /// `bool`, ca o încercare picată pe rețea să mai poată fi reluată.
  Future<void> _advancePhase(MatchInfo info) async {
    if (_resolving) return;
    final now = DateTime.now();
    if (_lastResolveAttempt != null && now.difference(_lastResolveAttempt!) < const Duration(milliseconds: 1200)) {
      return;
    }
    _lastResolveAttempt = now;
    _resolving = true;
    try {
      if (info.roundPhase == RoundPhase.answering) {
        await MultiplayerService.instance.closeTanksAnswering(
          matchId: widget.matchId,
          roundIndex: info.roundIndex,
          correctAnswer: _questionFor(info.roundIndex).answer,
        );
      } else if (info.roundPhase == RoundPhase.targeting) {
        await MultiplayerService.instance.resolveTanksRound(
          matchId: widget.matchId,
          roundIndex: info.roundIndex,
        );
      }
    } finally {
      _resolving = false;
    }
  }

  // ─── Sunet, sincronizat cu animația ───────────────────────────────────

  /// Sunetele nu se pot programa cu timere separate: faza de foc pornește
  /// când AJUNGE documentul din Firestore, deci singurul ceas de încredere e
  /// chiar controlerul animației. Fiecare proiectil își trage sunetul o
  /// singură dată — de-aia seturile de indici, nu un simplu contor.
  void _onFireTick() {
    if (_flights.isEmpty) return;
    final t = _fire.value * tanksRevealSeconds;
    for (var i = 0; i < _flights.length; i++) {
      final f = _flights[i];
      if (t >= f.startAt && _playedShot.add(i)) TankSfx.fire();
      if (t >= f.impactAt && _playedImpact.add(i)) {
        if (f.hit) {
          TankSfx.hit();
        } else {
          TankSfx.dodge();
        }
      }
    }
    // Explozia tancurilor distruse vine DUPĂ ce s-au terminat impacturile,
    // ca să nu se piardă în ele: e evenimentul cel mai important al rundei.
    if (!_playedExplosions && t >= _drainStart + _drainDuration) {
      _playedExplosions = true;
      if (_pendingDestroyed > 0) TankSfx.explode();
    }
    // Fără setState aici, deliberat: arena se redesenează singură, fiind
    // învelită într-un AnimatedBuilder legat de [_fire]. Un setState pe
    // cadru ar fi reconstruit și panoul de jos (întrebare + variante), care
    // n-are ce animație să urmărească.
  }

  // ─── Efecte derivate din datele live ──────────────────────────────────

  /// Apelat din build, ca RoomLobbyScreen._maybeNavigateToMatch și
  /// MultiplayerHigherLowerScreen._onData: pornește/oprește animații,
  /// cere rezolvarea rundei, navighează la rezultate.
  void _onData(MatchInfo info, List<MatchPlayer> players) {
    if (info.roundIndex != _lastRoundIndex) {
      _lastRoundIndex = info.roundIndex;
      _hpAtRoundStart
        ..clear()
        ..addEntries(players.map((p) => MapEntry(p.id, p.hp)));
      _flights = const [];
      _flightsBuiltForRound = -1;
      _playedShot.clear();
      _playedImpact.clear();
      _playedAlarm = false;
      _playedExplosions = false;
      _lastResolveAttempt = null;
      _advanceTimer?.cancel();
      _advanceTimer = null;
      // Post-frame, nu aici: [_onData] rulează CHIAR ÎN TIMPUL build-ului, iar
      // `reset()` schimbă valoarea controlerului, ceea ce ar cere o
      // reconstruire a AnimatedBuilder-ului din arenă în mijlocul
      // construcției lui — exact eroarea „setState called during build".
      // Un cadru cu valoarea veche nu se vede: [_flights] e deja golită mai
      // sus, deci nu se desenează nimic din runda trecută.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fire.reset();
      });
    }

    if (info.roundPhase == RoundPhase.answering) {
      final aliveIds = players.where((p) => !p.eliminated).map((p) => p.id).toSet();
      final allAnswered = aliveIds.isNotEmpty && aliveIds.every(info.roundAnswers.containsKey);
      final timedOut = _secondsLeftFor(info) <= 0;
      // Ultimele două secunde: un bip scurt. La cinci secunde pe rundă, cine
      // se uită la variante nu are cum să vadă și cronometrul.
      if (!_playedAlarm && !allAnswered && _secondsLeftFor(info) <= 2) {
        _playedAlarm = true;
        final me = MultiplayerService.instance.currentPlayerId;
        final iAmOut = players.any((p) => p.id == me && p.eliminated);
        if (!info.roundAnswers.containsKey(me) && !iAmOut) TankSfx.alarm();
      }
      if (allAnswered || timedOut) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _advancePhase(info));
      }
    } else if (info.roundPhase == RoundPhase.targeting) {
      // Se trage când toți țintașii ȘI-AU ALES victima, sau când li s-a
      // scurs timpul. Un țintaș plecat din meci între timp nu blochează
      // runda: se numără doar cei încă la masă.
      final present = players.map((p) => p.id).toSet();
      final shooters = info.roundWinnerIds.where(present.contains);
      final allPicked = shooters.isNotEmpty && shooters.every(info.roundTargets.containsKey);
      if (allPicked || _targetSecondsLeftFor(info) <= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _advancePhase(info));
      }
    } else if (info.roundPhase == RoundPhase.revealed && info.status != MatchStatus.finished) {
      // Doar dacă meciul CONTINUĂ: la ultima rundă, o cerere de avansare ar
      // fi pornit degeaba o rundă nouă într-un meci deja încheiat, exact în
      // clipa în care toată lumea pleacă spre clasament.
      _advanceTimer ??= Timer(const Duration(seconds: tanksRevealSeconds), () {
        MultiplayerService.instance.advanceSyncRound(matchId: widget.matchId, roundIndex: info.roundIndex);
      });
    }

    if (info.status == MatchStatus.finished && !_navigatedToResults) {
      _navigatedToResults = true;
      // Meciul se încheie în aceeași scriere care rezolvă ultima rundă, deci
      // fără pauza asta lovitura decisivă n-ar apuca să fie văzută niciodată:
      // ecranul ar sări la clasament exact când pleacă proiectilul.
      Future.delayed(const Duration(seconds: tanksRevealSeconds), () {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MultiplayerResultsScreen(matchId: widget.matchId, gameMode: MatchGameMode.quizzTanks),
          ),
        );
      });
    }
  }

  /// Traduce tragerile citite din Firestore în traiectorii pe ecran. Se
  /// poate face abia când se știe cât de mare e arena, deci se cheamă din
  /// LayoutBuilder-ul ei — dar exact o dată pe rundă ([_flightsBuiltForRound]).
  void _ensureFlights(MatchInfo info, List<MatchPlayer> players, Map<String, Offset> centers) {
    if (_flightsBuiltForRound == info.roundIndex) return;
    if (info.roundPhase != RoundPhase.revealed) return;
    _flightsBuiltForRound = info.roundIndex;

    final seeds = {for (final p in players) p.id: p.avatarSeed};
    final flights = <ShotFlight>[];
    for (var i = 0; i < info.roundShots.length; i++) {
      final s = info.roundShots[i];
      final from = centers[s.byId];
      final to = centers[s.atId];
      if (from == null || to == null) continue; // jucător plecat între timp
      flights.add(ShotFlight(
        from: from,
        to: to,
        hit: s.hit,
        damage: s.damage,
        startAt: _firstShotAt + i * _shotStagger,
        color: pickAvatarColor(seeds[s.byId] ?? s.byId),
      ));
    }
    _flights = flights;
    _pendingDestroyed = info.roundDestroyedIds.length;
    _drainStart = flights.isEmpty
        ? _firstShotAt
        : flights.map((f) => f.impactAt).reduce(max) + 0.15;
    // Post-frame din același motiv ca resetul din [_onData]: metoda asta e
    // chemată din build. La `from: 0` valoarea nu se schimbă (controlerul e
    // deja resetat), deci cadrul curent desenează corect timpul zero.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fire.forward(from: 0);
    });
  }

  /// Cât de „scursă" e bara în clipa asta: 0 cât proiectilele sunt încă în
  /// aer, 1 după ce s-au așezat toate.
  double get _drainProgress {
    if (_flightsBuiltForRound == -1 || _flights.isEmpty) return 1;
    final t = _fire.value * tanksRevealSeconds;
    return ((t - _drainStart) / _drainDuration).clamp(0.0, 1.0);
  }

  /// Zguduitura ecranului la impact — mică (max 5 px) și scurtă, cât să se
  /// simtă lovitura fără să facă textul ilizibil.
  Offset get _shake {
    if (_flights.isEmpty) return Offset.zero;
    final t = _fire.value * tanksRevealSeconds;
    var strength = 0.0;
    for (final f in _flights) {
      if (!f.hit) continue;
      final since = t - f.impactAt;
      if (since >= 0 && since < 0.22) {
        strength = max(strength, (1 - since / 0.22) * (f.damage / tanksDamageMax));
      }
    }
    if (strength <= 0) return Offset.zero;
    return Offset(sin(t * 78) * 5 * strength, cos(t * 61) * 3.5 * strength);
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
                  return const Center(child: CircularProgressIndicator(color: AppColors.blue));
                }
                return StreamBuilder<List<MatchPlayer>>(
                  stream: _playersStream,
                  builder: (context, playersSnap) {
                    final players = List.of(playersSnap.data ?? const <MatchPlayer>[])
                      // aceeași ordine pe toate telefoanele (și aceeași cu
                      // ordinea tragerilor din serviciu), ca poziția din arenă
                      // să fie un reper comun, nu o surpriză locală.
                      ..sort((a, b) => a.id.compareTo(b.id));
                    _onData(info, players);
                    // Țintirea ia ecranul CU TOTUL, nu e o bară în plus sub
                    // arenă: e singurul moment din rundă în care jucătorul ia
                    // o decizie despre altcineva, iar dacă ar sta lângă
                    // întrebare ar fi tratată ca încă un buton de apăsat.
                    if (info.roundPhase == RoundPhase.targeting) {
                      return _TargetingView(
                        info: info,
                        players: players,
                        question: _questionFor(info.roundIndex),
                        secondsLeft: _targetSecondsLeftFor(info),
                        onPick: (id) => _pickTarget(info, id),
                      );
                    }
                    return Column(
                      children: [
                        _buildTopBar(info),
                        Expanded(child: _buildArena(info, players)),
                        _buildBottomPanel(info, players),
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
    final seconds = _secondsLeftFor(info);
    final answering = info.roundPhase == RoundPhase.answering;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 2),
      child: Row(
        children: [
          IconButton(onPressed: _leave, icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70)),
          const Text(
            'QUIZZ TANKS',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2.2),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(16),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              tr('RUNDA ${info.roundIndex + 1}', 'ROUND ${info.roundIndex + 1}'),
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
          ),
          const SizedBox(width: 10),
          // În faza de foc cronometrul n-are ce număra: acolo se arată o
          // țintă aprinsă, ca să fie limpede că nu mai e nimic de apăsat.
          AnimatedScale(
            duration: const Duration(milliseconds: 180),
            scale: answering && seconds <= 2 ? 1.14 : 1.0,
            child: answering
                ? _CountdownDial(seconds: seconds)
                : const Icon(Icons.gps_fixed_rounded, color: AppColors.orange, size: 30),
          ),
        ],
      ),
    );
  }

  // ─── Arena ────────────────────────────────────────────────────────────

  /// AnimatedBuilder, nu setState pe cadru: arena e singura parte a
  /// ecranului care se mișcă în cele patru secunde de foc.
  Widget _buildArena(MatchInfo info, List<MatchPlayer> players) {
    return AnimatedBuilder(
      animation: _fire,
      builder: (context, _) => _buildArenaFrame(info, players),
    );
  }

  Widget _buildArenaFrame(MatchInfo info, List<MatchPlayer> players) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        const sidePad = 14.0;
        final cellW = (c.maxWidth - sidePad * 2 - gap) / 2;
        // Cutiile cresc cât le lasă ecranul, până la o limită peste care
        // tancurile ar pluti într-o cutie goală. Grila iese aproape mereu mai
        // scundă decât spațiul primit (bara de jos e mică la o întrebare
        // scurtă), deci se CENTREAZĂ pe verticală — altfel rămânea lipită de
        // titlu, cu o bandă goală mare sub ea.
        final cellH = ((c.maxHeight - gap - 6) / 2).clamp(92.0, 168.0);
        final gridH = cellH * 2 + gap;
        final top = ((c.maxHeight - gridH) / 2).clamp(0.0, double.infinity);

        // Grila 2×2 e fixă: locul unui jucător e dat de poziția lui în lista
        // sortată, deci nu se mișcă de la o rundă la alta.
        final centers = <String, Offset>{};
        for (var i = 0; i < players.length && i < tanksPlayerCount; i++) {
          final col = i % 2;
          final row = i ~/ 2;
          centers[players[i].id] = Offset(
            sidePad + col * (cellW + gap) + cellW / 2,
            top + row * (cellH + gap) + cellH / 2,
          );
        }
        _ensureFlights(info, players, centers);

        return ClipRect(
          child: Transform.translate(
            offset: _shake,
            child: SizedBox(
              width: c.maxWidth,
              height: c.maxHeight,
              child: Stack(
                children: [
                  const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _BattlefieldPainter()))),
                  for (var i = 0; i < players.length && i < tanksPlayerCount; i++)
                    Positioned(
                      left: sidePad + (i % 2) * (cellW + gap),
                      top: top + (i ~/ 2) * (cellH + gap),
                      width: cellW,
                      height: cellH,
                      child: _TankCard(
                        player: players[i],
                        facingRight: i % 2 == 0,
                        isMe: players[i].id == MultiplayerService.instance.currentPlayerId,
                        hasAnswered: info.roundAnswers.containsKey(players[i].id),
                        showAnswerTicks: info.roundPhase == RoundPhase.answering,
                        isFiring: info.roundPhase == RoundPhase.revealed &&
                            info.roundShots.any((s) => s.byId == players[i].id) &&
                            _fire.value * tanksRevealSeconds >= _firstShotAt - 0.3,
                        previousHp: _hpAtRoundStart[players[i].id] ?? players[i].hp,
                        drainProgress: _drainProgress,
                        tankWidth: (cellW * 0.46).clamp(56.0, 96.0),
                      ),
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: TankShotsPainter(flights: _flights, time: _fire.value * tanksRevealSeconds),
                      ),
                    ),
                  ),
                  if (info.roundPhase == RoundPhase.revealed) _buildFireBanner(info),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// „FOC!" — o clipire scurtă peste arenă, în prima jumătate de secundă a
  /// fazei de tragere. Dacă nimeni n-a răspuns corect, scrie asta în loc:
  /// altfel o rundă fără niciun proiectil ar părea un bug.
  Widget _buildFireBanner(MatchInfo info) {
    final t = _fire.value * tanksRevealSeconds;
    if (t > _firstShotAt + 0.45) return const SizedBox.shrink();
    final noShots = info.roundShots.isEmpty;
    final fade = (1 - (t / (_firstShotAt + 0.45))).clamp(0.0, 1.0);
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Opacity(
            opacity: noShots ? 1.0 : fade,
            child: Transform.scale(
              scale: 1 + (1 - fade) * 0.5,
              child: Text(
                noShots ? tr('NIMENI N-A NIMERIT', 'NOBODY SCORED') : tr('FOC!', 'FIRE!'),
                style: TextStyle(
                  color: noShots ? Colors.white70 : AppColors.orange,
                  fontSize: noShots ? 15 : 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  shadows: const [Shadow(color: Colors.black87, blurRadius: 12)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Întrebarea și variantele ─────────────────────────────────────────

  Widget _buildBottomPanel(MatchInfo info, List<MatchPlayer> players) {
    final me = MultiplayerService.instance.currentPlayerId;
    final iAmDestroyed = players.any((p) => p.id == me && p.eliminated);
    final question = _questionFor(info.roundIndex);
    final revealed = info.roundPhase == RoundPhase.revealed;
    final myAnswer = info.roundAnswers[me];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(70),
        border: Border(top: BorderSide(color: Colors.white.withAlpha(20))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            question.question,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.25),
          ),
          const SizedBox(height: 10),
          if (iAmDestroyed)
            _buildSpectatorNote()
          else
            ...List.generate(4, (i) {
              final choices = _choicesFor(info.roundIndex);
              if (i >= choices.length) return const SizedBox.shrink();
              final choice = choices[i];
              return Padding(
                padding: EdgeInsets.only(bottom: i == 3 ? 0 : 6),
                child: _AnswerButton(
                  letter: String.fromCharCode(65 + i),
                  text: choice,
                  picked: myAnswer == choice,
                  // Răspunsul corect se arată abia în faza de foc — până
                  // atunci nimeni nu vede nimic, nici măcar propria greșeală.
                  correct: revealed && choice == question.answer,
                  dimmed: myAnswer != null && myAnswer != choice && !revealed,
                  onTap: myAnswer == null && !revealed ? () => _answer(info, choice) : null,
                ),
              );
            }),
          if (!iAmDestroyed && myAnswer != null && !revealed) ...[
            const SizedBox(height: 8),
            Text(
              tr('✓ ARMAT — aștept ceilalți jucători', '✓ LOADED — waiting for the others'),
              style: const TextStyle(color: AppColors.play, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpectatorNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.danger.withAlpha(28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withAlpha(120)),
      ),
      child: Text(
        tr('💥 Tancul tău a fost distrus. Rămâi și te uiți până la final — '
            'prada se împarte după daunele făcute, iar ale tale sunt deja socotite.',
            '💥 Your tank is wrecked. Stay and watch to the end — the salvage is '
                'split by damage dealt, and yours is already counted.'),
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// **Ecranul de țintire** — se arată tuturor între răspuns și foc, dar
/// arată complet diferit după cum ai nimerit sau nu întrebarea:
///
///  • cine a răspuns CORECT alege victima dintre adversarii rămași în viață,
///    din cutii mari, cu viața la vedere;
///  • cine a greșit (sau n-a apucat să răspundă) vede răspunsul corect și
///    faptul că e luat la ochi — nu are ce apăsa, dar nici nu stă degeaba
///    șase secunde: află ce trebuia să răspundă.
///
/// Nu e un `Navigator.push`: e o altă înfățișare a aceleiași rute. Un ecran
/// împins ar fi trebuit închis exact la timp de fiecare client, iar o
/// deconectare la mijloc l-ar fi lăsat pe cineva blocat peste meciul care
/// merge mai departe. Aici, faza din Firestore decide singură ce se vede.
class _TargetingView extends StatelessWidget {
  final MatchInfo info;
  final List<MatchPlayer> players;
  final CultureQuestion question;
  final int secondsLeft;
  final void Function(String targetId) onPick;

  const _TargetingView({
    required this.info,
    required this.players,
    required this.question,
    required this.secondsLeft,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final me = MultiplayerService.instance.currentPlayerId;
    final iAmShooter = info.roundWinnerIds.contains(me);
    final myTarget = info.roundTargets[me];
    final enemies = players.where((p) => p.id != me && !p.eliminated).toList();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: iAmShooter
              ? [const Color(0xFF2A0F0F), const Color(0xFF120B1E), AppColors.bg]
              : [const Color(0xFF11162B), AppColors.bg, AppColors.bg],
        ),
      ),
      child: Stack(
        children: [
          // Cadranul de ochire din spate — colțuri de vizor, inele
          // concentrice și o linie de scanare. Fără el, ecranul cu un singur
          // adversar rămas era o cutie singură pe un fundal gol.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _TargetingBackdropPainter(active: iAmShooter)),
            ),
          ),
          Column(
            children: [
              const SizedBox(height: 14),
              _header(iAmShooter, myTarget != null),
              // Conținutul stă CENTRAT pe verticală: la patru jucători sunt
              // trei cutii și se umple ecranul, dar spre finalul meciului
              // rămâne una singură, iar lipită de titlu arăta a pagină
              // neterminată.
              Expanded(child: Center(child: iAmShooter ? _targets(enemies, myTarget) : _waitingRoom())),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                child: _answerReveal(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(bool iAmShooter, bool alreadyPicked) {
    final color = iAmShooter ? AppColors.danger : AppColors.blue;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iAmShooter ? Icons.gps_fixed_rounded : Icons.shield_rounded, color: color, size: 22),
            const SizedBox(width: 10),
            Text(
              iAmShooter ? tr('ALEGE ȚINTA', 'PICK YOUR TARGET') : tr('LA ADĂPOST!', 'BRACE!'),
              style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3),
            ),
            const SizedBox(width: 10),
            _TargetClock(secondsLeft: secondsLeft, color: color),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          iAmShooter
              ? (alreadyPicked
                  ? tr('Țintă blocată. Aștept ceilalți tunari...', 'Target locked. Waiting for the other gunners...')
                  : tr('Ai nimerit răspunsul — ai dreptul la o lovitură.',
                      'You got it right — you have earned one shot.'))
              : tr('Ai greșit runda asta: nu tragi și eviți mult mai greu.',
                  'You missed this round: you do not fire, and you dodge much worse.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  /// Cutiile adversarilor. Cel mai slăbit e marcat explicit, fiindcă ăsta e
  /// și cel pe care tragi automat dacă nu apuci să alegi — jucătorul trebuie
  /// să vadă dinainte ce se întâmplă dacă ezită.
  Widget _targets(List<MatchPlayer> enemies, String? myTarget) {
    if (enemies.isEmpty) {
      return Text(tr('Nu mai are cine să fie țintă.', 'Nobody left to target.'),
          style: const TextStyle(color: Colors.white54));
    }
    final weakest = enemies.reduce((a, b) => b.hp < a.hp ? b : a);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in enemies)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TargetCard(
                player: p,
                selected: myTarget == p.id,
                locked: myTarget != null,
                isWeakest: enemies.length > 1 && p.id == weakest.id,
                onTap: () => onPick(p.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _waitingRoom() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.crisis_alert_rounded, color: AppColors.orange, size: 54),
          const SizedBox(height: 14),
          Text(
            tr('Tunarii te iau la ochi', 'The gunners are taking aim'),
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            tr('Nu se știe în cine trag până nu pleacă proiectilele.',
                'Nobody knows who they picked until the shells fly.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Răspunsul corect, arătat tuturor cât se țintește. Cele șase secunde ar
  /// fi fost oricum de așteptare — așa cel care a greșit pleacă măcar cu
  /// informația, ceea ce e tot rostul unui joc de întrebări.
  Widget _answerReveal() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.play.withAlpha(24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.play.withAlpha(110)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            question.question,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 11.5),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.play, size: 15),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  question.answer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.play, fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cadranul de ochire din spatele ecranului de țintire: colțuri de vizor,
/// inele concentrice și o cruce fină. Static (fără animație) — e fundal, iar
/// o animație în plus aici ar fi concurat cu cronometrul, singurul lucru de
/// pe ecran care chiar trebuie urmărit.
class _TargetingBackdropPainter extends CustomPainter {
  /// Vizorul se aprinde doar pentru cine chiar are ce ținti; celui care a
  /// greșit i se desenează palid, ca semn că arma nu e a lui runda asta.
  final bool active;
  const _TargetingBackdropPainter({required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.52);
    final base = active ? AppColors.danger : AppColors.blue;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = base.withAlpha(active ? 34 : 20);

    for (final r in [0.30, 0.48, 0.66]) {
      canvas.drawCircle(center, size.width * r, line);
    }
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), line);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), line);

    // colțuri de vizor
    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = base.withAlpha(active ? 110 : 55);
    const pad = 16.0;
    const len = 26.0;
    final rect = Rect.fromLTRB(pad, pad + 46, size.width - pad, size.height - pad - 76);
    for (final corner in [
      (rect.topLeft, 1.0, 1.0),
      (rect.topRight, -1.0, 1.0),
      (rect.bottomLeft, 1.0, -1.0),
      (rect.bottomRight, -1.0, -1.0),
    ]) {
      final (p, dx, dy) = corner;
      canvas.drawLine(p, p + Offset(len * dx, 0), bracket);
      canvas.drawLine(p, p + Offset(0, len * dy), bracket);
    }
  }

  @override
  bool shouldRepaint(covariant _TargetingBackdropPainter oldDelegate) => oldDelegate.active != active;
}

/// O victimă posibilă: tanc mare, viața la vedere, o cruce de ochire care
/// se aprinde la selecție.
class _TargetCard extends StatelessWidget {
  final MatchPlayer player;
  final bool selected;
  final bool locked;
  final bool isWeakest;
  final VoidCallback onTap;

  const _TargetCard({
    required this.player,
    required this.selected,
    required this.locked,
    required this.isWeakest,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = pickAvatarColor(player.avatarSeed);
    final hpColor = TankHpBar.hpColor(player.hp);
    return Opacity(
      // dupa ce ai ales, ceilalti se sting — decizia e luata, nu se schimba
      opacity: locked && !selected ? 0.35 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: locked ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.danger.withAlpha(38) : Colors.white.withAlpha(14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? AppColors.danger : Colors.white24, width: selected ? 2.2 : 1),
              boxShadow: selected
                  ? [BoxShadow(color: AppColors.danger.withAlpha(120), blurRadius: 18, spreadRadius: -4)]
                  : null,
            ),
            child: Row(
              children: [
                Avatar(
                  size: 40,
                  label: player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
                  accentColor: color,
                  photoUrl: player.photoUrl,
                  style: avatarStyleFromId(player.avatarStyle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              player.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${player.hp} HP',
                              style: TextStyle(color: hpColor, fontSize: 12.5, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      TankHpBar(
                        hp: player.hp,
                        previousHp: player.hp,
                        drainProgress: 1,
                        color: hpColor,
                        height: 7,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            tr('${player.damageDealt} daune făcute', '${player.damageDealt} damage dealt'),
                            style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                          ),
                          if (isWeakest) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.orange.withAlpha(45),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                tr('CEL MAI SLĂBIT', 'WEAKEST'),
                                style: const TextStyle(color: AppColors.orange, fontSize: 8.5, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                TankArt(color: color, width: 62, facingRight: false, damage: 1 - (player.hp / tanksMaxHp)),
                const SizedBox(width: 6),
                Icon(
                  selected ? Icons.gps_fixed_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppColors.danger : Colors.white24,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cronometrul fazei de țintire — mai discret decât cel de la răspuns, ca
/// să nu grăbească o decizie care are voie să dureze.
class _TargetClock extends StatelessWidget {
  final int secondsLeft;
  final Color color;
  const _TargetClock({required this.secondsLeft, required this.color});

  @override
  Widget build(BuildContext context) {
    final urgent = secondsLeft <= 2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: (urgent ? AppColors.danger : color).withAlpha(35),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: urgent ? AppColors.danger : color.withAlpha(150)),
      ),
      child: Text(
        '${secondsLeft}s',
        style: TextStyle(
          color: urgent ? AppColors.danger : color,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// Cronometrul rundei — cifră mare într-un hexagon, roșu în ultimele două
/// secunde. Nu e CountdownRing (folosit la Higher & Lower / Daily): acolo
/// sunt 15 secunde și inelul are ce descrie, aici sunt cinci și contează să
/// se citească cifra dintr-o privire periferică.
class _CountdownDial extends StatelessWidget {
  final int seconds;
  const _CountdownDial({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final urgent = seconds <= 2;
    final color = urgent ? AppColors.danger : AppColors.play;
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color, width: 1.8),
        boxShadow: urgent ? [BoxShadow(color: color.withAlpha(120), blurRadius: 12, spreadRadius: -2)] : null,
      ),
      child: Text(
        '$seconds',
        style: TextStyle(color: color, fontSize: 19, fontWeight: FontWeight.w900),
      ),
    );
  }
}

/// Cutia unui jucător din arenă: avatar, nume, viață, tanc și starea lui în
/// runda curentă (a răspuns / trage / e epavă).
class _TankCard extends StatelessWidget {
  final MatchPlayer player;
  final bool facingRight;
  final bool isMe;
  final bool hasAnswered;
  final bool showAnswerTicks;
  final bool isFiring;
  final int previousHp;
  final double drainProgress;
  final double tankWidth;

  const _TankCard({
    required this.player,
    required this.facingRight,
    required this.isMe,
    required this.hasAnswered,
    required this.showAnswerTicks,
    required this.isFiring,
    required this.previousHp,
    required this.drainProgress,
    required this.tankWidth,
  });

  @override
  Widget build(BuildContext context) {
    final color = pickAvatarColor(player.avatarSeed);
    final destroyed = player.eliminated;
    final hpColor = TankHpBar.hpColor(player.hp);
    // Cine trage e încadrat portocaliu, cu strălucire: în trei secunde de
    // haos, ăsta e singurul semn din care înțelegi de ce te-a lovit cineva.
    final border = destroyed
        ? Colors.white12
        : isFiring
            ? AppColors.orange
            : isMe
                ? color
                : Colors.white24;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 6),
      decoration: BoxDecoration(
        color: destroyed ? Colors.black.withAlpha(90) : Colors.white.withAlpha(isMe ? 22 : 13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: isFiring || isMe ? 1.8 : 1),
        boxShadow: isFiring ? [BoxShadow(color: AppColors.orange.withAlpha(120), blurRadius: 16, spreadRadius: -3)] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Opacity(
                    opacity: destroyed ? 0.45 : 1,
                    child: Avatar(
                      size: 26,
                      label: player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
                      accentColor: color,
                      photoUrl: player.photoUrl,
                      style: avatarStyleFromId(player.avatarStyle),
                    ),
                  ),
                  if (hasAnswered && showAnswerTicks && !destroyed)
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        padding: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(
                          color: AppColors.play,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.bg, width: 1),
                        ),
                        child: const Icon(Icons.check_rounded, size: 9, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isMe ? tr('${player.name} (tu)', '${player.name} (you)') : player.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: destroyed ? Colors.white38 : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                destroyed ? 'KO' : '${player.hp}',
                style: TextStyle(
                  color: destroyed ? AppColors.danger : hpColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          TankHpBar(
            hp: player.hp,
            previousHp: previousHp,
            drainProgress: drainProgress,
            color: hpColor,
            height: 8,
          ),
          const Spacer(),
          Align(
            alignment: facingRight ? Alignment.centerLeft : Alignment.centerRight,
            child: TankArt(
              color: color,
              width: tankWidth,
              facingRight: facingRight,
              destroyed: destroyed,
              damage: 1 - (player.hp / tanksMaxHp),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fundalul arenei: un orizont în perspectivă și un halou cald la bază.
/// Foarte discret intenționat — tot ce se întâmplă important se desenează
/// deasupra lui.
class _BattlefieldPainter extends CustomPainter {
  const _BattlefieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [AppColors.orange.withAlpha(26), Colors.transparent],
      ).createShader(Rect.fromCircle(center: Offset(size.width / 2, size.height * 0.5), radius: size.width * 0.72));
    canvas.drawRect(Offset.zero & size, glow);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withAlpha(12);
    for (var i = 1; i < 7; i++) {
      final y = size.height * (i / 7);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    for (var i = 1; i < 6; i++) {
      final x = size.width * (i / 6);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
  }

  @override
  bool shouldRepaint(covariant _BattlefieldPainter oldDelegate) => false;
}

/// O variantă de răspuns. Litera din stânga (A-D) nu e decor: la cinci
/// secunde, ochiul găsește mai repede o poziție marcată decât un rând de
/// text fără reper.
class _AnswerButton extends StatelessWidget {
  final String letter;
  final String text;
  final bool picked;
  final bool correct;
  final bool dimmed;
  final VoidCallback? onTap;

  const _AnswerButton({
    required this.letter,
    required this.text,
    required this.picked,
    required this.correct,
    required this.dimmed,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = correct
        ? AppColors.play
        : picked
            ? AppColors.blue
            : Colors.white;
    return Opacity(
      opacity: dimmed ? 0.4 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: correct || picked ? color.withAlpha(38) : Colors.white.withAlpha(14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: correct || picked ? color : Colors.white24,
                width: correct || picked ? 1.6 : 1,
              ),
              boxShadow: correct ? [BoxShadow(color: color.withAlpha(90), blurRadius: 12, spreadRadius: -3)] : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: correct || picked ? color.withAlpha(60) : Colors.white.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    letter,
                    style: TextStyle(
                      color: correct || picked ? color : Colors.white70,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                if (correct) const Icon(Icons.check_circle_rounded, color: AppColors.play, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
