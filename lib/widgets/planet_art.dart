import 'dart:math';
import 'package:flutter/material.dart';

/// Suprafața unei planete, desenată ca un CORP SFERIC, nu ca un disc colorat.
///
/// Ce o face să pară rotundă, în ordinea în care contează ochiul:
///
///  1. BENZI LATITUDINALE CURBATE. Un gigant gazos nu are pete împrăștiate
///     aleator, ci dungi paralele cu ecuatorul. Curbura lor (mai plate la
///     ecuator, tot mai arcuite spre poli) e singurul indiciu care spune
///     "sferă" și nu "cerc" — de-aia sunt desenate ca arce de elipsă cu
///     înălțime variabilă, nu ca linii drepte.
///  2. TERMINATOR. Umbra care se îngroașă spre marginea opusă sursei de
///     lumină. Fără ea, planeta pare iluminată uniform, adică plată.
///  3. LUMINĂ DE MARGINE (rim light). O dungă subțire, luminoasă, pe conturul
///     dinspre lumină — separă planeta de fundal și îi dă volum.
///  4. O FURTUNĂ (ca Pata Roșie a lui Jupiter) — un oval ușor înclinat, care
///     dă scară și un punct de interes; altfel benzile singure par un
///     material textil.
///
/// [rotation] (0..1) derulează benzile pe orizontală. Trecută dintr-o buclă
/// de animație, planeta chiar pare că se rotește în jurul axei ei; lăsată pe
/// 0, desenul e static, dar la fel de rotund.
class PlanetSurfacePainter extends CustomPainter {
  /// Același seed dă mereu aceeași planetă — fiecare categorie trebuie să
  /// arate identic la fiecare redesenare, nu să se re-randomizeze.
  final int seed;
  final Color base;
  final double rotation;

  /// Din ce direcție bate lumina, în unități normalizate (-1..1). Trebuie să
  /// fie ACEEAȘI cu centrul gradientului radial din spatele desenului, altfel
  /// luciul și umbra se contrazic și efectul 3D se rupe.
  final Alignment light;

  const PlanetSurfacePainter({
    required this.seed,
    required this.base,
    this.rotation = 0,
    this.light = const Alignment(-0.4, -0.45),
  });

  static Color _shade(Color c, double dl, [double ds = 0]) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + dl).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation + ds).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = size.center(Offset.zero);
    final rnd = Random(seed * 97 + 13);

    // Tot desenul stă în interiorul discului — părintele are deja
    // clipBehavior, dar pe web/desktop marginea iese altfel, deci clipăm și
    // aici ca rezultatul să fie identic peste tot.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));

    _paintBands(canvas, c, r, rnd);
    _paintStorm(canvas, c, r, rnd);
    _paintTerminator(canvas, c, r);
    _paintRimLight(canvas, c, r);

    canvas.restore();
  }

  /// Benzile: fiecare e un arc de elipsă care traversează sfera. Cu cât banda
  /// e mai aproape de un pol (|y| mare), cu atât e mai scurtă (proiecția
  /// sferei) și mai curbată.
  void _paintBands(Canvas canvas, Offset c, double r, Random rnd) {
    const bandCount = 7;
    for (var i = 0; i < bandCount; i++) {
      // latitudine în -0.85..0.85 (nu chiar polii, acolo banda ar fi un punct)
      final lat = -0.85 + (i / (bandCount - 1)) * 1.7;
      final y = c.dy + lat * r;
      // jumătatea lățimii benzii la latitudinea asta = raza cercului de
      // secțiune al sferei. Ăsta e motivul pentru care benzile se scurtează
      // spre poli fără să fie nevoie de vreun truc.
      final halfWidth = r * sqrt(max(0.0, 1 - lat * lat));
      if (halfWidth < 2) continue;

      final thickness = r * (0.10 + rnd.nextDouble() * 0.10);
      final lighter = rnd.nextBool();
      // rotația derulează benzile: fiecare bandă primește un mic decalaj pe
      // orizontală, ca textura să pară că trece pe lângă privitor.
      final drift = sin(rotation * 2 * pi + i * 0.7) * r * 0.06;

      final paint = Paint()
        ..color = (lighter ? _shade(base, 0.16, 0.05) : _shade(base, -0.16, 0.05))
            .withAlpha(lighter ? 60 : 80)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, thickness * 0.45);

      // arc curbat: mijlocul benzii e împins spre polul cel mai apropiat,
      // ca dunga să urmeze suprafața sferei, nu să taie drept peste ea.
      final bow = -lat * r * 0.18;
      final path = Path()
        ..moveTo(c.dx - halfWidth + drift, y)
        ..quadraticBezierTo(c.dx + drift, y + bow, c.dx + halfWidth + drift, y);
      canvas.drawPath(
        path,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness,
      );
    }
  }

  /// Furtuna — un oval întors ușor, cu un miez mai deschis, așezat pe una
  /// dintre benzi (nu la întâmplare pe disc).
  void _paintStorm(Canvas canvas, Offset c, double r, Random rnd) {
    final lat = -0.45 + rnd.nextDouble() * 0.9;
    final halfWidth = r * sqrt(max(0.0, 1 - lat * lat));
    final sx = c.dx + (rnd.nextDouble() - 0.5) * halfWidth * 1.2 + sin(rotation * 2 * pi) * r * 0.06;
    final sy = c.dy + lat * r;
    final rx = r * (0.20 + rnd.nextDouble() * 0.10);
    final ry = rx * 0.62;

    canvas.save();
    canvas.translate(sx, sy);
    canvas.rotate(-0.25);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      Paint()
        ..color = _shade(base, -0.24, 0.18).withAlpha(110)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rx * 0.35),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: rx * 1.1, height: ry * 1.1),
      Paint()
        ..color = _shade(base, 0.22, 0.12).withAlpha(90)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rx * 0.25),
    );
    canvas.restore();
  }

  /// Umbra care se îngroașă spre partea opusă luminii — partea care chiar
  /// transformă discul în sferă.
  void _paintTerminator(Canvas canvas, Offset c, double r) {
    final dark = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(-light.x, -light.y),
          radius: 1.15,
          colors: [
            Colors.black.withAlpha(120),
            Colors.black.withAlpha(45),
            Colors.black.withAlpha(0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(dark),
    );
  }

  /// Dunga luminoasă de pe conturul dinspre lumină — subțire, doar pe arcul
  /// dinspre sursă, nu de jur împrejur (altfel ar arăta ca un contur desenat).
  void _paintRimLight(Canvas canvas, Offset c, double r) {
    final start = atan2(light.y, light.x) - 1.1;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 1.2),
      start,
      2.2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..color = _shade(base, 0.42, 0.1).withAlpha(170)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
    );
  }

  @override
  bool shouldRepaint(covariant PlanetSurfacePainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.base != base || oldDelegate.rotation != rotation || oldDelegate.light != light;
}

/// Planeta „adormită" — cum arată o categorie încă blocată. NU un cerc gri cu
/// lacăt: e aceeași planetă, doar stinsă, ținută sub un câmp de containment.
///
/// Ideea vizuală: corpul e desaturat aproape complet (se ghicește ce culoare
/// ar avea, fără s-o arate), peste el trece un grilaj de „energie" rece, iar
/// în jur se rotesc două arce punctate — semnul că nu e stricată, ci ținută
/// închisă și că se poate deschide.
class DormantPlanetPainter extends CustomPainter {
  final int seed;
  /// Culoarea reală a categoriei — folosită STINSĂ, doar cât să lase impresia
  /// că planeta are o identitate care așteaptă să fie aprinsă.
  final Color base;
  final double phase;

  const DormantPlanetPainter({required this.seed, required this.base, required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = size.center(Offset.zero);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));

    // corpul stins — o urmă de culoare, nu culoarea plină
    final grey = HSLColor.fromColor(base).withSaturation(0.14).withLightness(0.26).toColor();
    canvas.drawCircle(c, r, Paint()..color = grey);

    // relief slab, ca să nu fie o pată uniformă
    final rnd = Random(seed * 31 + 7);
    for (var i = 0; i < 5; i++) {
      final a = rnd.nextDouble() * 2 * pi;
      final d = rnd.nextDouble() * r * 0.7;
      canvas.drawCircle(
        c + Offset(cos(a) * d, sin(a) * d),
        r * (0.10 + rnd.nextDouble() * 0.14),
        Paint()
          ..color = Colors.black.withAlpha(40)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12),
      );
    }

    // grilaj de containment — linii orizontale reci care „scanează" corpul,
    // derulate de [phase]; ele spun „ținut închis", nu „stricat".
    final scan = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF7FE7FF).withAlpha(45);
    for (var i = -6; i <= 6; i++) {
      final y = c.dy + ((i / 6) * r) + (phase % 1.0) * (r / 3);
      if ((y - c.dy).abs() > r) continue;
      canvas.drawLine(Offset(c.dx - r, y), Offset(c.dx + r, y), scan);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DormantPlanetPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.base != base || oldDelegate.phase != phase;
}

/// Arc punctat care se rotește — folosit ca „câmp de containment" în jurul
/// unei planete blocate. Două instanțe suprapuse, cu raze și viteze diferite,
/// dau senzația de dispozitiv activ, nu de chenar decorativ.
class ContainmentArcPainter extends CustomPainter {
  final Color color;
  final int dashCount;
  final double gapFraction;

  const ContainmentArcPainter({required this.color, this.dashCount = 14, this.gapFraction = 0.55});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final dash = (2 * pi / dashCount) * (1 - gapFraction);
    final gap = (2 * pi / dashCount) * gapFraction;
    var a = 0.0;
    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), a, dash, false, paint);
      a += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant ContainmentArcPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dashCount != dashCount || oldDelegate.gapFraction != gapFraction;
}
