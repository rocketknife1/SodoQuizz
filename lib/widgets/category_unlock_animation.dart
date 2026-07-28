import 'dart:math';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/theme.dart';

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

  const CategoryUnlockAnimation({
    super.key,
    required this.categoryTitle,
    required this.unlockedCount,
  });

  static Future<void> show(
    BuildContext context, {
    required String categoryTitle,
    required int unlockedCount,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => CategoryUnlockAnimation(
        categoryTitle: categoryTitle,
        unlockedCount: unlockedCount,
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
                          AppColors.coin.withAlpha(_alpha(160, burstOpacity).toInt()),
                          AppColors.coin.withAlpha(0),
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
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (isUnlocked ? AppColors.coin : AppColors.purple).withAlpha(50),
                            border: Border.all(
                              color: (isUnlocked ? AppColors.coin : AppColors.purple).withAlpha(180),
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            isUnlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                            color: Colors.white,
                            size: 46,
                          ),
                        ),
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
                          '+${widget.unlockedCount} întrebări deblocate!',
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

  /// Câțiva nori simpli (Icons.cloud) care plutesc dinspre margini spre
  /// centru și apoi se risipesc odată ce lacătul se deschide — acoperă
  /// lacătul chiar înainte de deblocare, ca să pară că "iese" din spatele
  /// lor. Traiectoria foloseşte o curbă ease în ambele sensuri, nu
  /// interpolare liniară, ca mişcarea să nu pară mecanică.
  List<Widget> _buildClouds(double t) {
    const specs = [
      (dx: -1.0, dy: -0.35, size: 90.0, delay: 0.0),
      (dx: 1.0, dy: -0.25, size: 110.0, delay: 0.06),
      (dx: -0.9, dy: 0.4, size: 100.0, delay: 0.12),
      (dx: 0.95, dy: 0.45, size: 80.0, delay: 0.09),
    ];
    // norii intră (0.0-0.34), stau peste lacăt cât acesta se deschide,
    // apoi se împrăștie spre margini din nou (0.58-0.95).
    return specs.map((s) {
      final inRaw = ((t - s.delay) / 0.34).clamp(0.0, 1.0);
      final outRaw = ((t - 0.58) / 0.37).clamp(0.0, 1.0);
      final inT = Curves.easeOutCubic.transform(inRaw);
      final outT = Curves.easeInCubic.transform(outRaw);
      final travel = inT * (1 - outT);
      final offsetX = s.dx * (1 - travel) * 140;
      final offsetY = s.dy * (1 - travel) * 140 - outT * 40;
      final opacity = inT * (1 - outT * outT);
      return Transform.translate(
        offset: Offset(offsetX, offsetY),
        child: Icon(
          Icons.cloud_rounded,
          color: Colors.white.withAlpha(_alpha(60, opacity).toInt()),
          size: s.size,
        ),
      );
    }).toList();
  }
}
