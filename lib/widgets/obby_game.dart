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
/// Două scene, comutate prin [phase]:
///  - [ObbyPhase.choosing] — personajul local stă în fața celor
///    [obbyPlatformChoiceCount] plăci; alegerea se face prin butoanele din
///    ecran sau prin tap direct pe placă.
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
  _PlayerRigComponent? _rig;

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
  /// placă înainte ca ea să cedeze sub el.
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

  // ─── Scena de alegere: personajul local + 3 plăci în față ────────────────

  void _buildChoosingScene() {
    _cam.stop();
    _cameraFollowing = false;
    _cam.viewfinder.position = Vector2.zero();
    _setZoom(1, instant: !_cameraEverAttached);

    final me = _racers.where((r) => r.isMe).firstOrNull;
    final color = me?.color ?? Colors.blue;

    _world.add(_SkyGroundComponent());

    for (var i = 0; i < obbyPlatformChoiceCount; i++) {
      final dx = (i - (obbyPlatformChoiceCount - 1) / 2) * _laneGap;
      _world.add(_PlatformComponent(index: i, position: Vector2(dx, -_platformY)));
    }

    _rig = _PlayerRigComponent(color: color, position: Vector2(0, 40))..anchor = Anchor.center;
    _world.add(_rig!);
    _choiceSent = false;

    _updateChoosingHighlight();
  }

  bool _choiceSent = false;

  void _updateChoosingHighlight() {
    for (final c in _world.children.whereType<_PlatformComponent>()) {
      c.selected = false;
      c.locked = _myChoice != null && c.index != _myChoice;
      c.chosen = c.index == _myChoice;
    }
  }

  /// Apelat când jucătorul apasă direct o placă din scenă — echivalent cu
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
    for (final p in _world.children.whereType<_PlatformComponent>()) {
      final rect = Rect.fromCenter(center: p.position.toOffset(), width: 70, height: 70);
      if (rect.contains(local.toOffset())) {
        tapPlatform(p.index);
        return;
      }
    }
  }

  // ─── Scena de reveal: pista completă, camera urmărește personajul local ──

  void _buildRevealScene() {
    _world.add(_GroundComponent());

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

/// Fundal simplu cer/pământ pentru scena de alegere — personajul stă pe loc,
/// doar plăcile contează.
class _SkyGroundComponent extends PositionComponent {
  @override
  void render(Canvas canvas) {
    final sky = Paint()..color = const Color(0xFF232A52);
    canvas.drawRect(const Rect.fromLTWH(-2000, -2000, 4000, 2000), sky);
    final ground = Paint()..color = const Color(0xFF1E4230);
    canvas.drawRect(const Rect.fromLTWH(-2000, 0, 4000, 2000), ground);
  }

  @override
  int get priority => -10;
}

/// O placă din faza de alegere — pătrat simplu, colorat după stare (neutru /
/// ales de mine / blocat fiindcă am ales alta).
class _PlatformComponent extends PositionComponent {
  final int index;
  bool selected = false;
  bool locked = false;
  bool chosen = false;

  _PlatformComponent({required this.index, required Vector2 position}) : super(position: position, size: Vector2(70, 24), anchor: Anchor.center);

  @override
  void render(Canvas canvas) {
    final color = chosen
        ? const Color(0xFF3DDC97)
        : selected
            ? const Color(0xFF5EC8F2)
            : const Color(0xFFB08D57);
    final paint = Paint()..color = locked && !chosen ? color.withAlpha(80) : color;
    final rect = Rect.fromCenter(center: Offset.zero, width: size.x, height: size.y);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), paint);
    if (selected || chosen) {
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), border);
    }
  }
}

/// Personajul controlat local, în faza de alegere — o siluetă simplă,
/// desenată procedural (fără sprite-uri), care abia se leagănă (idle).
class _PlayerRigComponent extends PositionComponent {
  final Color color;
  double _t = 0;

  _PlayerRigComponent({required this.color, required Vector2 position}) : super(position: position, size: Vector2(48, 66));

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
  }

  @override
  void render(Canvas canvas) {
    final bob = sin(_t * 2.4) * 2;
    final bounds = Rect.fromLTWH(0, bob, size.x, size.y);
    _paintSilhouette(canvas, bounds, color);
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

  _RunnerComponent({required this.data, required double startDepth}) : super(size: Vector2(46, 62), anchor: Anchor.center) {
    _depth = startDepth;
    // Poziția de start se pune din constructor, nu lăsată pe seama lerp-ului
    // din [update]: altfel primul cadru al scenei i-ar fi arătat pe toți la
    // linia de start, cu un salt vizibil imediat după.
    position.y = -startDepth * 900;
  }

  /// [jumpT] și [fallT] sunt 0..1 și se exclud reciproc — o rundă e ori
  /// săritură reușită, ori cădere, niciodată amândouă (vezi
  /// [ObbyRoundOutcome]).
  void setDepth(double depth, {double jumpT = 0, double fallT = 0}) {
    _depth = depth;
    _jumpT = jumpT;
    _fallT = fallT;
  }

  @override
  void update(double dt) {
    super.update(dt);
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

  @override
  void render(Canvas canvas) {
    final lift = sin(_jumpT.clamp(0, 1) * pi) * 44;
    final fade = 1 - _fallT;
    final alpha = (255 * fade).round().clamp(0, 255);
    final color = _fallT > 0 ? data.color.withAlpha(alpha) : data.color;

    // Umbra dispare de îndată ce personajul n-are pe ce s-o mai lase.
    if (_fallT < 0.05) {
      final shadowPaint = Paint()..color = Colors.black.withAlpha(90);
      canvas.drawOval(Rect.fromCenter(center: Offset(0, size.y / 2), width: size.x * 0.7, height: size.x * 0.25), shadowPaint);
    }

    canvas.save();
    if (_fallT > 0) canvas.rotate(_fallT * 0.9); // se răsucește cât cade
    final bounds = Rect.fromLTWH(-size.x / 2, -size.y / 2 - lift, size.x, size.y);
    _paintSilhouette(canvas, bounds, color);
    canvas.restore();

    if (fade > 0.15) {
      final tp = TextPainter(
        text: TextSpan(
          text: data.name,
          style: TextStyle(color: Colors.white.withAlpha(alpha), fontSize: 11, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 80);
      tp.paint(canvas, Offset(-tp.width / 2, -size.y / 2 - lift - tp.height - 2));
    }
  }
}

/// Solul din scena de reveal — o pistă simplă, cu marcaje la fiecare
/// obstacol, ca jucătorul să simtă distanța parcursă cât camera îl urmărește.
class _GroundComponent extends PositionComponent {
  @override
  void render(Canvas canvas) {
    final sky = Paint()..color = const Color(0xFF232A52);
    canvas.drawRect(const Rect.fromLTWH(-3000, -3000, 6000, 3000), sky);
    final ground = Paint()..color = const Color(0xFF1E4230);
    canvas.drawRect(const Rect.fromLTWH(-3000, -1200, 6000, 4200), ground);

    final railPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white.withAlpha(60);
    canvas.drawLine(const Offset(-90, 0), const Offset(-160, -1000), railPaint);
    canvas.drawLine(const Offset(90, 0), const Offset(160, -1000), railPaint);

    final markPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withAlpha(50);
    for (var i = 1; i <= obbyObstacleCount; i++) {
      final depth = i / obbyObstacleCount;
      final y = -depth * 900;
      final spread = 90 + (1 - depth) * 90;
      canvas.drawLine(Offset(-spread, y), Offset(spread, y), markPaint);
    }
  }

  @override
  int get priority => -10;
}

/// Desenul comun (cap rotund + corp capsulă + două picioare), la fel pentru
/// personajul din faza de alegere și pentru fiecare alergător din reveal.
void _paintSilhouette(Canvas canvas, Rect bounds, Color color) {
  final w = bounds.width;
  final h = bounds.height;
  final cx = bounds.center.dx;
  final top = bounds.top;

  final bodyPaint = Paint()..color = color;
  final headR = w * 0.24;
  final headCy = top + headR * 1.1;
  canvas.drawCircle(Offset(cx, headCy), headR, bodyPaint);

  final bodyTop = headCy + headR * 0.75;
  final bodyBottom = bounds.bottom - h * 0.18;
  final bodyRect = RRect.fromRectAndRadius(
    Rect.fromLTRB(cx - w * 0.22, bodyTop, cx + w * 0.22, bodyBottom),
    Radius.circular(w * 0.18),
  );
  canvas.drawRRect(bodyRect, bodyPaint);

  final legPaint = Paint()
    ..color = color
    ..strokeWidth = w * 0.14
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(Offset(cx - w * 0.07, bodyBottom - h * 0.02), Offset(cx - w * 0.09, bounds.bottom), legPaint);
  canvas.drawLine(Offset(cx + w * 0.07, bodyBottom - h * 0.02), Offset(cx + w * 0.09, bounds.bottom), legPaint);
}
