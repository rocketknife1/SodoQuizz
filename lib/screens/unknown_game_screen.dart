import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/audio.dart';
import '../core/bot_brain.dart';
import '../core/game_pause.dart';
import '../core/lang.dart';
import '../core/stable_hash.dart';
import '../core/theme.dart';
import '../core/unknown_game.dart';
import '../data/auth_service.dart';
import '../data/culture_questions.dart';
import '../data/storage_service.dart';
import '../widgets/space_background.dart';
import '../widgets/unknown_board.dart';

/// Ecranul modului „Unknown" (regulile: core/unknown_game.dart). Joci cu
/// 1–5 boți, fără internet. Motorul e pur; aici stă doar regia: ordinea
/// scenelor, animațiile și deciziile jucătorului.
///
/// Ritmul e dinadins domol: fiecare aruncare, scară sau șarpe stă pe ecran
/// destul cât să vezi ce s-a întâmplat și cu cine.
class UnknownGameScreen extends StatefulWidget {
  const UnknownGameScreen({super.key, required this.botCount, required this.difficulty});

  final int botCount;
  final int difficulty;

  @override
  State<UnknownGameScreen> createState() => _UnknownGameScreenState();
}

enum _Phase { intro, question, reveal, moving, chest, chestDrop, shop, results }

/// Aruncată când ecranul se închide în mijlocul regiei — oprește bucla fără
/// să mai atingă `setState`.
class _Stop implements Exception {}

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

class _UnknownGameScreenState extends State<UnknownGameScreen> with SingleTickerProviderStateMixin {
  static const _me = 'me';
  static const _botRewardCounter = 'bot_matches';

  // Ritmul (milisecunde). Toate într-un loc, ca să se poată regla ușor.
  static const _hopSeconds = 0.34;
  static const _revealMs = 2200;
  static const _bannerMs = 1500;
  static const _diceHoldMs = 1300;
  static const _noteMs = 1500;
  static const _botDecisionMs = 1900;
  static const _betweenPlayersMs = 800;

  final _rnd = Random();
  late final UnknownGame _g;
  late final List<CultureQuestion> _pool;
  int _qIndex = 0;

  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  final _scene = UnknownScene();
  final List<_HopAnim> _hops = [];
  final List<Timer> _timers = [];
  Duration _lastTick = Duration.zero;
  bool _disposed = false;
  bool _ready = false;

  _Phase _phase = _Phase.intro;
  String _log = '';

  // Întrebarea curentă (runda, duel sau întrebarea de aur).
  CultureQuestion? _question;
  String _questionHeader = '';
  String? _myPick;
  final Set<String> _answered = {};
  Map<String, UnknownAnswer> _revealAnswers = {};

  /// `true` la întrebarea pentru toată masa; la duel și la întrebarea de aur
  /// răspunde doar jucătorul, deci ceilalți nu primesc ✓/✗.
  bool _tableQuestion = false;
  int _secondsLeft = 0;
  void Function(String choice)? _onPick;

  // Zarurile.
  bool _diceVisible = false;
  bool _diceRolling = false;
  List<int> _dice = [];
  List<String> _diceLabels = [];
  String _diceOwner = '';

  // Bannerul mare peste tablă („Runda 4", „🪜 Scara!").
  String? _banner;
  int _bannerKey = 0;

  // Deciziile jucătorului.
  Completer<Object?>? _choice;
  List<UnknownRelic> _relicOffers = [];
  List<UnknownItem> _itemOffers = [];
  UnknownRelic? _pendingRelic;

  // Finalul.
  List<UnknownPlayer> _final = [];
  int _coinsEarned = 0;
  int _xpEarned = 0;
  bool _capReached = false;

  UnknownPlayer get _mePlayer => _g.player(_me);

  @override
  void initState() {
    super.initState();
    final seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    _pool = List.of(cultureQuestions);
    stableShuffle(_pool, seed);
    final names = botNames(widget.botCount, _rnd);
    _g = UnknownGame(
      seed: seed,
      players: [
        UnknownPlayer(id: _me, name: tr('Tu', 'You'), isBot: false, colorIndex: 0),
        for (var i = 0; i < widget.botCount; i++)
          UnknownPlayer(id: 'bot$i', name: names[i], isBot: true, colorIndex: i + 1),
      ],
    );
    for (final p in _g.players) {
      _scene.pawns[p.id] = UnknownPawn(id: p.id, colorIndex: p.colorIndex, initial: _initial(p.name), tile: p.pos);
    }
    _scene.camTarget = unknownTileCenters[0];
    _scene.cam = unknownTileCenters[0];
    _ticker = createTicker(_tick)..start();
    _loadName();
  }

  Future<void> _loadName() async {
    try {
      final id = await AuthService.instance.multiplayerIdentity();
      if (!mounted) return;
      _scene.pawns[_me] = UnknownPawn(id: _me, colorIndex: 0, initial: _initial(id.name), tile: 0);
    } catch (e) {
      debugPrint('UnknownGameScreen._loadName: $e');
    }
    if (mounted) setState(() => _ready = true);
  }

  static String _initial(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return String.fromCharCodes(t.runes.take(1)).toUpperCase();
  }

  String _who(UnknownPlayer p) => p.isBot ? p.name : tr('Tu', 'You');

  @override
  void dispose() {
    _disposed = true;
    for (final t in _timers) {
      t.cancel();
    }
    GamePause.instance.resume();
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
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
        h.done.complete();
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
    if (id == null) {
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

  // ─── Regia ───────────────────────────────────────────────────────────

  void _alive() {
    if (_disposed || !mounted) throw _Stop();
  }

  Future<void> _wait(int ms) async {
    var left = ms;
    while (left > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      _alive();
      if (!GamePause.instance.isPaused) left -= 50;
    }
  }

  void _set(VoidCallback fn) {
    _alive();
    setState(fn);
  }

  Future<void> _showBanner(String text, {int ms = _bannerMs}) async {
    _set(() {
      _banner = text;
      _bannerKey++;
    });
    await _wait(ms);
    _set(() => _banner = null);
  }

  Future<void> _start() async {
    try {
      await _run();
    } on _Stop {
      return;
    }
  }

  Future<void> _run() async {
    _set(() => _phase = _Phase.moving);
    _focusOn(null);
    await _showBanner(tr('Pornim! Primul la $unknownFinish câștigă', 'Go! First to $unknownFinish wins'), ms: 1800);
    while (!_g.isOver) {
      await _playRound();
      _g.endRound();
      for (final p in _g.players.where((p) => p.isBot)) {
        unknownBotArm(_g, p);
      }
    }
    await _finish();
  }

  CultureQuestion _nextQuestion() => _pool[_qIndex++ % _pool.length];

  Future<void> _playRound() async {
    _focusOn(null);
    _scene.activeId = null;
    await _showBanner(tr('Runda ${_g.round + 1}', 'Round ${_g.round + 1}'), ms: 1300);

    final q = _nextQuestion();
    final answers = await _askTable(q);
    await _reveal(answers);

    final res = _g.resolveAnswers(answers);
    for (final f in res.fx) {
      _floater(f);
    }
    // „Schimbul" mută pionii încă de la zaruri.
    await _syncPawns();
    if (res.fx.isNotEmpty) await _wait(1200);

    for (final id in _g.moveOrder(answers)) {
      await _moveOne(id, res.rolls[id]!);
    }
  }

  // ─── Întrebarea pentru toată masa ────────────────────────────────────

  Future<Map<String, UnknownAnswer>> _askTable(CultureQuestion q) async {
    final answers = <String, UnknownAnswer>{};
    final racing = [for (final p in _g.players) if (!p.finished) p];
    final done = Completer<void>();
    final started = DateTime.now();
    void check() {
      if (racing.every((p) => answers.containsKey(p.id)) && !done.isCompleted) done.complete();
    }

    for (final p in racing.where((p) => p.isBot)) {
      final delay = botThinkTime(difficulty: widget.difficulty, roundSeconds: unknownQuestionSeconds, rnd: _rnd);
      final pick = botPickAnswer(correct: q.answer, choices: q.choices, difficulty: widget.difficulty, rnd: _rnd);
      _timers.add(Timer(delay, () {
        if (_disposed || done.isCompleted) return;
        answers[p.id] = UnknownAnswer(correct: pick == q.answer, ms: delay.inMilliseconds);
        setState(() => _answered.add(p.id));
        check();
      }));
    }

    _set(() {
      _phase = _Phase.question;
      _question = q;
      _questionHeader = tr('Toată masa răspunde', 'Everyone answers');
      _tableQuestion = true;
      _myPick = null;
      _answered.clear();
      _revealAnswers = {};
      _secondsLeft = unknownQuestionSeconds;
      _onPick = (choice) {
        if (answers.containsKey(_me) || done.isCompleted || _mePlayer.finished) return;
        Sfx.tileSelect();
        answers[_me] = UnknownAnswer(correct: choice == q.answer, ms: DateTime.now().difference(started).inMilliseconds);
        setState(() {
          _myPick = choice;
          _answered.add(_me);
        });
        check();
      };
    });

    await _countdown(done, unknownQuestionSeconds);
    _onPick = null;
    return answers;
  }

  /// Numără secundele până se completează [done] sau expiră timpul.
  Future<void> _countdown(Completer<void> done, int seconds) async {
    var left = seconds * 1000;
    while (!done.isCompleted && left > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      _alive();
      if (GamePause.instance.isPaused) continue;
      left -= 100;
      final s = (left / 1000).ceil();
      if (s != _secondsLeft) setState(() => _secondsLeft = s);
    }
    if (!done.isCompleted) done.complete();
  }

  Future<void> _reveal(Map<String, UnknownAnswer> answers) async {
    _set(() {
      _phase = _Phase.reveal;
      _revealAnswers = answers;
    });
    if (answers[_me]?.correct == true) Sfx.coinHit();
    await _wait(_revealMs);
    _set(() => _phase = _Phase.moving);
  }

  // ─── Întrebarea unui singur jucător (duel, întrebarea de aur) ────────

  Future<UnknownAnswer> _askMe(CultureQuestion q, String header, {int seconds = 12}) async {
    final done = Completer<void>();
    final started = DateTime.now();
    UnknownAnswer? answer;
    _set(() {
      _phase = _Phase.question;
      _question = q;
      _questionHeader = header;
      _tableQuestion = false;
      _myPick = null;
      _answered.clear();
      _revealAnswers = {};
      _secondsLeft = seconds;
      _onPick = (choice) {
        if (answer != null || done.isCompleted) return;
        Sfx.tileSelect();
        answer = UnknownAnswer(correct: choice == q.answer, ms: DateTime.now().difference(started).inMilliseconds);
        setState(() => _myPick = choice);
        done.complete();
      };
    });
    await _countdown(done, seconds);
    _onPick = null;
    final result = answer ?? UnknownAnswer(correct: false, ms: seconds * 1000);
    _set(() {
      _phase = _Phase.reveal;
      _revealAnswers = {_me: result};
    });
    await _wait(1800);
    _set(() => _phase = _Phase.moving);
    return result;
  }

  UnknownAnswer _botAnswer(CultureQuestion q) {
    final pick = botPickAnswer(correct: q.answer, choices: q.choices, difficulty: widget.difficulty, rnd: _rnd);
    final ms = botThinkTime(difficulty: widget.difficulty, roundSeconds: 12, rnd: _rnd).inMilliseconds;
    return UnknownAnswer(correct: pick == q.answer, ms: ms);
  }

  // ─── Mutarea unui jucător ────────────────────────────────────────────

  Future<void> _moveOne(String id, UnknownRoll roll) async {
    final p = _g.player(id);
    final pawn = _scene.pawns[id]!;
    _scene.activeId = id;
    _focusOn(id);

    if (roll.skipped) {
      _set(() => _log = tr('⏸️ ${_who(p)} ${p.isBot ? 'stă' : 'stai'} o tură (capcana).',
          '⏸️ ${_who(p)} ${p.isBot ? 'sits' : 'sit'} this one out (the trap).'));
      _g.move(p, roll);
      await _wait(_noteMs);
      return;
    }

    _set(() => _log = p.isBot ? tr('${p.name} aruncă zarurile…', '${p.name} rolls…') : tr('Arunci zarurile…', 'You roll…'));
    await _rollDice(p, roll);

    final start = p.pos;
    final move = _g.move(p, roll);
    var walked = 0;
    for (final hop in move.hops) {
      switch (hop.kind) {
        case UnknownHopKind.walk:
          await _hopTo(pawn, hop.tile);
          walked++;
          Sfx.tileSelect();
        case UnknownHopKind.ladder:
          _hideDice();
          await _showNote(p, move.landing.note);
          await _hopTo(pawn, hop.tile, seconds: 1.2, arc: 18);
          Sfx.rewardPop();
        case UnknownHopKind.snake:
          // Pionul stă pe capul șarpelui (ultimul pas de mers).
          final head = pawn.tile;
          _hideDice();
          await _showNote(p, move.landing.note);
          if (unknownSnakes[head] == hop.tile) {
            await _hopTo(pawn, hop.tile, seconds: 1.5, arc: 0, path: (t) => unknownSnakePoint(head, t));
          } else {
            // Umbrela: șarpele te lasă la jumătatea drumului.
            await _hopTo(pawn, hop.tile, seconds: 1.0, arc: 40);
          }
          TankSfx.hit();
        case UnknownHopKind.jump:
          _hideDice();
          await _showNote(p, move.landing.note);
          await _hopTo(pawn, hop.tile, seconds: 0.7, arc: 90);
      }
      _alive();
      pawn.tile = hop.tile;
      for (final f in hop.fx) {
        _floater(f);
      }
      if (hop.fx.isNotEmpty) await _wait(500);
    }
    pawn.moving = false;
    _hideDice();
    final hadMovementNote = move.hops.any((h) => h.kind != UnknownHopKind.walk);
    if (!hadMovementNote && move.landing.note != null) await _showNote(p, move.landing.note);
    if (move.hops.isEmpty && walked == 0 && start == p.pos) await _wait(300);

    if (p.finished) {
      Sfx.rewardPop();
      _floaterText(p.id, '🏁', AppColors.coin, big: true);
      await _showBanner(tr('🏁 ${_who(p)} ${p.isBot ? 'a ajuns' : 'ai ajuns'}!', '🏁 ${_who(p)} made it!'), ms: 2200);
    }
    await _land(p, move.landing);
    await _syncPawns();
    await _wait(_betweenPlayersMs);
  }

  Future<void> _showNote(UnknownPlayer p, String? note) async {
    if (note == null) return;
    _set(() => _log = '${_who(p)}: $note');
    _floaterText(p.id, note.split(' ').first, Colors.white, big: true);
    await _showBanner(note, ms: _noteMs);
  }

  Future<void> _rollDice(UnknownPlayer p, UnknownRoll roll) async {
    _set(() {
      _diceVisible = true;
      _diceRolling = true;
      _diceOwner = _who(p);
      _diceLabels = [];
      _dice = [for (final _ in roll.dice) 1 + _rnd.nextInt(6)];
    });
    for (var i = 0; i < 9; i++) {
      await _wait(90);
      _set(() => _dice = [for (final _ in roll.dice) 1 + _rnd.nextInt(6)]);
    }
    Sfx.next();
    _set(() {
      _diceRolling = false;
      _dice = roll.dice;
      _diceLabels = roll.labels;
    });
    await _wait(roll.labels.isEmpty ? _diceHoldMs : _diceHoldMs + 500);
  }

  void _hideDice() {
    if (_diceVisible) _set(() => _diceVisible = false);
  }

  /// Aduce pionii la pozițiile din motor (Vârtej, Cutremur, Schimb…).
  Future<void> _syncPawns() async {
    final moves = <Future<void>>[];
    for (final p in _g.players) {
      final pawn = _scene.pawns[p.id]!;
      if (pawn.tile != p.pos) {
        moves.add(_hopTo(pawn, p.pos, seconds: 0.8, arc: 120).then((_) {
          pawn.tile = p.pos;
          pawn.moving = false;
        }));
      }
    }
    if (moves.isNotEmpty) await Future.wait(moves);
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
    } else {
      _floaterText(f.playerId, f.label, Colors.white);
    }
  }

  // ─── Ce se întâmplă pe câmpul de aterizare ───────────────────────────

  Future<void> _land(UnknownPlayer p, UnknownLanding landing) async {
    for (final f in landing.fx) {
      _floater(f);
    }
    if (landing.event != null) {
      _set(() => _log = '${unknownEventTitle(landing.event!)}\n${unknownEventDesc(landing.event!)}');
      await _showBanner('❓ ${unknownEventTitle(landing.event!)}', ms: 1800);
      await _wait(600);
    } else if (landing.fx.isNotEmpty) {
      await _wait(900);
    }

    switch (landing.kind) {
      case UnknownLandingKind.none:
        break;
      case UnknownLandingKind.chest:
        await _chest(p, landing.relicOffers);
      case UnknownLandingKind.shop:
        await _shop(p, landing.itemOffers);
      case UnknownLandingKind.duel:
        await _duel(p, _g.player(landing.opponentId!));
      case UnknownLandingKind.goldenQuestion:
        await _golden(p);
    }
  }

  Future<T> _waitChoice<T>() async {
    final c = Completer<Object?>();
    _choice = c;
    final v = await c.future;
    _alive();
    return v as T;
  }

  void _choose(Object? value) {
    final c = _choice;
    if (c == null || c.isCompleted) return;
    _choice = null;
    Sfx.tileSelect();
    c.complete(value);
  }

  Future<void> _chest(UnknownPlayer p, List<UnknownRelic> offers) async {
    if (p.isBot) {
      final pick = unknownBotPickRelic(p, offers);
      _g.takeRelic(p, pick.take, drop: pick.drop);
      _set(() => _log = pick.take == null
          ? tr('🎁 ${p.name} n-a găsit nimic pe gustul lui în cufăr.', '🎁 ${p.name} found nothing to like in the chest.')
          : tr('🎁 ${p.name} a luat ${unknownRelicEmoji(pick.take!)} ${unknownRelicName(pick.take!)}:\n${unknownRelicDesc(pick.take!)}',
              '🎁 ${p.name} took ${unknownRelicEmoji(pick.take!)} ${unknownRelicName(pick.take!)}:\n${unknownRelicDesc(pick.take!)}'));
      if (pick.take != null) _floaterText(p.id, unknownRelicEmoji(pick.take!), Colors.white, big: true);
      await _wait(_botDecisionMs + 400);
      return;
    }
    Sfx.rewardPop();
    _set(() {
      _phase = _Phase.chest;
      _relicOffers = offers;
    });
    var take = await _waitChoice<UnknownRelic?>();
    UnknownRelic? drop;
    if (take != null && p.relics.length >= unknownMaxRelics) {
      _set(() {
        _phase = _Phase.chestDrop;
        _pendingRelic = take;
      });
      drop = await _waitChoice<UnknownRelic?>();
      if (drop == null) take = null;
    }
    _g.takeRelic(p, take, drop: drop);
    _set(() {
      _phase = _Phase.moving;
      _log = take == null ? '' : tr('Ai luat ${unknownRelicName(take)}!', 'You took ${unknownRelicName(take)}!');
    });
    if (take != null) {
      _floaterText(p.id, unknownRelicEmoji(take), Colors.white, big: true);
      await _wait(900);
    }
  }

  Future<void> _shop(UnknownPlayer p, List<UnknownItem> offers) async {
    if (p.isBot) {
      final item = unknownBotPickItem(p, offers);
      if (item != null && _g.buyItem(p, item)) {
        _set(() => _log = tr('🛒 ${p.name} a cumpărat ${unknownItemEmoji(item)} ${unknownItemName(item)}',
            '🛒 ${p.name} bought ${unknownItemEmoji(item)} ${unknownItemName(item)}'));
      } else {
        _set(() => _log = tr('🛒 ${p.name} doar s-a uitat prin magazin.', '🛒 ${p.name} just window-shopped.'));
      }
      await _wait(_botDecisionMs);
      return;
    }
    _set(() {
      _phase = _Phase.shop;
      _itemOffers = offers;
    });
    final item = await _waitChoice<UnknownItem?>();
    if (item != null && _g.buyItem(p, item)) {
      Sfx.coinHit();
      _set(() => _log = tr('Ai cumpărat ${unknownItemName(item)}. Apasă-l jos ca să-l folosești.',
          'You bought ${unknownItemName(item)}. Tap it below to use it.'));
    }
    _set(() => _phase = _Phase.moving);
  }

  Future<void> _duel(UnknownPlayer attacker, UnknownPlayer defender) async {
    await _showBanner('⚔️ ${_who(attacker)} vs ${defender.isBot ? defender.name : tr('tu', 'you')}', ms: 1700);
    final q = _nextQuestion();
    final human = attacker.isBot ? (defender.isBot ? null : defender) : attacker;
    final UnknownAnswer a;
    final UnknownAnswer d;
    if (human == null) {
      a = _botAnswer(q);
      d = _botAnswer(q);
    } else {
      final other = human == attacker ? defender : attacker;
      final mine = await _askMe(q, tr('⚔️ Duel cu ${other.name} — cine nimerește ia 6 🪙', '⚔️ Duel with ${other.name} — winner takes 6 🪙'));
      final theirs = _botAnswer(q);
      a = human == attacker ? mine : theirs;
      d = human == attacker ? theirs : mine;
    }
    final res = _g.resolveDuel(attacker, defender, a, d);
    for (final f in res.fx) {
      _floater(f);
    }
    final winner = res.winnerId == null ? null : _g.player(res.winnerId!);
    _set(() => _log = winner == null
        ? tr('⚔️ Nimeni n-a nimerit — duel nul.', '⚔️ Nobody got it — a draw.')
        : winner.isBot
            ? tr('⚔️ ${winner.name} câștigă duelul!', '⚔️ ${winner.name} wins the duel!')
            : tr('⚔️ Ai câștigat duelul!', '⚔️ You won the duel!'));
    if (winner != null && !winner.isBot) Sfx.rewardPop();
    await _wait(2200);
  }

  Future<void> _golden(UnknownPlayer p) async {
    final q = _nextQuestion();
    final UnknownAnswer a = p.isBot ? _botAnswer(q) : await _askMe(q, tr('✨ Întrebarea de aur — corect: +4 câmpuri', '✨ Golden question — right: +4 spaces'));
    final ok = _g.resolveGolden(p, a.correct);
    _set(() => _log = ok
        ? tr('✨ ${_who(p)}: întrebarea de aur, +4 câmpuri!', '✨ ${_who(p)}: golden question, +4 spaces!')
        : tr('✨ Întrebarea de aur a scăpat.', '✨ The golden question slipped away.'));
    await _syncPawns();
    await _wait(1400);
  }

  // ─── Finalul ─────────────────────────────────────────────────────────

  Future<void> _finish() async {
    _scene.activeId = null;
    _focusOn(null);
    final standings = _g.standings();
    await _reward(standings.indexWhere((p) => p.id == _me), standings.length);
    _set(() {
      _final = standings;
      _phase = _Phase.results;
      _log = '';
      _diceVisible = false;
    });
    if (standings.first.id == _me) Sfx.rewardPop();
  }

  /// Aceeași recompensă și același plafon zilnic ca celelalte meciuri cu
  /// boți (core/bot_brain.dart) — modul nou nu deschide o fermă de monede.
  Future<void> _reward(int place, int total) async {
    try {
      if (await StorageService.getDailyCounter(_botRewardCounter) >= botRewardedMatchesPerDay) {
        _capReached = true;
        return;
      }
      await StorageService.incrementDailyCounter(_botRewardCounter);
      final r = botMatchReward(place: place, totalPlayers: total, difficulty: widget.difficulty, botCount: widget.botCount);
      _coinsEarned = r.coins;
      _xpEarned = r.xp;
      await StorageService.addCoins(r.coins);
      await StorageService.addXp(r.xp);
    } catch (e) {
      debugPrint('UnknownGameScreen._reward: $e');
    }
  }

  Future<bool> _confirmExit() async {
    if (_phase == _Phase.results) return true;
    GamePause.instance.pause();
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(tr('Ieși din meci?', 'Leave the match?'), style: const TextStyle(color: Colors.white)),
        content: Text(tr('Meciul se pierde și nu primești nimic.', 'The match is lost and you get nothing.'),
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Rămân', 'Stay'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Ies', 'Leave'))),
        ],
      ),
    );
    GamePause.instance.resume();
    return leave == true;
  }

  /// Legenda câmpurilor. Jocul stă pe pauză cât o citești.
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
              row(dot(UnknownTile.chest), tr('Cufărul', 'Chest'), tr('Alegi 1 din 3 artefacte (maxim 3).', 'Pick 1 of 3 relics (max 3).')),
              row(dot(UnknownTile.shop), tr('Magazinul', 'Shop'), tr('Cumperi obiecte cu monede (maxim 2).', 'Buy items with coins (max 2).')),
              row(dot(UnknownTile.duel), tr('Duelul', 'Duel'), tr('O întrebare cu cel mai bogat; cine nimerește ia 6 🪙.', 'One question vs the richest; the winner takes 6 🪙.')),
              row(dot(UnknownTile.event), tr('Evenimentul', 'Event'), tr('Orice se poate întâmpla.', 'Anything can happen.')),
              row(dot(UnknownTile.coins), '+3 🪙', tr('Monede.', 'Coins.')),
              row(dot(UnknownTile.tax), '−3 🪙', tr('Taxă.', 'A tax.')),
              const SizedBox(height: 8),
              Text(
                tr('Corect = 2 zaruri, greșit = 1. Cel mai rapid răspuns corect: +3 🪙. Ultimul din cursă: +2 pași.',
                    'Right = 2 dice, wrong = 1. Fastest right answer: +3 🪙. Last in the race: +2 steps.'),
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmExit()) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SpaceBackground(
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    _topBar(),
                    _playerStrip(),
                    Expanded(child: _boardArea()),
                    _myBar(),
                    _panel(),
                  ],
                ),
                if (_phase == _Phase.intro) _introOverlay(),
                if (_phase == _Phase.results) _resultsOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (await _confirmExit()) navigator.pop();
            },
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const Text('Unknown', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          const Spacer(),
          _pill(tr('Runda ${_g.round + 1}', 'Round ${_g.round + 1}'), Colors.white24),
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

  Widget _playerStrip() {
    final ranking = {for (final (i, p) in _g.standings().indexed) p.id: i + 1};
    final compact = _g.players.length > 4;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          for (final p in _g.players)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _playerChip(p, ranking[p.id]!, compact),
              ),
            ),
        ],
      ),
    );
  }

  Widget _playerChip(UnknownPlayer p, int place, bool compact) {
    final color = unknownPlayerColors[p.colorIndex % unknownPlayerColors.length];
    final active = _scene.activeId == p.id;
    final answered = _phase == _Phase.question && _answered.contains(p.id);
    final reveal = _phase == _Phase.reveal && (_tableQuestion || !p.isBot) ? _revealAnswers[p.id] : null;
    final status = [
      if (p.shielded) '🛡️',
      if (p.skipNext) '⏸️',
      if (!compact) ...p.relics.map(unknownRelicEmoji),
    ].join();
    return AnimatedContainer(
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
                  p.isBot ? p.name.replaceAll(' 🤖', '') : tr('Tu', 'You'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
              ),
              if (answered) const Icon(Icons.check_circle, size: 13, color: Colors.white70),
              if (reveal != null)
                Icon(reveal.correct ? Icons.check_circle : Icons.cancel,
                    size: 14, color: reveal.correct ? AppColors.play : AppColors.danger),
              if (_phase == _Phase.reveal && _tableQuestion && reveal == null && !p.finished)
                const Icon(Icons.cancel, size: 14, color: AppColors.danger),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${p.finished ? '🏁' : '📍${p.pos}'}  🪙${p.coins}',
              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900),
            ),
          ),
          if (status.isNotEmpty) Text(status, style: const TextStyle(fontSize: 11)),
        ],
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
                Text(tr('= $total pași', '= $total steps'),
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Artefactele și obiectele tale. Obiectele se apasă ca să le pregătești
  /// pentru mutarea următoare; apăsat din nou = le pui înapoi.
  Widget _myBar() {
    final me = _mePlayer;
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
          if (me.armed != null) _itemChip(me.armed!, armed: true),
          for (final i in me.items) _itemChip(i, armed: false),
        ],
      ),
    );
  }

  Widget _itemChip(UnknownItem item, {required bool armed}) {
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (armed) {
              _g.disarm(_mePlayer);
            } else {
              _g.arm(_mePlayer, item);
              _toast(tr('${unknownItemName(item)}: ${unknownItemDesc(item)} — se folosește la mutarea următoare.',
                  '${unknownItemName(item)}: ${unknownItemDesc(item)} — used on your next move.'));
            }
          });
          Sfx.tileSelect();
        },
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

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
  }

  Widget _panel() {
    final Widget child = switch (_phase) {
      _Phase.question || _Phase.reveal => _questionPanel(),
      _Phase.chest => _choicePanel(
          title: tr('🎁 Cufăr! Alege un artefact', '🎁 Chest! Pick a relic'),
          cards: [
            for (final r in _relicOffers)
              _ChoiceCard(emoji: unknownRelicEmoji(r), title: unknownRelicName(r), body: unknownRelicDesc(r), onTap: () => _choose(r)),
          ],
          skipLabel: tr('Nu iau nimic', 'Take nothing'),
        ),
      _Phase.chestDrop => _choicePanel(
          title: tr('Ai deja 3. Pe care îl lași pentru ${unknownRelicEmoji(_pendingRelic!)}?',
              'You already have 3. Which one goes for ${unknownRelicEmoji(_pendingRelic!)}?'),
          cards: [
            for (final r in _mePlayer.relics)
              _ChoiceCard(emoji: unknownRelicEmoji(r), title: unknownRelicName(r), body: unknownRelicDesc(r), onTap: () => _choose(r)),
          ],
          skipLabel: tr('Le păstrez pe ale mele', 'Keep mine'),
        ),
      _Phase.shop => _choicePanel(
          title: tr('🛒 Magazin — ai ${_mePlayer.coins} 🪙', '🛒 Shop — you have ${_mePlayer.coins} 🪙'),
          cards: [
            for (final i in _itemOffers)
              _ChoiceCard(
                emoji: unknownItemEmoji(i),
                title: '${unknownItemName(i)} · ${unknownItemPrice(i)} 🪙',
                body: unknownItemDesc(i),
                onTap: _mePlayer.coins >= unknownItemPrice(i) && _mePlayer.items.length < unknownMaxItems ? () => _choose(i) : null,
              ),
          ],
          skipLabel: tr('Plec', 'Leave'),
        ),
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

  Widget _questionPanel() {
    final q = _question!;
    final revealed = _phase == _Phase.reveal;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(_questionHeader,
                  style: const TextStyle(color: Colors.white60, fontSize: 12.5, fontWeight: FontWeight.w800)),
            ),
            if (!revealed)
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _secondsLeft <= 3 ? AppColors.danger : AppColors.play, width: 3),
                ),
                child: Text('$_secondsLeft', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
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
          children: [for (final c in q.choices) _answerButton(c, q, revealed)],
        ),
        if (_mePlayer.finished && _tableQuestion)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('Ai ajuns — te uiți doar.', 'You made it — just watching.'),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _answerButton(String choice, CultureQuestion q, bool revealed) {
    final picked = _myPick == choice;
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
      onTap: _myPick == null && !revealed ? () => _onPick?.call(choice) : null,
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

  Widget _choicePanel({required String title, required List<Widget> cards, required String skipLabel}) {
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
          onPressed: () => _choose(null),
          child: Text(skipLabel, style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  // ─── Suprapunerile ───────────────────────────────────────────────────

  Widget _dim({required Widget child}) => Positioned.fill(
        child: Container(
          color: const Color(0xCC060A18),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      );

  Widget _introOverlay() {
    Widget rule(String emoji, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 34, child: Text(emoji, style: const TextStyle(fontSize: 20))),
              Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.3))),
            ],
          ),
        );
    return _dim(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.coin.withAlpha(120), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🏁', style: TextStyle(fontSize: 44)),
            Text(tr('Primul la $unknownFinish câștigă', 'First to $unknownFinish wins'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            rule('❓', tr('Toți răspundem deodată. Corect = 2 zaruri, greșit = 1. Tot avansezi.',
                'Everyone answers at once. Right = 2 dice, wrong = 1. You always move.')),
            rule('🪜', tr('Scările te urcă, șerpii te trag înapoi.', 'Ladders lift you, snakes drag you back.')),
            rule('🍀', tr('Trifoiul îți dă imunitate. Capcana te ține o tură.', 'The clover makes you immune. The trap holds you one turn.')),
            rule('🎁', tr('Cuferele dau artefacte care se combină. Alege bine.', 'Chests give relics that stack. Choose well.')),
            rule('❔', tr('Butonul ? de sus explică fiecare câmp oricând.', 'The ? button up top explains every space anytime.')),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.play,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _ready ? _start : null,
                child: Text(tr('Hai!', 'Let\'s go!'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultsOverlay() {
    final myPlace = _final.indexWhere((p) => p.id == _me) + 1;
    final title = myPlace == 1 ? tr('Ai câștigat! 🏆', 'You won! 🏆') : tr('Locul $myPlace din ${_final.length}', 'Place $myPlace of ${_final.length}');
    return _dim(
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: myPlace == 1 ? AppColors.coin : Colors.white24, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            Text(tr('${_g.round} runde', '${_g.round} rounds'), style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
            const SizedBox(height: 12),
            for (final (i, p) in _final.indexed)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: p.id == _me ? AppColors.play.withAlpha(50) : Colors.white.withAlpha(12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(switch (i) { 0 => '🥇', 1 => '🥈', 2 => '🥉', _ => '${i + 1}.' },
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                    ),
                    Expanded(
                      child: Text(_who(p),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                    Text('${p.finished ? '🏁' : '📍${p.pos}'}   🪙 ${p.coins}',
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _capReached
                  ? tr('Ai jucat destule meciuri cu boți azi — de acum fără recompensă până mâine.',
                      'You have played enough bot matches today — no more rewards until tomorrow.')
                  : '+$_coinsEarned 🪙   +$_xpEarned XP',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _capReached ? Colors.white60 : AppColors.coin,
                fontSize: _capReached ? 12.5 : 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white38),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Înapoi', 'Back'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.play,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => UnknownGameScreen(botCount: widget.botCount, difficulty: widget.difficulty)),
                    ),
                    child: Text(tr('Încă unul', 'Play again'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
