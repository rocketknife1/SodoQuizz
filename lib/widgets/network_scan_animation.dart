import 'dart:math';
import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Animație de "hartă cibernetică" pentru ecranul de matchmaking (Join
/// Online) — noduri aleatorii unite prin linii, care plutesc ușor și
/// pulsează, cu impulsuri "de rețea" care circulă pe muchii, ca o scanare
/// vie în căutarea unui adversar. Pur decorativă, nu reflectă rețeaua reală.
class NetworkScanAnimation extends StatefulWidget {
  final double size;
  const NetworkScanAnimation({super.key, this.size = 220});

  @override
  State<NetworkScanAnimation> createState() => _NetworkScanAnimationState();
}

class _NetworkScanAnimationState extends State<NetworkScanAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Offset> _nodes; // coordonate normalizate 0..1
  late final List<(int, int)> _edges;
  late final List<double> _driftFreqX;
  late final List<double> _driftFreqY;
  late final List<double> _driftPhase;
  late final List<double> _pulseSpeed;

  // durata mare (nu 3-4s) ca bucla sa nu se vada - t creste aproape linear
  // pe toata durata folosirii ecranului, fara resetari vizibile.
  static const _loopSeconds = 3600;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: _loopSeconds))..repeat();

    final rnd = Random();
    const nodeCount = 16;
    _nodes = List.generate(nodeCount, (_) => Offset(0.08 + rnd.nextDouble() * 0.84, 0.08 + rnd.nextDouble() * 0.84));
    _edges = [];
    for (var i = 0; i < nodeCount; i++) {
      for (var j = i + 1; j < nodeCount; j++) {
        if ((_nodes[i] - _nodes[j]).distance < 0.34) _edges.add((i, j));
      }
    }
    // fiecare nod pluteste pe propriul ritm (frecvente/faze diferite), ca
    // miscarea sa para organica, nu sincronizata.
    _driftFreqX = List.generate(nodeCount, (_) => 0.12 + rnd.nextDouble() * 0.22);
    _driftFreqY = List.generate(nodeCount, (_) => 0.12 + rnd.nextDouble() * 0.22);
    _driftPhase = List.generate(nodeCount, (_) => rnd.nextDouble() * 2 * pi);
    // fiecare impuls circula cu o viteza usor diferita pe muchia lui.
    _pulseSpeed = List.generate(_edges.length, (_) => 0.35 + rnd.nextDouble() * 0.55);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _NetworkPainter(
            nodes: _nodes,
            edges: _edges,
            driftFreqX: _driftFreqX,
            driftFreqY: _driftFreqY,
            driftPhase: _driftPhase,
            pulseSpeed: _pulseSpeed,
            t: _controller.value * _loopSeconds,
          ),
        ),
      ),
    );
  }
}

class _NetworkPainter extends CustomPainter {
  final List<Offset> nodes;
  final List<(int, int)> edges;
  final List<double> driftFreqX;
  final List<double> driftFreqY;
  final List<double> driftPhase;
  final List<double> pulseSpeed;
  final double t;
  _NetworkPainter({
    required this.nodes,
    required this.edges,
    required this.driftFreqX,
    required this.driftFreqY,
    required this.driftPhase,
    required this.pulseSpeed,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // pozitii curente = pozitia de baza + o usoara plutire independenta per nod.
    const driftAmount = 0.028;
    final pts = List.generate(nodes.length, (i) {
      final base = nodes[i];
      final dx = base.dx + sin(t * driftFreqX[i] + driftPhase[i]) * driftAmount;
      final dy = base.dy + cos(t * driftFreqY[i] + driftPhase[i] * 1.3) * driftAmount;
      return Offset(dx * size.width, dy * size.height);
    });

    // liniile, cu o usoara scanteiere (intensitatea "traficului") pe fiecare muchie.
    final linePaint = Paint()..strokeWidth = 1;
    for (var e = 0; e < edges.length; e++) {
      final (a, b) = edges[e];
      final flicker = (sin(t * 0.9 + e * 2.1) + 1) / 2;
      linePaint.color = AppColors.blue.withAlpha((35 + flicker * 55).round());
      canvas.drawLine(pts[a], pts[b], linePaint);
    }

    // impulsuri care circula pe muchii, fiecare in viteza proprie - cateva
    // dus, cateva intors, ca traficul sa para bidirectional.
    final pulsePaint = Paint();
    for (var i = 0; i < edges.length; i++) {
      final (a, b) = edges[i];
      final speed = pulseSpeed[i];
      final reverse = i.isOdd;
      var phase = (t * speed + i * 0.37) % 1.0;
      if (reverse) phase = 1.0 - phase;
      final pos = Offset.lerp(pts[a], pts[b], phase)!;
      final fade = sin(((reverse ? 1.0 - phase : phase)) * pi).clamp(0.0, 1.0);
      canvas.drawCircle(pos, 2.6, pulsePaint..color = AppColors.blue.withAlpha((90 + fade * 165).round()));
    }

    // nodurile, pulsand mai viu - fiecare cu propriul ritm.
    for (var i = 0; i < pts.length; i++) {
      final phase = (sin(t * 1.8 + i * 1.7) + 1) / 2;
      final radius = 2.4 + phase * 3.2;
      canvas.drawCircle(pts[i], radius, Paint()..color = AppColors.blue.withAlpha((100 + phase * 155).round()));
      canvas.drawCircle(
        pts[i],
        radius + 5.5,
        Paint()
          ..color = AppColors.blue.withAlpha((25 + phase * 55).round())
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NetworkPainter oldDelegate) => oldDelegate.t != t;
}
