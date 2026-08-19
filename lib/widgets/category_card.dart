import 'dart:math';
import 'package:flutter/material.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import 'planet_art.dart';
import 'pressable.dart';

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

  /// Bucla continuă (0..1, repetitivă) care ține planeta vie — inelul lui
  /// Saturn se rotește, glow-ul respiră. Un singur controller, împărțit de
  /// toate cardurile din listă (vezi CategoriesScreen._liveCtrl), nu unul
  /// per card.
  final Animation<double> pulse;

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
    required this.pulse,
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
    return Pressable(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, child) {
          // respirație lentă (0..1..0) — nu o rampă liniară 0..1 care sare
          // înapoi brusc la capăt de buclă.
          final breathe = (sin(pulse.value * 2 * pi) + 1) / 2;
          return Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(locked ? 8 : 16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: rim, width: 1.4),
              boxShadow: locked
                  ? null
                  : [
                      BoxShadow(
                        color: color.withAlpha((50 + breathe * 45).round()),
                        blurRadius: 14 + breathe * 8,
                        spreadRadius: -3,
                      ),
                    ],
            ),
            child: child,
          );
        },
        child: Row(
          children: [
            _Planet(color: color, icon: icon, locked: locked, seed: index, pulse: pulse),
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
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final breathe = (sin(pulse.value * 2 * pi) + 1) / 2;
        return Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withAlpha(70),
            boxShadow: [BoxShadow(color: color.withAlpha((90 + breathe * 60).round()), blurRadius: 8 + breathe * 6, spreadRadius: -1)],
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
              // traseul de progres primește o culoare în gradient (nu plată)
              // prin ShaderMask — capătul arcului e mai luminos decât baza,
              // ca un mic accent electric, nu doar o linie colorată uniform.
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (rect) => SweepGradient(
                  colors: [color, _Planet._shade(color, 0.35, 0.1)],
                  startAngle: -pi / 2,
                  endAngle: -pi / 2 + 2 * pi,
                ).createShader(rect),
                child: CircularProgressIndicator(
                  value: _pct == 0 ? 0.012 : _pct,
                  strokeWidth: 4.5,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              Text(
                '${(_pct * 100).round()}',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, height: 1),
              ),
            ],
          ),
        );
      },
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
  final Animation<double> pulse;

  const _Planet({required this.color, required this.icon, required this.locked, required this.seed, required this.pulse});

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
    // Inelul e mai lat decât globul, iar cutia planetei trebuie să fie destul
    // de lată cât să-l CUPRINDĂ. Altfel (cu OverflowBox peste o cutie de
    // mărimea globului) inelul iese peste coloana de text de lângă și
    // acoperă începutul subtitlului.
    const ringWidth = size * 1.3;
    return SizedBox(
      width: ringWidth,
      height: size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // inelul (Saturn) — desenat SUB glob, ușor înclinat, colorat pe tema
          // categoriei, și rotit ÎNCET, continuu (vezi CategoriesScreen._liveCtrl)
          // — planeta se simte vie, nu doar desenată static.
          //
          if (!locked)
            AnimatedBuilder(
              animation: pulse,
              // LEGĂNARE în jurul înclinării naturale, nu rotație completă:
              // un inel de Saturn rotit 360° ajunge vertical la jumătatea
              // buclei și arată ca o toartă de coș, nu ca un inel. ±0.22 rad
              // (~13°) e destul cât să se vadă că se mișcă, fără să iasă din
              // silueta recognoscibilă de planetă.
              builder: (context, child) =>
                  Transform.rotate(angle: -0.34 + sin(pulse.value * 2 * pi) * 0.22, child: child),
              child: Container(
                width: ringWidth,
                height: size * 0.52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _shade(color, 0.28), width: 2.6),
                  boxShadow: [BoxShadow(color: color.withAlpha(140), blurRadius: 8)],
                ),
                // un mic "glint" alb, fixat la un capăt al inelului — se
                // rotește ODATĂ CU el, ca mișcarea să se vadă limpede chiar
                // și într-o captură statică, nu doar la privire directă.
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [BoxShadow(color: Colors.white.withAlpha(200), blurRadius: 6, spreadRadius: 1)],
                    ),
                  ),
                ),
              ),
            ),
          // CÂMPUL DE CONTAINMENT al unei categorii blocate — două arce
          // punctate care se rotesc în sensuri opuse. Înlocuiesc lacătul
          // simplu: o categorie blocată nu e „stricată", e ținută închisă și
          // se poate deschide, iar asta trebuie să se vadă din desen.
          if (locked) ...[
            AnimatedBuilder(
              animation: pulse,
              builder: (context, child) => Transform.rotate(angle: pulse.value * 2 * pi, child: child),
              child: CustomPaint(
                size: const Size(size + 8, size + 8),
                painter: const ContainmentArcPainter(color: Color(0x807FE7FF), dashCount: 12, gapFraction: 0.55),
              ),
            ),
            AnimatedBuilder(
              animation: pulse,
              builder: (context, child) => Transform.rotate(angle: -pulse.value * 2 * pi * 0.7, child: child),
              child: CustomPaint(
                size: const Size(size - 2, size - 2),
                painter: const ContainmentArcPainter(color: Color(0x5A7FE7FF), dashCount: 8, gapFraction: 0.6),
              ),
            ),
          ],
          // globul propriu-zis, cu textură + luciu, deasupra inelului — glow-ul
          // respiră în ritmul [pulse], nu rămâne fix.
          AnimatedBuilder(
            animation: pulse,
            builder: (context, child) {
              final breathe = (sin(pulse.value * 2 * pi) + 1) / 2;
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: locked
                      ? null
                      : RadialGradient(
                          center: const Alignment(-0.4, -0.45),
                          radius: 1.05,
                          colors: [
                            _shade(color, 0.30, 0.05),
                            _shade(color, 0.06),
                            color,
                            _shade(color, -0.20, 0.10),
                            _shade(color, -0.34, 0.10),
                          ],
                          stops: const [0.0, 0.28, 0.55, 0.8, 1.0],
                        ),
                  // Conturul e DOAR o separare de fundal, nu un desen: la
                  // opacitate plină ieșea aproape negru și tăia exact peste
                  // lumina de margine, adică peste lucrul care dă volumul.
                  border: Border.all(
                    color: locked
                        ? const Color(0xFF7FE7FF).withAlpha(70)
                        : _shade(color, -0.30, 0.1).withAlpha(120),
                    width: 1.0,
                  ),
                  boxShadow: locked
                      // și planeta stinsă respiră, doar rece și mult mai slab —
                      // semn că e „în hibernare", nu că lipsește.
                      ? [BoxShadow(color: const Color(0xFF7FE7FF).withAlpha((25 + breathe * 35).round()), blurRadius: 8 + breathe * 6)]
                      : [
                          BoxShadow(color: color.withAlpha((100 + breathe * 60).round()), blurRadius: 14 + breathe * 8, spreadRadius: 0.5),
                          const BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 3)),
                        ],
                ),
                clipBehavior: Clip.antiAlias,
                child: child,
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (locked)
                  // corpul stins + grilajul de scanare, derulat de [pulse]
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: pulse,
                      builder: (context, _) => CustomPaint(
                        painter: DormantPlanetPainter(seed: seed, base: color, phase: pulse.value),
                      ),
                    ),
                  )
                else
                  Positioned.fill(child: CustomPaint(painter: PlanetSurfacePainter(seed: seed, base: color))),
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
                // La blocat se vede ICONIȚA CATEGORIEI, stinsă, nu un lacăt:
                // jucătorul trebuie să știe CE anume e închis acolo. Lacătul
                // rămâne, dar mic, într-un colț — indiciu, nu subiect.
                Icon(
                  icon,
                  color: Colors.white.withAlpha(locked ? 90 : 255),
                  size: 22,
                  shadows: const [Shadow(color: Colors.black45, blurRadius: 3)],
                ),
                if (locked)
                  Positioned(
                    right: size * 0.10,
                    bottom: size * 0.10,
                    child: AnimatedBuilder(
                      animation: pulse,
                      builder: (context, child) => Opacity(
                        opacity: 0.55 + (sin(pulse.value * 2 * pi) + 1) / 2 * 0.45,
                        child: child,
                      ),
                      child: const Icon(Icons.lock_rounded, color: Color(0xFF7FE7FF), size: 13),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
                locked ? tr('DEBLOCHEAZĂ', 'UNLOCK') : 'UPGRADE',
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
