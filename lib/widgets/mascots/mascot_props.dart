import 'dart:math';
import 'package:flutter/material.dart';

/// Un mic ceas de buzunar care "apare de după spate" (culisează de jos în
/// sus, cu fade-in/out), cu acele mișcându-se — folosit de toate cele trei
/// mascote de pe Home pentru gestul comun "se uită la ceas". [t] e
/// progresul gestului curent (0..1); apariția/dispariția se calculează
/// intern din el, ca widget-ul să rămână fără stare proprie.
class ClockProp extends StatelessWidget {
  final double t;
  const ClockProp({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    final inT = (t / 0.25).clamp(0.0, 1.0);
    final outT = ((t - 0.75) / 0.25).clamp(0.0, 1.0);
    final appear = t < 0.75 ? Curves.easeOutBack.transform(inT) : 1 - Curves.easeIn.transform(outT);
    final slide = (1 - appear.clamp(0.0, 1.0)) * 14;
    final handAngle = sin(t * pi * 6) * 0.5;

    return Opacity(
      opacity: appear.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, slide),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: const Color(0xFFFFC542),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF15152A), width: 2),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 5)],
          ),
          child: CustomPaint(painter: _ClockHandsPainter(handAngle)),
        ),
      ),
    );
  }
}

class _ClockHandsPainter extends CustomPainter {
  final double angle;
  const _ClockHandsPainter(this.angle);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..color = const Color(0xFF15152A)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c, c + const Offset(0, -7), paint);
    canvas.drawLine(c, c + Offset(cos(angle) * 5, sin(angle) * 5), paint);
  }

  @override
  bool shouldRepaint(covariant _ClockHandsPainter oldDelegate) => oldDelegate.angle != angle;
}

/// Balon de vorbă generic, cu codiță — folosit atât pentru CTA-ul fix al
/// mascotei de Discord ("Visit us!"), cât și pentru replicile trecătoare
/// ("Ce mai faci?") ale celorlalte mascote. [t] (0..1) controlează
/// fade-in/out când e parte dintr-un gest temporar; pentru un CTA cu
/// propriul ciclu de vizibilitate se poate lăsa t=1 (mereu "apărut") și
/// controla vizibilitatea din exterior (ex: cu un Opacity separat).
class MascotBubble extends StatelessWidget {
  final String text;
  final Color color;
  final double t;
  const MascotBubble({super.key, required this.text, required this.color, this.t = 1});

  @override
  Widget build(BuildContext context) {
    final inT = (t / 0.15).clamp(0.0, 1.0);
    final outT = ((t - 0.85) / 0.15).clamp(0.0, 1.0);
    final appear = t < 0.85 ? inT : 1 - outT;
    return Opacity(
      opacity: appear.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.85 + appear.clamp(0.0, 1.0) * 0.15,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              constraints: const BoxConstraints(maxWidth: 130),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color, width: 1.5),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
            CustomPaint(size: const Size(12, 7), painter: _BubbleTailPainter(color)),
          ],
        ),
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color color;
  const _BubbleTailPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.5 - 5, 0)
      ..lineTo(size.width * 0.5 + 5, 0)
      ..lineTo(size.width * 0.5, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) => oldDelegate.color != color;
}
