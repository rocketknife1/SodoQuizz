import 'dart:math';

import 'package:flutter/material.dart';
import '../core/lang.dart';

/// Avatarele pe care și le poate alege jucătorul din Profil, pe lângă poza
/// implicită.
///
/// Sunt DESENATE în cod, nu imagini: la fel ca mascotele din widgets/mascots/,
/// se redau curat la orice dimensiune (de la 36px în lista de prieteni până la
/// 88px în Profil) și nu îngroașă APK-ul — poza implicită singură are 1 MB, iar
/// patru PNG-uri în plus s-ar fi văzut direct în mărimea descărcării.
///
/// [AvatarStyle.poza] înseamnă „lasă cum era": poza de Google dacă ești logat,
/// altfel poza implicită din assets. Restul înlocuiesc complet poza, inclusiv
/// pentru conturile Google — altfel alegerea n-ar avea niciun efect vizibil
/// pentru cine e logat.
enum AvatarStyle {
  poza('poza', 'Poza mea', 'My picture'),
  fata('fata', 'Fată', 'Girl'),
  baiat('baiat', 'Băiat', 'Boy'),
  pisica('pisica', 'Pisică', 'Cat'),
  porcusor('porcusor', 'Porcușor', 'Piglet');

  const AvatarStyle(this.id, this._labelRo, this._labelEn);

  /// Id-ul scris în SharedPreferences și în profilul public din Firestore.
  /// Deliberat un șir scurt și stabil, NU indexul din enum: o reordonare a
  /// valorilor de mai jos ar schimba altfel avatarul tuturor jucătorilor.
  final String id;
  final String _labelRo;
  final String _labelEn;

  /// Numele arătat în ecranul de Profil. Getter, nu câmp: o constantă de enum
  /// nu poate chema tr(), deci se țin ambele variante și se alege la citire.
  String get label => tr(_labelRo, _labelEn);

  bool get isArt => this != AvatarStyle.poza;
}

AvatarStyle avatarStyleFromId(String? id) {
  for (final s in AvatarStyle.values) {
    if (s.id == id) return s;
  }
  return AvatarStyle.poza;
}

/// Avatarul desenat, fără cerc de contur — cel care încadrează îl pune
/// [Avatar] (widgets/avatar.dart), ca stilurile astea să arate identic cu
/// pozele în orice loc din aplicație.
class AvatarArt extends StatelessWidget {
  final AvatarStyle style;
  final double size;

  const AvatarArt({super.key, required this.style, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _AvatarPainter(style)),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  final AvatarStyle style;
  const _AvatarPainter(this.style);

  // Paleta e ținută aici, nu în theme.dart: sunt culori de personaj (piele,
  // blană, păr), n-au ce căuta în paleta de UI a aplicației.
  static const _skin = Color(0xFFF6C9A8);
  static const _skinShadow = Color(0xFFE0A882);
  static const _hairGirl = Color(0xFF5B3A29);
  static const _hairBoy = Color(0xFF2F2A28);
  static const _catFur = Color(0xFF8A8FA3);
  static const _catFurDark = Color(0xFF6D7287);
  static const _pigFur = Color(0xFFC98A5B);
  static const _pigCream = Color(0xFFF3E2CE);
  static const _ink = Color(0xFF2B2233);
  static const _blush = Color(0x55E9698A);
  static const _pink = Color(0xFFEE8FA6);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);

    // fundalul: fiecare stil are propriul cerc colorat, ca avatarele să se
    // deosebească dintr-o privire chiar și la 36px, în lista de prieteni
    final bg = switch (style) {
      AvatarStyle.fata => const [Color(0xFFF7A8C4), Color(0xFFCE5C92)],
      AvatarStyle.baiat => const [Color(0xFF7FC8F5), Color(0xFF3E7FD1)],
      AvatarStyle.pisica => const [Color(0xFFB6BDD6), Color(0xFF6B72A0)],
      AvatarStyle.porcusor => const [Color(0xFFF6C98A), Color(0xFFCE8447)],
      AvatarStyle.poza => const [Color(0xFF8B7BD8), Color(0xFF5B4CA8)],
    };
    canvas.drawCircle(
      c,
      s / 2,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bg,
        ).createShader(Rect.fromCircle(center: c, radius: s / 2)),
    );

    switch (style) {
      case AvatarStyle.fata:
        _paintGirl(canvas, s);
      case AvatarStyle.baiat:
        _paintBoy(canvas, s);
      case AvatarStyle.pisica:
        _paintCat(canvas, s);
      case AvatarStyle.porcusor:
        _paintPig(canvas, s);
      case AvatarStyle.poza:
        break;
    }
  }

  // ─── piese comune ────────────────────────────────────────────────────────

  /// Ochi rotunzi cu lumină în ei. [pupilW] sub 1 îngustează pupila — așa se
  /// obține privirea de pisică, fără un desen separat.
  void _eyes(Canvas canvas, double s, double y, double dx, double r,
      {double pupilW = 1.0}) {
    final white = Paint()..color = Colors.white;
    final ink = Paint()..color = _ink;
    final shine = Paint()..color = Colors.white;
    for (final sign in [-1.0, 1.0]) {
      final e = Offset(s / 2 + sign * dx, y);
      canvas.drawCircle(e, r, white);
      canvas.drawOval(
        Rect.fromCenter(center: e, width: r * 1.15 * pupilW, height: r * 1.3),
        ink,
      );
      canvas.drawCircle(Offset(e.dx + r * 0.28, y - r * 0.34), r * 0.24, shine);
    }
  }

  void _blushMarks(Canvas canvas, double s, double y, double dx, double r) {
    final p = Paint()..color = _blush;
    for (final sign in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(s / 2 + sign * dx, y), width: r * 2, height: r * 1.4),
        p,
      );
    }
  }

  void _smile(Canvas canvas, double s, double y, double w, double depth) {
    canvas.drawArc(
      Rect.fromCenter(center: Offset(s / 2, y), width: w, height: depth),
      pi * 0.15,
      pi * 0.7,
      false,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.035
        ..strokeCap = StrokeCap.round,
    );
  }

  // ─── fată ────────────────────────────────────────────────────────────────

  void _paintGirl(Canvas canvas, double s) {
    final hair = Paint()..color = _hairGirl;
    // părul lung, în spatele feței
    canvas.drawOval(
      Rect.fromCenter(center: Offset(s / 2, s * 0.56), width: s * 0.78, height: s * 0.82),
      hair,
    );
    // fața
    canvas.drawCircle(Offset(s / 2, s * 0.53), s * 0.30, Paint()..color = _skin);
    // breton: un arc gros peste fruntea
    canvas.drawArc(
      Rect.fromCenter(center: Offset(s / 2, s * 0.50), width: s * 0.62, height: s * 0.60),
      pi,
      pi,
      true,
      hair,
    );
    // fundița, pe stânga sus — piesa care o face „fancy"
    final bow = Paint()..color = _pink;
    final bx = s * 0.24, by = s * 0.28;
    canvas.drawPath(
      Path()
        ..moveTo(bx, by)
        ..lineTo(bx - s * 0.13, by - s * 0.08)
        ..lineTo(bx - s * 0.13, by + s * 0.08)
        ..close(),
      bow,
    );
    canvas.drawPath(
      Path()
        ..moveTo(bx, by)
        ..lineTo(bx + s * 0.12, by - s * 0.09)
        ..lineTo(bx + s * 0.12, by + s * 0.07)
        ..close(),
      bow,
    );
    canvas.drawCircle(Offset(bx, by), s * 0.045, Paint()..color = const Color(0xFFF7B3C6));

    _eyes(canvas, s, s * 0.52, s * 0.115, s * 0.062);
    _blushMarks(canvas, s, s * 0.62, s * 0.185, s * 0.05);
    _smile(canvas, s, s * 0.63, s * 0.17, s * 0.12);
  }

  // ─── băiat ───────────────────────────────────────────────────────────────

  void _paintBoy(Canvas canvas, double s) {
    // fața
    canvas.drawCircle(Offset(s / 2, s * 0.54), s * 0.31, Paint()..color = _skin);
    // urechile
    final ear = Paint()..color = _skinShadow;
    canvas.drawCircle(Offset(s * 0.19, s * 0.55), s * 0.052, ear);
    canvas.drawCircle(Offset(s * 0.81, s * 0.55), s * 0.052, ear);
    // părul: calotă peste frunte, cu un moț în dreapta
    final hair = Paint()..color = _hairBoy;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(s / 2, s * 0.50), width: s * 0.64, height: s * 0.58),
      pi * 1.02,
      pi * 0.96,
      true,
      hair,
    );
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.62, s * 0.25)
        ..quadraticBezierTo(s * 0.78, s * 0.16, s * 0.72, s * 0.31)
        ..quadraticBezierTo(s * 0.68, s * 0.27, s * 0.62, s * 0.25)
        ..close(),
      hair,
    );

    _eyes(canvas, s, s * 0.53, s * 0.115, s * 0.062);
    _blushMarks(canvas, s, s * 0.63, s * 0.19, s * 0.048);
    _smile(canvas, s, s * 0.64, s * 0.19, s * 0.13);
  }

  // ─── pisică ──────────────────────────────────────────────────────────────

  void _paintCat(Canvas canvas, double s) {
    final fur = Paint()..color = _catFur;
    final inner = Paint()..color = _pink;
    // urechile
    for (final sign in [-1.0, 1.0]) {
      final bx = s / 2 + sign * s * 0.20;
      canvas.drawPath(
        Path()
          ..moveTo(bx - s * 0.09, s * 0.40)
          ..lineTo(bx + sign * s * 0.02, s * 0.14)
          ..lineTo(bx + s * 0.11, s * 0.42)
          ..close(),
        fur,
      );
      canvas.drawPath(
        Path()
          ..moveTo(bx - s * 0.045, s * 0.38)
          ..lineTo(bx + sign * s * 0.015, s * 0.23)
          ..lineTo(bx + s * 0.06, s * 0.39)
          ..close(),
        inner,
      );
    }
    // capul
    canvas.drawCircle(Offset(s / 2, s * 0.56), s * 0.29, fur);
    // botul, mai deschis
    canvas.drawOval(
      Rect.fromCenter(center: Offset(s / 2, s * 0.66), width: s * 0.30, height: s * 0.20),
      Paint()..color = _catFurDark.withAlpha(70),
    );
    // ochi cu pupila verticală
    _eyes(canvas, s, s * 0.54, s * 0.115, s * 0.065, pupilW: 0.42);
    // năsucul
    canvas.drawPath(
      Path()
        ..moveTo(s / 2 - s * 0.035, s * 0.625)
        ..lineTo(s / 2 + s * 0.035, s * 0.625)
        ..lineTo(s / 2, s * 0.665)
        ..close(),
      inner,
    );
    // mustăți
    final w = Paint()
      ..color = Colors.white.withAlpha(210)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.018
      ..strokeCap = StrokeCap.round;
    for (final sign in [-1.0, 1.0]) {
      for (var i = 0; i < 3; i++) {
        final y = s * (0.62 + i * 0.045);
        canvas.drawLine(
          Offset(s / 2 + sign * s * 0.10, y),
          Offset(s / 2 + sign * s * 0.31, y - s * 0.03 + i * s * 0.028),
          w,
        );
      }
    }
    // gurița în „w"
    final mouth = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.028
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCenter(center: Offset(s / 2 - s * 0.045, s * 0.695), width: s * 0.09, height: s * 0.07), 0, pi, false, mouth);
    canvas.drawArc(Rect.fromCenter(center: Offset(s / 2 + s * 0.045, s * 0.695), width: s * 0.09, height: s * 0.07), 0, pi, false, mouth);
  }

  // ─── porcușor de Guineea ─────────────────────────────────────────────────

  void _paintPig(Canvas canvas, double s) {
    final fur = Paint()..color = _pigFur;
    final cream = Paint()..color = _pigCream;
    // urechile: rotunde, lipite de cap, cum le are un porcușor
    canvas.drawOval(Rect.fromCenter(center: Offset(s * 0.235, s * 0.40), width: s * 0.20, height: s * 0.16), fur);
    canvas.drawOval(Rect.fromCenter(center: Offset(s * 0.765, s * 0.40), width: s * 0.20, height: s * 0.16), fur);
    canvas.drawOval(Rect.fromCenter(center: Offset(s * 0.24, s * 0.405), width: s * 0.11, height: s * 0.085), Paint()..color = _pink.withAlpha(160));
    canvas.drawOval(Rect.fromCenter(center: Offset(s * 0.76, s * 0.405), width: s * 0.11, height: s * 0.085), Paint()..color = _pink.withAlpha(160));
    // capul: lat, ușor turtit
    canvas.drawOval(
      Rect.fromCenter(center: Offset(s / 2, s * 0.57), width: s * 0.66, height: s * 0.60),
      fur,
    );
    // pata de blană deschisă de pe frunte și bot — porcușorii sunt aproape
    // mereu bicolori, fără ea ar arăta a hamster
    canvas.drawOval(
      Rect.fromCenter(center: Offset(s / 2, s * 0.42), width: s * 0.26, height: s * 0.18),
      cream,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(s / 2, s * 0.685), width: s * 0.34, height: s * 0.24),
      cream,
    );

    _eyes(canvas, s, s * 0.53, s * 0.145, s * 0.06);

    // năsucul
    canvas.drawPath(
      Path()
        ..moveTo(s / 2 - s * 0.04, s * 0.635)
        ..lineTo(s / 2 + s * 0.04, s * 0.635)
        ..lineTo(s / 2, s * 0.678)
        ..close(),
      Paint()..color = _pink,
    );
    // dințișorii
    final tooth = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(s / 2 - s * 0.026, s * 0.735), width: s * 0.042, height: s * 0.062),
        Radius.circular(s * 0.012),
      ),
      tooth,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(s / 2 + s * 0.026, s * 0.735), width: s * 0.042, height: s * 0.062),
        Radius.circular(s * 0.012),
      ),
      tooth,
    );
    _blushMarks(canvas, s, s * 0.635, s * 0.235, s * 0.055);
  }

  @override
  bool shouldRepaint(covariant _AvatarPainter oldDelegate) => oldDelegate.style != style;
}
