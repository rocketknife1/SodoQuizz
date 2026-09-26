import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/audio.dart';
import '../../core/breadcrumbs.dart';
import '../../core/game_pause.dart';
import '../../core/lang.dart';
import '../../core/powerup_ui.dart';
import '../../core/stable_hash.dart';
import '../../core/theme.dart';
import '../../core/unknown_game.dart';
import '../../data/bot_match.dart';
import '../../data/culture_questions.dart';
import '../../data/multiplayer_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/match_overlay.dart';
import '../../widgets/unknown_board.dart';
import 'multiplayer_results_screen.dart';

/// **Unknown** — cursa pe numere 1..60 (regulile: core/unknown_game.dart).
///
/// CE FACE ECRANUL ĂSTA ȘI CE NU: nu decide nimic. Întrebarea o are local
/// (pool comun, amestecat determinist din `matchId`), răspunsul îl trimite
/// cu timpul măsurat de telefon, iar runda o închide oricine apucă primul
/// (MultiplayerService.closeUnknownRound — zarurile se aruncă O SINGURĂ DATĂ,
/// acolo). Apoi toată lumea animă același jurnal (`unknownLog`), în același
/// ritm; cine termină primul animația trece masa la runda următoare.
///
/// Același ecran și pentru meciul cu boți (data/bot_match.dart): se schimbă
/// doar baza de date, boții trimit răspunsuri și alegeri ca oamenii.
///
/// Ritmul e dinadins domol: fiecare aruncare, scară sau șarpe stă pe ecran
/// destul cât să vezi ce s-a întâmplat și cu cine.
class MultiplayerUnknownScreen extends StatefulWidget {
  final String matchId;

  /// Meci cu boți — null într-un meci online normal.
  final BotMatch? bot;

  const MultiplayerUnknownScreen({super.key, required this.matchId, this.bot});

  @override
  State<MultiplayerUnknownScreen> createState() => _MultiplayerUnknownScreenState();
}

/// Aruncată când regia unei runde trebuie oprită (ecran închis, sau a
/// sosit deja runda următoare) — iese din bucla de animații fără să mai
/// atingă `setState`.
class _Stop implements Exception {}

enum _Panel { log, question, reveal, chest, chestDrop, shop }

class _HopAnim {
  _HopAnim(this.pawn, this.from, this.to, this.start, this.dur, this.arc, this.done, this.path);

  final UnknownPawn pawn;
  final Offset from;
  final Offset to;
  final double start;
  final double dur;
  final double arc;
  final Completer<void> done;

  /// Drum curb (corpul șarpelui); null = linie dreaptă.
  final Offset Function(double t)? path;
}

class _MultiplayerUnknownScreenState extends State<MultiplayerUnknownScreen> with SingleTickerProviderStateMixin {
  MultiplayerService get _mp => widget.bot?.service ?? MultiplayerService.instance;
  String get _me => _mp.currentPlayerId;

  // Ritmul (milisecunde). Toate într-un loc, ca să se poată regla ușor.
  static const _hopSeconds = 0.34;
  static const _revealMs = 2200;
  static const _bannerMs = 1500;
  static const _diceHoldMs = 1300;
  static const _noteMs = 1500;
  static const _betweenPlayersMs = 800;
  static const _choiceWindowMs = 10000;

  late final List<CultureQuestion> _pool = _buildPool();
  List<String>? _cachedChoices;
  int _cachedChoicesRound = -1;

  StreamSubscription<MatchInfo>? _matchSub;
  StreamSubscription<List<MatchPlayer>>? _playersSub;
  MatchInfo? _info;
  List<MatchPlayer> _players = const [];
  final Map<String, MatchPlayer> _playerById = {};
  Set<String> _seenPlayerIds = const {};
  final Set<String> _announcedLeftIds = {};

  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  final _scene = UnknownScene();
  final List<_HopAnim> _hops = [];
  Duration _lastTick = Duration.zero;
  Timer? _clock;
  Timer? _heartbeat;
  bool _disposed = false;
  bool _left = false;
  bool _navigatedToResults = false;

  // ─── Starea afișată ────────────────────────────────────────────────────

  /// Ultima stare cunoscută a jocului (din `unknown`).
  UnknownGame? _game;

  /// Pozițiile și monedele de pe ecran — rămân în urma stării reale cât
  /// se animă runda, ca cifrele să crească odată cu animația.
  final Map<String, List<int>> _shown = {};

  /// Runda al cărei jurnal l-am animat (sau sărit) deja.
  int _playedLogRound = -1;

  /// Crește la fiecare regie nouă; o regie veche care vede alt număr se oprește.
  int _regieToken = 0;
  bool _regieRunning = false;
  bool _regieDoneForRound = false;

  // ─── Întrebarea ────────────────────────────────────────────────────────

  int _questionRound = -1;
  DateTime _questionShownAt = DateTime.now();
  String? _myPick;
  DateTime? _lastCloseAttempt;
  bool _closing = false;

  // ─── Panoul de jos, zarurile, bannerul ─────────────────────────────────

  _Panel _panel = _Panel.log;
  String _log = '';
  bool _diceVisible = false;
  bool _diceRolling = false;
  List<int> _dice = [];
  List<String> _diceLabels = [];
  String _diceOwner = '';
  String? _banner;
  int _bannerKey = 0;

  // Alegerea mea de la cufăr/magazin (oferta din starea jocului).
  UnknownOffer? _myOffer;
  int _myOfferRound = -1;
  bool _myOfferSent = false;
  UnknownRelic? _pendingRelic;
  final _rnd = Random();

  List<CultureQuestion> _buildPool() {
    final pool = List.of(cultureQuestions);
    stableShuffle(pool, stableHash(widget.matchId));
    return pool;
  }

  CultureQuestion _questionFor(int round) => _pool[round % _pool.length];

  /// Variantele amestecate determinist pe rundă, ca răspunsul corect să nu
  /// stea mereu pe aceeași poziție.
  List<String> _choicesFor(int round) {
    if (_cachedChoicesRound == round && _cachedChoices != null) return _cachedChoices!;
    final choices = List.of(_questionFor(round).choices);
    stableShuffle(choices, stableHash('${widget.matchId}#$round'));
    _cachedChoices = choices;
    _cachedChoicesRound = round;
    return choices;
  }

  @override
  void initState() {
    super.initState();
    Breadcrumbs.drop('ecran: Meci Unknown');
    _mp.markActiveMatch(widget.matchId, MatchGameMode.unknown);
    _scene.camTarget = unknownTileCenters[0];
    _scene.cam = unknownTileCenters[0];
    _ticker = createTicker(_tick)..start();
    _matchSub = _mp.watchMatch(widget.matchId).listen((info) {
      _info = info;
      _onData();
    });
    _playersSub = _mp.watchPlayers(widget.matchId).listen((players) {
      _players = players;
      _playerById
        ..clear()
        ..addEntries(players.map((p) => MapEntry(p.id, p)));
      _detectPlayersWhoLeft(players);
      _onData();
    });
    // Cronometrul întrebării scade vizibil o dată pe secundă.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
        _onData();
      }
    });
    _heartbeat = Timer.periodic(MultiplayerService.matchHeartbeatInterval, (_) => _mp.matchHeartbeat(widget.matchId));
  }

  @override
  void dispose() {
    _disposed = true;
    _matchSub?.cancel();
    _playersSub?.cancel();
    _clock?.cancel();
    _heartbeat?.cancel();
    GamePause.instance.resume();
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _detectPlayersWhoLeft(List<MatchPlayer> players) {
    final ids = players.map((p) => p.id).toSet();
    if (_seenPlayerIds.isNotEmpty && _info?.status == MatchStatus.playing) {
      for (final id in _seenPlayerIds.difference(ids)) {
        if (id == _me || !_announcedLeftIds.add(id)) continue;
        final name = _nameOf(id);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) notifyPlayerLeft(context, name);
        });
      }
    }
    _seenPlayerIds = ids;
  }

  String _nameOf(String id) {
    final p = _playerById[id];
    if (p != null) return p.name;
    final g = _game?.players.where((q) => q.id == id).firstOrNull;
    return g?.name ?? '?';
  }

  String _who(String id) => id == _me ? tr('Tu', 'You') : _nameOf(id);

  // ─── Datele din Firestore → ce facem ───────────────────────────────────

  void _onData() {
    final info = _info;
    if (info == null || _disposed) return;

    // Starea jocului: prima dată pionii se pun direct unde sunt (intrare în
    // mijlocul meciului); după aceea doar regia îi mută.
    final raw = info.unknownState;
    if (raw != null) {
      final game = UnknownGame.fromJson(raw);
      final first = _game == null;
      _game = game;
      final logRound = (info.unknownLog?['r'] as num?)?.toInt() ?? -1;
      // Prima stare văzută fără să fi văzut și întrebarea rundei ei =
      // intrare în mijlocul meciului (reconectare): pionii sar direct unde
      // sunt, iar jurnalul acelei runde nu se mai animă. Dacă am văzut
      // întrebarea, e pur și simplu prima rundă — se animă normal.
      if (first && _questionRound != logRound) {
        _syncPawnsToGame(game);
        _playedLogRound = logRound;
        if (info.roundPhase == RoundPhase.revealed) _regieDoneForRound = true;
      }
    }
    _ensurePawns();

    if (info.roundPhase == RoundPhase.answering) {
      _onAnswering(info);
    } else if (info.roundPhase == RoundPhase.revealed) {
      _onRevealed(info);
    }
    if (mounted) setState(() {});
  }

  /// Pionii tuturor jucătorilor de la masă, și înainte de prima rundă (când
  /// încă nu există starea jocului).
  void _ensurePawns() {
    final ids = _game?.players.map((p) => p.id).toList() ?? (_players.map((p) => p.id).toList()..sort());
    for (final (i, id) in ids.indexed) {
      if (_scene.pawns.containsKey(id)) continue;
      final gp = _game?.players.where((p) => p.id == id).firstOrNull;
      final name = gp?.name ?? _nameOf(id);
      _scene.pawns[id] = UnknownPawn(id: id, colorIndex: gp?.colorIndex ?? i, initial: _initial(name), tile: gp?.pos ?? 0);
      _shown.putIfAbsent(id, () => [gp?.pos ?? 0, gp?.coins ?? unknownStartCoins]);
    }
  }

  void _syncPawnsToGame(UnknownGame game) {
    for (final p in game.players) {
      final pawn = _scene.pawns[p.id];
      if (pawn != null) {
        pawn
          ..tile = p.pos
          ..pos = unknownTileCenters[p.pos]
          ..moving = false
          ..lift = 0;
      }
      _shown[p.id] = [p.pos, p.coins];
    }
  }

  static String _initial(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return String.fromCharCodes(t.runes.take(1)).toUpperCase();
  }

  bool _racing(String id) {
    final g = _game?.players.where((p) => p.id == id).firstOrNull;
    return g == null || g.racing;
  }

  void _onAnswering(MatchInfo info) {
    if (_questionRound != info.roundIndex) {
      _questionRound = info.roundIndex;
      _questionShownAt = DateTime.now();
      _myPick = null;
      _myOffer = null;
      _regieDoneForRound = false;
      // O regie rămasă în urmă (telefon lent) se oprește: pionii sar direct
      // la poziția reală, altfel întrebarea nouă ar apărea peste animația veche.
      if (_regieRunning) {
        _regieToken++;
        _regieRunning = false;
        _hops.clear();
        final g = _game;
        if (g != null) _syncPawnsToGame(g);
        _diceVisible = false;
        _banner = null;
      }
      _scene.activeId = null;
      _focusOn(null);
    }
    if (!_regieRunning) _panel = _Panel.question;

    final racingIds = [for (final p in _players) if (_racing(p.id)) p.id];
    final allAnswered = racingIds.isNotEmpty && racingIds.every(info.roundAnswers.containsKey);
    if (allAnswered || _secondsLeft(info) <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _closeRound(info));
    }
  }

  int _secondsLeft(MatchInfo info) {
    final started = info.roundStartedAt?.toDate();
    if (started == null) return unknownQuestionSeconds;
    final elapsed = DateTime.now().difference(started).inSeconds;
    return (unknownQuestionSeconds - elapsed).clamp(0, unknownQuestionSeconds);
  }

  Future<void> _closeRound(MatchInfo info) async {
    if (_closing || info.roundPhase != RoundPhase.answering) return;
    final now = DateTime.now();
    if (_lastCloseAttempt != null && now.difference(_lastCloseAttempt!) < const Duration(milliseconds: 900)) return;
    _lastCloseAttempt = now;
    _closing = true;
    try {
      await _mp.closeUnknownRound(
        matchId: widget.matchId,
        roundIndex: info.roundIndex,
        correctAnswer: _questionFor(info.roundIndex).answer,
      );
    } finally {
      _closing = false;
    }
  }

  void _onRevealed(MatchInfo info) {
    final raw = info.unknownLog;
    if (raw == null) return;
    final round = (raw['r'] as num?)?.toInt() ?? -1;
    if (round != info.roundIndex) return;
    if (round > _playedLogRound && !_regieRunning) {
      _playedLogRound = round;
      final token = ++_regieToken;
      _regieRunning = true;
      _playLog(UnknownRoundLog.fromJson(raw), info, token);
    } else if (_regieDoneForRound) {
      _afterRegie(info);
    }
  }

  /// Runda pentru care am cerut deja trecerea mai departe (o singură cerere).
  int _advanceRequested = -1;

  /// După animație: meciul continuă → runda următoare; s-a terminat → clasament.
  void _afterRegie(MatchInfo info) {
    if (info.status == MatchStatus.finished) {
      if (_navigatedToResults) return;
      _navigatedToResults = true;
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MultiplayerResultsScreen(bot: widget.bot, matchId: widget.matchId, gameMode: MatchGameMode.unknown),
          ),
        );
      });
      return;
    }
    if (_advanceRequested == info.roundIndex) return;
    _advanceRequested = info.roundIndex;
    _mp.advanceSyncRound(matchId: widget.matchId, roundIndex: info.roundIndex);
  }

  // ─── Ceasul animațiilor ──────────────────────────────────────────────

  void _tick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _scene.time = elapsed.inMicroseconds / 1e6;

    for (final h in List.of(_hops)) {
      final t = ((_scene.time - h.start) / h.dur).clamp(0.0, 1.0);
      final e = Curves.easeInOut.transform(t);
      h.pawn.pos = h.path != null ? h.path!(e) : Offset.lerp(h.from, h.to, e)!;
      h.pawn.lift = sin(pi * t) * h.arc;
      if (t >= 1) {
        h.pawn.lift = 0;
        _hops.remove(h);
        if (!h.done.isCompleted) h.done.complete();
      }
    }

    final active = _scene.activeId == null ? null : _scene.pawns[_scene.activeId];
    if (active != null && active.moving) _scene.camTarget = active.pos;
    final k = min(1.0, dt * 3.5);
    _scene.cam = Offset.lerp(_scene.cam, _scene.camTarget, k)!;
    _scene.zoom += (_scene.zoomTarget - _scene.zoom) * k;
    _scene.floaters.removeWhere((f) => _scene.time - f.born > unknownFloaterLife + 0.2);
    _repaint.value++;
  }

  void _focusOn(String? id, {double zoom = 1.4}) {
    if (id == null || !_scene.pawns.containsKey(id)) {
      _scene.camTarget = unknownWorldCenter;
      _scene.zoomTarget = 1.0;
      return;
    }
    final pawn = _scene.pawns[id]!;
    _scene.camTarget = pawn.moving ? pawn.pos : _scene.restingPos(pawn);
    _scene.zoomTarget = zoom;
  }

  Future<void> _hopTo(
    UnknownPawn pawn,
    int tile, {
    double seconds = _hopSeconds,
    double arc = 34,
    Offset Function(double t)? path,
  }) {
    final from = pawn.moving ? pawn.pos : _scene.restingPos(pawn);
    pawn.moving = true;
    final done = Completer<void>();
    _hops.add(_HopAnim(pawn, from, unknownTileCenters[tile], _scene.time, seconds, arc, done, path));
    return done.future;
  }

  // ─── Regia unei runde ────────────────────────────────────────────────

  void _alive(int token) {
    if (_disposed || !mounted || token != _regieToken) throw _Stop();
  }

  Future<void> _wait(int ms, int token) async {
    var left = ms;
    while (left > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      _alive(token);
      if (!GamePause.instance.isPaused) left -= 50;
    }
  }

  void _set(int token, VoidCallback fn) {
    _alive(token);
    setState(fn);
  }

  Future<void> _showBanner(String text, int token, {int ms = _bannerMs}) async {
    _set(token, () {
      _banner = text;
      _bannerKey++;
    });
    await _wait(ms, token);
    _set(token, () => _banner = null);
  }

  Future<void> _playLog(UnknownRoundLog log, MatchInfo info, int token) async {
    try {
      await _runLog(log, info, token);
      if (token == _regieToken) {
        _regieRunning = false;
        _regieDoneForRound = true;
        final latest = _info;
        if (latest != null && latest.roundPhase == RoundPhase.revealed && latest.roundIndex == log.round) {
          _afterRegie(latest);
        }
      }
    } on _Stop {
      if (token == _regieToken) _regieRunning = false;
    }
  }

  Future<void> _runLog(UnknownRoundLog log, MatchInfo info, int token) async {
    // 1. Dezvăluirea răspunsului: cine a nimerit, cine nu.
    _set(token, () => _panel = _Panel.reveal);
    final mine = info.roundAnswers[_me];
    if (mine != null && mine == _questionFor(log.round).answer) Sfx.coinHit();
    await _wait(_revealMs, token);
    _set(token, () {
      _panel = _Panel.log;
      _log = '';
    });
    _focusOn(null);

    // 2. Alegerile de la cufăr/magazin din runda trecută.
    for (final c in log.choices) {
      final what = c.chest
          ? (c.relic == null ? null : '${unknownRelicEmoji(c.relic!)} ${unknownRelicName(c.relic!)}')
          : (c.item == null ? null : '${unknownItemEmoji(c.item!)} ${unknownItemName(c.item!)}');
      if (what == null) continue;
      _floaterText(c.playerId, c.chest ? unknownRelicEmoji(c.relic!) : unknownItemEmoji(c.item!), Colors.white, big: true);
      _set(token, () => _log = tr('${_who(c.playerId)}: $what', '${_who(c.playerId)}: $what'));
      await _wait(1100, token);
    }

    // 3. Duelurile și întrebările de aur decise de întrebarea asta.
    for (final d in log.duels) {
      await _showBanner('⚔️ ${_who(d.attackerId)} vs ${_who(d.defenderId)}', token, ms: 1300);
      for (final f in d.fx) {
        _floater(f);
      }
      _set(token, () => _log = d.winnerId == null
          ? tr('⚔️ Niciunul n-a nimerit — duel nul.', '⚔️ Neither got it — a draw.')
          : d.winnerId == _me
              ? tr('⚔️ Ai câștigat duelul!', '⚔️ You won the duel!')
              : tr('⚔️ ${_nameOf(d.winnerId!)} câștigă duelul!', '⚔️ ${_nameOf(d.winnerId!)} wins the duel!'));
      if (d.winnerId == _me) Sfx.rewardPop();
      await _wait(1600, token);
    }
    for (final e in log.golden.entries) {
      _set(token, () => _log = e.value
          ? tr('✨ ${_who(e.key)}: întrebarea de aur, +4 câmpuri!', '✨ ${_who(e.key)}: golden question, +4 spaces!')
          : tr('✨ ${_who(e.key)}: întrebarea de aur a scăpat.', '✨ ${_who(e.key)}: the golden question slipped away.'));
      await _wait(1200, token);
    }

    // 4. Monedele de la răspunsuri, apoi pozițiile de dinaintea mutărilor
    //    (întrebarea de aur, Schimbul).
    for (final f in log.answerFx) {
      _floater(f);
    }
    await _applySnapshot(log.prelude, token);
    if (log.answerFx.isNotEmpty) await _wait(1100, token);

    // 5. Mutările, pe rând.
    for (final m in log.moves) {
      await _moveOne(m, token);
    }

    // 6. Fereastra de alegere la cufăr/magazin.
    _scene.activeId = null;
    _focusOn(null);
    final game = _game;
    final offers = game?.pendingOffers ?? const <String, UnknownOffer>{};
    if (offers.isNotEmpty) {
      final waitingFor = offers.keys.where((id) => _playerById.containsKey(id)).toList();
      var left = _choiceWindowMs;
      while (left > 0) {
        final chosen = _info?.roundChoices ?? const {};
        final missing = waitingFor.where((id) => !chosen.containsKey(id)).toList();
        if (missing.isEmpty) break;
        _set(token, () => _log = missing.contains(_me) && missing.length == 1
            ? tr('Alege-ți premiul — ${(left / 1000).ceil()} s', 'Pick your prize — ${(left / 1000).ceil()}s')
            : tr('${missing.map(_who).join(', ')} ${missing.length == 1 ? 'alege' : 'aleg'}… ${(left / 1000).ceil()} s',
                '${missing.map(_who).join(', ')} choosing… ${(left / 1000).ceil()}s'));
        await _wait(250, token);
        left -= 250;
      }
    }
    _set(token, () {
      _myOffer = null;
      if (_panel != _Panel.question) _panel = _Panel.log;
      _log = '';
    });
    await _wait(400, token);
  }

  Future<void> _moveOne(UnknownMoveLog m, int token) async {
    final id = m.roll.playerId;
    final pawn = _scene.pawns[id];
    if (pawn == null) return;
    _scene.activeId = id;
    _focusOn(id);
    final landing = m.move.landing;

    if (m.roll.skipped) {
      _set(token, () => _log = '${_who(id)}: ${landing.noteText ?? ''}');
      await _wait(_noteMs, token);
      await _applySnapshot(m.after, token);
      return;
    }

    _set(token, () => _log = id == _me ? tr('Arunci zarurile…', 'You roll…') : tr('${_nameOf(id)} aruncă zarurile…', '${_nameOf(id)} rolls…'));
    await _rollDice(id, m.roll, token);

    for (final hop in m.move.hops) {
      switch (hop.kind) {
        case UnknownHopKind.walk:
          await _hopTo(pawn, hop.tile);
          Sfx.tileSelect();
        case UnknownHopKind.ladder:
          _hideDice(token);
          await _showNote(id, landing.noteText, token);
          await _hopTo(pawn, hop.tile, seconds: 1.2, arc: 18);
          Sfx.rewardPop();
        case UnknownHopKind.snake:
          final head = pawn.tile;
          _hideDice(token);
          await _showNote(id, landing.noteText, token);
          if (unknownSnakes[head] == hop.tile) {
            await _hopTo(pawn, hop.tile, seconds: 1.5, arc: 0, path: (t) => unknownSnakePoint(head, t));
          } else {
            // Umbrela: șarpele te lasă la jumătatea drumului.
            await _hopTo(pawn, hop.tile, seconds: 1.0, arc: 40);
          }
          TankSfx.hit();
        case UnknownHopKind.jump:
          _hideDice(token);
          await _showNote(id, landing.noteText, token);
          await _hopTo(pawn, hop.tile, seconds: 0.7, arc: 90);
      }
      _alive(token);
      pawn.tile = hop.tile;
      for (final f in hop.fx) {
        _floater(f);
      }
      if (hop.fx.isNotEmpty) await _wait(500, token);
    }
    pawn.moving = false;
    _hideDice(token);
    final hadMovementNote = m.move.hops.any((h) => h.kind != UnknownHopKind.walk);
    if (!hadMovementNote && landing.noteText != null) await _showNote(id, landing.noteText, token);

    final finishedNow = (m.after[id]?[0] ?? 0) >= unknownFinish && (_shown[id]?[0] ?? 0) < unknownFinish;
    if (finishedNow) {
      Sfx.rewardPop();
      _floaterText(id, '🏁', AppColors.coin, big: true);
      await _showBanner(id == _me ? tr('🏁 Ai ajuns!', '🏁 You made it!') : tr('🏁 ${_nameOf(id)} a ajuns!', '🏁 ${_nameOf(id)} made it!'),
          token, ms: 2200);
    }

    await _land(id, landing, token);
    await _applySnapshot(m.after, token);
    await _wait(_betweenPlayersMs, token);
  }

  Future<void> _land(String id, UnknownLanding landing, int token) async {
    for (final f in landing.fx) {
      _floater(f);
    }
    final event = landing.event;
    if (event != null && landing.kind != UnknownLandingKind.goldenQuestion) {
      _set(token, () => _log = '${_who(id)} — ${unknownEventTitle(event)}\n${unknownEventDesc(event)}');
      await _showBanner('❓ ${unknownEventTitle(event)}', token, ms: 1800);
      await _wait(600, token);
    } else if (landing.fx.isNotEmpty) {
      await _wait(900, token);
    }

    switch (landing.kind) {
      case UnknownLandingKind.none:
        break;
      case UnknownLandingKind.chest:
      case UnknownLandingKind.shop:
        final chest = landing.kind == UnknownLandingKind.chest;
        if (id == _me) {
          final offer = _game?.pendingOffers[_me];
          if (offer != null) {
            Sfx.rewardPop();
            _set(token, () {
              _myOffer = offer;
              _myOfferRound = _info?.roundIndex ?? 0;
              _myOfferSent = false;
              _panel = offer.chest ? _Panel.chest : _Panel.shop;
            });
          }
        } else {
          _set(token, () => _log = chest
              ? tr('🎁 ${_nameOf(id)} a găsit un cufăr și alege un artefact…', '🎁 ${_nameOf(id)} found a chest and is picking a relic…')
              : tr('🛒 ${_nameOf(id)} a intrat în magazin…', '🛒 ${_nameOf(id)} walked into the shop…'));
          await _wait(1400, token);
        }
      case UnknownLandingKind.duel:
        final opp = landing.opponentId ?? '';
        await _showBanner('⚔️ ${_who(id)} vs ${_who(opp)}', token, ms: 1500);
        _set(token, () => _log = tr('⚔️ Duelul se decide la următoarea întrebare: cine răspunde corect și mai repede ia 6 🪙.',
            '⚔️ The duel is settled by the next question: right and faster takes 6 🪙.'));
        await _wait(1800, token);
      case UnknownLandingKind.goldenQuestion:
        await _showBanner('✨ ${unknownEventTitle(UnknownEvent.goldenQuestion)}', token, ms: 1500);
        _set(token, () => _log = tr('✨ ${_who(id)}: la următoarea întrebare, corect = +4 câmpuri.',
            '✨ ${_who(id)}: on the next question, right = +4 spaces.'));
        await _wait(1600, token);
    }
  }

  /// Aduce pionii și cifrele la [snap] (după Vârtej, Cutremur, Schimb…).
  Future<void> _applySnapshot(Map<String, List<int>> snap, int token) async {
    final moves = <Future<void>>[];
    for (final e in snap.entries) {
      final pawn = _scene.pawns[e.key];
      _shown[e.key] = e.value;
      if (pawn == null) continue;
      final pos = e.value[0];
      if (pawn.tile != pos) {
        moves.add(_hopTo(pawn, pos, seconds: 0.8, arc: 120).then((_) {
          pawn.tile = pos;
          pawn.moving = false;
        }));
      }
    }
    _set(token, () {});
    if (moves.isNotEmpty) await Future.wait(moves);
    _alive(token);
  }

  Future<void> _showNote(String id, String? note, int token) async {
    if (note == null) return;
    _set(token, () => _log = '${_who(id)}: $note');
    _floaterText(id, note.split(' ').first, Colors.white, big: true);
    await _showBanner(note, token, ms: _noteMs);
  }

  Future<void> _rollDice(String id, UnknownRoll roll, int token) async {
    _set(token, () {
      _diceVisible = true;
      _diceRolling = true;
      _diceOwner = _who(id);
      _diceLabels = [];
      _dice = [for (final _ in roll.dice) 1 + _rnd.nextInt(6)];
    });
    for (var i = 0; i < 9; i++) {
      await _wait(90, token);
      _set(token, () => _dice = [for (final _ in roll.dice) 1 + _rnd.nextInt(6)]);
    }
    Sfx.next();
    _set(token, () {
      _diceRolling = false;
      _dice = roll.dice;
      _diceLabels = roll.labels;
    });
    await _wait(roll.labels.isEmpty ? _diceHoldMs : _diceHoldMs + 500, token);
  }

  void _hideDice(int token) {
    if (_diceVisible) _set(token, () => _diceVisible = false);
  }

  void _floaterText(String playerId, String text, Color color, {bool big = false}) {
    final pawn = _scene.pawns[playerId];
    if (pawn == null) return;
    final pos = pawn.moving ? pawn.pos : _scene.restingPos(pawn);
    _scene.floaters.add(UnknownFloater(pos: pos, text: text, color: color, born: _scene.time, big: big));
  }

  void _floater(UnknownFx f) {
    if (f.coins != 0) {
      _floaterText(
        f.playerId,
        '${f.coins > 0 ? '+' : '−'}${f.coins.abs()} 🪙',
        f.coins > 0 ? const Color(0xFFFFE066) : const Color(0xFFFF6B6B),
      );
      if (f.coins > 0) Sfx.coinHit();
    } else if (f.label.isNotEmpty) {
      _floaterText(f.playerId, f.label, Colors.white);
    }
  }

  // ─── Acțiunile mele ──────────────────────────────────────────────────

  void _pick(String choice) {
    final info = _info;
    if (info == null || info.roundPhase != RoundPhase.answering || _myPick != null || !_racing(_me)) return;
    if (info.roundAnswers.containsKey(_me)) return;
    Sfx.tileSelect();
    setState(() => _myPick = choice);
    _mp.submitUnknownAnswer(
      matchId: widget.matchId,
      roundIndex: info.roundIndex,
      answer: choice,
      ms: DateTime.now().difference(_questionShownAt).inMilliseconds,
    );
  }

  void _toggleArm(UnknownItem item) {
    final info = _info;
    if (info == null) return;
    if (info.roundPhase != RoundPhase.answering) {
      _toast(tr('Obiectele se pregătesc cât stă întrebarea pe ecran.', 'Items are readied while the question is up.'));
      return;
    }
    final armedNow = info.roundArms[_me] == item.name;
    Sfx.tileSelect();
    _mp.submitUnknownArm(matchId: widget.matchId, roundIndex: info.roundIndex, item: armedNow ? null : item);
    if (!armedNow) {
      _toast(tr('${unknownItemName(item)}: ${unknownItemDesc(item)} — se folosește la mutarea de acum.',
          '${unknownItemName(item)}: ${unknownItemDesc(item)} — used on this move.'));
    }
  }

  void _sendChoice(UnknownChoice choice) {
    if (_myOfferSent) return;
    Sfx.tileSelect();
    _myOfferSent = true;
    _mp.submitUnknownChoice(matchId: widget.matchId, offerRound: _myOfferRound, choice: choice);
    setState(() {
      _panel = _Panel.log;
      _log = choice.take == null ? '' : tr('Gata — se aplică la runda următoare.', 'Done — it applies next round.');
    });
  }

  void _pickRelic(UnknownRelic? relic) {
    if (relic == null) {
      _sendChoice(UnknownChoice.none);
      return;
    }
    final mine = _game?.players.where((p) => p.id == _me).firstOrNull;
    if (mine != null && mine.relics.length >= unknownMaxRelics) {
      setState(() {
        _pendingRelic = relic;
        _panel = _Panel.chestDrop;
      });
      return;
    }
    _sendChoice(UnknownChoice(take: relic.name));
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
  }

  Future<void> _leave() async {
    if (_left) return;
    GamePause.instance.pause();
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(tr('Ieși din meci?', 'Leave the match?'), style: const TextStyle(color: Colors.white)),
        content: Text(tr('Meciul se pierde, inclusiv miza.', 'You lose the match, stake included.'),
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Rămân', 'Stay'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Ies', 'Leave'))),
        ],
      ),
    );
    GamePause.instance.resume();
    if (leave != true || _left) return;
    _left = true;
    try {
      await _mp.leaveMatch(widget.matchId);
    } catch (e) {
      debugPrint('MultiplayerUnknownScreen._leave: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  /// Legenda câmpurilor. Animațiile stau pe pauză cât o citești.
  Future<void> _showLegend() async {
    GamePause.instance.pause();
    Widget row(Widget lead, String title, String body) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(width: 44, child: Center(child: lead)),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$title  ', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                    TextSpan(text: body, style: const TextStyle(color: Colors.white70)),
                  ]),
                  style: const TextStyle(fontSize: 13.5, height: 1.3),
                ),
              ),
            ],
          ),
        );
    Widget dot(UnknownTile t) => Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: unknownTileColor(t),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Icon(unknownTileIcon(t) ?? Icons.circle, size: 18, color: Colors.white),
        );
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(tr('Ce face fiecare câmp', 'What each space does'),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 10),
              row(const Text('🪜', style: TextStyle(fontSize: 24)), tr('Scara', 'Ladder'),
                  tr('Ai picat la baza ei? Urci până sus.', 'Land at its foot and you climb to the top.')),
              row(const Text('🐍', style: TextStyle(fontSize: 24)), tr('Șarpele', 'Snake'),
                  tr('Ai picat pe capul lui? Aluneci până la coadă.', 'Land on its head and you slide down to its tail.')),
              row(dot(UnknownTile.back3), tr('Înapoi 3', 'Back 3'), tr('Dai înapoi 3 câmpuri.', 'You go back 3 spaces.')),
              row(dot(UnknownTile.trap), tr('Capcana', 'Trap'), tr('Stai o tură (tot răspunzi la întrebare).', 'Skip a move (you still answer).')),
              row(dot(UnknownTile.clover), tr('Trifoiul', 'Clover'),
                  tr('Imunitate: următorul șarpe, „înapoi 3" sau capcană nu te prinde.', 'Immunity: the next snake, “back 3” or trap misses you.')),
              row(dot(UnknownTile.chest), tr('Cufărul', 'Chest'),
                  tr('Alegi 1 din 3 artefacte (maxim 3), cât se termină runda.', 'Pick 1 of 3 relics (max 3) before the round ends.')),
              row(dot(UnknownTile.shop), tr('Magazinul', 'Shop'), tr('Cumperi obiecte cu monede (maxim 2).', 'Buy items with coins (max 2).')),
              row(dot(UnknownTile.duel), tr('Duelul', 'Duel'),
                  tr('Cu cel mai bogat; se decide la următoarea întrebare — corect și mai repede ia 6 🪙.',
                      'Against the richest; settled by the next question — right and faster takes 6 🪙.')),
              row(dot(UnknownTile.event), tr('Evenimentul', 'Event'), tr('Orice se poate întâmpla.', 'Anything can happen.')),
              row(dot(UnknownTile.coins), '+3 🪙', tr('Monede.', 'Coins.')),
              row(dot(UnknownTile.tax), '−3 🪙', tr('Taxă.', 'A tax.')),
              const SizedBox(height: 8),
              Text(
                tr('Corect = 2 zaruri, greșit = 1. Cel mai rapid răspuns corect: +3 🪙 și muți primul. Ultimul din cursă: +2 pași. Obiectele le pregătești cât stă întrebarea.',
                    'Right = 2 dice, wrong = 1. Fastest right answer: +3 🪙 and you move first. Last in the race: +2 steps. Ready items while the question is up.'),
                style: const TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
    GamePause.instance.resume();
  }

  // ─── Interfața ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        floatingActionButton: widget.bot == null ? MatchOverlay(matchId: widget.matchId) : null,
        floatingActionButtonLocation: matchOverlayLocation,
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.spaceGradient),
          child: SafeArea(
            child: info == null
                ? const Center(child: CircularProgressIndicator(color: AppColors.coin))
                : Column(
                    children: [
                      _topBar(info),
                      _playerStrip(info),
                      Expanded(child: _boardArea()),
                      _myBar(info),
                      _bottomPanel(info),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(MatchInfo info) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 8, 0),
      child: Row(
        children: [
          IconButton(onPressed: _leave, icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
          const Text('Unknown', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          const Spacer(),
          _pill(tr('Runda ${info.roundIndex + 1}', 'Round ${info.roundIndex + 1}'), Colors.white24),
          const SizedBox(width: 6),
          _pill('🏁 $unknownFinish', const Color(0x55FFD700)),
          IconButton(
            onPressed: _showLegend,
            icon: const Icon(Icons.help_outline_rounded, color: Colors.white70),
            tooltip: tr('Ce face fiecare câmp', 'What each space does'),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)),
      );

  List<String> get _tableIds => _game?.players.map((p) => p.id).toList() ?? (_players.map((p) => p.id).toList()..sort());

  Widget _playerStrip(MatchInfo info) {
    final ids = _tableIds;
    int key(String id) {
      final s = _shown[id] ?? const [0, 0];
      final fo = _game?.players.where((p) => p.id == id).firstOrNull?.finishOrder;
      if (fo != null && s[0] >= unknownFinish) return 10000000 - fo * 100000;
      return s[0] * 1000 + min(s[1], 999);
    }

    final ranked = List.of(ids)..sort((a, b) => key(b).compareTo(key(a)));
    final compact = ids.length > 4;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          for (final id in ids)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _playerChip(info, id, ranked.indexOf(id) + 1, compact),
              ),
            ),
        ],
      ),
    );
  }

  Widget _playerChip(MatchInfo info, String id, int place, bool compact) {
    final g = _game?.players.where((p) => p.id == id).firstOrNull;
    final color = unknownPlayerColors[(g?.colorIndex ?? _tableIds.indexOf(id)) % unknownPlayerColors.length];
    final active = _scene.activeId == id;
    final gone = !_playerById.containsKey(id);
    final answering = info.roundPhase == RoundPhase.answering && !_regieRunning;
    final answered = answering && info.roundAnswers.containsKey(id);
    final revealing = _panel == _Panel.reveal;
    final answer = info.roundAnswers[id];
    final correct = answer != null && answer == _questionFor(info.roundIndex).answer;
    final shown = _shown[id] ?? const [0, unknownStartCoins];
    final status = [
      if (g?.shielded == true) '🛡️',
      if (g?.skipNext == true) '⏸️',
      if (!compact && g != null) ...g.relics.map(unknownRelicEmoji),
    ].join();
    return Opacity(
      opacity: gone ? 0.4 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: active ? color.withAlpha(70) : Colors.white.withAlpha(14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? color : Colors.white12, width: active ? 2 : 1),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Text('$place', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    id == _me ? tr('Tu', 'You') : _nameOf(id).replaceAll(' 🤖', ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
                if (answered) const Icon(Icons.check_circle, size: 13, color: Colors.white70),
                if (revealing && _racing(id))
                  Icon(correct ? Icons.check_circle : Icons.cancel, size: 14, color: correct ? AppColors.play : AppColors.danger),
              ],
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${shown[0] >= unknownFinish ? '🏁' : '📍${shown[0]}'}  🪙${shown[1]}',
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900),
              ),
            ),
            if (status.isNotEmpty) Text(status, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _boardArea() {
    return Stack(
      children: [
        Positioned.fill(child: UnknownBoard(scene: _scene, repaint: _repaint)),
        // Sus, nu în centru: camera ține pionul care se mută fix în mijloc.
        if (_diceVisible) Align(alignment: const Alignment(0, -0.85), child: _diceView()),
        if (_banner != null)
          Align(
            alignment: const Alignment(0, 0.55),
            child: TweenAnimationBuilder<double>(
              key: ValueKey(_bannerKey),
              tween: Tween(begin: 0.4, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xE6111833),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.coin, width: 2),
                  boxShadow: const [BoxShadow(color: Color(0x88FFD700), blurRadius: 24)],
                ),
                child: Text(_banner!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _diceView() {
    final bonus = _diceLabels.fold(0, (a, l) => a + (int.tryParse(l.split('+').last.trim()) ?? 0));
    final total = _dice.fold(0, (a, b) => a + b) + bonus;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1229),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_diceOwner, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, d) in _dice.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Transform.rotate(
                    angle: _diceRolling ? (_rnd.nextDouble() - 0.5) * 0.9 : (i.isEven ? -0.06 : 0.06),
                    child: _Die(value: d),
                  ),
                ),
            ],
          ),
          if (!_diceRolling) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final l in _diceLabels)
                  Text(l, style: const TextStyle(color: AppColors.coin, fontSize: 13, fontWeight: FontWeight.w900)),
                Text(tr('= $total ${total == 1 ? 'pas' : 'pași'}', '= $total ${total == 1 ? 'step' : 'steps'}'),
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Artefactele și obiectele mele. Obiectele se pregătesc cât stă
  /// întrebarea pe ecran; apăsat din nou = le pui înapoi.
  Widget _myBar(MatchInfo info) {
    final me = _game?.players.where((p) => p.id == _me).firstOrNull;
    if (me == null) return const SizedBox(height: 42);
    final armedName = info.roundPhase == RoundPhase.answering ? info.roundArms[_me] : null;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          for (final r in me.relics)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () => _toast('${unknownRelicEmoji(r)} ${unknownRelicName(r)}: ${unknownRelicDesc(r)}'),
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x66FFB020)),
                  ),
                  child: Text(unknownRelicEmoji(r), style: const TextStyle(fontSize: 17)),
                ),
              ),
            ),
          if (me.relics.isEmpty)
            Text(tr('Cuferele dau artefacte', 'Chests give relics'), style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
          const Spacer(),
          for (final i in me.items) _itemChip(i, armed: armedName == i.name),
        ],
      ),
    );
  }

  Widget _itemChip(UnknownItem item, {required bool armed}) {
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: GestureDetector(
        onTap: () => _toggleArm(item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: armed ? AppColors.coin : Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: armed ? AppColors.coin : Colors.white30),
            boxShadow: armed ? const [BoxShadow(color: Color(0x99FFD700), blurRadius: 12)] : null,
          ),
          child: Text(
            '${unknownItemEmoji(item)} ${armed ? tr('gata', 'ready') : tr('folosește', 'use')}',
            style: TextStyle(
              color: armed ? const Color(0xFF0B1229) : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomPanel(MatchInfo info) {
    final offer = _myOffer;
    final Widget child = switch (_panel) {
      _Panel.question || _Panel.reveal => _questionPanel(info),
      _Panel.chest when offer != null => _choicePanel(
          title: tr('🎁 Cufăr! Alege un artefact', '🎁 Chest! Pick a relic'),
          cards: [
            for (final r in offer.relics)
              _ChoiceCard(emoji: unknownRelicEmoji(r), title: unknownRelicName(r), body: unknownRelicDesc(r), onTap: () => _pickRelic(r)),
          ],
          skipLabel: tr('Nu iau nimic', 'Take nothing'),
          onSkip: () => _pickRelic(null),
        ),
      _Panel.chestDrop when _pendingRelic != null => _choicePanel(
          title: tr('Ai deja 3. Pe care îl lași pentru ${unknownRelicEmoji(_pendingRelic!)}?',
              'You already have 3. Which one goes for ${unknownRelicEmoji(_pendingRelic!)}?'),
          cards: [
            for (final r in _game?.players.where((p) => p.id == _me).firstOrNull?.relics ?? const <UnknownRelic>[])
              _ChoiceCard(
                emoji: unknownRelicEmoji(r),
                title: unknownRelicName(r),
                body: unknownRelicDesc(r),
                onTap: () => _sendChoice(UnknownChoice(take: _pendingRelic!.name, drop: r.name)),
              ),
          ],
          skipLabel: tr('Le păstrez pe ale mele', 'Keep mine'),
          onSkip: () => _sendChoice(UnknownChoice.none),
        ),
      _Panel.shop when offer != null => _shopPanel(offer),
      _ => _logPanel(),
    };
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: const BoxDecoration(
          color: Color(0xF0101733),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: child,
      ),
    );
  }

  Widget _shopPanel(UnknownOffer offer) {
    final me = _game?.players.where((p) => p.id == _me).firstOrNull;
    final coins = me?.coins ?? 0;
    final full = (me?.items.length ?? 0) >= unknownMaxItems;
    return _choicePanel(
      title: tr('🛒 Magazin — ai $coins 🪙', '🛒 Shop — you have $coins 🪙'),
      cards: [
        for (final i in offer.items)
          _ChoiceCard(
            emoji: unknownItemEmoji(i),
            title: '${unknownItemName(i)} · ${unknownItemPrice(i)} 🪙',
            body: unknownItemDesc(i),
            onTap: coins >= unknownItemPrice(i) && !full ? () => _sendChoice(UnknownChoice(take: i.name)) : null,
          ),
      ],
      skipLabel: tr('Plec', 'Leave'),
      onSkip: () => _sendChoice(UnknownChoice.none),
    );
  }

  Widget _logPanel() {
    return SizedBox(
      height: 72,
      child: Center(
        child: Text(
          _log.isEmpty ? ' ' : _log,
          textAlign: TextAlign.center,
          maxLines: 3,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.3),
        ),
      ),
    );
  }

  /// Antetul întrebării: dacă am un duel sau o întrebare de aur în joc, o
  /// spune — altfel e doar întrebarea obișnuită.
  String _questionHeader() {
    final g = _game;
    if (g != null) {
      for (final (a, d) in g.pendingDuels) {
        if (a == _me || d == _me) {
          final other = a == _me ? d : a;
          return tr('⚔️ Duel cu ${_nameOf(other)}: corect și mai repede ia 6 🪙', '⚔️ Duel with ${_nameOf(other)}: right and faster takes 6 🪙');
        }
      }
      if (g.pendingGolden.contains(_me)) return tr('✨ Întrebarea de aur: corect = +4 câmpuri', '✨ Golden question: right = +4 spaces');
    }
    return tr('Toată masa răspunde', 'Everyone answers');
  }

  Widget _questionPanel(MatchInfo info) {
    final round = _panel == _Panel.reveal ? _playedLogRound : info.roundIndex;
    final q = _questionFor(round);
    final revealed = _panel == _Panel.reveal;
    final seconds = _secondsLeft(info);
    final mine = info.roundAnswers[_me] ?? _myPick;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(_questionHeader(), style: const TextStyle(color: Colors.white60, fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
            if (!revealed)
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: seconds <= 3 ? AppColors.danger : AppColors.play, width: 3),
                ),
                child: Text('$seconds', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(q.question,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800, height: 1.25)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 3.3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [for (final c in _choicesFor(round)) _answerButton(c, q, revealed, mine)],
        ),
        if (!_racing(_me))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('Ai ajuns — te uiți doar.', 'You made it — just watching.'),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _answerButton(String choice, CultureQuestion q, bool revealed, String? mine) {
    final picked = mine == choice;
    Color bg = Colors.white.withAlpha(16);
    Color border = Colors.white24;
    if (revealed && choice == q.answer) {
      bg = AppColors.play.withAlpha(90);
      border = AppColors.play;
    } else if (revealed && picked) {
      bg = AppColors.danger.withAlpha(90);
      border = AppColors.danger;
    } else if (picked) {
      bg = AppColors.blue.withAlpha(90);
      border = AppColors.blue;
    }
    return GestureDetector(
      onTap: mine == null && !revealed ? () => _pick(choice) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 2)),
        child: Text(choice,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _choicePanel({
    required String title,
    required List<Widget> cards,
    required String skipLabel,
    required VoidCallback onSkip,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        // IntrinsicHeight: cărțile au aceeași înălțime (a celei mai lungi), dar
        // finită — un `stretch` direct într-o coloană fără limită de înălțime
        // cere înălțime infinită și golea tot ecranul în release.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in cards) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: c)),
            ],
          ),
        ),
        TextButton(
          onPressed: onSkip,
          child: Text(skipLabel, style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.emoji, required this.title, required this.body, required this.onTap});

  final String emoji;
  final String title;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap != null ? 1 : 0.4,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(16),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x88FFB020), width: 1.5),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(height: 4),
              Text(title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(body, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.25)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un zar cu puncte, nu cu cifră — se citește dintr-o privire, ca unul adevărat.
class _Die extends StatelessWidget {
  const _Die({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: CustomPaint(painter: _PipPainter(value)),
    );
  }
}

class _PipPainter extends CustomPainter {
  _PipPainter(this.value);

  final int value;

  static const Map<int, List<Offset>> _pips = {
    1: [Offset(0.5, 0.5)],
    2: [Offset(0.27, 0.27), Offset(0.73, 0.73)],
    3: [Offset(0.27, 0.27), Offset(0.5, 0.5), Offset(0.73, 0.73)],
    4: [Offset(0.27, 0.27), Offset(0.73, 0.27), Offset(0.27, 0.73), Offset(0.73, 0.73)],
    5: [Offset(0.27, 0.27), Offset(0.73, 0.27), Offset(0.5, 0.5), Offset(0.27, 0.73), Offset(0.73, 0.73)],
    6: [
      Offset(0.27, 0.25), Offset(0.73, 0.25), Offset(0.27, 0.5),
      Offset(0.73, 0.5), Offset(0.27, 0.75), Offset(0.73, 0.75),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = value == 1 ? AppColors.danger : const Color(0xFF1B2140);
    for (final p in _pips[value.clamp(1, 6)]!) {
      canvas.drawCircle(Offset(p.dx * size.width, p.dy * size.height), size.width * 0.085, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PipPainter old) => old.value != value;
}
