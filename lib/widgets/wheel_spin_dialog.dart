import 'dart:math';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';

enum _PrizeType { coins, xp, life }

class _WheelPrize {
  final IconData icon;
  final Color color;
  final _PrizeType type;
  final int amount;
  const _WheelPrize({required this.icon, required this.color, required this.type, required this.amount});
}

const List<_WheelPrize> _prizes = [
  _WheelPrize(icon: Icons.monetization_on_rounded, color: AppColors.coin, type: _PrizeType.coins, amount: 22),
  _WheelPrize(icon: Icons.star_rounded, color: AppColors.purple, type: _PrizeType.xp, amount: 33),
  _WheelPrize(icon: Icons.monetization_on_rounded, color: AppColors.coin, type: _PrizeType.coins, amount: 46),
  _WheelPrize(icon: Icons.favorite_rounded, color: AppColors.life, type: _PrizeType.life, amount: 1),
  _WheelPrize(icon: Icons.star_rounded, color: AppColors.purple, type: _PrizeType.xp, amount: 28),
  _WheelPrize(icon: Icons.monetization_on_rounded, color: AppColors.coin, type: _PrizeType.coins, amount: 68),
  _WheelPrize(icon: Icons.star_rounded, color: AppColors.purple, type: _PrizeType.xp, amount: 38),
  _WheelPrize(icon: Icons.monetization_on_rounded, color: AppColors.coin, type: _PrizeType.coins, amount: 30),
];

/// Roata norocului a inelului — un premiu (monede/XP/viață) o dată la 24h
/// reale (vezi [StorageService.canSpinRing]). Se deschide ca dialog peste
/// Home; recompensa se aplică imediat la finalul rotației, iar butonul de
/// închidere reîmprospătează header-ul.
class WheelSpinDialog extends StatefulWidget {
  const WheelSpinDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(context: context, barrierDismissible: false, builder: (_) => const WheelSpinDialog());
  }

  @override
  State<WheelSpinDialog> createState() => _WheelSpinDialogState();
}

class _WheelSpinDialogState extends State<WheelSpinDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  double _finalAngle = 0;
  bool _spinning = false;
  bool _done = false;
  _WheelPrize? _result;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _doSpin() async {
    if (_spinning || _done) return;
    final resultIndex = Random().nextInt(_prizes.length);
    final segmentAngle = 2 * pi / _prizes.length;
    // acul e sus (unghi -pi/2 în convenția noastră). Segmentul i e desenat
    // cu centrul la unghiul local -pi/2 + (i+0.5)*segmentAngle, așa că
    // rotația care îl aduce sub ac e doar -(i+0.5)*segmentAngle — fără -pi/2
    // suplimentar (bug-ul vechi scădea -pi/2 de două ori, ceea ce ateriza
    // segmentul cerut la stânga acului, nu sub el).
    final targetAngle = -(resultIndex + 0.5) * segmentAngle;
    final extraSpins = 5 + Random().nextInt(3);
    setState(() {
      _spinning = true;
      _finalAngle = extraSpins * 2 * pi + targetAngle;
    });
    Sfx.tileSelect();
    await _spin.forward(from: 0);

    final prize = _prizes[resultIndex];
    switch (prize.type) {
      case _PrizeType.coins:
        await StorageService.addCoins(prize.amount);
        break;
      case _PrizeType.xp:
        await StorageService.addXp(prize.amount);
        break;
      case _PrizeType.life:
        await StorageService.addLivesUncapped(prize.amount);
        break;
    }
    await StorageService.recordRingSpin();
    Sfx.rewardPop();
    if (!mounted) return;
    setState(() {
      _spinning = false;
      _done = true;
      _result = prize;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Roata norocului', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Un premiu o dată la 24 de ore', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 20),
            SizedBox(
              width: 240,
              height: 240,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) {
                      final angle = Curves.easeOutQuint.transform(_spin.value) * _finalAngle;
                      return Transform.rotate(
                        angle: angle,
                        child: CustomPaint(size: const Size(240, 240), painter: _WheelPainter()),
                      );
                    },
                  ),
                  IgnorePointer(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 3),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: -8,
                    child: Icon(Icons.arrow_drop_down_rounded, color: Colors.white, size: 44, shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            if (_done && _result != null) ...[
              const Text('Ai câștigat!', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_result!.icon, color: _result!.color, size: 26),
                  const SizedBox(width: 8),
                  Text('+${_result!.amount}', style: TextStyle(color: _result!.color, fontSize: 24, fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.play, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12)),
                child: const Text('Super!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ] else
              ElevatedButton(
                onPressed: _spinning ? null : _doSpin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.coin,
                  disabledBackgroundColor: Colors.white24,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text(
                  _spinning ? 'Se învârte...' : 'ÎNVÂRTE',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final segmentAngle = 2 * pi / _prizes.length;

    for (var i = 0; i < _prizes.length; i++) {
      final prize = _prizes[i];
      final startAngle = -pi / 2 + i * segmentAngle;
      final fill = Paint()..color = prize.color.withAlpha(i.isEven ? 215 : 160);
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, segmentAngle, true, fill);

      final line = Paint()
        ..color = Colors.black38
        ..strokeWidth = 2;
      canvas.drawLine(center, center + Offset(cos(startAngle), sin(startAngle)) * radius, line);

      final midAngle = startAngle + segmentAngle / 2;
      final iconPos = center + Offset(cos(midAngle), sin(midAngle)) * radius * 0.66;
      _paintText(canvas, String.fromCharCode(prize.icon.codePoint), prize.icon.fontFamily, prize.icon.fontPackage, iconPos, 22, Colors.white);
      final labelPos = center + Offset(cos(midAngle), sin(midAngle)) * radius * 0.9;
      _paintText(canvas, '${prize.amount}', null, null, labelPos, 12, Colors.white, bold: true);
    }

    canvas.drawCircle(center, radius, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white24);
  }

  void _paintText(Canvas canvas, String text, String? fontFamily, String? fontPackage, Offset pos, double size, Color color, {bool bold = false}) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: size,
        fontFamily: fontFamily,
        package: fontPackage,
        color: color,
        fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
        shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
      ),
    );
    tp.layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
