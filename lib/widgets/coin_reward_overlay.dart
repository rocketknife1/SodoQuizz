import 'dart:math';
import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Animația de recompensă: un praf magic (scântei) explodează din centrul
/// ecranului și dezvăluie simbolurile recompensei, care apoi zboară pe o
/// traiectorie șerpuită spre [targetKey], cu un mic "pop" la impact. La
/// impact apar câteva simboluri "+" care plutesc și se sting, iar
/// [onImpact] e apelat exact în momentul impactului — locul potrivit să
/// reîncarci balanța, ca numărul să se actualizeze sincron cu animația, nu
/// înainte. [icon]/[color] implicite (monedă) — orice alt apelant poate
/// arăta un alt tip de recompensă (XP, vieți) fără să schimbe nimic altundeva.
/// [serpentine] înlocuiește arcul simplu cu o traiectorie șerpuită.
class CoinRewardOverlay {
  static void show(
    BuildContext context, {
    required int amount,
    required GlobalKey targetKey,
    VoidCallback? onImpact,
    VoidCallback? onFinished,
    IconData icon = Icons.monetization_on_rounded,
    Color color = AppColors.coin,
    Duration flightDuration = const Duration(milliseconds: 950),
    bool serpentine = false,
  }) {
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
        color: color,
        flightDuration: flightDuration,
        serpentine: serpentine,
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
  final bool serpentine;
  final VoidCallback? onImpact;
  final VoidCallback onRemove;

  const _CoinRewardAnimation({
    required this.amount,
    required this.target,
    required this.icon,
    required this.color,
    required this.flightDuration,
    required this.serpentine,
    required this.onRemove,
    this.onImpact,
  });

  @override
  State<_CoinRewardAnimation> createState() => _CoinRewardAnimationState();
}

class _CoinRewardAnimationState extends State<_CoinRewardAnimation> with TickerProviderStateMixin {
  late final AnimationController _flight;
  late final AnimationController _plus;
  bool _impactFired = false;

  static const _iconAngles = [0.0, 60.0, 120.0, 180.0, 240.0, 300.0];
  static const _dustAngles = [15.0, 55.0, 95.0, 135.0, 175.0, 215.0, 255.0, 295.0, 335.0];

  @override
  void initState() {
    super.initState();
    _flight = AnimationController(vsync: this, duration: widget.flightDuration)
      ..addListener(_maybeFireImpact)
      ..forward();
    // faza de "+"-uri e scurtă și fixă — nu trebuie să se scaleze cu durata
    // zborului, altfel ținta întârzie inutil de mult să se simtă "gata".
    _plus = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
    _flight.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _plus.forward();
      }
    });
    _plus.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onRemove();
    });
  }

  void _maybeFireImpact() {
    if (!_impactFired && _flight.value >= 0.98) {
      _impactFired = true;
      widget.onImpact?.call();
    }
  }

  @override
  void dispose() {
    _flight.dispose();
    _plus.dispose();
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
              animation: _flight,
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

  Widget _buildFlightPhase(Offset center) {
    final t = _flight.value;

    // praful magic: scântei mici care explodează repede din centru și se
    // sting — "dezvăluie" simbolurile care apar chiar peste el.
    final dustBurst = Interval(0.0, 0.4, curve: Curves.easeOut).transform(t.clamp(0, 1));
    final dustFade = 1 - Interval(0.15, 0.45).transform(t.clamp(0, 1));
    final revealT = Interval(0.05, 0.3, curve: Curves.easeOutBack).transform(t.clamp(0, 1));
    final burstT = Interval(0.1, 0.45, curve: Curves.easeOut).transform(t.clamp(0, 1));
    final flightT = Interval(0.4, 1.0, curve: Curves.easeInOutCubic).transform(t.clamp(0, 1));

    return Stack(
      children: [
        if (dustFade > 0)
          for (var i = 0; i < _dustAngles.length; i++) _buildDustSpark(i, center, dustBurst, dustFade),
        _buildAmountLabel(center, t),
        for (var i = 0; i < _iconAngles.length; i++) _buildIcon(i, center, revealT, burstT, flightT),
      ],
    );
  }

  /// Arată "+cantitate" chiar deasupra exploziei de praf magic, ÎNAINTE ca
  /// simbolurile să pornească spre pastilă (vezi feedback-ul jucătorului: fără
  /// numărul ăsta, nu se știe cât s-a primit decât la impact) — se stinge
  /// exact când începe faza de zbor, ca să nu se suprapună cu traiectoria.
  Widget _buildAmountLabel(Offset center, double t) {
    final fadeIn = Interval(0.0, 0.16, curve: Curves.easeOut).transform(t.clamp(0.0, 1.0));
    final fadeOut = 1 - Interval(0.28, 0.46).transform(t.clamp(0.0, 1.0));
    final opacity = (fadeIn * fadeOut).clamp(0.0, 1.0);
    if (opacity <= 0) return const SizedBox.shrink();
    final rise = -16 * Interval(0.0, 0.46).transform(t.clamp(0.0, 1.0));
    return Positioned(
      left: center.dx - 70,
      top: center.dy - 56 + rise,
      width: 140,
      child: Center(
        child: Text(
          '+${widget.amount}',
          style: TextStyle(
            color: _withOpacity(widget.color, opacity),
            fontSize: 24,
            fontWeight: FontWeight.w900,
            shadows: [Shadow(color: _withOpacity(Colors.black54, opacity), blurRadius: 5)],
          ),
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

  Widget _buildIcon(int i, Offset center, double revealT, double burstT, double flightT) {
    final angle = _iconAngles[i] * pi / 180;
    final scatter = center + Offset(cos(angle), sin(angle)) * 58;

    Offset pos;
    double scale;
    double opacity = revealT;
    if (flightT <= 0) {
      pos = Offset.lerp(center, scatter, burstT)!;
      scale = revealT * (0.7 + burstT * 0.3);
    } else {
      final base = Offset.lerp(scatter, widget.target, flightT)!;
      if (widget.serpentine) {
        // traiectorie șerpuită: oscilație perpendiculară pe direcția de
        // zbor, cu amplitudine care se strânge spre țintă (nu "trece prin"
        // pastilă la impact) — fiecare simbol are o fază ușor decalată,
        // ca mișcarea să pară organică, nu sincronizată perfect.
        final delta = widget.target - scatter;
        final dist = delta.distance;
        final dir = dist > 0 ? delta / dist : const Offset(1, 0);
        final perp = Offset(-dir.dy, dir.dx);
        final wave = sin(flightT * pi * 2.6 + i * 0.6) * 50 * (1 - flightT * 0.9);
        pos = base + perp * wave;
      } else {
        final arc = -sin(pi * flightT) * 60;
        pos = base + Offset(0, arc);
      }
      // mic "pop" la sosire: scala trece ușor peste 1 înainte să se strângă,
      // în loc să se micșoreze liniar tot drumul — se simte mai satisfăcător.
      final approach = Curves.easeIn.transform(flightT.clamp(0, 1));
      final pop = flightT > 0.82 ? sin((flightT - 0.82) / 0.18 * pi) * 0.35 : 0.0;
      scale = 1 - approach * 0.55 + pop;
      if (flightT > 0.88) opacity = ((1 - flightT) / 0.12).clamp(0.0, 1.0);
    }

    final spin = (burstT + flightT) * 6 * pi;
    final o = opacity.clamp(0.0, 1.0);

    return Positioned(
      left: pos.dx - 17,
      top: pos.dy - 17,
      child: Transform.rotate(
        angle: spin,
        child: Transform.scale(
          scale: scale.clamp(0.0, 1.7),
          child: Icon(
            widget.icon,
            color: _withOpacity(widget.color, o),
            size: 34,
            shadows: [Shadow(color: _withOpacity(Colors.black45, o), blurRadius: 5)],
          ),
        ),
      ),
    );
  }

  Widget _buildPlusPhase() {
    if (_flight.status != AnimationStatus.completed) return const SizedBox.shrink();
    const staggers = [0.0, 0.15, 0.3];
    const dxs = [-20.0, 0.0, 20.0];

    return Stack(
      children: [
        for (var i = 0; i < staggers.length; i++) _buildPlusSign(i, staggers[i], dxs[i]),
      ],
    );
  }

  Widget _buildPlusSign(int i, double stagger, double dx) {
    final local = Interval(stagger, (stagger + 0.7).clamp(0.0, 1.0)).transform(_plus.value);
    final rise = -56 * local;
    final opacity = local < 0.15 ? local / 0.15 : (1 - ((local - 0.15) / 0.85)).clamp(0.0, 1.0);

    final o = opacity.clamp(0.0, 1.0);
    return Positioned(
      left: widget.target.dx - 12 + dx,
      top: widget.target.dy - 16 + rise,
      child: Text(
        '+',
        style: TextStyle(
          color: _withOpacity(widget.color, o),
          fontSize: 26,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: _withOpacity(Colors.black54, o), blurRadius: 4)],
        ),
      ),
    );
  }
}
