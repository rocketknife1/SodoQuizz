import 'dart:math';
import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Fundal spațial reutilizabil — gradient navy → violet, două nebuloase
/// difuze și un câmp de stele (poziții cu seed fix, ca să nu se
/// re-randomizeze la fiecare rebuild). Folosit în spatele meniului
/// principal și al ecranului de categorii, ca bază vizuală comună
/// pentru tema de "planete".
class SpaceBackground extends StatelessWidget {
  final Widget child;
  const SpaceBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.spaceGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _StarfieldPainter())),
          ),
          Positioned(top: -70, left: -60, child: _nebula(AppColors.purple.withAlpha(70), 220)),
          Positioned(bottom: -90, right: -70, child: _nebula(AppColors.blue.withAlpha(45), 260)),
          child,
        ],
      ),
    );
  }

  Widget _nebula(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withAlpha(0)]),
        ),
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  const _StarfieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7);
    final paint = Paint();
    for (var i = 0; i < 110; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final r = rnd.nextDouble() * 1.3 + 0.3;
      paint.color = Colors.white.withAlpha(50 + rnd.nextInt(150));
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
