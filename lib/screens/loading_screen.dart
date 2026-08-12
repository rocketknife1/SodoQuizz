import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/lang.dart';
import 'game_screen.dart';

class LoadingScreen extends StatefulWidget {
  final String? gameModeId;
  final WidgetBuilder? nextBuilder;
  final Duration duration;

  /// Taxa deja plătită pentru sesiunea care urmează — vezi
  /// categories_screen.dart._enterCategory / GameScreen._settleExitReward.
  /// 0 = sesiune fără taxă (n-ar trebui să se întâmple pe acest traseu, dar
  /// rămâne implicit ca [GameScreen] să poată fi refolosit și fără taxă).
  final int entryFeePaid;

  const LoadingScreen({
    super.key,
    this.gameModeId,
    this.nextBuilder,
    this.duration = const Duration(milliseconds: 1200),
    this.entryFeePaid = 0,
  });

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
    // navigate after configured duration
    _timer = Timer(widget.duration, () {
      if (widget.nextBuilder != null) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: widget.nextBuilder!));
      } else if (widget.gameModeId != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => GameScreen(
                  gameModeId: widget.gameModeId!,
                  entryFeePaid: widget.entryFeePaid)),
        );
      } else {
        Navigator.pop(context);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0f1623), Color(0xFF071036)],
              ),
            ),
          ),
          // subtle grid
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GridPainter(opacity: 0.06, offset: _ctrl.value),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('SODO QUIZZ',
                    style: TextStyle(
                        letterSpacing: 3,
                        color: const Color(0xFF9A5AFB).withAlpha(220),
                        fontWeight: FontWeight.w800,
                        fontSize: 28,
                        shadows: [
                          const Shadow(color: Color(0xFF00FFC6), blurRadius: 12)
                        ])),
                const SizedBox(height: 18),
                SizedBox(
                  width: 140,
                  height: 140,
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (_, __) {
                      return Transform.rotate(
                        angle: _ctrl.value * 2 * pi,
                        child: CustomPaint(
                          painter: _RingPainter(progress: _ctrl.value),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Text(tr('Pregătesc întrebările...', 'Getting the questions ready...'),
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final double opacity;
  final double offset;
  _GridPainter({required this.opacity, required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha((opacity * 255).round());
    const step = 24.0;
    for (double x = -step + (offset * step); x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = -step + (offset * step); y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.offset != offset || old.opacity != opacity;
}

class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = Colors.white12;
    canvas.drawCircle(center, radius, bg);

    final prog = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
              colors: [Color(0xFF9A5AFB), Color(0xFF00FFC6)],
              stops: [0.0, 1.0],
              startAngle: 0.0,
              endAngle: 3.14)
          .createShader(Rect.fromCircle(center: center, radius: radius));

    final start = -3.14 / 2 + progress * 3.14 * 2;
    final sweep = 3.14 * 0.9;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start,
        sweep, false, prog);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress;
}
