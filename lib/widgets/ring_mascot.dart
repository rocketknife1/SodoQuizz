import 'dart:math';
import 'package:flutter/material.dart';
import '../core/sfx.dart';
import '../data/storage_service.dart';
import 'googly_eyes.dart';
import 'wheel_spin_dialog.dart';

/// A doua mascotă decorativă, aceeași "specie" ca PaperclipMascot (ochi
/// jucăuși, personalitate proprie) dar cu alt corp — un inel cu margine
/// colorată, tip smart-ring — și o funcție reală: deschide Roata norocului
/// (vezi [WheelSpinDialog]), o dată la 24h. Când nu e disponibil spin-ul,
/// tap-ul face doar reacția decorativă + arată timpul rămas.
class RingMascot extends StatefulWidget {
  final VoidCallback? onRewardsChanged;

  const RingMascot({super.key, this.onRewardsChanged});

  @override
  State<RingMascot> createState() => _RingMascotState();
}

class _RingMascotState extends State<RingMascot> with TickerProviderStateMixin {
  late final AnimationController _idle;
  late final AnimationController _excite;
  bool _excited = false;
  bool _ready = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _excite = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
    _refreshReady();
  }

  Future<void> _refreshReady() async {
    final ready = await StorageService.canSpinRing();
    if (!mounted) return;
    setState(() {
      _ready = ready;
      _checked = true;
    });
  }

  @override
  void dispose() {
    _idle.dispose();
    _excite.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_excite.isAnimating) return;
    if (_ready) {
      Sfx.rewardPop();
      setState(() => _excited = true);
      await _excite.forward(from: 0);
      if (mounted) setState(() => _excited = false);
      if (!mounted) return;
      await WheelSpinDialog.show(context);
      widget.onRewardsChanged?.call();
      await _refreshReady();
      return;
    }

    Sfx.tileSelect();
    setState(() => _excited = true);
    _excite.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _excited = false);
    });
    if (_checked) {
      final remaining = await StorageService.ringSpinTimeRemaining();
      if (!mounted) return;
      final h = remaining.inHours;
      final m = remaining.inMinutes % 60;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Roata norocului revine în ${h}h ${m}min')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: SizedBox(
        width: 78,
        height: 78,
        child: AnimatedBuilder(
          animation: Listenable.merge([_idle, _excite]),
          builder: (context, _) {
            final pulse = (sin(_idle.value * 2 * pi) + 1) / 2;
            final tilt = sin(_idle.value * 2 * pi * 0.5) * 0.07;
            final rimSpin = _idle.value * 2 * pi;
            final ripple = _excite.value;
            final exciteScale = _excited ? (1 - ripple) * 0.22 : 0.0;

            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: (_ready ? 0.22 + pulse * 0.28 : 0.1 + pulse * 0.1).clamp(0.0, 1.0),
                  child: Container(
                    width: 60 + pulse * 14,
                    height: 60 + pulse * 14,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: _ready ? const Color(0xFFFFC542) : const Color(0xFF534AB7)),
                  ),
                ),
                if (ripple > 0)
                  Opacity(
                    opacity: (1 - ripple).clamp(0.0, 1.0),
                    child: Container(
                      width: 48 + ripple * 46,
                      height: 48 + ripple * 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                Transform.rotate(
                  angle: tilt,
                  child: Transform.scale(
                    scale: 1 + exciteScale,
                    child: CustomPaint(size: const Size(56, 56), painter: _RingPainter(rimAngle: rimSpin, dimmed: !_ready)),
                  ),
                ),
                if (_ready)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE24B4A),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF1A1A2E), width: 2),
                      ),
                    ),
                  ),
                Positioned(top: 22, child: GooglyEyes(size: 8, excited: _excited)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double rimAngle;
  final bool dimmed;
  const _RingPainter({required this.rimAngle, required this.dimmed});

  static const _rimColors = [
    Color(0xFF534AB7),
    Color(0xFF1D9E75),
    Color(0xFFFFC542),
    Color(0xFFFF7A1A),
    Color(0xFFE24B4A),
    Color(0xFF534AB7),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..shader = SweepGradient(
        colors: dimmed ? _rimColors.map((c) => c.withAlpha(90)).toList() : _rimColors,
        transform: GradientRotation(rimAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, rim);

    final core = Paint()..color = const Color(0xFF15152A);
    canvas.drawCircle(center, radius - 5.5, core);

    final shine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withAlpha(60);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius - 5.5), -2.6, 1.0, false, shine);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.rimAngle != rimAngle || oldDelegate.dimmed != dimmed;
}
