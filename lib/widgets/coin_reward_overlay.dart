import 'dart:math';
import 'dart:ui' show PathMetric;
import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Câte copii ale iconiței formează șirul, pentru o recompensă de [amount] —
/// plafonat la [_maxTrailUnits] indiferent cât de mare e recompensa reală
/// (ex. bonus de sesiune). Extrasă ca funcție separată ca să rămână
/// testabilă: cauza reală a bug-ului "traseu invizibil" la 6 simboluri a
/// fost rotația+umbra blur desenate PE FIECARE iconiță (eliminate între
/// timp, vezi [_CoinRewardAnimationState]), dar plafonul de mai jos e
/// singura parte din reparație care mai poate regresa silențios — dacă
/// cineva îl ridică peste ce s-a verificat vizual ca sigur, sau îl scoate.
int trailUnitCount(int amount) => amount.clamp(1, _maxTrailUnits);
const _maxTrailUnits = 5;

/// Animația de recompensă: un praf magic (scântei) explodează EXACT din
/// centrul ecranului, dezvăluie simbolurile recompensei, care apoi zboară în
/// "șir indian" (vezi [_maxTrailUnits]) pe UN SINGUR traseu de tip slalom
/// (vezi [_ensurePath]) spre [targetKey], cu o dâră care arată traseul și un
/// mic "pop" la impact. La impact apare "+cantitate" sub pastila țintă, ținut la opacitate maximă
/// destul cât să fie citit clar, apoi se stinge cu un fade out lent (vezi
/// [_buildPlusPhase]) — feedback-ul jucătorului: fără cifra asta clar
/// vizibilă la impact, nu se știe exact cât s-a primit. [onImpact] e apelat
/// exact în momentul impactului — locul potrivit să reîncarci balanța, ca
/// numărul din pastilă să se actualizeze sincron cu animația, nu înainte.
/// [icon]/[color] implicite (monedă) — orice alt apelant poate arăta un alt
/// tip de recompensă (XP, vieți, gems, hints) fără să schimbe nimic
/// altundeva. Aceeași animație pentru toate tipurile de recompensă — nu mai
/// există o variantă "simplă" separată.
class CoinRewardOverlay {
  static void show(
    BuildContext context, {
    required int amount,
    required GlobalKey targetKey,
    VoidCallback? onImpact,
    VoidCallback? onFinished,
    IconData icon = Icons.monetization_on_rounded,
    Color? color,
    Duration flightDuration = const Duration(milliseconds: 1650),
  }) {
    final resolvedColor = color ?? AppColors.coin;
    final overlay = Overlay.of(context);
    final renderBox = targetKey.currentContext?.findRenderObject() as RenderBox?;
    final targetOffset = renderBox != null
        ? renderBox.localToGlobal(renderBox.size.center(Offset.zero))
        : Offset(MediaQuery.of(context).size.width - 50, 70);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _CoinRewardAnimation(
        amount: amount,
        target: targetOffset,
        icon: icon,
        color: resolvedColor,
        flightDuration: flightDuration,
        onImpact: onImpact,
        onRemove: () {
          entry.remove();
          onFinished?.call();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _CoinRewardAnimation extends StatefulWidget {
  final int amount;
  final Offset target;
  final IconData icon;
  final Color color;
  final Duration flightDuration;
  final VoidCallback? onImpact;
  final VoidCallback onRemove;

  const _CoinRewardAnimation({
    required this.amount,
    required this.target,
    required this.icon,
    required this.color,
    required this.flightDuration,
    required this.onRemove,
    this.onImpact,
  });

  @override
  State<_CoinRewardAnimation> createState() => _CoinRewardAnimationState();
}

class _CoinRewardAnimationState extends State<_CoinRewardAnimation> with TickerProviderStateMixin {
  late final AnimationController _flight;
  late final AnimationController _plus;
  late final AnimationController _trailBurn;
  bool _impactFired = false;

  // ─── Dâra "fitil ars" după impact ──────────────────────────────────────
  // Fără asta, dâra desenată de [_TrailPainter] rămâne întinsă, statică, pe
  // ecran cât ține toată faza "+cantitate" (vezi [_plusDuration]), apoi
  // dispare brusc odată cu tot overlay-ul. În loc de asta, imediat după
  // impact, segmentul rămas se "arde" rapid dinspre coadă spre cap — ca un
  // fitil aprins — cu o scânteie la capătul care arde (vezi [_TrailPainter]).
  // Independent de [_plus] (acela ține "+cantitate" mult mai mult timp).
  static const _trailBurnDuration = Duration(milliseconds: 380);

  static const _dustAngles = [15.0, 55.0, 95.0, 135.0, 175.0, 215.0, 255.0, 295.0, 335.0];

  // ─── Modul "șir indian" ────────────────────────────────────────────────
  // Câte copii ale iconiței formează șirul — plafonat, ca un reward mare
  // (ex. bonus de sesiune) să nu trimită un tren de 20 de inimi deodată.
  // Fiecare unitate parcurge ÎNTREGUL traseu comun (vezi [_ensurePath]) pe
  // propria ei fereastră de timp, eșalonate cu [_staggerStep] — ferestrele
  // se suprapun mult (durata unei curse > decalajul dintre start-uri), deci
  // la orice moment sunt mai multe vizibile simultan, înșirate pe traseu,
  // nu doar una singură. Fără rotație+umbră blur PE FIECARE (asta a fost
  // cauza reală a bug-ului "traseu invizibil" de mai sus la 6 simboluri) —
  // traseul vizibil vine din dâra desenată cu [_TrailPainter] (UN singur
  // Path desenat per cadru, indiferent câte inimi zboară), nu din umbre.
  static const _trailUnitWindow = 0.5;
  static const _trailBurstEnd = 0.30;

  PathMetric? _cachedMetric;
  Offset? _cachedPathCenter;

  // ─── Faza "+cantitate" de sub pastilă (după impact) ────────────────────
  // Durata totală + fracțiunile de mai jos controlează comportamentul cerut:
  // apare, RĂMÂNE clar vizibilă câteva secunde (destul să citești cifra),
  // apoi un fade out lin, nu unul brusc.
  static const _plusDuration = Duration(milliseconds: 2400);
  static const _plusFadeInEnd = 0.08;
  static const _plusHoldEnd = 0.62;

  int get _trailUnitCount => trailUnitCount(widget.amount);

  double get _staggerStep {
    final n = _trailUnitCount;
    return n > 1 ? (1.0 - _trailBurstEnd - _trailUnitWindow) / (n - 1) : 0.0;
  }

  /// Progresul LOCAL (0..1) al unității [i] pe traseul ei — 0 înainte să-i
  /// vină rândul, 1 odată ajunsă. Unitatea 0 e mereu "capul" șirului.
  double _unitLocalT(int i, double t) {
    final start = _trailBurstEnd + i * _staggerStep;
    if (t <= start) return 0.0;
    return ((t - start) / _trailUnitWindow).clamp(0.0, 1.0);
  }

  /// Construiește traseul comun O SINGURĂ DATĂ (nu la fiecare cadru) — pleacă
  /// EXACT din centrul ecranului (nu dintr-un punct "împrăștiat" lângă el, ca
  /// înainte) și face un "slalom" ca la ski până la pastila țintă: o
  /// oscilație laterală sinusoidală ([_slalomGates] schimbări de sens) a
  /// cărei amplitudine se stinge liniar spre 0 pe măsură ce se apropie de
  /// țintă, ca traiectoria să "aterizeze" curat pe pastilă, nu să oscileze
  /// peste ea. Eșantionată din multe segmente drepte scurte (ca la
  /// [_EnergyWavePainter._wavePath]) — cu destule puncte, arată la fel de
  /// neted ca o curbă, fără să mai fie nevoie de Bezier.
  static const _slalomGates = 3;
  static const _slalomSteps = 48;

  void _ensurePath(Offset center) {
    if (_cachedPathCenter == center && _cachedMetric != null) return;
    final delta = widget.target - center;
    final dist = delta.distance;
    final dir = dist > 0 ? delta / dist : const Offset(1, 0);
    final perp = Offset(-dir.dy, dir.dx);
    final amplitude = (dist * 0.14).clamp(18.0, 46.0);

    final path = Path()..moveTo(center.dx, center.dy);
    for (var i = 1; i <= _slalomSteps; i++) {
      final f = i / _slalomSteps;
      final along = center + delta * f;
      final wave = sin(f * pi * _slalomGates) * amplitude * (1 - f);
      final p = along + perp * wave;
      path.lineTo(p.dx, p.dy);
    }
    _cachedMetric = path.computeMetrics().first;
    _cachedPathCenter = center;
  }

  @override
  void initState() {
    super.initState();
    _flight = AnimationController(vsync: this, duration: widget.flightDuration)
      ..addListener(_maybeFireImpact)
      ..forward();
    // faza de "+cantitate" e scurtă și fixă — nu trebuie să se scaleze cu
    // durata zborului, altfel ținta întârzie inutil de mult să se simtă
    // "gata". Duratele interne (vezi _buildPlusPhase) sunt gândite ca
    // fracțiuni din [_plusDuration]: apariție rapidă, ținută vizibilă mult
    // mai mult timp (ca să fie clar citibilă), apoi un fade out lent.
    _plus = AnimationController(vsync: this, duration: _plusDuration);
    _trailBurn = AnimationController(vsync: this, duration: _trailBurnDuration);
    _flight.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _plus.forward();
        _trailBurn.forward();
      }
    });
    _plus.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onRemove();
    });
  }

  /// Balanța se actualizează la sosirea PRIMEI unități (capul șirului), nu la
  /// a ultimei — răspuns vizual imediat, restul șirului rămâne doar spectacol.
  void _maybeFireImpact() {
    if (_impactFired) return;
    final fired = _unitLocalT(0, _flight.value) >= 0.98;
    if (fired) {
      _impactFired = true;
      widget.onImpact?.call();
    }
  }

  @override
  void dispose() {
    _flight.dispose();
    _plus.dispose();
    _trailBurn.dispose();
    super.dispose();
  }

  static Color _withOpacity(Color c, double factor) => c.withAlpha((c.a * 255 * factor.clamp(0.0, 1.0)).round());

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final center = Offset(size.width / 2, size.height * 0.4);

    // RepaintBoundary izolează animația (până la ~18 iconițe/scântei/simboluri
    // "+" simultan) de restul arborelui de sub ea, ca ecranul din spate să nu
    // se re-picteze inutil la fiecare cadru cât zboară recompensa.
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_flight, _trailBurn]),
              builder: (context, _) => _buildFlightPhase(center),
            ),
            AnimatedBuilder(
              animation: _plus,
              builder: (context, _) => _buildPlusPhase(),
            ),
          ],
        ),
      ),
    );
  }

  /// Faza de zbor "șir indian" — vezi comentariul de pe [_maxTrailUnits]:
  /// explozie de praf din centru, apoi o dâră (traseul deja parcurs de capul
  /// șirului) urmată de până la [_trailUnitCount] iconițe eșalonate pe UNUL
  /// SINGUR traseu explicit (slalom, vezi [_ensurePath]).
  Widget _buildFlightPhase(Offset center) {
    _ensurePath(center);
    final t = _flight.value;
    final dustBurst = Interval(0.0, 0.4, curve: Curves.easeOut).transform(t.clamp(0, 1));
    final dustFade = 1 - Interval(0.15, 0.45).transform(t.clamp(0, 1));
    final n = _trailUnitCount;
    final leadLocal = _unitLocalT(0, t);
    final burnT = _trailBurn.value;

    return Stack(
      children: [
        if (dustFade > 0)
          for (var i = 0; i < _dustAngles.length; i++) _buildDustSpark(i, center, dustBurst, dustFade),
        if (leadLocal > 0 && burnT < 1) _buildTrailStreak(leadLocal, burnT),
        for (var i = 0; i < n; i++) _buildTrailUnit(i, t),
      ],
    );
  }

  /// Dâra care face traseul EFECTIV vizibil — un singur [Path] (porțiunea
  /// deja parcursă de capul șirului), desenat cu un gradient care se stinge
  /// spre coadă, ca o cometă. Cost fix per cadru (un draw call), indiferent
  /// de câte iconițe zboară — spre deosebire de o umbră blur pe fiecare.
  /// După impact, [burnT] (vezi [_trailBurn]) taie progresiv capătul dinspre
  /// coadă — traseul desenat se scurtează dinspre coadă spre cap, ca un
  /// fitil care arde, în loc să rămână întins static pe ecran.
  Widget _buildTrailStreak(double leadLocal, double burnT) {
    final metric = _cachedMetric;
    if (metric == null) return const SizedBox.shrink();
    final headDist = (metric.length * leadLocal).clamp(0.0, metric.length);
    final burnDist = (headDist * burnT).clamp(0.0, headDist);
    final tail = metric.getTangentForOffset(burnDist)?.position;
    final head = metric.getTangentForOffset(headDist)?.position;
    if (tail == null || head == null) return const SizedBox.shrink();
    return CustomPaint(
      size: Size.infinite,
      painter: _TrailPainter(
        path: metric.extractPath(burnDist, headDist),
        tail: tail,
        head: head,
        color: widget.color,
        emberT: burnT,
      ),
    );
  }

  /// O singură "mărgea" a șirului: poziția vine STRICT de pe [_cachedMetric]
  /// (același traseu ca dâra de mai sus, nu un calcul separat) — garantează
  /// că iconițele chiar stau PE dâră, nu doar lângă ea. Rotație continuă
  /// (ieftină, o simplă transformare), FĂRĂ umbră blur — vezi motivul din
  /// comentariul de pe [_maxTrailUnits].
  Widget _buildTrailUnit(int i, double t) {
    final local = _unitLocalT(i, t);
    final metric = _cachedMetric;
    if (metric == null || local <= 0) return const SizedBox.shrink();

    final eased = Curves.easeInOutCubic.transform(local);
    final dist = (metric.length * eased).clamp(0.0, metric.length);
    final pos = metric.getTangentForOffset(dist)?.position;
    if (pos == null) return const SizedBox.shrink();

    // mic "pop" la sosire — nu se micșorează liniar tot drumul, trece puțin
    // peste scara 1 chiar înainte de impact.
    final pop = local > 0.85 ? sin((local - 0.85) / 0.15 * pi) * 0.35 : 0.0;
    final shrink = Curves.easeIn.transform(local) * 0.5;
    final scale = (1 - shrink + pop).clamp(0.0, 1.5);
    final opacity = local < 0.08 ? local / 0.08 : (local > 0.92 ? ((1 - local) / 0.08).clamp(0.0, 1.0) : 1.0);
    final spin = local * 4 * pi + i * 0.7;

    return Positioned(
      left: pos.dx - 15,
      top: pos.dy - 15,
      child: Transform.rotate(
        angle: spin,
        child: Transform.scale(
          scale: scale,
          child: Icon(widget.icon, color: _withOpacity(widget.color, opacity), size: 30),
        ),
      ),
    );
  }

  Widget _buildDustSpark(int i, Offset center, double burstT, double fade) {
    final angle = _dustAngles[i] * pi / 180;
    final dist = 18 + burstT * 46;
    final pos = center + Offset(cos(angle), sin(angle)) * dist;
    return Positioned(
      left: pos.dx - 4,
      top: pos.dy - 4,
      child: Icon(
        Icons.auto_awesome_rounded,
        color: _withOpacity(Colors.white.withAlpha(230), fade),
        size: 8 + burstT * 4,
      ),
    );
  }

  /// "+cantitate" sub pastila țintă — apare imediat după impact, rămâne la
  /// opacitate maximă un timp bun (ca să fie clar citibil cât s-a primit),
  /// apoi se stinge cu un fade out lin. Vezi constantele [_plusDuration]/
  /// [_plusFadeInEnd]/[_plusHoldEnd] pentru cum se împarte durata.
  Widget _buildPlusPhase() {
    if (_flight.status != AnimationStatus.completed) return const SizedBox.shrink();
    final t = _plus.value;
    final opacity = t < _plusFadeInEnd
        ? t / _plusFadeInEnd
        : t < _plusHoldEnd
            ? 1.0
            : 1 - ((t - _plusHoldEnd) / (1 - _plusHoldEnd));
    final o = opacity.clamp(0.0, 1.0);
    if (o <= 0) return const SizedBox.shrink();
    // ușoară apropiere de pastilă pe durata fade-in-ului, apoi stă pe loc.
    final settle = 1 - Interval(0.0, _plusFadeInEnd).transform(t.clamp(0.0, 1.0));
    return Positioned(
      left: widget.target.dx - 70,
      top: widget.target.dy + 20 + settle * 8,
      width: 140,
      child: Center(
        child: Text(
          '+${widget.amount}',
          style: TextStyle(
            color: _withOpacity(widget.color, o),
            fontSize: 20,
            fontWeight: FontWeight.w900,
            shadows: [Shadow(color: Colors.black.withAlpha((180 * o).round()), blurRadius: 5)],
          ),
        ),
      ),
    );
  }
}

/// Desenează porțiunea de traseu deja parcursă de capul șirului, ca o dâră
/// tip cometă — un gradient liniar de la transparent (coadă) la culoarea
/// recompensei (cap), pe un singur [Path]. Un singur draw call per cadru:
/// asta e mecanismul prin care traseul e "vizibil" pentru jucător, în loc
/// să fie doar implicit din poziția iconițelor. După impact, [tail] e chiar
/// punctul unde "arde" fitilul (vezi [_CoinRewardAnimationState._buildTrailStreak]),
/// nu mai capătul fix al traseului — [emberT] (0 înainte de impact, →1 cât
/// se stinge dâra) desenează acolo o mică scânteie alb-caldă, ca vârful unui
/// fitil aprins care tocmai a mistuit acea porțiune.
class _TrailPainter extends CustomPainter {
  final Path path;
  final Offset tail;
  final Offset head;
  final Color color;
  final double emberT;
  const _TrailPainter({
    required this.path,
    required this.tail,
    required this.head,
    required this.color,
    this.emberT = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(colors: [color.withAlpha(0), color.withAlpha(190)])
          .createShader(Rect.fromPoints(tail, head));
    canvas.drawPath(path, paint);

    if (emberT > 0 && emberT < 1) {
      final emberFade = 1 - emberT;
      canvas.drawCircle(
        tail,
        7,
        Paint()
          ..color = Colors.white.withAlpha((150 * emberFade).round())
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(tail, 3, Paint()..color = Colors.white.withAlpha((235 * emberFade).round()));
    }
  }

  @override
  bool shouldRepaint(covariant _TrailPainter oldDelegate) =>
      oldDelegate.head != head ||
      oldDelegate.tail != tail ||
      oldDelegate.color != color ||
      oldDelegate.emberT != emberT;
}
