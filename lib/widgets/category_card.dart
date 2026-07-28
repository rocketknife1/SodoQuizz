import 'dart:math';
import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Card orizontal, lat cât ecranul, pentru o categorie (gamemod) — planetă
/// texturată în stânga (inel înclinat + luciu + suprafață pictată), titlu +
/// progres numeric la mijloc, inel colorat cu procentul de măiestrie în
/// dreapta. Un singur rând pe categorie (nu grid 2 coloane) — cu titluri
/// românești mai lungi ("Mașini de Lux", "Fotbal & Sport"), o coloană lată
/// e singura variantă care nu trunchiază numele.
class CategoryCard extends StatelessWidget {
  final int index;
  final IconData icon;
  final String title;
  final int totalQuestions;
  final int answered;
  final Color color;
  final bool locked;
  final VoidCallback onTap;

  /// Textul de sub titlu — calculat de apelant (categories_screen.dart), nu
  /// aici, fiindcă motivul blocării (conținut inexistent încă vs. blocat cu
  /// Gems) și starea de progres (jucate/deblocate/total) depind de context
  /// pe care doar apelantul îl are complet.
  final String subtitle;

  /// Preț (Gems) pentru următoarea treaptă de upgrade — null dacă nu mai e
  /// nimic de deblocat (tier maxim atins sau categorie complet deblocată).
  final int? upgradePrice;
  final VoidCallback? onUpgrade;

  const CategoryCard({
    super.key,
    required this.index,
    required this.icon,
    required this.title,
    required this.totalQuestions,
    required this.answered,
    required this.color,
    required this.onTap,
    required this.subtitle,
    this.locked = false,
    this.upgradePrice,
    this.onUpgrade,
  });

  double get _pct => totalQuestions > 0 ? (answered / totalQuestions).clamp(0.0, 1.0) : 0.0;

  @override
  Widget build(BuildContext context) {
    final rim = locked ? Colors.white24 : color.withAlpha(150);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(locked ? 8 : 16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: rim, width: 1.4),
          boxShadow: locked
              ? null
              : [BoxShadow(color: color.withAlpha(65), blurRadius: 16, spreadRadius: -3)],
        ),
        child: Row(
          children: [
            _Planet(color: color, icon: icon, locked: locked, seed: index),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _numberChip(),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withAlpha(locked ? 170 : 255),
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  if (upgradePrice != null && onUpgrade != null) ...[
                    const SizedBox(height: 6),
                    _UpgradeChip(price: upgradePrice!, locked: locked, onTap: onUpgrade!),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            _ring(),
          ],
        ),
      ),
    );
  }

  Widget _numberChip() {
    return Container(
      width: 19,
      height: 19,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: (locked ? Colors.white24 : color).withAlpha(60),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$index',
        style: TextStyle(color: locked ? Colors.white60 : color, fontSize: 10.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _ring() {
    if (locked) {
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 1.2)),
        alignment: Alignment.center,
        child: const Icon(Icons.lock_outline_rounded, color: Colors.white38, size: 16),
      );
    }
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withAlpha(70),
        boxShadow: [BoxShadow(color: color.withAlpha(110), blurRadius: 10, spreadRadius: -1)],
      ),
      padding: const EdgeInsets.all(5),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: 1,
            strokeWidth: 4.5,
            strokeCap: StrokeCap.round,
            valueColor: AlwaysStoppedAnimation(Colors.white.withAlpha(28)),
          ),
          CircularProgressIndicator(
            value: _pct == 0 ? 0.012 : _pct,
            strokeWidth: 4.5,
            strokeCap: StrokeCap.round,
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Text(
            '${(_pct * 100).round()}',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, height: 1),
          ),
        ],
      ),
    );
  }
}

/// Planetă texturată: gradient în mai multe trepte (nu doar 2 tonuri),
/// pată de luciu în colțul stâng-sus, inel înclinat tip Saturn și un strat
/// subtil de "cratere" pictate cu seed fix (nu se re-randomizează la
/// rebuild) — mult mai aproape de referința trimisă decât un cerc plat.
class _Planet extends StatelessWidget {
  final Color color;
  final IconData icon;
  final bool locked;
  final int seed;

  const _Planet({required this.color, required this.icon, required this.locked, required this.seed});

  static Color _shade(Color c, double dl, [double ds = 0]) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + dl).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + ds).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    const size = 58.0;
    return SizedBox(
      width: size,
      height: size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // inelul (Saturn) — desenat SUB glob, ușor înclinat, colorat pe tema categoriei.
          if (!locked)
            Transform.rotate(
              angle: -0.34,
              child: Container(
                width: size * 1.62,
                height: size * 0.5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withAlpha(150), width: 2.2),
                  gradient: LinearGradient(colors: [color.withAlpha(0), color.withAlpha(90), color.withAlpha(0)]),
                ),
              ),
            ),
          // globul propriu-zis, cu textură + luciu, deasupra inelului.
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.4, -0.45),
                radius: 1.05,
                colors: locked
                    ? [Colors.white.withAlpha(45), Colors.white.withAlpha(22), Colors.white.withAlpha(10)]
                    : [
                        _shade(color, 0.30, 0.05),
                        _shade(color, 0.06),
                        color,
                        _shade(color, -0.20, 0.10),
                        _shade(color, -0.34, 0.10),
                      ],
                // stops trebuie să aibă mereu aceeași lungime ca [colors] —
                // varianta locked are doar 3 culori, nu 5 (vezi mai sus).
                stops: locked ? const [0.0, 0.5, 1.0] : const [0.0, 0.28, 0.55, 0.8, 1.0],
              ),
              border: Border.all(color: locked ? Colors.white24 : _shade(color, -0.32, 0.1), width: 1.3),
              boxShadow: locked
                  ? null
                  : [
                      BoxShadow(color: color.withAlpha(130), blurRadius: 16, spreadRadius: 0.5),
                      const BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 3)),
                    ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!locked) Positioned.fill(child: CustomPaint(painter: _PlanetSurfacePainter(seed: seed, base: color))),
                // luciu sticlos, colț stânga-sus.
                if (!locked)
                  Positioned(
                    left: size * 0.10,
                    top: size * 0.08,
                    child: Container(
                      width: size * 0.34,
                      height: size * 0.22,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Colors.white.withAlpha(150), Colors.white.withAlpha(0)],
                        ),
                      ),
                    ),
                  ),
                Icon(
                  locked ? Icons.lock_rounded : icon,
                  color: Colors.white.withAlpha(locked ? 150 : 255),
                  size: 22,
                  shadows: const [Shadow(color: Colors.black45, blurRadius: 3)],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cratere/pete de suprafață, cu poziții determinate de un seed fix (per
/// categorie) — desenate o singură dată, nu se re-randomizează la rebuild.
class _PlanetSurfacePainter extends CustomPainter {
  final int seed;
  final Color base;
  const _PlanetSurfacePainter({required this.seed, required this.base});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(seed * 97 + 13);
    final dark = HSLColor.fromColor(base).withLightness(0.2).toColor();
    final light = HSLColor.fromColor(base).withLightness(0.75).toColor();
    for (var i = 0; i < 6; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final r = size.width * (0.06 + rnd.nextDouble() * 0.11);
      final useDark = rnd.nextBool();
      canvas.drawCircle(
        Offset(dx, dy),
        r,
        Paint()..color = (useDark ? dark : light).withAlpha(useDark ? 40 : 26),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlanetSurfacePainter oldDelegate) => oldDelegate.seed != seed || oldDelegate.base != base;
}

/// Buton compact "Upgrade" cu preț în Gems — Material+InkWell (nu un simplu
/// GestureDetector) ca tap-ul lui să nu se propage și către [onTap]-ul
/// cardului părinte, care e mult mai mare.
class _UpgradeChip extends StatelessWidget {
  final int price;
  final bool locked;
  final VoidCallback onTap;

  const _UpgradeChip({required this.price, required this.locked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.gem.withAlpha(45),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.gem.withAlpha(150)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                locked ? 'DEBLOCHEAZĂ' : 'UPGRADE',
                style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.3),
              ),
              const SizedBox(width: 5),
              const Icon(Icons.diamond_rounded, color: AppColors.gem, size: 12),
              const SizedBox(width: 2),
              Text('$price', style: const TextStyle(color: AppColors.gem, fontSize: 11, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}
