import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../core/obby.dart';
import '../core/stable_hash.dart';

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
/// **CAMERĂ COMUNĂ, NU INDIVIDUALĂ** — cerință explicită a userului: toți
/// jucătorii văd EXACT aceeași imagine, unul lângă altul în galaxie, tot
/// timpul. Singura excepție e [ObbyPhase.choosing], unde fiecare își vede
/// propriile trei plăci din care alege (acolo alegerea chiar e personală).
/// De-aia camera NU mai face `follow` pe personajul local, ci încadrează
/// întreg grupul — vezi [_frameGroup].
///
/// Trei scene, comutate prin [phase]:
///  - [ObbyPhase.choosing] — personajul local stă în fața celor
///    [obbyPlatformChoiceCount] bolovani; alegerea se face prin butoanele din
///    ecran sau prin tap direct pe bolovan. SINGURUL cadru individual.
///  - [ObbyPhase.waiting] — camera comună, toți stau nemișcați (idle) pe
///    platformele lor. Reutilizează EXACT construcția scenei de [revealed]
///    (vezi [_rebuildScene]): dacă toți alergătorii au
///    [ObbyRoundOutcome.none], nu se animă nimic.
///  - [ObbyPhase.revealed] — aceeași cameră comună, dar acum alergătorii
///    chiar sar/cad, cu rezultatul rundei.
///
/// Ecranul de întrebare NU mai ascunde scena: întrebarea și variantele se
/// desenează PESTE imaginea jucătorilor (vezi MultiplayerObbyScreen), tot la
/// cererea userului.
enum ObbyPhase { idle, choosing, waiting, revealed }

class ObbyGame extends FlameGame with TapCallbacks {
  final void Function(int platformIndex) onPlatformChosen;
  ObbyGame({required this.onPlatformChosen});

  ObbyPhase phase = ObbyPhase.idle;
  List<ObbyRacerData> _racers = const [];
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

  @override
  Future<void> onLoad() async {
    _world = World();
    _cam = CameraComponent(world: _world)..viewfinder.anchor = Anchor.center;
    addAll([_world, _cam]);
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Construcția amânată a scenei — vezi [applyRoundState]. Aici jocul e
    // garantat montat, deci [_world] chiar există.
    if (_needsRebuild) {
      _needsRebuild = false;
      _rebuildScene();
    }
    // Easing de zoom, cadru cu cadru — lerp exponențial spre țintă. Pragul
    // oprește urmărirea când diferența devine invizibilă, ca să nu rămână o
    // scriere pe viewfinder la fiecare cadru din meci.
    final z = _cam.viewfinder.zoom;
    if ((z - _targetZoom).abs() > 0.002) {
      _cam.viewfinder.zoom = z + (_targetZoom - z) * min(1.0, dt * 3.5);
    }
    // Aceeași idee pentru poziția camerei de grup (vezi [_frameGroup]).
    final gt = _groupTarget;
    if (gt != null) {
      final p = _cam.viewfinder.position;
      if ((p - gt).length > 0.5) {
        _cam.viewfinder.position = p + (gt - p) * min(1.0, dt * 3.0);
      } else {
        _groupTarget = null;
      }
    }
  }

  /// Apelat din StreamBuilder-ul ecranului la fiecare snapshot nou —
  /// singurul punct de intrare de date în joc. Idempotent: poate fi apelat
  /// de mai multe ori cu aceleași date fără efecte vizibile suplimentare.
  /// Cine sunt EU nu se mai ține aici: de când camera încadrează tot grupul
  /// (vezi [_frameGroup]), singurul lucru care depinde de asta e marcajul de
  /// deasupra propriului personaj, iar acela citește [ObbyRacerData.isMe],
  /// deja prezent pe fiecare alergător.
  void applyRoundState({
    required ObbyPhase phase,
    required List<ObbyRacerData> racers,
    int? myChoice,
    double revealT = 0,
  }) {
    _myChoice = myChoice;
    _revealT = revealT;

    // Se reconstruiește DOAR la schimbare de fază sau când se schimbă cine e
    // la masă. Progresul și deznodământul se aplică pe componentele deja
    // existente — o reconstrucție la fiecare snapshot ar fi retezat orice
    // animație în curs, iar Firestore trimite mai multe snapshot-uri în
    // timpul unui singur deznodământ.
    final rosterChanged = !_sameRoster(_racers, racers);
    _racers = racers;
    final phaseChanged = phase != this.phase;
    this.phase = phase;

    // BUG REPARAT: primele snapshot-uri Firestore ajung ÎNAINTE ca `onLoad`
    // să apuce să ruleze, iar [_world] e `late` — orice atingere a scenei
    // acolo arunca LateInitializationError. Cum `phase`/[_racers] se scriu
    // (corect) mai sus, apelurile următoare vedeau "nimic schimbat" și
    // scena nu se mai construia NICIODATĂ: ecran negru tot meciul, fără
    // nicio eroare vizibilă. De-aia intenția se ține într-un steag și se
    // aplică în [update], care rulează doar după ce jocul chiar e montat.
    if (phaseChanged || rosterChanged) _needsRebuild = true;
    if (!isLoaded) return;
    if (_needsRebuild) {
      _needsRebuild = false;
      _rebuildScene();
    } else if (phase == ObbyPhase.revealed) {
      _updateReveal();
    } else if (phase == ObbyPhase.choosing) {
      _updateChoosingHighlight();
    }
  }

  /// Scena trebuie (re)construită de îndată ce jocul e montat — vezi
  /// comentariul din [applyRoundState].
  bool _needsRebuild = false;

  /// De câte ori s-a construit efectiv scena. Există DOAR pentru test:
  /// „lumea are copii" nu se poate verifica în `flutter_test` (Flame amână
  /// montarea componentelor, deci `world.children` raportează 0 chiar și
  /// când în aplicația reală scena se vede), iar bug-ul care a produs
  /// ecranul negru era exact „construcția nu s-a întâmplat niciodată".
  @visibleForTesting
  int sceneBuilds = 0;

  bool _sameRoster(List<ObbyRacerData> a, List<ObbyRacerData> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _rebuildScene() {
    sceneBuilds++;
    _world.removeAll(_world.children.toList());
    _runners.clear();
    _rig = null;

    switch (phase) {
      case ObbyPhase.idle:
        break;
      case ObbyPhase.choosing:
        _buildChoosingScene();
        break;
      case ObbyPhase.waiting:
      case ObbyPhase.revealed:
        // Aceeași construcție de scenă pentru amândouă — diferența e DOAR în
        // date: [ObbyPhase.waiting] vine mereu cu toți alergătorii pe
        // [ObbyRoundOutcome.none] (vezi MultiplayerObbyScreen._feedGame),
        // deci [_updateReveal] nu are ce anima, doar îi ține pe loc.
        _buildRevealScene();
        break;
    }
  }

  // ─── Scena de alegere: personajul local + 3 bolovani în față ─────────────

  void _buildChoosingScene() {
    _cam.stop();
    _groupTarget = null;
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

  // ─── Scena de pistă: toți alergătorii, într-un cadru COMUN ──────────────

  void _buildRevealScene() {
    _world.add(_SpaceTrackComponent(starCount: 140));

    for (final r in _racers) {
      final runner = _RunnerComponent(data: r, startDepth: _lastDepth[r.id] ?? r.progress)
        ..position = Vector2(_laneXFor(r), 0);
      _runners[r.id] = runner;
      _world.add(runner);
    }

    // Camera NU mai urmărește un personaj anume — vezi comentariul de la
    // [ObbyPhase]. `stop()` e obligatoriu: dacă rămâne un `follow` dintr-o
    // rundă anterioară, el rescrie poziția viewfinder-ului la fiecare cadru
    // și încadrarea de grup n-ar avea niciun efect vizibil.
    _cam.stop();
    _frameGroup(instant: !_cameraEverAttached);
    _cameraEverAttached = true;
    _updateReveal();
  }

  /// Încadrează TOT grupul: camera se așază pe centrul de greutate al
  /// alergătorilor și dă zoom cât să încapă toți, și pe lățime (culoarele) și
  /// pe adâncime (diferența de progres dintre primul și ultimul).
  ///
  /// Rulează pe adâncimile de la ÎNCEPUTUL rundei (pozițiile reale ale
  /// componentelor), nu pe cele de la final: altfel cadrul ar fi sărit brusc
  /// în clipa în care ajunge rezultatul din Firestore, adică exact înainte de
  /// animația pe care jucătorul trebuie s-o vadă.
  void _frameGroup({bool instant = false}) {
    if (_runners.isEmpty) return;
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final r in _runners.values) {
      minX = min(minX, r.position.x);
      maxX = max(maxX, r.position.x);
      minY = min(minY, r.position.y);
      maxY = max(maxY, r.position.y);
    }
    // Marja lasă loc numelor de deasupra capetelor și platformelor de dedesubt,
    // plus spațiu pentru arcul săriturii (care urcă vizibil peste cap).
    const marginX = 150.0;
    const marginY = 210.0;
    final w = (maxX - minX) + marginX * 2;
    final h = (maxY - minY) + marginY * 2;
    final target = Vector2((minX + maxX) / 2, (minY + maxY) / 2);
    // Dimensiunea logică a ecranului; la primul cadru poate fi încă zero.
    final view = _cam.viewport.size;
    if (view.x > 0 && view.y > 0) {
      final fit = min(view.x / w, view.y / h);
      _setZoom(fit.clamp(0.35, 1.15), instant: instant);
    }
    if (instant) {
      _cam.viewfinder.position = target;
    } else {
      _groupTarget = target;
    }
  }

  /// Unde vrea camera de grup să ajungă — urmărit lin în [update], nu scris
  /// direct: un salt de cadru între două runde se citește ca o tăietură de
  /// montaj, nu ca o mișcare de cameră.
  Vector2? _groupTarget;

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
    _rockPath = buildObbyRockPath(rng, size.x, size.y);
    _craters = List.generate(3, (i) {
      final a = rng.nextDouble() * pi * 2;
      final r = size.x * (0.12 + rng.nextDouble() * 0.16);
      return Offset(cos(a) * r, sin(a) * r * 0.6);
    });
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

  /// Platforma de sub picioare — solidă cât timp stau pe ea, spartă în
  /// cioburi ([_shards]) cât cad. Formă proprie fiecărui jucător (sămânța
  /// vine din [data.id]), ca pista să nu arate cu bolovani identici,
  /// copiați, sub fiecare alergător.
  final Paint _platformFillPaint = Paint()..color = const Color(0xFF9C8A73);
  final Paint _platformRimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..color = Colors.white24;
  late final Path _platformPath;
  late final List<_PlatformShard> _shards;

  _RunnerComponent({required this.data, required double startDepth}) : super(size: Vector2(46, 62), anchor: Anchor.center) {
    _depth = startDepth;
    // Poziția de start se pune din constructor, nu lăsată pe seama lerp-ului
    // din [update]: altfel primul cadru al scenei i-ar fi arătat pe toți la
    // linia de start, cu un salt vizibil imediat după.
    position.y = -startDepth * 900;
    // StableRandom: forma bolovanului trebuie sa fie aceeasi pentru toti cei
    // care se uita la acelasi jucator, indiferent de platforma.
    final rng = StableRandom(stableHash(data.id));
    _platformPath = buildObbyRockPath(rng, 78, 30);
    _shards = _buildObbyPlatformShards(rng);
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

  /// "Pe pământ" = nu e la mijlocul unui arc de săritură — fie stă pe loc
  /// (idle/waiting), fie tocmai a aterizat, fie cade (o cădere nu trece
  /// niciodată prin [_jumpT], vezi [setDepth]). DOAR în starea asta se
  /// desenează o platformă sub picioare: în plin arc de săritură, personajul
  /// e în aer, între două platforme, deci n-are pe ce sta.
  bool get _grounded => _jumpT <= 0.05 || _jumpT >= 0.95;

  /// Coregrafia unei sărituri, pe fracțiuni din [_jumpT] — un salt real are
  /// patru momente distincte, nu doar un arc: te ghemuiești (încarci),
  /// împingi, zbori strâns, aterizezi și te turtești o clipă. Fără pasul de
  /// ghemuire, personajul „țâșnea" din poziție dreaptă și arăta ca un obiect
  /// mutat, nu ca un corp care sare.
  static const _crouchEnd = 0.18; // se ghemuiește (încarcă)
  static const _airborneEnd = 0.82; // e în aer
  static const _squashEnd = 0.94; // se turtește la aterizare

  /// Cât de ghemuit e personajul acum: 1 = complet ghemuit, 0 = drept.
  /// Se folosește ȘI la încărcarea săriturii, ȘI la turtirea de aterizare —
  /// aceeași deformare, în două momente diferite.
  double get _crouchAmount {
    if (_jumpT <= 0) return 0;
    if (_jumpT < _crouchEnd) {
      // 0 → 1 pe măsură ce se lasă pe vine
      return (_jumpT / _crouchEnd).clamp(0.0, 1.0);
    }
    if (_jumpT < _airborneEnd) {
      // în aer: se întinde (0), cu o urmă de „tuck" la mijlocul zborului
      final airT = (_jumpT - _crouchEnd) / (_airborneEnd - _crouchEnd);
      return sin(airT * pi) * 0.25;
    }
    if (_jumpT < _squashEnd) {
      // impactul cu placa: turtire scurtă și adâncă
      return 1 - ((_jumpT - _airborneEnd) / (_squashEnd - _airborneEnd)) * 0.15;
    }
    // revenire lină în picioare
    return (1 - (_jumpT - _squashEnd) / (1 - _squashEnd)).clamp(0.0, 1.0) * 0.85;
  }

  /// Înălțimea la care e personajul în arcul săriturii. Zero cât se
  /// ghemuiește (încă e pe placă) și zero după aterizare — ridicarea are loc
  /// STRICT în intervalul de zbor, altfel „decolează" înainte să împingă.
  double get _jumpLift {
    if (_jumpT <= _crouchEnd || _jumpT >= _airborneEnd) return 0;
    final airT = (_jumpT - _crouchEnd) / (_airborneEnd - _crouchEnd);
    return sin(airT * pi) * 58;
  }

  @override
  void render(Canvas canvas) {
    if (_finishedThisJump && _jumpT >= 0.999) {
      _paintShuttle(canvas);
      return;
    }

    if (_grounded) _paintPlatform(canvas);

    final lift = _jumpLift;
    final crouch = _crouchAmount;
    // Legănat abia vizibil cât stau pe loc (idle/waiting) — altfel scena de
    // așteptare pare o fotografie, nu un personaj viu. Se stinge automat de
    // îndată ce sare sau cade.
    final idleBob = (_jumpT <= 0 && _fallT <= 0) ? sin(_time * 2.2) * 2.5 : 0.0;
    // Balans lateral cât cade — o cădere perfect verticală, fără nicio
    // abatere, se citește ca un obiect țeapăn, nu ca un corp care își pierde
    // echilibrul.
    final fallWobble = _fallT > 0 ? sin(_fallT * 9) * (1 - _fallT) * 7 : 0.0;
    // Picioarele se depărtează în aer (elan) și se strâng la aterizare.
    final legSpread = (_jumpT > _crouchEnd && _jumpT < _airborneEnd)
        ? sin(((_jumpT - _crouchEnd) / (_airborneEnd - _crouchEnd)) * pi) * 0.9
        : (_fallT > 0 ? sin(_fallT * 14) * 0.6 : 0.0); // dă din picioare cât cade
    final fade = 1 - _fallT;
    final alpha = (255 * fade).round().clamp(0, 255);
    _bodyPaint.color = _fallT > 0 ? data.color.withAlpha(alpha) : data.color;

    // Umbra dispare de îndată ce personajul n-are pe ce s-o mai lase, și se
    // micșorează cât e sus în aer — indiciul care face înălțimea lizibilă.
    if (_fallT < 0.05) {
      final shadowShrink = 1 - (lift / 58) * 0.55;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, size.y / 2),
          width: size.x * 0.7 * shadowShrink,
          height: size.x * 0.25 * shadowShrink,
        ),
        _shadowPaint..color = Colors.black.withAlpha((90 * shadowShrink).round().clamp(0, 255)),
      );
    }

    canvas.save();
    canvas.translate(fallWobble, 0);
    // Se răsucește tot mai repede cât cade — o rotație liniară arăta ca o
    // piesă care se învârte constant, nu ca cineva care se prăbușește.
    if (_fallT > 0) canvas.rotate(_fallT * _fallT * 2.2);
    final bounds = Rect.fromLTWH(-size.x / 2, -size.y / 2 - lift - idleBob, size.x, size.y);
    paintObbyAstronaut(canvas, bounds, _bodyPaint.color, legSpread: legSpread, crouch: crouch);
    canvas.restore();

    // Marcaj deasupra propriului personaj — de când camera încadrează tot
    // grupul (nu mai urmărește pe nimeni anume), fără el nu-ți mai găseai
    // rapid personajul între ceilalți.
    if (data.isMe && fade > 0.15) {
      final markY = -size.y / 2 - lift - idleBob - 16;
      final path = Path()
        ..moveTo(-5, markY - 6)
        ..lineTo(5, markY - 6)
        ..lineTo(0, markY)
        ..close();
      canvas.drawPath(path, Paint()..color = Colors.white.withAlpha(alpha));
    }

    if (fade > 0.15) {
      if (_nameTpFor != data.name) {
        _nameTp = _buildNameTp();
        _nameTpFor = data.name;
      }
      final tp = _nameTp!;
      final offset = Offset(fallWobble - tp.width / 2, -size.y / 2 - lift - idleBob - tp.height - 18);
      if (fade < 0.999) {
        canvas.saveLayer(null, Paint()..color = Colors.white.withAlpha(alpha));
        tp.paint(canvas, offset);
        canvas.restore();
      } else {
        tp.paint(canvas, offset);
      }
    }
  }

  /// Platforma de sub picioare — solidă cât timp nu cad ([_fallT] == 0),
  /// spartă în [_shards] care zboară și se sting pe măsură ce [_fallT]
  /// crește. Sincronizată cu momentul în care personajul chiar începe să
  /// cadă (aceeași variabilă, [_fallT]), ca placa să cedeze EXACT când
  /// personajul dispare prin ea, nu înainte sau după.
  void _paintPlatform(Canvas canvas) {
    final platformY = size.y * 0.44;
    if (_fallT <= 0.001) {
      canvas.save();
      canvas.translate(0, platformY);
      canvas.drawPath(_platformPath, _platformFillPaint);
      canvas.drawPath(_platformPath, _platformRimPaint);
      canvas.restore();
      return;
    }
    final t = _fallT.clamp(0.0, 1.0);
    final alpha = (255 * (1 - t)).round().clamp(0, 255);
    final shardColor = const Color(0xFF9C8A73).withAlpha(alpha);
    for (final s in _shards) {
      canvas.save();
      canvas.translate(s.dirX * t * 70, platformY + s.dirY * t * 50 + t * t * 90);
      canvas.rotate(s.rotSpeed * t);
      canvas.drawPath(s.path, _platformFillPaint..color = shardColor);
      canvas.restore();
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

/// Conturul stâncos comun oricărui bolovan de asteroid din joc — folosit
/// atât de bolovanii din scena de alegere ([_AsteroidComponent]), cât și de
/// platforma de sub picioarele fiecărui alergător din scena de pistă
/// ([_RunnerComponent]), ca cele două să arate ca aceeași "materie", nu ca
/// două desene neînrudite.
Path buildObbyRockPath(Random rng, double w, double h) {
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

/// O bucată din platforma care cedează sub un alergător care cade — vezi
/// [_RunnerComponent._paintPlatform]. [dirX]/[dirY] sunt direcția în care
/// zboară bucata (normalizată informal, nu strict unitară), [rotSpeed] cât
/// se rotește pe măsură ce se depărtează.
class _PlatformShard {
  final Path path;
  final double dirX, dirY, rotSpeed;
  const _PlatformShard(this.path, this.dirX, this.dirY, this.rotSpeed);
}

/// Sparge platforma în câteva cioburi zimțate, aruncate în direcții
/// diferite — nu e o simplă tăiere geometrică a formei reale (inutil de
/// complicat pentru un efect cosmetic local, care n-are nevoie să fie
/// determinist între clienți, vezi comentariul de mai jos), ci bucăți noi,
/// mici, care doar SUGEREAZĂ spargerea.
List<_PlatformShard> _buildObbyPlatformShards(Random rng) {
  const count = 6;
  return List.generate(count, (i) {
    final angle = (i / count) * pi * 2 + rng.nextDouble() * 0.5;
    final w = 12 + rng.nextDouble() * 10;
    final h = 8 + rng.nextDouble() * 7;
    final path = Path()
      ..moveTo(-w / 2, -h / 2)
      ..lineTo(w / 2, -h / 3)
      ..lineTo(w / 3, h / 2)
      ..lineTo(-w / 3, h / 3)
      ..close();
    return _PlatformShard(path, cos(angle), sin(angle) * 0.6, (rng.nextBool() ? 1 : -1) * (2 + rng.nextDouble() * 3));
  });
}

/// Desenul comun al astronautului (cască + vizor + rucsac + corp + picioare
/// îndoite din genunchi + brațe) — folosit atât pentru personajul din scena
/// de alegere/pistă, cât și pentru cel din colțul ecranului.
///
/// [legSpread] depărtează picioarele (mers/elan în aer), [crouch] (0..1)
/// GHEMUIEȘTE efectiv personajul: corpul coboară și se turtește, genunchii
/// se îndoaie în afară, brațele se duc în spate ca la o încărcare de
/// săritură. Nu mai e o simplă coborâre de câțiva pixeli ca înainte — de
/// asta depinde acum tot începutul și sfârșitul unei sărituri (vezi
/// [_RunnerComponent._crouchAmount]).
void paintObbyAstronaut(Canvas canvas, Rect bounds, Color suitColor, {double legSpread = 0, double crouch = 0}) {
  final w = bounds.width;
  final h = bounds.height;
  final cx = bounds.center.dx;
  final c = crouch.clamp(0.0, 1.0);
  // Ghemuirea scurtează silueta pe verticală: capul coboară vizibil, iar
  // trunchiul se comprimă — exact ce face un corp care încarcă o săritură.
  final top = bounds.top + h * c * 0.26;

  final backpackPaint = Paint()..color = Color.lerp(suitColor, Colors.black, 0.4)!;
  final suitPaint = Paint()..color = suitColor;
  final limbPaint = Paint()
    ..color = Color.lerp(suitColor, Colors.black, 0.18)!
    ..strokeWidth = w * 0.15
    ..strokeCap = StrokeCap.round;
  final helmetPaint = Paint()..color = const Color(0xFFE8ECF2);
  final visorPaint = Paint()..color = const Color(0xFF12141C);
  final highlightPaint = Paint()..color = Colors.white70;

  final headR = w * 0.26;
  final headCy = top + headR * 1.05;

  final bodyTop = headCy + headR * 0.7;
  // Talpa rămâne pe loc (personajul nu "plutește" când se ghemuiește), doar
  // șoldul urcă spre ea.
  final footY = bounds.bottom;
  final bodyBottom = bounds.bottom - h * 0.2 + c * h * 0.12;

  // Rucsacul stă în spatele corpului, deci se desenează primul.
  final backpackRect = RRect.fromRectAndRadius(
    Rect.fromLTRB(cx - w * 0.16, bodyTop + h * 0.02, cx + w * 0.16, bodyBottom - h * 0.04),
    Radius.circular(w * 0.08),
  );
  canvas.drawRRect(backpackRect, backpackPaint);

  // Picioarele au acum un GENUNCHI: două segmente, nu o linie dreaptă.
  // Genunchiul iese în afară cu cât e mai ghemuit — silueta „în Z" e ce
  // face diferența dintre un stickman care sare și unul care alunecă.
  final hipY = bodyBottom - h * 0.02;
  final kneeOut = w * (0.10 + c * 0.30);
  final kneeY = hipY + (footY - hipY) * (0.52 - c * 0.10);
  for (final side in [-1.0, 1.0]) {
    final hipX = cx + side * w * 0.07;
    final kneeX = cx + side * (w * 0.07 + kneeOut);
    final footX = cx + side * (w * 0.09 + legSpread * w * 0.2);
    canvas.drawLine(Offset(hipX, hipY), Offset(kneeX, kneeY), limbPaint);
    canvas.drawLine(Offset(kneeX, kneeY), Offset(footX, footY), limbPaint);
  }

  final bodyRect = RRect.fromRectAndRadius(
    Rect.fromLTRB(cx - w * 0.24, bodyTop, cx + w * 0.24, bodyBottom),
    Radius.circular(w * 0.2),
  );
  canvas.drawRRect(bodyRect, suitPaint);

  // Brațele: în spate cât se încarcă săritura, ridicate în aer cât zboară
  // (legSpread e mare doar în zbor, vezi apelantul).
  final shoulderY = bodyTop + h * 0.10;
  final armSwing = c * 0.9 - legSpread * 0.5;
  for (final side in [-1.0, 1.0]) {
    final shoulderX = cx + side * w * 0.20;
    final handX = shoulderX + side * w * 0.16;
    final handY = shoulderY + h * (0.16 - armSwing * 0.20);
    canvas.drawLine(Offset(shoulderX, shoulderY), Offset(handX, handY), limbPaint);
  }

  // Casca acoperă corpul de sus, cu vizorul suprapus și un mic reflex de
  // sticlă — asta desparte "astronaut" de silueta generică cu cap rotund.
  canvas.drawCircle(Offset(cx, headCy), headR, helmetPaint);
  canvas.drawOval(
    Rect.fromCenter(center: Offset(cx + headR * 0.08, headCy), width: headR * 1.25, height: headR * 1.5),
    visorPaint,
  );
  canvas.drawCircle(Offset(cx - headR * 0.28, headCy - headR * 0.3), headR * 0.16, highlightPaint);
}
