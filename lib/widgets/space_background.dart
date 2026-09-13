import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/theme.dart';

/// Fundal spațial reutilizabil — gradient navy → violet, două nebuloase
/// difuze și un câmp de stele cu o derivă lentă și continuă (cerută explicit
/// pe telefon, 2026-09-09: „sa para ca esti in spatiu si e miscare").
/// Folosit în spatele meniului principal și al ecranului de categorii, ca
/// bază vizuală comună pentru tema de "planete".
class SpaceBackground extends StatefulWidget {
  final Widget child;
  const SpaceBackground({super.key, required this.child});

  @override
  State<SpaceBackground> createState() => _SpaceBackgroundState();
}

class _SpaceBackgroundState extends State<SpaceBackground> with SingleTickerProviderStateMixin {
  /// Secunde scurse de la montarea widget-ului, CRESC LA NESFÂRȘIT (nu se
  /// resetează niciodată la o buclă) — fiecare stea își înfășoară singură
  /// poziția cu `% 1.0` în [_StarfieldPainter], deci mișcarea rămâne
  /// continuă oricât ar sta ecranul deschis, fără nicio săritură vizibilă la
  /// vreun "capăt de buclă" (nu există unul).
  ///
  /// [ValueNotifier] în loc de `setState`: painter-ul e legat de el prin
  /// `CustomPainter(repaint: ...)`, care redesenează DOAR canvas-ul de
  /// stele la fiecare cadru, fără să reconstruiască restul arborelui (adică
  /// [widget.child] — ecranul întreg din spatele căruia stă fundalul ăsta).
  /// Un `setState` aici, la 60 de cadre pe secundă, ar fi însemnat un
  /// rebuild complet al ecranului de fiecare dată.
  final ValueNotifier<double> _seconds = ValueNotifier(0);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _seconds.value = elapsed.inMicroseconds / 1e6;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.spaceGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _StarfieldPainter(_seconds))),
          ),
          Positioned(top: -70, left: -60, child: _nebula(AppColors.purple.withAlpha(70), 220)),
          Positioned(bottom: -90, right: -70, child: _nebula(AppColors.blue.withAlpha(45), 260)),
          widget.child,
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

/// O stea — poziție ca FRACȚIE din suprafață (0..1), ca același câmp să se
/// întindă corect pe orice mărime de ecran fără recalcul. [depth] e doar un
/// multiplicator de viteză (1 sau 1,6): stelele "mai apropiate" derivează
/// puțin mai repede decât cele "îndepărtate", pentru o senzație discretă de
/// adâncime, nu un paralax accentuat.
class _Star {
  final double dx, dy;
  final double radius;
  final int baseAlpha;
  final double depth;
  const _Star(this.dx, this.dy, this.radius, this.baseAlpha, this.depth);
}

class _StarfieldPainter extends CustomPainter {
  final ValueListenable<double> seconds;
  _StarfieldPainter(this.seconds) : super(repaint: seconds);

  static final List<_Star> _stars = _generate();

  static List<_Star> _generate() {
    final rnd = Random(7);
    return [
      for (var i = 0; i < 110; i++)
        _Star(
          rnd.nextDouble(),
          rnd.nextDouble(),
          rnd.nextDouble() * 1.3 + 0.3,
          50 + rnd.nextInt(150),
          rnd.nextBool() ? 1.0 : 1.6,
        ),
    ];
  }

  /// Cât din înălțime/lățime parcurge un strat "de bază" (depth 1.0) într-o
  /// secundă. Deliberat FOARTE lent — cerința explicită a fost „putin cat sa
  /// se miste", nu un tunel de stele: la [_perSecondY] de mai jos, un strat
  /// normal traversează tot ecranul o dată la ~2:40 minute.
  static const double _perSecondY = 1 / 160;
  static const double _perSecondX = _perSecondY * 0.22; // ușor pe diagonală

  @override
  void paint(Canvas canvas, Size size) {
    final t = seconds.value;
    final paint = Paint();
    for (final s in _stars) {
      final fx = (s.dx + t * _perSecondX * s.depth) % 1.0;
      final fy = (s.dy + t * _perSecondY * s.depth) % 1.0;
      paint.color = Colors.white.withAlpha(s.baseAlpha);
      canvas.drawCircle(Offset(fx * size.width, fy * size.height), s.radius, paint);
    }
  }

  /// Repictarea reală vine din `repaint: seconds` (mai sus) — sistemul de
  /// widget-uri cheamă [paint] direct la fiecare tick al lui, fără să treacă
  /// prin [shouldRepaint]. Asta rămâne relevant doar dacă vreodată s-ar
  /// construi un painter NOU (alt `seconds`), ceea ce azi nu se întâmplă.
  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) => oldDelegate.seconds != seconds;
}
