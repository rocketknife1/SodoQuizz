import 'dart:math';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';

/// Un premiu de la Roata norocului — model flexibil (nu un singur
/// tip+cantitate) ca să poată reprezenta și pachete combinate (ex. XP+viață).
/// Toate câmpurile de recompensă sunt opționale (0 = nu se acordă); orice
/// combinație nenulă e posibilă. [weight] controlează șansa relativă de a
/// pica pe acest premiu — segmentele de pe roată rămân vizual egale ca
/// mărime (toate mereu vizibile), raritatea vine din probabilitate, nu din
/// mărimea feliei.
class _WheelPrize {
  final IconData icon;
  final Color color;
  /// Textul scurt desenat pe roată, sub icon (ex. "25", "1", "24h").
  final String wheelLabel;
  final int weight;
  final int coins;
  final int xp;
  final int hints;
  final int gems;
  final int lives;
  /// Premiul-jackpot: vieți nelimitate pentru această durată (altfel null).
  final Duration? unlimitedLives;

  const _WheelPrize({
    required this.icon,
    required this.color,
    required this.wheelLabel,
    required this.weight,
    this.coins = 0,
    this.xp = 0,
    this.hints = 0,
    this.gems = 0,
    this.lives = 0,
    this.unlimitedLives,
  });
}

const _gemColor = Color(0xFF5EC8F2);
const _jackpotColor = Color(0xFFFFD700);

/// 11 premii — orice resursă (monede, XP, hints, viață, gems) sau pachet
/// combinat (mai rar) poate ieși la o rotire, plus premiul special ultra-rar:
/// vieți nelimitate 24h. Greutățile sunt relative, nu procente — vezi
/// [_WheelSpinDialogState._pickWeightedIndex].
const List<_WheelPrize> _prizes = [
  _WheelPrize(icon: Icons.monetization_on_rounded, color: AppColors.coin, wheelLabel: '25', weight: 20, coins: 25),
  _WheelPrize(icon: Icons.star_rounded, color: AppColors.purple, wheelLabel: '30', weight: 20, xp: 30),
  _WheelPrize(icon: Icons.monetization_on_rounded, color: AppColors.coin, wheelLabel: '60', weight: 14, coins: 60),
  _WheelPrize(icon: Icons.tips_and_updates_rounded, color: AppColors.hint, wheelLabel: '1', weight: 16, hints: 1),
  _WheelPrize(icon: Icons.star_rounded, color: AppColors.purple, wheelLabel: '70', weight: 14, xp: 70),
  _WheelPrize(icon: Icons.favorite_rounded, color: AppColors.life, wheelLabel: '1', weight: 10, lives: 1),
  _WheelPrize(icon: Icons.tips_and_updates_rounded, color: AppColors.hint, wheelLabel: '2', weight: 8, hints: 2),
  _WheelPrize(icon: Icons.diamond_rounded, color: _gemColor, wheelLabel: '3', weight: 6, gems: 3),
  // pachete combinate — mai rare (weight mic) decât o resursă singură.
  _WheelPrize(icon: Icons.card_giftcard_rounded, color: Color(0xFFB388FF), wheelLabel: 'XP+❤', weight: 4, xp: 40, lives: 1),
  _WheelPrize(icon: Icons.redeem_rounded, color: _gemColor, wheelLabel: '💎+', weight: 3, gems: 5, coins: 40),
  // jackpot — ultra-rar (weight 1 din 116 total ≈ 0.9%).
  _WheelPrize(icon: Icons.all_inclusive_rounded, color: _jackpotColor, wheelLabel: '24h', weight: 1, unlimitedLives: Duration(hours: 24)),
];

/// Roata norocului a inelului — un premiu o dată la 24h reale (vezi
/// [StorageService.canSpinRing]). Se deschide ca dialog peste Home;
/// recompensa se aplică imediat la finalul rotației, iar butonul de
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

  /// Tragere ponderată (nu uniformă) — indexul ales alimentează aceeași
  /// logică de unghi-țintă de mai jos, deci nu schimbă nimic din animația
  /// roții, doar CE index e ales.
  int _pickWeightedIndex() {
    final total = _prizes.fold<int>(0, (sum, p) => sum + p.weight);
    var roll = Random().nextDouble() * total;
    for (var i = 0; i < _prizes.length; i++) {
      roll -= _prizes[i].weight;
      if (roll <= 0) return i;
    }
    return _prizes.length - 1;
  }

  Future<void> _doSpin() async {
    if (_spinning || _done) return;
    final resultIndex = _pickWeightedIndex();
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
    if (prize.coins > 0) await StorageService.addCoins(prize.coins);
    if (prize.xp > 0) await StorageService.addXp(prize.xp);
    if (prize.hints > 0) await StorageService.addHints(prize.hints);
    if (prize.gems > 0) await StorageService.addGems(prize.gems);
    if (prize.lives > 0) await StorageService.addLivesUncapped(prize.lives);
    if (prize.unlimitedLives != null) {
      await StorageService.activateUnlimitedLives(prize.unlimitedLives!);
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
              Text(
                _result!.unlimitedLives != null ? 'JACKPOT! 🎉' : 'Ai câștigat!',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              _buildResultRows(_result!),
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

  /// Listează TOATE resursele câștigate — nu doar una — ca pachetele
  /// combinate (ex. XP+viață) să arate ambele rânduri, nu doar primul.
  Widget _buildResultRows(_WheelPrize prize) {
    if (prize.unlimitedLives != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.all_inclusive_rounded, color: _jackpotColor, size: 30),
          SizedBox(width: 10),
          Text('Vieți nelimitate\n24 de ore!', textAlign: TextAlign.center, style: TextStyle(color: _jackpotColor, fontSize: 18, fontWeight: FontWeight.w900)),
        ],
      );
    }
    final rows = <Widget>[];
    void addRow(IconData icon, Color color, String text) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
          ],
        ),
      ));
    }

    if (prize.coins > 0) addRow(Icons.monetization_on_rounded, AppColors.coin, '+${prize.coins}');
    if (prize.xp > 0) addRow(Icons.star_rounded, AppColors.purple, '+${prize.xp}');
    if (prize.hints > 0) addRow(Icons.tips_and_updates_rounded, AppColors.hint, '+${prize.hints}');
    if (prize.gems > 0) addRow(Icons.diamond_rounded, _gemColor, '+${prize.gems}');
    if (prize.lives > 0) addRow(Icons.favorite_rounded, AppColors.life, '+${prize.lives}');
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
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
      final iconPos = center + Offset(cos(midAngle), sin(midAngle)) * radius * 0.64;
      _paintText(canvas, String.fromCharCode(prize.icon.codePoint), prize.icon.fontFamily, prize.icon.fontPackage, iconPos, 20, Colors.white);
      final labelPos = center + Offset(cos(midAngle), sin(midAngle)) * radius * 0.89;
      _paintText(canvas, prize.wheelLabel, null, null, labelPos, 11, Colors.white, bold: true);
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
