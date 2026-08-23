import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../core/obby.dart';

/// Ce a pățit un alergător în runda tocmai încheiată — se calculează în ecran
/// (vezi MultiplayerObbyScreen._advancedThisRound) și ajunge aici gata
/// calculat, ca jocul Flame să n-aibă nevoie nici de regulile din
/// core/obby.dart, nici de conținutul rundei din Firestore.
///
/// [none] înseamnă și „a răspuns greșit, deci n-a sărit deloc": personajul
/// rămâne pe loc, fără nicio animație — nu e totuna cu [fell], care e o
/// alegere greșită de placă și SE VEDE.
enum ObbyRoundOutcome { none, jumped, fell }

/// După ce fracție din deznodământ cedează placa falsă și începe căderea.
///
/// Public fiindcă ecranul trebuie să pornească sunetul de cădere EXACT
/// atunci, nu la începutul deznodământului — vezi
/// MultiplayerObbyScreen._playRevealSfx. Dacă se schimbă aici, sunetul se
/// mută odată cu animația, singur.
const double obbyFallDelayFraction = 0.15;

/// Un alergător de pe pistă, cât e nevoie ca [ObbyGame] să-l deseneze — extras
/// din `MatchPlayer` de ecran, ca jocul Flame să nu importe modelul Firestore
/// direct (aceeași graniță UI/date pe care restul proiectului o respectă).
class ObbyRacerData {
  final String id;
  final String name;
  final Color color;
  final double progress; // 0..1, cât din pistă a trecut DUPĂ runda asta
  final bool isMe;
  final ObbyRoundOutcome outcome;

  const ObbyRacerData({
    required this.id,
    required this.name,
    required this.color,
    required this.progress,
    required this.isMe,
    this.outcome = ObbyRoundOutcome.none,
  });
}

/// Jocul Flame din spatele Obby-ului — o singură instanță, creată o dată per
/// ecran (`late final` în State, niciodată recreată) și HRĂNITĂ cu date noi
/// la fiecare snapshot Firestore prin [applyRoundState]. NU importă
/// data/multiplayer_service.dart: primește [onPlatformChosen] ca să rămână
/// doar strat de randare, exact granița pe care restul proiectului o
/// respectă între ecrane (UI+date) și widget-uri (doar randare).
///
/// Temă: o cursă printre bolovani de asteroid, în spațiu — de la 2 la 6
/// astronauți sar din stâncă în stâncă, iar cine trece de ultimul obstacol
/// urcă direct în naveta de scăpare (vezi [_RunnerComponent._paintShuttle]).
///
/// Două scene, comutate prin [phase]:
///  - [ObbyPhase.choosing] — personajul local stă în fața celor
///    [obbyPlatformChoiceCount] bolovani; alegerea se face prin butoanele din
///    ecran sau prin tap direct pe bolovan.
///  - [ObbyPhase.revealed] — camera trece la 3rd-person, urmărește personajul
///    local (`camera.follow`) cât toți alergătorii avansează/cad.
enum ObbyPhase { idle, choosing, revealed }

class ObbyGame extends FlameGame with TapCallbacks {
  final void Function(int platformIndex) onPlatformChosen;
  ObbyGame({required this.onPlatformChosen});

  ObbyPhase phase = ObbyPhase.idle;
  List<ObbyRacerData> _racers = const [];
  String? _myId;
  int? _myChoice;
  double _revealT = 0; // 0..1, cat de avansata e animatia de reveal curenta

  late final World _world;
  late final CameraComponent _cam;
  final Map<String, _RunnerComponent> _runners = {};
  _AstronautIdleComponent? _rig;

  /// Unde stătea fiecare alergător la sfârșitul deznodământului precedent.
  ///
  /// Scena e demontată complet între runde (faza de răspuns golește lumea),
  /// deci fără memoria asta fiecare alergător ar fi reapărut la linia de
  /// start și ar fi alunecat de acolo până la locul lui, în fiecare rundă.
  /// Cu ea, personajul pornește DE UNDE A RĂMAS și parcurge exact obstacolul
  /// tocmai câștigat.
  final Map<String, double> _lastDepth = {};

  static const _laneGap = 90.0;
  static const _platformY = 120.0;

  /// Cât din durata deznodământului ocupă săritura, respectiv căderea.
  /// Săritura e scurtă și la început (e o mișcare de reflex); căderea începe
  /// cu o clipă mai târziu — jucătorul trebuie să apuce să vadă că a pășit pe
  /// bolovan înainte ca el să cedeze sub el.
  static const _jumpWindow = 0.35;
  static const _fallDelay = obbyFallDelayFraction;
  static const _fallWindow = 0.55;

  /// Zoom-ul spre care se duce camera. NU se scrie direct pe viewfinder: o
  /// schimbare bruscă de zoom la trecerea alegere → deznodământ se citește ca
  /// un salt al imaginii, nu ca o mișcare de cameră. Vezi [update].
  double _targetZoom = 1;
  bool _cameraEverAttached = false;

  /// Urmărește camera acum un personaj? Se stinge când cad eu (vezi
  /// [_updateReveal]) și se reaprinde la fiecare scenă de deznodământ nouă.
  bool _cameraFollowing = false;

  bool get _myFell => _racers.any((r) => r.isMe && r.outcome == ObbyRoundOutcome.fell);

  @override
  Future<void> onLoad() async {
    _world = World();
    _cam = CameraComponent(world: _world)..viewfinder.anchor = Anchor.center;
    addAll([_world, _cam]);
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Easing de zoom, cadru cu cadru — lerp exponențial spre țintă. Pragul
    // oprește urmărirea când diferența devine invizibilă, ca să nu rămână o
    // scriere pe viewfinder la fiecare cadru din meci.
    final z = _cam.viewfinder.zoom;
    if ((z - _targetZoom).abs() > 0.002) {
      _cam.viewfinder.zoom = z + (_targetZoom - z) * min(1.0, dt * 3.5);
    }
  }

  /// Apelat din StreamBuilder-ul ecranului la fiecare snapshot nou —
  /// singurul punct de intrare de date în joc. Idempotent: poate fi apelat
  /// de mai multe ori cu aceleași date fără efecte vizibile suplimentare.
  void applyRoundState({
    required ObbyPhase phase,
    required List<ObbyRacerData> racers,
    required String myId,
    int? myChoice,
    double revealT = 0,
  }) {
    _myId = myId;
    _myChoice = myChoice;
    _revealT = revealT;

    // Se reconstruiește DOAR la schimbare de fază sau când se schimbă cine e
    // la masă. Progresul și deznodământul se aplică pe componentele deja
    // existente — o reconstrucție la fiecare snapshot ar fi retezat orice
    // animație în curs, iar Firestore trimite mai multe snapshot-uri în
    // timpul unui singur deznodământ.
    final rosterChanged = !_sameRoster(_racers, racers);
    _racers = racers;

    if (phase != this.phase || rosterChanged) {
      this.phase = phase;
      _rebuildScene();
    } else if (phase == ObbyPhase.revealed) {
      _updateReveal();
    } else if (phase == ObbyPhase.choosing) {
      _updateChoosingHighlight();
    }
  }

  bool _sameRoster(List<ObbyRacerData> a, List<ObbyRacerData> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _rebuildScene() {
    _world.removeAll(_world.children.toList());
    _runners.clear();
    _rig = null;

    switch (phase) {
      case ObbyPhase.idle:
        break;
      case ObbyPhase.choosing:
        _buildChoosingScene();
        break;
      case ObbyPhase.revealed:
        _buildRevealScene();
        break;
    }
  }

  // ─── Scena de alegere: personajul local + 3 bolovani în față ─────────────

  void _buildChoosingScene() {
    _cam.stop();
    _cameraFollowing = false;
    _cam.viewfinder.position = Vector2.zero();
    _setZoom(1, instant: !_cameraEverAttached);

    final me = _racers.where((r) => r.isMe).firstOrNull;
    final color = me?.color ?? Colors.blue;

    _world.add(_SpaceBackdropComponent(starCount: 70));

    for (var i = 0; i < obbyPlatformChoiceCount; i++) {
      final dx = (i - (obbyPlatformChoiceCount - 1) / 2) * _laneGap;
      _world.add(_AsteroidComponent(index: i, position: Vector2(dx, -_platformY)));
    }

    _rig = _AstronautIdleComponent(color: color, position: Vector2(0, 40))..anchor = Anchor.center;
    _world.add(_rig!);
    _choiceSent = false;

    _updateChoosingHighlight();
  }

  bool _choiceSent = false;

  void _updateChoosingHighlight() {
    for (final c in _world.children.whereType<_AsteroidComponent>()) {
      c.selected = false;
      c.locked = _myChoice != null && c.index != _myChoice;
      c.chosen = c.index == _myChoice;
    }
  }

  /// Apelat când jucătorul apasă direct un bolovan din scenă — echivalent cu
  /// butoanele din ecran (vezi [MultiplayerObbyScreen._platformButton]).
  void tapPlatform(int index) {
    if (phase != ObbyPhase.choosing || _myChoice != null || _choiceSent) return;
    _choiceSent = true;
    onPlatformChosen(index);
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (phase != ObbyPhase.choosing) return;
    final local = _cam.globalToLocal(event.devicePosition);
    for (final p in _world.children.whereType<_AsteroidComponent>()) {
      final rect = Rect.fromCenter(center: p.position.toOffset(), width: 70, height: 70);
      if (rect.contains(local.toOffset())) {
        tapPlatform(p.index);
        return;
      }
    }
  }

  // ─── Scena de reveal: pista completă, camera urmărește personajul local ──

  void _buildRevealScene() {
    _world.add(_SpaceTrackComponent(starCount: 140));

    for (final r in _racers) {
      final runner = _RunnerComponent(data: r, startDepth: _lastDepth[r.id] ?? r.progress)
        ..position = Vector2(_laneXFor(r), 0);
      _runners[r.id] = runner;
      _world.add(runner);
    }

    final myRunner = _myId == null ? null : _runners[_myId];
    if (myRunner != null) {
      // Camera sare instant doar când chiar e departe de țintă: prima montare
      // din meci, sau venirea din scena de alegere (unde stă la origine).
      // Între două runde distanța e un singur obstacol, iar acolo saltul ar
      // fi tăiat exact mișcarea pe care vrem s-o vadă jucătorul.
      final dist = (_cam.viewfinder.position - myRunner.position).length;
      final farAway = !_cameraEverAttached || dist > 260;
      _cam.follow(myRunner, maxSpeed: 420, snap: farAway);
      _cameraEverAttached = true;
      _cameraFollowing = true;
      _setZoom(1.05);
    } else {
      _cam.stop();
      _cameraFollowing = false;
      _cam.viewfinder.position = Vector2.zero();
      _setZoom(0.9, instant: !_cameraEverAttached);
    }
    _updateReveal();
  }

  void _setZoom(double target, {bool instant = false}) {
    _targetZoom = target;
    if (instant) _cam.viewfinder.zoom = target;
  }

  /// Distanța laterală dintre două culoare. NU e doar o chestiune de aer în
  /// jurul personajelor: la 70 (cât era) numele scrise deasupra capetelor se
  /// suprapuneau vizibil chiar și cu doar doi alergători pe pistă.
  static const _laneWidth = 110.0;

  double _laneXFor(ObbyRacerData r) {
    final idx = _racers.indexOf(r);
    final mid = (_racers.length - 1) / 2;
    return (idx - mid) * _laneWidth;
  }

  void _updateReveal() {
    final jumpT = (_revealT / _jumpWindow).clamp(0.0, 1.0);
    final fallT = ((_revealT - _fallDelay) / _fallWindow).clamp(0.0, 1.0);
    // Cât de avansată e decolarea navetei DUPĂ ce săritura s-a terminat —
    // doar cine a terminat cursa (progress == 1) o folosește, vezi
    // _RunnerComponent._paintShuttle.
    final liftoffT = ((_revealT - _jumpWindow) / (1 - _jumpWindow)).clamp(0.0, 1.0);
    // Când EU cad, camera se opreșe din urmărit. Altfel se ducea în jos odată
    // cu mine și căderea se vedea aproape deloc: personajul rămânea în
    // mijlocul ecranului, iar singurul indiciu erau rotirea și estomparea.
    // Cu camera pe loc, chiar dispar sub pistă.
    if (fallT > 0 && _cameraFollowing && _myFell) {
      _cam.stop();
      _cameraFollowing = false;
    }
    for (final r in _racers) {
      final runner = _runners[r.id];
      if (runner == null) continue;
      runner.data = r;
      runner.setDepth(
        r.progress,
        jumpT: r.outcome == ObbyRoundOutcome.jumped ? jumpT : 0,
        fallT: r.outcome == ObbyRoundOutcome.fell ? fallT : 0,
        liftoffT: liftoffT,
      );
      // Cine a căzut n-a înaintat, deci [ObbyRacerData.progress] e tot cel
      // vechi (resolverul nu i-a dat obstacolul) — se ține minte la fel,
      // pentru runda următoare.
      _lastDepth[r.id] = r.progress;
    }
  }
}

extension on Iterable<ObbyRacerData> {
  ObbyRacerData? get firstOrNull => isEmpty ? null : first;
}

// ─── Componente ──────────────────────────────────────────────────────────

/// Un câmp de stele, generat o singură dată la construcție — NU la fiecare
/// cadru — ca desenul să coste doar niște `drawCircle`-uri fixe, nu și
/// calculul pozițiilor. Poziția aleatoare e determinată de un `Random` fără
/// sămânță fixă: scena se reconstruiește la fiecare schimbare de fază, deci
/// stelele oricum "sar" vizual atunci, un pic de variație în plus nu se simte.
class _StarField {
  final List<Offset> positions;
  final List<double> radii;
  final List<int> alphas;

  _StarField(int count, Rect bounds) : positions = [], radii = [], alphas = [] {
    final rng = Random();
    for (var i = 0; i < count; i++) {
      positions.add(Offset(
        bounds.left + rng.nextDouble() * bounds.width,
        bounds.top + rng.nextDouble() * bounds.height,
      ));
      radii.add(0.6 + rng.nextDouble() * 1.4);
      alphas.add(70 + rng.nextInt(150));
    }
  }

  void paint(Canvas canvas, Paint reusablePaint) {
    for (var i = 0; i < positions.length; i++) {
      reusablePaint.color = Colors.white.withAlpha(alphas[i]);
      canvas.drawCircle(positions[i], radii[i], reusablePaint);
    }
  }
}

/// Fundal de spațiu pentru scena de alegere — personajul stă pe loc, doar
/// bolovanii contează, dar cerul din spate trebuie să arate ca vidul, nu ca
/// un teren de fotbal.
class _SpaceBackdropComponent extends PositionComponent {
  late final _StarField _stars;
  final Paint _starPaint = Paint();
  final Paint _voidPaint = Paint()..color = const Color(0xFF05060F);
  final Paint _glowPaint = Paint()..color = const Color(0x220C2A6B);

  _SpaceBackdropComponent({required int starCount}) {
    _stars = _StarField(starCount, const Rect.fromLTWH(-260, -320, 520, 480));
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(const Rect.fromLTWH(-2000, -2000, 4000, 4000), _voidPaint);
    canvas.drawCircle(const Offset(0, -80), 260, _glowPaint);
    _stars.paint(canvas, _starPaint);
  }

  @override
  int get priority => -10;
}

/// Un bolovan de asteroid din faza de alegere — formă stâncoasă, colorată
/// după stare (neutru / ales de mine / blocat fiindcă am ales altul).
class _AsteroidComponent extends PositionComponent {
  final int index;
  bool selected = false;
  bool locked = false;
  bool chosen = false;

  late final Path _rockPath;
  late final List<Offset> _craters;
  final Paint _fillPaint = Paint();
  final Paint _rimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4
    ..color = Colors.white38;
  final Paint _craterPaint = Paint()..color = const Color(0xFF4A4038);

  _AsteroidComponent({required this.index, required Vector2 position})
      : super(position: position, size: Vector2(64, 46), anchor: Anchor.center) {
    final rng = Random(index * 97 + 13);
    _rockPath = _buildRockPath(rng, size.x, size.y);
    _craters = List.generate(3, (i) {
      final a = rng.nextDouble() * pi * 2;
      final r = size.x * (0.12 + rng.nextDouble() * 0.16);
      return Offset(cos(a) * r, sin(a) * r * 0.6);
    });
  }

  static Path _buildRockPath(Random rng, double w, double h) {
    const points = 9;
    final path = Path();
    for (var i = 0; i < points; i++) {
      final angle = (i / points) * pi * 2;
      final jitter = 0.78 + rng.nextDouble() * 0.24;
      final dx = cos(angle) * (w / 2) * jitter;
      final dy = sin(angle) * (h / 2) * jitter;
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    path.close();
    return path;
  }

  @override
  void render(Canvas canvas) {
    final base = chosen
        ? const Color(0xFF3DDC97)
        : selected
            ? const Color(0xFF5EC8F2)
            : const Color(0xFF9C8A73);
    _fillPaint.color = locked && !chosen ? base.withAlpha(80) : base;
    canvas.drawPath(_rockPath, _fillPaint);
    if (!(locked && !chosen)) {
      for (final c in _craters) {
        canvas.drawCircle(c, size.x * 0.07, _craterPaint);
      }
    }
    if (selected || chosen) {
      canvas.drawPath(_rockPath, _rimPaint..color = Colors.white);
    } else {
      canvas.drawPath(_rockPath, _rimPaint..color = Colors.white24);
    }
  }
}

/// Personajul controlat local, în faza de alegere — un mic astronaut desenat
/// procedural (fără sprite-uri), care abia se leagănă (idle).
class _AstronautIdleComponent extends PositionComponent {
  final Color color;
  double _t = 0;

  _AstronautIdleComponent({required this.color, required Vector2 position}) : super(position: position, size: Vector2(48, 66));

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void render(Canvas canvas) {
    final bob = sin(_t * 2.4) * 2;
    final bounds = Rect.fromLTWH(0, bob, size.x, size.y);
    paintObbyAstronaut(canvas, bounds, color, legSpread: sin(_t * 2.4) * 0.15);
  }
}

/// Un alergător de pe pistă, în scena de reveal — poziția lui de-a lungul
/// pistei (adâncime) se animă local cu [setDepth], nu cu poziția reală
/// Flame direct (ca umbra/scara/săritura să rămână corecte).
class _RunnerComponent extends PositionComponent {
  ObbyRacerData data;
  double _depth = 0;
  double _jumpT = 0;
  double _fallT = 0;
  double _liftoffT = 0;
  double _time = 0;

  final Paint _bodyPaint = Paint();
  final Paint _shadowPaint = Paint()..color = Colors.black.withAlpha(90);
  TextPainter? _nameTp;
  String? _nameTpFor;

  _RunnerComponent({required this.data, required double startDepth}) : super(size: Vector2(46, 62), anchor: Anchor.center) {
    _depth = startDepth;
    // Poziția de start se pune din constructor, nu lăsată pe seama lerp-ului
    // din [update]: altfel primul cadru al scenei i-ar fi arătat pe toți la
    // linia de start, cu un salt vizibil imediat după.
    position.y = -startDepth * 900;
  }

  /// A terminat cursa cu săritura asta? Dacă da, în loc să rămână în picioare
  /// pe ultimul bolovan, urcă direct în naveta de scăpare — vezi
  /// [_paintShuttle].
  bool get _finishedThisJump => data.outcome == ObbyRoundOutcome.jumped && data.progress >= 0.999;

  /// [jumpT] și [fallT] sunt 0..1 și se exclud reciproc — o rundă e ori
  /// săritură reușită, ori cădere, niciodată amândouă (vezi
  /// [ObbyRoundOutcome]). [liftoffT] avansează pe tot deznodământul, dar
  /// contează doar pentru [_finishedThisJump].
  void setDepth(double depth, {double jumpT = 0, double fallT = 0, double liftoffT = 0}) {
    _depth = depth;
    _jumpT = jumpT;
    _fallT = fallT;
    _liftoffT = liftoffT;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    // adancimea pe pista = departe pe axa Y (in fata), scara mica departe
    final targetY = -_depth * 900;
    if (_fallT > 0) {
      // Căderea NU trece prin lerp-ul de mai jos: acela e ease-out (pornește
      // repede, se domolește), adică exact pe dos față de o cădere. Pătratul
      // lui [_fallT] dă accelerația care se citește drept gravitație.
      position.y = targetY + _fallT * _fallT * 520;
    } else {
      position.y += (targetY - position.y) * min(1, dt * 6);
    }
    final targetScale = (1.6 - _depth * 1.1).clamp(0.5, 1.6) * (1 - 0.45 * _fallT);
    scale.setAll(targetScale);
  }

  TextPainter _buildNameTp() {
    return TextPainter(
      text: TextSpan(
        text: data.name,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 80);
  }

  @override
  void render(Canvas canvas) {
    if (_finishedThisJump && _jumpT >= 0.999) {
      _paintShuttle(canvas);
      return;
    }

    final lift = sin(_jumpT.clamp(0, 1) * pi) * 44;
    final fade = 1 - _fallT;
    final alpha = (255 * fade).round().clamp(0, 255);
    _bodyPaint.color = _fallT > 0 ? data.color.withAlpha(alpha) : data.color;

    // Umbra dispare de îndată ce personajul n-are pe ce s-o mai lase.
    if (_fallT < 0.05) {
      canvas.drawOval(Rect.fromCenter(center: Offset(0, size.y / 2), width: size.x * 0.7, height: size.x * 0.25), _shadowPaint);
    }

    canvas.save();
    if (_fallT > 0) canvas.rotate(_fallT * 0.9); // se răsucește cât cade
    final bounds = Rect.fromLTWH(-size.x / 2, -size.y / 2 - lift, size.x, size.y);
    paintObbyAstronaut(canvas, bounds, _bodyPaint.color);
    canvas.restore();

    if (fade > 0.15) {
      if (_nameTpFor != data.name) {
        _nameTp = _buildNameTp();
        _nameTpFor = data.name;
      }
      final tp = _nameTp!;
      final offset = Offset(-tp.width / 2, -size.y / 2 - lift - tp.height - 2);
      if (fade < 0.999) {
        canvas.saveLayer(null, Paint()..color = Colors.white.withAlpha(alpha));
        tp.paint(canvas, offset);
        canvas.restore();
      } else {
        tp.paint(canvas, offset);
      }
    }
  }

  /// Naveta de scăpare — apare exact unde a aterizat ultimul astronaut și se
  /// ridică din cadru pe măsură ce [_liftoffT] avansează, cu flacăra
  /// motorului pâlpâind (funcție de [_time], nu de un `Random` per-cadru, ca
  /// pâlpâirea să rămână fluidă și nu zgomotoasă).
  void _paintShuttle(Canvas canvas) {
    final riseDelay = 0.15; // o clipă pe bolovan, ca aterizarea să se vadă, înainte de decolare
    final riseT = ((_liftoffT - riseDelay) / (1 - riseDelay)).clamp(0.0, 1.0);
    final riseY = riseT * riseT * 620; // accelerează la fel ca o decolare reală
    final fadeStart = 0.82;
    final fade = riseT < fadeStart ? 1.0 : (1 - (riseT - fadeStart) / (1 - fadeStart)).clamp(0.0, 1.0);
    final alpha = (255 * fade).round().clamp(0, 255);

    final flicker = 0.7 + 0.3 * sin(_time * 26) * sin(_time * 11 + 1.3).abs();

    canvas.save();
    canvas.translate(0, -riseY);
    if (fade < 0.05) {
      canvas.restore();
      return;
    }

    if (riseT < 0.9) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(0, size.y / 2 - riseY * 0.02), width: size.x * 0.55, height: size.x * 0.2),
        _shadowPaint..color = Colors.black.withAlpha((70 * (1 - riseT)).round()),
      );
    }

    final w = size.x * 0.62;
    final bodyTop = -size.y * 0.34;
    final bodyBottom = size.y * 0.22;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(-w / 2, bodyTop + w * 0.5, w / 2, bodyBottom),
      Radius.circular(w * 0.5),
    );
    final hullPaint = Paint()..color = const Color(0xFFDCE3EC).withAlpha(alpha);
    canvas.drawRRect(bodyRect, hullPaint);

    final nose = Path()
      ..moveTo(-w / 2, bodyTop + w * 0.5)
      ..lineTo(0, bodyTop)
      ..lineTo(w / 2, bodyTop + w * 0.5)
      ..close();
    canvas.drawPath(nose, hullPaint);

    final finPaint = Paint()..color = data.color.withAlpha(alpha);
    final finY = bodyBottom - w * 0.18;
    canvas.drawPath(
      Path()
        ..moveTo(-w / 2, finY)
        ..lineTo(-w * 0.95, bodyBottom + w * 0.22)
        ..lineTo(-w * 0.32, bodyBottom)
        ..close(),
      finPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w / 2, finY)
        ..lineTo(w * 0.95, bodyBottom + w * 0.22)
        ..lineTo(w * 0.32, bodyBottom)
        ..close(),
      finPaint,
    );

    canvas.drawCircle(Offset(0, bodyTop + w * 0.62), w * 0.18, Paint()..color = const Color(0xFF1B2540).withAlpha(alpha));
    canvas.drawCircle(Offset(-w * 0.05, bodyTop + w * 0.56), w * 0.06, Paint()..color = Colors.white.withAlpha((alpha * 0.8).round()));

    if (fade > 0.1) {
      final flameLen = (w * 0.9 * flicker) * fade;
      final flameOuter = Path()
        ..moveTo(-w * 0.24, bodyBottom)
        ..lineTo(0, bodyBottom + flameLen)
        ..lineTo(w * 0.24, bodyBottom)
        ..close();
      canvas.drawPath(flameOuter, Paint()..color = const Color(0xFFFF8A3D).withAlpha((alpha * 0.85).round()));
      final flameInner = Path()
        ..moveTo(-w * 0.12, bodyBottom)
        ..lineTo(0, bodyBottom + flameLen * 0.6)
        ..lineTo(w * 0.12, bodyBottom)
        ..close();
      canvas.drawPath(flameInner, Paint()..color = const Color(0xFFFFE580).withAlpha(alpha));
    }

    canvas.restore();
  }
}

/// Pista din scena de reveal — vid stelar cu un traseu de bolovani de
/// asteroid marcând fiecare obstacol, ca jucătorul să simtă distanța
/// parcursă cât camera îl urmărește.
class _SpaceTrackComponent extends PositionComponent {
  late final _StarField _stars;
  final Paint _starPaint = Paint();
  final Paint _voidPaint = Paint()..color = const Color(0xFF05060F);
  final Paint _glowPaint = Paint()..color = const Color(0x1A24408F);
  final Paint _railPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..color = Colors.white24;
  final Paint _markPaint = Paint()..color = const Color(0xFF9C8A73);

  _SpaceTrackComponent({required int starCount}) {
    _stars = _StarField(starCount, const Rect.fromLTWH(-1400, -3000, 2800, 3600));
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(const Rect.fromLTWH(-3000, -3000, 6000, 3000), _voidPaint);
    canvas.drawRect(const Rect.fromLTWH(-3000, -1200, 6000, 4200), _voidPaint);
    for (var i = 0; i <= obbyObstacleCount; i++) {
      final depth = i / obbyObstacleCount;
      canvas.drawCircle(Offset(0, -depth * 900), 420 * (1 - depth * 0.4), _glowPaint);
    }
    _stars.paint(canvas, _starPaint);

    canvas.drawLine(const Offset(-90, 0), const Offset(-160, -1000), _railPaint);
    canvas.drawLine(const Offset(90, 0), const Offset(160, -1000), _railPaint);

    for (var i = 1; i <= obbyObstacleCount; i++) {
      final depth = i / obbyObstacleCount;
      final y = -depth * 900;
      final spread = 90 + (1 - depth) * 90;
      canvas.drawCircle(Offset(-spread, y), 5, _markPaint);
      canvas.drawCircle(Offset(spread, y), 5, _markPaint);
    }
  }

  @override
  int get priority => -10;
}

/// Desenul comun al astronautului (cască + vizor + rucsac + corp + picioare)
/// — folosit atât pentru personajul din scena de alegere/reveal, cât și
/// pentru cel din colțul ecranului în timpul răspunsului (vezi
/// MultiplayerObbyScreen._CornerCharacter). [legSpread] mișcă picioarele
/// (mers/idle), [crouch] coboară puțin corpul (folosit la idle-ul din colț).
void paintObbyAstronaut(Canvas canvas, Rect bounds, Color suitColor, {double legSpread = 0, double crouch = 0}) {
  final w = bounds.width;
  final h = bounds.height;
  final cx = bounds.center.dx;
  final top = bounds.top + h * crouch * 0.15;

  final backpackPaint = Paint()..color = Color.lerp(suitColor, Colors.black, 0.4)!;
  final suitPaint = Paint()..color = suitColor;
  final helmetPaint = Paint()..color = const Color(0xFFE8ECF2);
  final visorPaint = Paint()..color = const Color(0xFF12141C);
  final highlightPaint = Paint()..color = Colors.white70;

  final headR = w * 0.26;
  final headCy = top + headR * 1.05;

  final bodyTop = headCy + headR * 0.7;
  final bodyBottom = bounds.bottom - h * 0.2 + crouch * h * 0.08;

  // Rucsacul stă în spatele corpului, deci se desenează primul.
  final backpackRect = RRect.fromRectAndRadius(
    Rect.fromLTRB(cx - w * 0.16, bodyTop + h * 0.02, cx + w * 0.16, bodyBottom - h * 0.04),
    Radius.circular(w * 0.08),
  );
  canvas.drawRRect(backpackRect, backpackPaint);

  final legPaint = Paint()
    ..color = suitColor
    ..strokeWidth = w * 0.15
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(
    Offset(cx - w * 0.07, bodyBottom - h * 0.02),
    Offset(cx - w * 0.09 - legSpread * w * 0.2, bounds.bottom),
    legPaint,
  );
  canvas.drawLine(
    Offset(cx + w * 0.07, bodyBottom - h * 0.02),
    Offset(cx + w * 0.09 + legSpread * w * 0.2, bounds.bottom),
    legPaint,
  );

  final bodyRect = RRect.fromRectAndRadius(
    Rect.fromLTRB(cx - w * 0.24, bodyTop, cx + w * 0.24, bodyBottom),
    Radius.circular(w * 0.2),
  );
  canvas.drawRRect(bodyRect, suitPaint);

  // Casca acoperă corpul de sus, cu vizorul suprapus și un mic reflex de
  // sticlă — asta desparte "astronaut" de silueta generică cu cap rotund.
  canvas.drawCircle(Offset(cx, headCy), headR, helmetPaint);
  canvas.drawOval(
    Rect.fromCenter(center: Offset(cx + headR * 0.08, headCy), width: headR * 1.25, height: headR * 1.5),
    visorPaint,
  );
  canvas.drawCircle(Offset(cx - headR * 0.28, headCy - headR * 0.3), headR * 0.16, highlightPaint);
}
