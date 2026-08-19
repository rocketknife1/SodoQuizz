import 'dart:math';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import 'planet_art.dart';

/// Animație scurtă (dialog peste ecranul curent) arătată când jucătorul
/// deblochează un lot nou de întrebări la o categorie: un lacăt se
/// descuie printre nori, urmat de un puls auriu, apoi totul se estompează
/// și dialogul se închide singur — fără niciun tap necesar.
///
/// Apelul e "fire and forget" din punct de vedere al UI-ului care o
/// declanșează: [show] se închide automat, deci codul apelant doar
/// așteaptă Future-ul returnat înainte să continue (ex. reîncărcarea
/// întrebărilor), fără să mai gestioneze el Navigator.pop.
///
/// Notă de performanță: nu se folosesc widget-uri [Opacity]/[FadeTransition]
/// suprapuse pe elementele animate (fiecare ar cere un `saveLayer` — strat
/// offscreen — recompus la fiecare frame, ceea ce dă exact senzația de
/// "lag" pe un dialog plin de elemente ca acesta). În loc de asta, opacitatea
/// fiecărei forme e amestecată direct în canalul alfa al culorii ei, iar
/// singurul `Opacity` real e cel de pe fundal, izolat într-un
/// [RepaintBoundary] separat de restul compoziției.
class CategoryUnlockAnimation extends StatefulWidget {
  final String categoryTitle;
  final int unlockedCount;

  /// Culoarea și iconița categoriei deblocate — planeta care se trezește
  /// trebuie să fie CHIAR planeta ei, nu un lacăt generic. Fără ele animația
  /// nu spune ce anume s-a deschis.
  final Color color;
  final IconData icon;
  final int seed;

  const CategoryUnlockAnimation({
    super.key,
    required this.categoryTitle,
    required this.unlockedCount,
    required this.color,
    required this.icon,
    this.seed = 3,
  });

  static Future<void> show(
    BuildContext context, {
    required String categoryTitle,
    required int unlockedCount,
    required Color color,
    required IconData icon,
    int seed = 3,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => CategoryUnlockAnimation(
        categoryTitle: categoryTitle,
        unlockedCount: unlockedCount,
        color: color,
        icon: icon,
        seed: seed,
      ),
    );
  }

  @override
  State<CategoryUnlockAnimation> createState() => _CategoryUnlockAnimationState();
}

class _CategoryUnlockAnimationState extends State<CategoryUnlockAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  // Durată puțin mai lungă și fără accelerații bruște — fiecare fază are
  // propria curbă de easing, nu doar interpolare liniară pe fracțiuni de t.
  static const _duration = Duration(milliseconds: 3400);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _duration);
    _c.forward();
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Navigator.of(context).pop();
      }
    });
    // pocnet exact la momentul deschiderii lacătului (vezi _unlockEnd).
    Future.delayed(
      Duration(milliseconds: (_duration.inMilliseconds * _unlockEnd).round()),
      () {
        if (mounted) Sfx.rewardPop();
      },
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // Intervalul (din durata totală) în care lacătul trece din închis în
  // deschis — restul fazelor (intrare nori, ieșire) se calculează relativ.
  static const _unlockStart = 0.34;
  static const _unlockEnd = 0.52;

  static double _alpha(int base, double factor) => (base * factor.clamp(0.0, 1.0)).roundToDouble();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          // fade-in lin (0-0.18), stabil, fade-out lin la final (0.84-1.0) —
          // curbe ease pe ambele capete, nu treaptă liniară abruptă.
          final fadeInRaw = (t / 0.18).clamp(0.0, 1.0);
          final fadeOutRaw = 1.0 - ((t - 0.84) / 0.16).clamp(0.0, 1.0);
          final fadeIn = Curves.easeOutCubic.transform(fadeInRaw);
          final fadeOut = Curves.easeInCubic.transform(fadeOutRaw);
          final opacity = fadeIn * fadeOut;

          final unlockRaw = ((t - _unlockStart) / (_unlockEnd - _unlockStart)).clamp(0.0, 1.0);
          final unlockT = Curves.easeOutBack.transform(unlockRaw);
          final isUnlocked = unlockRaw >= 1.0;
          // mic "shake" chiar înainte de deschidere, amortizat exponențial.
          final shakeRaw = ((t - 0.22) / (_unlockStart - 0.22)).clamp(0.0, 1.0);
          final shake = sin(shakeRaw * pi * 5) * (1 - shakeRaw) * (1 - shakeRaw) * 0.09;

          // pulsul auriu apare exact când se deschide lacătul și se stinge
          // treptat spre finalul animației.
          final burstRaw = ((t - _unlockEnd) / 0.4).clamp(0.0, 1.0);
          final burstEase = Curves.easeOutCubic.transform(burstRaw);
          final burstScale = 0.3 + burstEase * 1.6;
          final burstOpacity = unlockRaw >= 1.0 ? (1 - burstEase).clamp(0.0, 1.0) : 0.0;

          final scale = 0.85 + fadeIn * 0.15 + unlockT.clamp(0.0, 1.0) * 0.06;

          return Opacity(
            opacity: opacity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ..._buildClouds(t),
                Transform.scale(
                  scale: burstScale,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          widget.color.withAlpha(_alpha(190, burstOpacity).toInt()),
                          widget.color.withAlpha(0),
                        ],
                      ),
                    ),
                  ),
                ),
                Transform.scale(
                  scale: scale,
                  child: Transform.rotate(
                    angle: isUnlocked ? 0 : shake,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPlanet(unlockRaw, isUnlocked, t),
                        const SizedBox(height: 18),
                        Text(
                          widget.categoryTitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withAlpha(_alpha(255, fadeIn).toInt()),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr('+${widget.unlockedCount} întrebări deblocate!',
                              '+${widget.unlockedCount} questions unlocked!'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.coin.withAlpha(_alpha(255, isUnlocked ? fadeIn : 0.0).toInt()),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Planeta care se trezește — miezul animației. Trece prin trei stări, în
  /// aceeași ordine în care le citește ochiul:
  ///
  ///  1. ADORMITĂ: corp stins, sub grilaj de scanare, strâns în două arce de
  ///     containment care se rotesc (același limbaj ca pe cardul blocat, ca
  ///     jucătorul să recunoască imediat CE se deschide).
  ///  2. APRINDERE: culoarea categoriei urcă din interior, benzile de
  ///     suprafață devin vizibile, glow-ul crește.
  ///  3. ELIBERARE: arcele se sparg și zboară în afară, rotindu-se.
  Widget _buildPlanet(double unlockRaw, bool isUnlocked, double t) {
    const d = 104.0;
    // cât de „aprinsă" e planeta (0 = stinsă, 1 = culoare plină)
    final lit = Curves.easeInOut.transform(unlockRaw);
    // arcele se depărtează după deschidere
    final shardOut = isUnlocked ? Curves.easeOutCubic.transform(((t - _unlockEnd) / 0.3).clamp(0.0, 1.0)) : 0.0;

    return SizedBox(
      width: d + 40,
      height: d + 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // corpul: stins dedesubt, culoarea reală desenată peste, cu alfa
          // care crește — asta face „aprinderea" fără să schimbăm widget-ul.
          Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF23283D),
              boxShadow: [
                BoxShadow(color: widget.color.withAlpha((160 * lit).round()), blurRadius: 26 * lit, spreadRadius: 2 * lit),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: DormantPlanetPainter(seed: widget.seed, base: widget.color, phase: t * 2)),
                ),
                // stratul „viu", cu opacitate crescătoare
                Positioned.fill(
                  child: Opacity(
                    opacity: lit,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: const Alignment(-0.4, -0.45),
                          radius: 1.05,
                          colors: [
                            _shade(widget.color, 0.30),
                            widget.color,
                            _shade(widget.color, -0.30),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                      child: CustomPaint(painter: PlanetSurfacePainter(seed: widget.seed, base: widget.color, rotation: t)),
                    ),
                  ),
                ),
                Icon(widget.icon, color: Colors.white.withAlpha((110 + 145 * lit).round()), size: 40),
              ],
            ),
          ),
          // arcele de containment — se rotesc cât planeta e închisă, apoi
          // zboară în afară și se sting.
          for (final (i, spec) in [(0, 1.0), (1, -0.7)].indexed)
            Transform.scale(
              scale: 1 + shardOut * (0.6 + i * 0.25),
              child: Transform.rotate(
                angle: t * 2 * pi * spec.$2,
                child: Opacity(
                  opacity: (1 - shardOut).clamp(0.0, 1.0),
                  child: CustomPaint(
                    size: Size(d + 16 - i * 14, d + 16 - i * 14),
                    painter: ContainmentArcPainter(
                      color: const Color(0xFF7FE7FF).withAlpha(i == 0 ? 190 : 120),
                      dashCount: i == 0 ? 12 : 8,
                      gapFraction: 0.55,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Color _shade(Color c, double dl) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + dl).clamp(0.0, 1.0)).toColor();
  }

  /// Resturi orbitale — mici scântei care se strâng în jurul planetei cât e
  /// încă închisă, apoi sunt împrăștiate afară de eliberare.
  ///
  /// Erau NORI (Icons.cloud) pe vremea când animația arăta un lacăt: pe
  /// lângă o planetă în spațiu, norii se citeau ca o greșeală de decor. Un
  /// corp ceresc are praf și fragmente în jur, nu vreme.
  List<Widget> _buildClouds(double t) {
    const specs = [
      (angle: 0.6, dist: 150.0, size: 7.0, delay: 0.00),
      (angle: 2.1, dist: 128.0, size: 5.0, delay: 0.05),
      (angle: 3.4, dist: 160.0, size: 8.0, delay: 0.10),
      (angle: 4.6, dist: 134.0, size: 5.5, delay: 0.07),
      (angle: 5.6, dist: 146.0, size: 6.5, delay: 0.13),
      (angle: 1.3, dist: 170.0, size: 4.5, delay: 0.16),
    ];
    return specs.map((s) {
      final inRaw = ((t - s.delay) / 0.34).clamp(0.0, 1.0);
      final outRaw = ((t - _unlockEnd) / 0.34).clamp(0.0, 1.0);
      final inT = Curves.easeOutCubic.transform(inRaw);
      final outT = Curves.easeInCubic.transform(outRaw);
      // se apropie până la ~60% din distanță, apoi sunt zvârlite dincolo de
      // punctul de plecare
      final dist = s.dist * (1 - inT * 0.4) + outT * 210;
      // se rotesc ușor în jurul planetei cât se apropie — orbitează, nu cad
      final a = s.angle + inT * 0.5 + outT * 0.35;
      final opacity = inT * (1 - outT * outT);
      return Transform.translate(
        offset: Offset(cos(a) * dist, sin(a) * dist),
        child: Container(
          width: s.size,
          height: s.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withAlpha(_alpha(210, opacity).toInt()),
            boxShadow: [
              BoxShadow(
                color: widget.color.withAlpha(_alpha(190, opacity).toInt()),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}
