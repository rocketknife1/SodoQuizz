import 'dart:math';
import 'package:flutter/material.dart';

/// Inel de numărătoare inversă pentru Daily Challenge — arc colorat
/// (verde → portocaliu → roșu pe măsură ce timpul scade) cu secundele
/// rămase afișate în mijloc. Folosit doar în modul cronometrat, nu în
/// gamemodurile normale.
class CountdownRing extends StatelessWidget {
  final int secondsLeft;
  final int totalSeconds;
  final double size;

  const CountdownRing({
    super.key,
    required this.secondsLeft,
    required this.totalSeconds,
    this.size = 48,
  });

  Color get _color {
    final frac = totalSeconds > 0 ? secondsLeft / totalSeconds : 0.0;
    if (frac > 0.5) return const Color(0xFF22C55E);
    if (frac > 0.25) return const Color(0xFFFF7A1A);
    return const Color(0xFFE24B4A);
  }

  @override
  Widget build(BuildContext context) {
    final frac = totalSeconds > 0 ? (secondsLeft / totalSeconds).clamp(0.0, 1.0) : 0.0;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress: frac, color: _color),
        child: Center(
          child: Text(
            '$secondsLeft',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.34,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = Colors.white24;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = color;
    const start = -pi / 2;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, progress * 2 * pi, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
