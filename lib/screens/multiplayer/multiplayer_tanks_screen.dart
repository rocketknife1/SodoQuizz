import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../../core/admin_reveal.dart';
import '../../core/audio.dart';
import '../../core/lang.dart';
import '../../core/powerup_ui.dart';
import '../../core/powerups.dart';
import '../../core/stable_hash.dart';
import '../../core/tanks.dart';
import '../../core/theme.dart';
import '../../data/culture_questions.dart';
import '../../data/multiplayer_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/match_emotes.dart';
import '../../widgets/avatar.dart';
import '../../widgets/powerup_inventory.dart';
import '../../widgets/round_event_banner.dart';
import '../../widgets/tank_art.dart';
import '../../widgets/tank_defence.dart';
import '../../widgets/tank_pov.dart';
import 'multiplayer_results_screen.dart';
import '../../core/breadcrumbs.dart';

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
  ///
  /// Zborul e mai lung decât ar cere arena (un drum de câțiva centimetri pe
  /// ecran) fiindcă ACELAȘI interval e și durata camerei de pe proiectil,
  /// unde chiar ai ce vedea — vezi widgets/tank_pov.dart. Toate cifrele de
  /// aici s-au dublat aproape peste tot (5→9s reveal, vezi
  /// core/tanks.dart.tanksRevealSeconds) după ce userul a văzut prima
  /// versiune live pe două ecrane și n-a apucat să citească nimic din ce
  /// scria pe cadru — nu era o părere, era cronometrată prea strâns.
  static const double _firstShotAt = 0.6;
  static const double _shotStagger = 0.22;
  static const double _flightDuration = 1.3;
  static const double _drainDuration = 1.0;

  /// Cât de mult se dau în lături, în pixeli, cele două obuze ale unui duel
  /// care se încrucișează. Merg pe același segment în sensuri opuse, deci
  /// fără asta s-ar suprapune perfect la mijloc și s-ar citi ca un singur
  /// proiectil care clipește (vezi [ShotFlight.lateral]).
  static const double _duelLateral = 7;

  /// Cât se așteaptă, după ULTIMUL impact, înainte ca barele să înceapă să
  /// scadă. Nu e o pauză de stil: bullet cam-ul ține ecranul până la
  /// `impactul meu + tankPovAftermath`, iar dacă barele ar scădea sub el,
  /// țintașul s-ar întoarce în arenă și ar găsi treaba deja făcută — adică
  /// exact evenimentul pe care lovitura lui l-a provocat i-ar rămâne
  /// nevăzut. Fiind puțin mai mare decât [tankPovAftermath] (1,7s), acoperă
  /// orice proiectil al rundei, nu doar pe al meu.
  static const double _drainDelayAfterImpacts = 1.9;

  Timer? _tick;
  Timer? _advanceTimer;
  Timer? _heartbeatTimer;
  int _lastRoundIndex = -1;
  bool _resolving = false;
  bool _navigatedToResults = false;
  bool _left = false;

  /// Viața fiecărui tanc la ÎNCEPUTUL rundei curente — reperul din care
  /// coboară „fantoma" barei (vezi TankHpBar). Se ia o singură dată pe
  /// rundă, cât suntem încă în faza de răspuns.
  final Map<String, int> _hpAtRoundStart = {};

  List<ShotFlight> _flights = const [];
  int _flightsBuiltForRound = -1;

  /// Proiectilul propriu al rundei și tancul în care pleacă — doar ele hrănesc
  /// camera de pe obuz (vezi [TankPovView]). `null` în rundele în care n-am
  /// răspuns corect, deci n-am tras: atunci plec în camera de apărare
  /// ([TankDefenceView]) dacă vine ceva spre mine, altfel rămân pe arenă.
  ShotFlight? _myFlight;
  MatchPlayer? _myPovTarget;
  int _myPovTargetHpAtStart = tanksMaxHp;

  /// A doua țintă a propriei lovituri duble, pentru camera de pe obuz. `null`
  /// la o tragere obișnuită — vezi [TankPovSecondTarget].
  TankPovSecondTarget? _myPovSecond;

  /// Duelul rundei, dacă există: ținta mea a tras, în aceeași clipă, chiar în
  /// mine. [_myDuelIntercepted] e cazul în care amândoi am ratat — atunci
  /// obuzele se izbesc între ele la mijlocul drumului (vezi
  /// [ShotFlight.intercepted]).
  bool _myDuel = false;
  bool _myDuelIntercepted = false;

  /// Obuzele care vin spre MINE în runda asta și cât încasez din ele. Lista
  /// hrănește camera de apărare; totalul se scrie și pe camera de pe obuz,
  /// pentru cel care trage și e lovit în același timp.
  List<IncomingShell> _myIncoming = const [];
  int _myDamageTaken = 0;

  /// Cum arăt eu în camera de apărare: culoarea, numele (din care iese partea
  /// în care smucesc la fereală) și viața de la începutul rundei.
  Color _myColor = AppColors.blue;
  String _myName = '';
  int _myHpAtRoundStart = tanksMaxHp;
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

  /// Eveniment/power-up determinist (core/powerups.dart), la fel ca-n
  /// celelalte moduri deja cablate. Vezi [_maybeGrantPowerUp]/[_usePowerUp].
  /// Puterile strânse, în ordinea primirii. ÎNAINTE era una singură: dacă
  /// primeai alta cât o aveai pe cea veche nefolosită, cea veche se pierdea
  /// în tăcere. Se golesc la finalul meciului (nu se duc în contul tău).
  final List<PowerUp> _myPowerUps = [];

  /// Runda în care s-a folosit deja o putere — regula e UNA pe rundă.
  int _powerUpUsedRound = -1;
  int? _powerUpRolledRound;
  Set<String> _hiddenChoices = const {};

  /// uid → nume, reîmprospătat la fiecare [_onData] — folosit de banner-ul
  /// de la [PowerUp.peek], care n-are lista de jucători la îndemână.
  final Map<String, String> _playerNames = {};

  /// Prima țintă apăsată în faza de țintire când am [PowerUp.doubleShot]:
  /// mai aștept a doua apăsare înainte de a trimite ambele. `null` = n-am
  /// lovitură dublă, sau încă n-am apăsat nimic. Se golește la runda nouă.
  String? _firstDoubleTarget;

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
    Breadcrumbs.drop('ecran: Meci Tancuri');
    // Reconectare: daca aplicatia moare in mijlocul meciului, butonul
    // de reconectare stie unde sa te intoarca (vezi MultiplayerService).
    MultiplayerService.instance.markActiveMatch(widget.matchId, MatchGameMode.quizzTanks);
    // Sunetele modului se încarcă abia acum, nu la pornirea aplicației —
    // vezi TankSfx pentru de ce.
    TankSfx.preload();
    _fire.addListener(_onFireTick);
    // Nicio actualizare Firestore nu vine „din ceas", dar cronometrul de 5
    // secunde trebuie să scadă vizibil în fiecare secundă.
    // O data pe secunda, NU la 250ms. Arena isi are propriul AnimatedBuilder legat de `_fire` (vezi comentariile
    // de la _buildArena): animatia obuzelor NU depinde de setState-ul asta.
    // Tick-ul asta exista doar pentru cronometru; la 250ms reconstruia tot
    // ecranul (lista de jucatori, avatare, tot) de patru ori pe secunda
    // degeaba. Verificarea de expirare a rundei ramane corecta — ruleaza in
    // continuare o data pe secunda.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _heartbeatTimer = Timer.periodic(MultiplayerService.matchHeartbeatInterval, (_) {
      MultiplayerService.instance.matchHeartbeat(widget.matchId);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _advanceTimer?.cancel();
    _heartbeatTimer?.cancel();
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
    if (_left) return;
    _left = true;
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

  /// Consumă power-up-ul curent.
  ///
  ///  - [PowerUp.fiftyFifty]: efect local, instant.
  ///  - [PowerUp.repairKit]: scriere directă de viață, instant.
  ///  - [PowerUp.megaRocket]/[PowerUp.doubleShot]/[PowerUp.shield]/
  ///    [PowerUp.reflect]: NU au efect local — se scriu pe `roundPowerUps`
  ///    (vezi [MultiplayerService.submitTanksPowerUp]) și [resolveTanksRound]
  ///    le citește de acolo la calculul loviturilor, ca orice client care
  ///    rezolvă runda să aplice exact același rezultat.
  ///  - [PowerUp.allyShield]: apără automat tancul cel mai slăbit, 2 runde
  ///    ([MultiplayerService.useTanksAllyShield]).
  ///  - [PowerUp.reflect]: se scrie pe `roundPowerUps`, întoarce lovitura la
  ///    rezolvare.
  ///  - [PowerUp.peek]: efect local — arată ce au răspuns ceilalți acum.
  void _usePowerUp(MatchInfo info, PowerUp p) {
    if (p == PowerUp.none || !_myPowerUps.contains(p)) return;
    // Fereastra de fază se verifică ÎNAINTEA regulii „una pe rundă": dacă
    // puterea n-ar fi mers oricum acum, ăsta e motivul real al refuzului.
    if (!powerUpUsableInPhase(p, info.roundPhase.name)) {
      notifyPowerUpTooLate(context);
      return; // păstrează puterea — nu o consuma pe o scriere care se pierde
    }
    // O singură putere pe rundă — vezi [_powerUpUsedRound].
    if (_powerUpUsedRound == info.roundIndex) {
      notifyPowerUpAlreadyUsed(context);
      return;
    }
    // 50/50 mai are o precondiție pe care faza n-o poate exprima: dacă am
    // răspuns deja, n-are ce ascunde. O păstrez pentru runda următoare în
    // loc s-o consum în gol (recenzie 2026-09-01).
    if (p == PowerUp.fiftyFifty &&
        info.roundAnswers.containsKey(MultiplayerService.instance.currentPlayerId)) {
      notifyPowerUpNoEffect(context);
      return;
    }
    Sfx.tileSelect();
    switch (p) {
      case PowerUp.fiftyFifty:
        final q = _questionFor(info.roundIndex);
        final wrong = q.choices.where((c) => c != q.answer).toList();
        stableShuffle(wrong, stableHash('${widget.matchId}#${info.roundIndex}#5050'));
        setState(() => _hiddenChoices = wrong.take(max(0, wrong.length - 1)).toSet());
      case PowerUp.repairKit:
        MultiplayerService.instance.useTanksRepairKit(matchId: widget.matchId);
      case PowerUp.megaRocket:
      case PowerUp.doubleShot:
      case PowerUp.shield:
      case PowerUp.reflect:
        MultiplayerService.instance.submitTanksPowerUp(matchId: widget.matchId, powerUp: p);
      case PowerUp.allyShield:
        MultiplayerService.instance.useTanksAllyShield(matchId: widget.matchId, roundIndex: info.roundIndex);
      case PowerUp.peek:
        showPeekResults(context, info, myId: MultiplayerService.instance.currentPlayerId, playerNames: _playerNames);
      default:
        break;
    }
    setState(() {
      _myPowerUps.remove(p);
      _powerUpUsedRound = info.roundIndex;
    });
  }

  /// Vezi core/powerups.dart — acordat cui a răspuns corect runda tocmai
  /// închisă (adică e în `roundWinnerIds`), cu șansă mai mare pentru cine e
  /// mai jos în clasamentul de daune făcute.
  void _maybeGrantPowerUp(MatchInfo info, List<MatchPlayer> players) {
    if (_powerUpRolledRound == info.roundIndex) return;
    _powerUpRolledRound = info.roundIndex;
    final me = MultiplayerService.instance.currentPlayerId;
    if (!info.roundWinnerIds.contains(me)) return;
    final ranked = List.of(players)..sort((a, b) => b.damageDealt.compareTo(a.damageDealt));
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
    );
    if (!granted) return;
    final picked = powerUpFor(matchId: widget.matchId, roundIndex: info.roundIndex, playerId: me, gameModeId: 'quizzTanks');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _myPowerUps.add(picked));
      Sfx.rewardPop();
      announcePowerUp(context, picked);
    });
  }

  void _pickTarget(MatchInfo info, String targetId) {
    if (info.roundPhase != RoundPhase.targeting) return;
    final me = MultiplayerService.instance.currentPlayerId;
    if (!info.roundWinnerIds.contains(me) || info.roundTargets.containsKey(me)) return;

    // Lovitură dublă: prima apăsare doar reține ținta, a doua trimite ambele
    // (pot fi aceeași — atunci lovitura e concentrată, vezi resolveTanksRound).
    if (info.roundPowerUps[me] == PowerUp.doubleShot.name) {
      if (_firstDoubleTarget == null) {
        TankSfx.lock();
        setState(() => _firstDoubleTarget = targetId);
        return;
      }
      TankSfx.lock();
      MultiplayerService.instance.submitTanksTarget(
        matchId: widget.matchId,
        targetId: _firstDoubleTarget!,
        secondTargetId: targetId,
      );
      return;
    }

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
    if (_lastResolveAttempt != null && now.difference(_lastResolveAttempt!) < const Duration(milliseconds: 900)) {
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
        } else if (f.intercepted) {
          // Ciocnirea a două obuze e un impact, nu un ricoșeu — dar unul
          // singur pentru amândouă zborurile ([ShotFlight.meetLead]), altfel
          // ar porni de două ori exact în aceeași milisecundă.
          if (f.meetLead) TankSfx.hit();
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
    for (final p in players) {
      _playerNames[p.id] = p.name;
    }
    if (info.roundIndex != _lastRoundIndex) {
      _lastRoundIndex = info.roundIndex;
      _hpAtRoundStart
        ..clear()
        ..addEntries(players.map((p) => MapEntry(p.id, p.hp)));
      _flights = const [];
      _flightsBuiltForRound = -1;
      _myFlight = null;
      _myPovTarget = null;
      _myPovSecond = null;
      _myDuel = false;
      _myDuelIntercepted = false;
      _myIncoming = const [];
      _myDamageTaken = 0;
      _playedShot.clear();
      _playedImpact.clear();
      _playedAlarm = false;
      _playedExplosions = false;
      _lastResolveAttempt = null;
      _hiddenChoices = const {};
      _firstDoubleTarget = null;
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
      // Ultimele două secunde: un bip scurt — cine citește variantele nu are
      // cum să se uite în același timp și la cronometru.
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
      // roundWinnerIds e cunoscut din clipa asta — de-aia power-up-ul se
      // acordă aici, nu în faza de răspuns.
      _maybeGrantPowerUp(info, players);
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
      // Durata se ia din rundă, nu din constantă: o rundă în care n-a tras
      // nimeni (toți au greșit) n-are nicio animație de acoperit, iar
      // asteptarea completa era timp mort pentru toată masa — vezi
      // [tanksRevealSecondsFor].
      _advanceTimer ??= Timer(
        Duration(seconds: tanksRevealSecondsFor(anyShots: info.roundShots.isNotEmpty)),
        () {
          MultiplayerService.instance.advanceSyncRound(matchId: widget.matchId, roundIndex: info.roundIndex);
        },
      );
    }

    if (info.status == MatchStatus.finished && !_navigatedToResults) {
      _navigatedToResults = true;
      // Meciul se încheie în aceeași scriere care rezolvă ultima rundă, deci
      // fără pauza asta lovitura decisivă n-ar apuca să fie văzută niciodată:
      // ecranul ar sări la clasament exact când pleacă proiectilul.
      // Aceeași socoteală ca la avansarea rundei: dacă meciul s-a terminat
      // fără să se tragă (ultimul tanc rămas, sau plafonul de runde atins
      // într-o rundă ratată de toți), n-are ce lovitură decisivă să apuce
      // cineva să vadă, deci n-are rost să ținem masa pe loc 9 secunde.
      Future.delayed(Duration(seconds: tanksRevealSecondsFor(anyShots: info.roundShots.isNotEmpty)), () {
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
  ///
  /// Tot aici se caută **duelurile** — perechile în care doi jucători și-au
  /// ales țintă unul pe altul. Ele nu schimbă niciun rezultat (zarurile s-au
  /// aruncat deja, o singură dată, în MultiplayerService.resolveTanksRound),
  /// dar schimbă punerea în scenă: cei doi trag DEODATĂ, obuzele merg unul pe
  /// lângă altul, iar dacă amândoi au ratat se izbesc între ele la jumătatea
  /// drumului în loc să se piardă fiecare pe lângă câte un tanc.
  void _ensureFlights(MatchInfo info, List<MatchPlayer> players, Map<String, Offset> centers, double arenaWidth) {
    if (_flightsBuiltForRound == info.roundIndex) return;
    if (info.roundPhase != RoundPhase.revealed) return;
    _flightsBuiltForRound = info.roundIndex;

    final shots = info.roundShots;
    final seeds = {for (final p in players) p.id: p.avatarSeed};
    final names = {for (final p in players) p.id: p.name};
    final me = MultiplayerService.instance.currentPlayerId;

    // Reflexii. `resolveTanksVolleys` scrie DOUĂ intrări pentru o reflexie:
    // trăgător→reflector (ratată) și reflector→trăgător (lovește). Le lipim
    // într-un singur zbor dus-întors: [reflectMerged] ține indicele intrării
    // „dus" → indicele intrării „întors" (pe care n-o mai desenăm separat).
    final reflectMerged = <int, int>{};
    final reflectSkip = <int>{};
    for (var i = 0; i < shots.length; i++) {
      for (var j = 0; j < shots.length; j++) {
        if (i == j) continue;
        final out = shots[i];
        final back = shots[j];
        if (out.byId == back.atId &&
            out.atId == back.byId &&
            !out.hit &&
            back.hit &&
            info.roundPowerUps[out.atId] == PowerUp.reflect.name) {
          reflectMerged[i] = j;
          reflectSkip.add(j);
        }
      }
    }

    // Lovitură dublă pe DOUĂ ținte diferite: `resolveTanksVolleys` scrie două
    // intrări cu același `byId`. Vizual pleacă UN obuz care se desparte în
    // două la [_splitAt] din drum — [splitPair] leagă cei doi indici, iar
    // primul din pereche desenează obuzul comun de dinainte de despărțire.
    final splitPair = <int, int>{};
    for (var i = 0; i < shots.length; i++) {
      if (reflectMerged.containsKey(i) || reflectSkip.contains(i)) continue;
      if (info.roundPowerUps[shots[i].byId] != PowerUp.doubleShot.name) continue;
      for (var j = i + 1; j < shots.length; j++) {
        if (shots[j].byId == shots[i].byId) {
          splitPair[i] = j;
          splitPair[j] = i;
        }
      }
    }

    // Perechile de duel. Un jucător trage o singură dată pe rundă, deci
    // partenerul e unic — nu se poate ajunge la un „triunghi" de dueluri.
    // O reflexie NU e duel (obuzul e al aceluiași trăgător, dus-întors).
    final partner = <int, int>{};
    for (var i = 0; i < shots.length; i++) {
      if (reflectMerged.containsKey(i) || reflectSkip.contains(i)) continue;
      for (var j = i + 1; j < shots.length; j++) {
        if (reflectMerged.containsKey(j) || reflectSkip.contains(j)) continue;
        if (shots[i].byId == shots[j].atId && shots[i].atId == shots[j].byId) {
          partner[i] = j;
          partner[j] = i;
        }
      }
    }

    // Momentul plecării. Tragerile obișnuite rămân decalate ([_shotStagger]),
    // ca ochiul să apuce să le urmărească pe rând; cele două ale unui duel
    // primesc ACELAȘI slot, fiindcă pe ele trebuie să le vezi plecând în
    // aceeași clipă — altfel „s-au întâlnit la mijloc" n-ar avea cum să iasă.
    final slot = <int, int>{};
    var nextSlot = 0;
    for (var i = 0; i < shots.length; i++) {
      if (slot.containsKey(i) || reflectSkip.contains(i)) continue;
      slot[i] = nextSlot;
      final j = partner[i] ?? splitPair[i];
      if (j != null) slot[j] = nextSlot; // duelul / lovitura dublă pleacă odată
      nextSlot++;
    }

    final flights = <ShotFlight>[];
    // obuzele care vin spre mine, cu poziția atacatorului în arenă („din ce
    // parte vine"), înainte de a fi așezate pe culoare în camera de apărare
    final atMe = <({TankShot shot, ShotFlight flight, double lane})>[];
    var damageTaken = 0;
    for (var i = 0; i < shots.length; i++) {
      if (reflectSkip.contains(i)) continue; // desenată ca parte din „dus-întors"
      final s = shots[i];
      final from = centers[s.byId];
      final to = centers[s.atId];
      if (from == null || to == null) continue; // jucător plecat între timp

      final bounceIdx = reflectMerged[i];
      if (bounceIdx != null) {
        // Reflexie: un singur zbor dus-întors. `s` e „dus" (trăgător→reflector,
        // ratată), `bounce` e „întors" (reflector→trăgător, lovește). Obuzul
        // explodează în trăgător.
        final bounce = shots[bounceIdx];
        final flight = ShotFlight(
          from: from,
          to: to,
          hit: true,
          damage: bounce.damage,
          startAt: _firstShotAt + slot[i]! * _shotStagger,
          flightDuration: _flightDuration * 1.8,
          color: pickAvatarColor(seeds[s.byId] ?? s.byId),
          reflectBackTo: from,
        );
        flights.add(flight);
        if (s.byId == me) {
          _myFlight = flight;
          _myDuel = false;
          _myDuelIntercepted = false;
          damageTaken += bounce.damage; // propriul obuz întors mă lovește
        }
        continue;
      }

      final j = partner[i];
      final duel = j != null;
      // Se izbesc între ele doar dacă AMÂNDOUĂ obuzele erau oricum ratate:
      // altfel am schimba rezultatul rundei dintr-o animație, exact lucrul pe
      // care modul îl ține strict în tranzacția de rezolvare.
      final intercepted = duel && !s.hit && !shots[j].hit;
      // Lovitură ratată pe un tanc cu scut = OPRITĂ, nu evitată la noroc.
      final blocked = !s.hit && info.roundShieldedIds.contains(s.atId);

      // Lovitură dublă pe două ținte: obuzul comun urcă până la un punct la
      // ~40% din drumul spre media celor două ținte, apoi se desparte.
      final sj = splitPair[i];
      Offset? splitPoint;
      if (sj != null) {
        final otherTo = centers[shots[sj].atId];
        if (otherTo != null) {
          final mid = Offset((to.dx + otherTo.dx) / 2, (to.dy + otherTo.dy) / 2);
          splitPoint = Offset.lerp(from, mid, 0.42)!;
        }
      }

      final flight = ShotFlight(
        from: from,
        to: to,
        hit: s.hit,
        damage: s.damage,
        startAt: _firstShotAt + slot[i]! * _shotStagger,
        flightDuration: _flightDuration,
        color: pickAvatarColor(seeds[s.byId] ?? s.byId),
        lateral: duel && !intercepted && !blocked ? _duelLateral : 0,
        intercepted: intercepted && !blocked,
        meetLead: intercepted && !blocked && i < j,
        blockedByShield: blocked,
        splitPoint: splitPoint,
        splitLead: sj != null && i < sj,
      );
      flights.add(flight);
      if (s.byId == me) {
        // Lovitură dublă: camera rămâne pe PRIMUL obuz al perechii, iar al
        // doilea devine [_myPovSecond]. Fără asta, a doua atribuire ar fi
        // suprascris-o pe prima și al doilea tanc n-ar fi apărut deloc.
        final isSecondOfPair = sj != null && !flight.splitLead;
        if (isSecondOfPair) {
          for (final p in players) {
            if (p.id != s.atId) continue;
            final hpStart = _hpAtRoundStart[p.id] ?? p.hp;
            _myPovSecond = TankPovSecondTarget(
              color: pickAvatarColor(p.avatarSeed),
              name: p.name,
              damageRatio: 1 - (hpStart / tanksMaxHp),
              hit: s.hit,
              damage: s.damage,
            );
          }
        } else {
          _myFlight = flight;
          _myDuel = duel;
          _myDuelIntercepted = intercepted;
          for (final p in players) {
            if (p.id == s.atId) {
              _myPovTarget = p;
              // viața de la ÎNCEPUTUL rundei: `p.hp` e deja cea de după
              // lovitura asta, iar camera arată drumul spre ea, nu urmarea.
              _myPovTargetHpAtStart = _hpAtRoundStart[p.id] ?? p.hp;
            }
          }
        }
      }
      if (s.atId == me) {
        if (s.hit) damageTaken += s.damage;
        atMe.add((shot: s, flight: flight, lane: ((from.dx - to.dx) / (arenaWidth * 0.5)).clamp(-1.0, 1.0)));
      }
    }
    _myDamageTaken = damageTaken;
    // Culoarele din camera de apărare: unul singur vine exact din partea în
    // care stă atacatorul în arenă; la doi sau trei, poziția reală se
    // amestecă cu o desfășurare egală, altfel doi adversari din aceeași
    // coloană ar trimite obuze pe același culoar, unul peste altul.
    _myIncoming = [
      for (var k = 0; k < atMe.length; k++)
        IncomingShell(
          launchAt: atMe[k].flight.startAt,
          impactAt: atMe[k].flight.impactAt,
          hit: atMe[k].shot.hit,
          damage: atMe[k].shot.damage,
          color: atMe[k].flight.color,
          blockedByShield: atMe[k].flight.blockedByShield,
          shooterName: names[atMe[k].shot.byId] ?? '?',
          lane: atMe.length == 1
              ? atMe[k].lane
              : (atMe[k].lane * 0.5 + (k - (atMe.length - 1) / 2) * 0.5).clamp(-0.92, 0.92),
        ),
    ];
    for (final p in players) {
      if (p.id != me) continue;
      _myColor = pickAvatarColor(p.avatarSeed);
      _myName = p.name;
      _myHpAtRoundStart = _hpAtRoundStart[p.id] ?? p.hp;
    }
    _flights = flights;
    _pendingDestroyed = info.roundDestroyedIds.length;
    _drainStart = flights.isEmpty
        ? _firstShotAt
        : flights.map((f) => f.impactAt).reduce(max) + _drainDelayAfterImpacts;
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
        floatingActionButton: MatchEmotesOverlay(matchId: widget.matchId),
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
                        firstDoubleTarget: _firstDoubleTarget,
                        onPick: (id) => _pickTarget(info, id),
                        // Inventarul merge CU ecranul de țintire: șase din
                        // puterile din `powerUpUsablePhases` au fereastră în
                        // faza asta, iar tot aici se și ACORDĂ puterea. Până
                        // la recenzia din 2026-09-01 dispărea din cadru
                        // exact în faza în care primeai anunțul „ai primit o
                        // putere" — deci nu se putea folosi.
                        inventory: PowerUpInventory(
                          powerUps: _myPowerUps,
                          usedThisRound: _powerUpUsedRound == info.roundIndex,
                          onUse: (p) => _usePowerUp(info, p),
                        ),
                      );
                    }
                    // Camera de pe obuz stă PESTE tot ecranul, nu doar peste
                    // arenă: în secunda aia întrebarea de jos nu mai are ce
                    // căuta în cadru, iar o suprapunere care lasă marginile
                    // vechi la vedere n-ar mai fi un punct de vedere, ci o
                    // fereastră.
                    return Stack(
                      children: [
                        Column(
                          children: [
                            _buildTopBar(info),
                            RoundEventBanner(
                              event: roundEventFor(matchId: widget.matchId, roundIndex: info.roundIndex, gameModeId: 'quizzTanks'),
                              compact: true,
                            ),
                            Expanded(child: _buildArena(info, players)),
                            // Sub tancuri, nu în colțul din dreapta sus: aici
                            // se uită oricum jucătorul între runde.
                            PowerUpInventory(
                              powerUps: _myPowerUps,
                              usedThisRound: _powerUpUsedRound == info.roundIndex,
                              onUse: (p) => _usePowerUp(info, p),
                            ),
                            _buildBottomPanel(info, players),
                          ],
                        ),
                        Positioned.fill(child: _buildPovOverlay(info)),
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

  /// Camera cinematică a rundei — una singură, peste tot ecranul, aleasă după
  /// rolul meu în runda tocmai rezolvată:
  ///
  ///  • **am tras** → camera de pe propriul obuz ([TankPovView]), cu tot cu
  ///    duel, dacă ținta a tras și ea în mine;
  ///  • **n-am tras, dar vine ceva spre mine** → camera din spatele propriului
  ///    tanc ([TankDefenceView]);
  ///  • **nici una, nici alta** → nimic, rămân pe arenă și văd tabloul întreg.
  ///
  /// Ordinea nu e negociabilă: dacă am tras, lovitura MEA e singurul lucru pe
  /// care l-am decis în runda aia, deci ea are ecranul. Ce am încasat între
  /// timp se scrie mic, în camera de pe obuz (vezi [TankPovView.damageTaken]),
  /// și se vede oricum pe bare când se retrage camera.
  ///
  /// AnimatedBuilder propriu (nu cel al arenei) fiindcă trăiește în afara ei.
  Widget _buildPovOverlay(MatchInfo info) {
    return AnimatedBuilder(
      animation: _fire,
      builder: (context, _) {
        if (info.roundPhase != RoundPhase.revealed) return const SizedBox.shrink();
        final t = _fire.value * tanksRevealSeconds;
        final flight = _myFlight;
        final target = _myPovTarget;
        if (flight != null && target != null) {
          if (t >= TankPovView.endAtFor(flight.impactAt)) return const SizedBox.shrink();
          return TankPovView(
            time: t,
            launchAt: flight.startAt,
            impactAt: flight.impactAt,
            hit: flight.hit,
            damage: flight.damage,
            blockedByShield: flight.blockedByShield,
            targetColor: pickAvatarColor(target.avatarSeed),
            targetName: target.name,
            targetHp: _myPovTargetHpAtStart,
            targetDamageRatio: 1 - (_myPovTargetHpAtStart / tanksMaxHp),
            // culoarea proiectilului e chiar a mea: ShotFlight.color e luată
            // din avatarSeed-ul celui care trage, iar zborul ăsta e al meu.
            shooterColor: flight.color,
            duelIncoming: _myDuel,
            duelIntercepted: _myDuelIntercepted,
            damageTaken: _myDamageTaken,
            second: _myPovSecond,
          );
        }
        if (_myIncoming.isEmpty || t >= TankDefenceView.endAtFor(_myIncoming)) {
          return const SizedBox.shrink();
        }
        return TankDefenceView(
          time: t,
          shells: _myIncoming,
          myColor: _myColor,
          myName: _myName,
          myHp: _myHpAtRoundStart,
        );
      },
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
          const SizedBox(width: 8),
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
        const gap = 10.0;
        const sidePad = 12.0;
        // Geometria grilei e o funcție PURĂ (core/tanks.dart), testată direct
        // pentru orice număr de jucători — vezi test/tank_arena_layout_test.dart.
        // Calculată pentru câți sunt CHIAR la masă, nu pentru plafonul
        // modului: o cameră de 2-3 prieteni tot primește cutii mari, nu o
        // grilă gândită pentru o masă plină de 10.
        final layout = computeTankArenaLayout(
          viewportWidth: c.maxWidth,
          viewportHeight: c.maxHeight,
          playerCount: players.length,
          gap: gap,
          sidePad: sidePad,
        );
        final cellW = layout.cellWidth;
        final cellH = layout.cellHeight;
        final top = layout.top;

        // Grila e fixă: locul unui jucător e dat de poziția lui în lista
        // sortată, deci nu se mișcă de la o rundă la alta.
        final centers = <String, Offset>{};
        for (var i = 0; i < players.length && i < tanksPlayerCount; i++) {
          final col = i % layout.cols;
          final row = i ~/ layout.cols;
          centers[players[i].id] = Offset(
            sidePad + col * (cellW + gap) + cellW / 2,
            top + row * (cellH + gap) + cellH / 2,
          );
        }
        _ensureFlights(info, players, centers, c.maxWidth);

        final content = Transform.translate(
          offset: _shake,
          child: SizedBox(
            width: c.maxWidth,
            height: layout.contentHeight,
            child: Stack(
              children: [
                const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _BattlefieldPainter()))),
                // Locurile nefolosite ale grilei — doar cât să completeze
                // ultimul rând (vezi [TankArenaLayout.slots]), NU până la
                // plafonul modului. Fără ele, colțul gol arăta a ecran care
                // nu s-a încărcat; așa se citește ca „aici putea sta cineva",
                // ceea ce e chiar adevărul.
                for (var i = players.length; i < layout.slots; i++)
                  Positioned(
                    left: sidePad + (i % layout.cols) * (cellW + gap),
                    top: top + (i ~/ layout.cols) * (cellH + gap),
                    width: cellW,
                    height: cellH,
                    child: const _EmptySlot(),
                  ),
                for (var i = 0; i < players.length && i < tanksPlayerCount; i++)
                  Positioned(
                    left: sidePad + (i % layout.cols) * (cellW + gap),
                    top: top + (i ~/ layout.cols) * (cellH + gap),
                    width: cellW,
                    height: cellH,
                    child: _TankCard(
                      player: players[i],
                      facingRight: i % layout.cols == 0,
                      isMe: players[i].id == MultiplayerService.instance.currentPlayerId,
                      hasAnswered: info.roundAnswers.containsKey(players[i].id),
                      showAnswerTicks: info.roundPhase == RoundPhase.answering,
                      isFiring: info.roundPhase == RoundPhase.revealed &&
                          info.roundShots.any((s) => s.byId == players[i].id) &&
                          _fire.value * tanksRevealSeconds >= _firstShotAt - 0.3,
                      previousHp: _hpAtRoundStart[players[i].id] ?? players[i].hp,
                      drainProgress: _drainProgress,
                      tankWidth: (cellW * 0.46).clamp(40.0, 96.0),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: TankShotsPainter(
                        flights: _flights,
                        time: _fire.value * tanksRevealSeconds,
                        shieldedCenters: info.roundPhase == RoundPhase.revealed
                            ? [
                                for (final id in info.roundShieldedIds)
                                  if (centers[id] != null) centers[id]!,
                              ]
                            : const [],
                      ),
                    ),
                  ),
                ),
                if (info.roundPhase == RoundPhase.revealed) _buildFireBanner(info),
                if (info.roundPhase == RoundPhase.revealed) _buildWreckBanner(info, players),
              ],
            ),
          ),
        );

        // Sub plafonul de jucători ai unei mese obișnuite (până la 4-6),
        // grila tot încape fără derulare, exact ca înainte. Doar la o masă
        // plină de 8-10 arena devine derulabilă vertical — tot ce ține de ea
        // (fundal, tancuri, proiectile) se mișcă împreună, fiindcă sunt toate
        // în ACELAȘI Stack dimensionat la [layout.contentHeight], nu
        // suprapuse din afară.
        return layout.scrolls ? SingleChildScrollView(child: content) : ClipRect(child: content);
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

  /// „X DISTRUS" — umple secunda și jumătate rămasă după ce s-au așezat
  /// barele. Fără el, sfârșitul rundei era o pauză moartă: exploziile se
  /// terminau, iar ecranul rămânea nemișcat până la întrebarea următoare,
  /// fără ca cineva să apuce să înțeleagă CINE tocmai a ieșit din joc.
  Widget _buildWreckBanner(MatchInfo info, List<MatchPlayer> players) {
    if (info.roundDestroyedIds.isEmpty) return const SizedBox.shrink();
    final t = _fire.value * tanksRevealSeconds;
    final showAt = _drainStart + _drainDuration + 0.15;
    if (t < showAt) return const SizedBox.shrink();
    final me = MultiplayerService.instance.currentPlayerId;
    final names = <String>[];
    var iAmWrecked = false;
    for (final p in players) {
      if (!info.roundDestroyedIds.contains(p.id)) continue;
      names.add(p.name);
      if (p.id == me) iAmWrecked = true;
    }
    if (names.isEmpty) return const SizedBox.shrink();
    final appear = ((t - showAt) / 0.28).clamp(0.0, 1.0);
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Opacity(
            opacity: appear,
            child: Transform.scale(
              scale: 0.85 + appear * 0.15,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(190),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.danger.withAlpha(170), width: 1.6),
                  boxShadow: [BoxShadow(color: AppColors.danger.withAlpha(90), blurRadius: 22, spreadRadius: -6)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('💥', style: TextStyle(fontSize: 26)),
                    const SizedBox(height: 4),
                    Text(
                      iAmWrecked && names.length == 1
                          ? tr('AI FOST DISTRUS', 'YOU ARE WRECKED')
                          : tr('${names.join(', ')} — DISTRUS', '${names.join(', ')} — WRECKED'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
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
              if (_hiddenChoices.contains(choice)) return const SizedBox.shrink();
              return Padding(
                padding: EdgeInsets.only(bottom: i == 3 ? 0 : 6),
                child: _AnswerButton(
                  letter: String.fromCharCode(65 + i),
                  text: choice,
                  picked: myAnswer == choice,
                  // Răspunsul corect se arată abia în faza de foc — până
                  // atunci nimeni nu vede nimic, nici măcar propria greșeală.
                  correct: revealed && choice == question.answer,
                  adminHint: !revealed && adminAnswerRevealOn && choice == question.answer,
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

  /// Prima țintă apăsată la [PowerUp.doubleShot], cât timp încă se așteaptă
  /// a doua apăsare (vezi `_MultiplayerTanksScreenState._firstDoubleTarget`).
  final String? firstDoubleTarget;
  final void Function(String targetId) onPick;

  /// Bara de puteri, construită de ecran (vezi [PowerUpInventory]) — se
  /// desenează sub conținut, deasupra dezvăluirii răspunsului.
  final Widget inventory;

  const _TargetingView({
    required this.info,
    required this.players,
    required this.question,
    required this.secondsLeft,
    required this.firstDoubleTarget,
    required this.onPick,
    required this.inventory,
  });

  @override
  Widget build(BuildContext context) {
    final me = MultiplayerService.instance.currentPlayerId;
    final iAmShooter = info.roundWinnerIds.contains(me);
    final submitted = info.roundTargets[me];
    final iHaveDoubleShot = info.roundPowerUps[me] == PowerUp.doubleShot.name;
    // Țintele de evidențiat: după trimitere, ambele (despărțite de „|"); în
    // timpul unei lovituri duble, prima apăsată; altfel niciuna.
    final Set<String> chosen = submitted != null
        ? submitted.split(tanksTargetSeparator).toSet()
        : {if (firstDoubleTarget != null) firstDoubleTarget!};
    final locked = submitted != null;
    // La lovitura dublă mai e o apăsare de făcut dacă am reținut prima dar
    // n-am trimis încă.
    final awaitingSecond = iHaveDoubleShot && !locked && firstDoubleTarget != null;
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
              _header(iAmShooter, locked, iHaveDoubleShot, awaitingSecond),
              // Conținutul stă CENTRAT pe verticală: la patru jucători sunt
              // trei cutii și se umple ecranul, dar spre finalul meciului
              // rămâne una singură, iar lipită de titlu arăta a pagină
              // neterminată.
              Expanded(child: Center(child: iAmShooter ? _targets(enemies, chosen, locked) : _waitingRoom())),
              inventory,
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

  Widget _header(bool iAmShooter, bool alreadyPicked, bool doubleShot, bool awaitingSecond) {
    final color = iAmShooter ? AppColors.danger : AppColors.blue;
    final String titleText;
    if (!iAmShooter) {
      titleText = tr('LA ADĂPOST!', 'BRACE!');
    } else if (doubleShot && !alreadyPicked) {
      titleText = awaitingSecond
          ? tr('ȚINTA 2 DIN 2', 'TARGET 2 OF 2')
          : tr('ȚINTA 1 DIN 2', 'TARGET 1 OF 2');
    } else {
      titleText = tr('ALEGE ȚINTA', 'PICK YOUR TARGET');
    }
    final String subText;
    if (!iAmShooter) {
      subText = tr('Ai greșit runda asta: nu tragi și eviți mult mai greu.',
          'You missed this round: you do not fire, and you dodge much worse.');
    } else if (alreadyPicked) {
      subText = tr('Țintă blocată. Aștept ceilalți tunari...', 'Target locked. Waiting for the other gunners...');
    } else if (doubleShot) {
      subText = awaitingSecond
          ? tr('Apasă din nou — aceeași țintă = o lovitură mai puternică.',
              'Tap again — same target = one stronger hit.')
          : tr('Lovitură dublă: alege ținta fiecărui proiectil.',
              'Double shot: aim each of your two shots.');
    } else {
      subText = tr('Ai nimerit răspunsul — ai dreptul la o lovitură.',
          'You got it right — you have earned one shot.');
    }
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iAmShooter ? Icons.gps_fixed_rounded : Icons.shield_rounded, color: color, size: 22),
            const SizedBox(width: 10),
            Text(
              titleText,
              style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3),
            ),
            const SizedBox(width: 10),
            _TargetClock(secondsLeft: secondsLeft, color: color),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          subText,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  /// Cutiile adversarilor. Cel mai slăbit e marcat explicit, fiindcă ăsta e
  /// și cel pe care tragi automat dacă nu apuci să alegi — jucătorul trebuie
  /// să vadă dinainte ce se întâmplă dacă ezită.
  Widget _targets(List<MatchPlayer> enemies, Set<String> chosen, bool locked) {
    if (enemies.isEmpty) {
      return Text(tr('Nu mai are cine să fie țintă.', 'Nobody left to target.'),
          style: const TextStyle(color: Colors.white54));
    }
    final weakest = enemies.reduce((a, b) => b.hp < a.hp ? b : a);
    // Cine face cele mai multe daune de la masă — „amenințarea", cifra după
    // care se decide clasamentul final (vezi core/tanks.dart). Marcată doar
    // dacă chiar a lovit ceva, altfel la runda 1 ar primi-o toată lumea.
    final topThreat = enemies.fold<int>(0, (best, p) => p.damageDealt > best ? p.damageDealt : best);
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
                selected: chosen.contains(p.id),
                locked: locked,
                isWeakest: enemies.length > 1 && p.id == weakest.id,
                // „În gardă" = a răspuns și el corect runda asta, deci e în
                // lista țintașilor și evită mult mai des. Vezi
                // MultiplayerService.resolveTanksRound, care citește exact
                // aceeași listă când aruncă zarul.
                onGuard: info.roundWinnerIds.contains(p.id),
                isTopThreat: enemies.length > 1 && topThreat > 0 && p.damageDealt == topThreat,
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

/// O victimă posibilă — fișa completă pe care se ia decizia rundei.
///
/// DE CE ATÂTA INFORMAȚIE PE UN SINGUR CARD: alegerea țintei era, până acum,
/// aproape o formalitate — vedeai un nume, o bară și trăgeai în cel mai roșu.
/// Dar cifra care decide de fapt rezultatul e ȘANSA DE LOVIRE, iar ea nu
/// depinde de viață, ci de dacă ținta a nimerit ea însăși întrebarea rundei
/// ([onGuard]). Un tanc slăbit „în gardă" evită mai mult de jumătate din
/// lovituri, pe când unul sănătos care a greșit e practic sigur atins.
/// Arătând amândouă, alegerea devine o socoteală adevărată: pariez pe o
/// lovitură ucigașă improbabilă, sau iau daune sigure de la cel sănătos?
///
/// Nimic de aici nu e secret: [onGuard] se citește din `roundWinnerIds`, care
/// e public pe documentul meciului din clipa în care se închide faza de
/// răspuns (vezi MultiplayerService.closeTanksAnswering).
class _TargetCard extends StatelessWidget {
  final MatchPlayer player;
  final bool selected;
  final bool locked;
  final bool isWeakest;
  final bool onGuard;
  final bool isTopThreat;
  final VoidCallback onTap;

  const _TargetCard({
    required this.player,
    required this.selected,
    required this.locked,
    required this.isWeakest,
    required this.onGuard,
    required this.isTopThreat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = pickAvatarColor(player.avatarSeed);
    final hpColor = TankHpBar.hpColor(player.hp);
    final hitChance = tanksHitChance(targetAnsweredCorrectly: onGuard);
    final canKill = tanksCanKill(player.hp);
    final chanceColor = hitChance >= 0.7 ? AppColors.play : AppColors.orange;

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
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: selected
                    ? [AppColors.danger.withAlpha(60), AppColors.danger.withAlpha(18)]
                    : [Colors.white.withAlpha(20), Colors.white.withAlpha(8)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? AppColors.danger : Colors.white24, width: selected ? 2.2 : 1),
              boxShadow: selected
                  ? [BoxShadow(color: AppColors.danger.withAlpha(120), blurRadius: 18, spreadRadius: -4)]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Avatar(
                      size: 40,
                      label: player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
                      accentColor: color,
                      photoUrl: player.photoUrl,
                      style: avatarStyleFromId(player.avatarStyle),
                    ),
                    const SizedBox(width: 11),
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
                                  style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('${player.hp}',
                                  style: TextStyle(color: hpColor, fontSize: 15, fontWeight: FontWeight.w900)),
                              Text(' HP', style: TextStyle(color: hpColor.withAlpha(160), fontSize: 10, fontWeight: FontWeight.w800)),
                            ],
                          ),
                          const SizedBox(height: 5),
                          TankHpBar(
                            hp: player.hp,
                            previousHp: player.hp,
                            drainProgress: 1,
                            color: hpColor,
                            height: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    TankArt(color: color, width: 58, facingRight: false, damage: 1 - (player.hp / tanksMaxHp)),
                    const SizedBox(width: 4),
                    Icon(
                      selected ? Icons.gps_fixed_rounded : Icons.radio_button_unchecked_rounded,
                      color: selected ? AppColors.danger : Colors.white24,
                      size: 22,
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                // Rândul de citire tactică. Șansa stă prima și cel mai mare:
                // e singura cifră care schimbă rezultatul aruncării.
                Row(
                  children: [
                    _readout(
                      icon: Icons.percent_rounded,
                      label: tr('ȘANSĂ', 'HIT'),
                      value: '${(hitChance * 100).round()}%',
                      color: chanceColor,
                    ),
                    const SizedBox(width: 7),
                    _readout(
                      icon: Icons.whatshot_rounded,
                      label: tr('DAUNE', 'DEALT'),
                      value: '${player.damageDealt}',
                      color: isTopThreat ? AppColors.danger : Colors.white54,
                    ),
                    const Spacer(),
                    if (canKill) _chip(tr('LOVITURĂ MORTALĂ', 'KILL SHOT'), AppColors.danger),
                  ],
                ),
                if (onGuard || isWeakest || isTopThreat) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      if (onGuard) _chip(tr('ÎN GARDĂ · evită des', 'ON GUARD · dodges often'), AppColors.blue),
                      if (isTopThreat) _chip(tr('CEL MAI PERICULOS', 'BIGGEST THREAT'), AppColors.danger),
                      if (isWeakest) _chip(tr('ȚINTA IMPLICITĂ', 'DEFAULT TARGET'), AppColors.orange),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _readout({required IconData icon, required String label, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color.withAlpha(180), fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
          const SizedBox(width: 5),
          Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.4),
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

/// Cronometrul rundei — cifră mare într-un pătrat rotunjit, roșu în ultimele
/// două secunde. Nu e CountdownRing (folosit la Higher & Lower / Daily):
/// aici contează să se citească CIFRA dintr-o privire periferică, în timp ce
/// ochiul e pe variante, nu cât a mai rămas dintr-un arc.
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
        // Placă de blindaj, nu o cutie plată: degradeul dinspre colțul din
        // stânga-sus dă volum, iar la cel care trage lumina vine din tun.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: destroyed
              ? [Colors.black.withAlpha(120), Colors.black.withAlpha(70)]
              : isFiring
                  ? [AppColors.orange.withAlpha(60), Colors.white.withAlpha(10)]
                  : [Colors.white.withAlpha(isMe ? 30 : 20), Colors.white.withAlpha(6)],
        ),
        borderRadius: const BorderRadius.only(
          // colț tăiat sus-stânga: siluetă de placă metalică, nu de card
          topLeft: Radius.circular(5),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
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
          Row(
            children: [
              if (!facingRight) const Spacer(),
              TankArt(
                color: color,
                width: tankWidth,
                facingRight: facingRight,
                destroyed: destroyed,
                damage: 1 - (player.hp / tanksMaxHp),
              ),
              if (facingRight) const Spacer(),
              // Starea din runda curentă, lângă tanc: „ARMAT" cât aștepți
              // ceilalți, „FOC" cât îți pleacă obuzul, „KO" la epavă. Ocupă
              // colțul care oricum rămânea gol sub bara de viață.
              if (destroyed)
                _statusChip(tr('KO', 'KO'), AppColors.danger)
              else if (isFiring)
                _statusChip(tr('FOC', 'FIRE'), AppColors.orange)
              else if (hasAnswered && showAnswerTicks)
                _statusChip(tr('ARMAT', 'LOADED'), AppColors.play),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(140)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.6),
      ),
    );
  }
}

/// Un loc liber din grila 2×2, la o cameră pornită cu mai puțin de patru
/// jucători. Doar un contur întrerupt — trebuie să se citească drept „gol",
/// nu drept încă un tanc pe care ai putea trage.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withAlpha(18)),
        ),
        child: Center(
          child: Icon(Icons.remove_rounded, color: Colors.white.withAlpha(26), size: 22),
        ),
      ),
    );
  }
}

/// Fundalul arenei: un câmp de luptă văzut de sus, cu orizont cald, creste
/// îndepărtate, cratere și o grilă tactică.
///
/// Rămâne DISCRET intenționat — tot ce contează (tancuri, bare, proiectile)
/// se desenează deasupra, iar un fundal care se bate cu ele ar face runda
/// ilizibilă tocmai în secundele în care se întâmplă totul. De-aia n-are
/// nicio animație: singura mișcare din arenă trebuie să fie a jocului.
class _BattlefieldPainter extends CustomPainter {
  const _BattlefieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // creste îndepărtate, două straturi — dau adâncime fără să ceară nimic
    for (final layer in [(0.20, 34, 0.055), (0.30, 22, 0.085)]) {
      final (yFrac, alpha, amp) = layer;
      final path = Path()..moveTo(0, h * yFrac);
      for (var x = 0.0; x <= w; x += w / 14) {
        final n = sin(x / w * 7 + yFrac * 21) * 0.5 + cos(x / w * 11 + yFrac * 5) * 0.5;
        path.lineTo(x, h * (yFrac + n * amp));
      }
      path
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0xFF2A1F3A).withAlpha(alpha));
    }

    // haloul cald dinspre orizont
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.orange.withAlpha(30), Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(w / 2, h * 0.34), radius: w * 0.85)),
    );

    // cratere — urme de bătălie, împrăștiate determinist (fără Random: fundalul
    // trebuie să arate la fel la fiecare redesenare)
    final crater = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 9; i++) {
      final x = w * (0.08 + ((i * 37) % 100) / 115);
      final y = h * (0.28 + ((i * 53) % 100) / 145);
      final r = w * (0.018 + ((i * 17) % 30) / 900);
      crater.color = Colors.black.withAlpha(40);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: r * 2.6, height: r * 1.5), crater);
      crater.color = Colors.white.withAlpha(9);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y - r * 0.22), width: r * 2.2, height: r * 1.2), crater);
    }

    // grila tactică
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withAlpha(11);
    for (var i = 1; i < 7; i++) {
      final y = h * (i / 7);
      canvas.drawLine(Offset(0, y), Offset(w, y), line);
    }
    for (var i = 1; i < 6; i++) {
      final x = w * (i / 6);
      canvas.drawLine(Offset(x, 0), Offset(x, h), line);
    }

    // axa centrală, marcată mai apăsat: împarte vizual masa în două tabere
    canvas.drawLine(
      Offset(w / 2, 0),
      Offset(w / 2, h),
      Paint()
        ..strokeWidth = 1
        ..color = AppColors.orange.withAlpha(26),
    );
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
  /// Toggle-ul de admin „vezi răspunsul corect" — chihlimbar, doar cât NU s-a
  /// dezvăluit încă runda (core/admin_reveal.dart). Pur vizual.
  final bool adminHint;
  final VoidCallback? onTap;

  const _AnswerButton({
    required this.letter,
    required this.text,
    required this.picked,
    required this.correct,
    required this.dimmed,
    this.adminHint = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = correct
        ? AppColors.play
        : adminHint
            ? adminRevealColor
            : picked
                ? AppColors.blue
                : Colors.white;
    final accent = correct || picked || adminHint;
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
              color: accent ? color.withAlpha(38) : Colors.white.withAlpha(14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accent ? color : Colors.white24,
                width: accent ? 1.6 : 1,
              ),
              boxShadow: correct || adminHint ? [BoxShadow(color: color.withAlpha(90), blurRadius: 12, spreadRadius: -3)] : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent ? color.withAlpha(60) : Colors.white.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    letter,
                    style: TextStyle(
                      color: accent ? color : Colors.white70,
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
