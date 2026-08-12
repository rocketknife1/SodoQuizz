/// Desenele modului Quizz Tanks: tancul propriu-zis, bara de viață în stil
/// joc de luptă și stratul peste care zboară proiectilele.
///
/// Totul e desenat din cod (CustomPainter), ca restul artei sintetizate din
/// joc (avatar_art.dart, spinning_planet.dart) — fără imagini noi în assets,
/// deci fără megaocteți în plus în APK și fără griji de licență. În plus,
/// tancul se colorează după culoarea jucătorului (`pickAvatarColor`), ceea
/// ce o poză fixă n-ar putea face.
library;

import 'dart:math';
import 'package:flutter/material.dart';
import '../core/tanks.dart';
import '../core/theme.dart';

/// Un tanc văzut din profil. [facingRight] întoarce țeava spre dreapta —
/// în arena 2×2 tancurile din stânga se uită spre dreapta și invers, ca
/// masa să pară o confruntare, nu patru vehicule parcate în aceeași
/// direcție.
class TankArt extends StatelessWidget {
  final Color color;
  final double width;
  final bool facingRight;
  final bool destroyed;

  /// 0 = intact, 1 = complet avariat. Peste ~0,5 apar urme de arsură pe
  /// blindaj: viața se citește și din desen, nu doar din bară.
  final double damage;

  const TankArt({
    super.key,
    required this.color,
    this.width = 64,
    this.facingRight = true,
    this.destroyed = false,
    this.damage = 0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 0.62,
      child: CustomPaint(
        painter: _TankPainter(
          color: color,
          facingRight: facingRight,
          destroyed: destroyed,
          damage: damage.clamp(0.0, 1.0),
        ),
      ),
    );
  }
}

class _TankPainter extends CustomPainter {
  final Color color;
  final bool facingRight;
  final bool destroyed;
  final double damage;

  const _TankPainter({
    required this.color,
    required this.facingRight,
    required this.destroyed,
    required this.damage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Un tanc distrus nu se mai vede în culoarea jucătorului: e o epavă
    // cenușie. Altfel, la finalul meciului, patru tancuri moarte ar arăta
    // exact ca patru tancuri vii.
    final base = destroyed ? const Color(0xFF3A3F52) : color;
    final hull = destroyed ? base : Color.lerp(base, Colors.black, 0.18)!;
    final turret = destroyed ? base : Color.lerp(base, Colors.white, 0.12)!;
    final tracks = const Color(0xFF232838);

    canvas.save();
    if (!facingRight) {
      // oglindire pe orizontală: un singur desen, două orientări.
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
    }
    // Epava stă strâmb, căzută pe o parte — semnalul cel mai rapid că acolo
    // nu mai e nimeni.
    if (destroyed) {
      canvas.translate(w / 2, h);
      canvas.rotate(0.18);
      canvas.translate(-w / 2, -h);
    }

    final paint = Paint()..style = PaintingStyle.fill;

    // șenile + roți
    paint.color = tracks;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.03, h * 0.62, w * 0.97, h * 0.97), Radius.circular(h * 0.18)),
      paint,
    );
    paint.color = const Color(0xFF151A28);
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(Offset(w * (0.13 + i * 0.185), h * 0.80), h * 0.085, paint);
    }

    // corp
    paint.color = hull;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(w * 0.06, h * 0.36, w * 0.94, h * 0.66),
        topLeft: Radius.circular(h * 0.10),
        topRight: Radius.circular(h * 0.22),
        bottomLeft: Radius.circular(h * 0.06),
        bottomRight: Radius.circular(h * 0.06),
      ),
      paint,
    );

    // turelă
    paint.color = turret;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.30, h * 0.14, w * 0.70, h * 0.40), Radius.circular(h * 0.11)),
      paint,
    );

    // țeavă + gura tunului
    paint.color = destroyed ? tracks : Color.lerp(base, Colors.black, 0.35)!;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.66, h * 0.21, w * 0.99, h * 0.30), Radius.circular(h * 0.045)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.90, h * 0.17, w * 1.0, h * 0.33), Radius.circular(h * 0.04)),
      paint,
    );

    // luciu pe turelă — dă volum fără să coste nimic
    if (!destroyed) {
      paint.color = Colors.white.withAlpha(46);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.34, h * 0.17, w * 0.66, h * 0.23), Radius.circular(h * 0.03)),
        paint,
      );
    }

    // urme de arsură, proporționale cu viața pierdută
    if (damage > 0.45 && !destroyed) {
      paint.color = Colors.black.withAlpha((70 * ((damage - 0.45) / 0.55)).round().clamp(0, 110));
      canvas.drawCircle(Offset(w * 0.24, h * 0.50), h * 0.13, paint);
      canvas.drawCircle(Offset(w * 0.44, h * 0.29), h * 0.08, paint);
    }

    canvas.restore();

    // fum peste epavă (desenat NEoglindit, fumul urcă la fel în ambele părți)
    if (destroyed) {
      final smoke = Paint()..style = PaintingStyle.fill;
      for (var i = 0; i < 3; i++) {
        smoke.color = Colors.white.withAlpha(38 - i * 10);
        canvas.drawCircle(Offset(w * (0.46 + i * 0.05), h * (0.22 - i * 0.09)), h * (0.10 + i * 0.05), smoke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TankPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.facingRight != facingRight ||
      oldDelegate.destroyed != destroyed ||
      oldDelegate.damage != damage;
}

/// Bara de viață în stil joc de luptă: sub bara colorată curentă rămâne o
/// „fantomă" roșie care coboară cu întârziere spre valoarea nouă.
///
/// Fantoma nu e decor: în ritmul unei runde, o bară care sare direct de
/// la 74 la 51 nu-i lasă ochiului timp să vadă CÂT s-a pierdut. Fâșia roșie
/// rămasă în urmă arată exact mărimea loviturii, chiar dacă te uitai în altă
/// parte în clipa impactului.
class TankHpBar extends StatelessWidget {
  final int hp;
  final int previousHp;

  /// 0 → fantoma e încă la [previousHp]; 1 → a ajuns din urmă bara reală.
  final double drainProgress;
  final Color color;
  final double height;

  const TankHpBar({
    super.key,
    required this.hp,
    required this.previousHp,
    required this.drainProgress,
    required this.color,
    this.height = 9,
  });

  static Color hpColor(int hp) {
    final frac = hp / tanksMaxHp;
    if (frac > 0.5) return AppColors.play;
    if (frac > 0.25) return AppColors.orange;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final live = (hp / tanksMaxHp).clamp(0.0, 1.0);
    final ghostFrom = (previousHp / tanksMaxHp).clamp(0.0, 1.0);
    final ghost = ghostFrom + (live - ghostFrom) * drainProgress.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(120),
                  borderRadius: BorderRadius.circular(height),
                  border: Border.all(color: Colors.white24, width: 0.8),
                ),
              ),
              // fantoma (ce s-a pierdut, încă vizibil)
              Container(
                width: w * ghost,
                decoration: BoxDecoration(
                  color: AppColors.danger.withAlpha(190),
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
              // viața reală
              Container(
                width: w * live,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color.withAlpha(220), color]),
                  borderRadius: BorderRadius.circular(height),
                  boxShadow: [BoxShadow(color: color.withAlpha(110), blurRadius: 6, spreadRadius: -1)],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Un proiectil în drum spre țintă, deja rezolvat (se știe de la început
/// dacă lovește sau e evitat — vezi MultiplayerService.resolveTanksRound).
/// Timpii sunt în secunde de la începutul fazei de foc.
class ShotFlight {
  final Offset from;
  final Offset to;
  final bool hit;
  final int damage;
  final double startAt;
  final double flightDuration;
  final Color color;

  const ShotFlight({
    required this.from,
    required this.to,
    required this.hit,
    required this.damage,
    required this.startAt,
    required this.color,
    this.flightDuration = 0.42,
  });

  double get impactAt => startAt + flightDuration;
}

/// Stratul de deasupra arenei: proiectile, explozii, ricoșeuri și cifrele de
/// daune care se ridică. Un singur painter pentru tot, hrănit de un singur
/// AnimationController din ecran — mult mai ieftin decât un widget animat
/// separat pentru fiecare din cele până la douăsprezece proiectile ale unei
/// runde.
class TankShotsPainter extends CustomPainter {
  final List<ShotFlight> flights;

  /// Secunde scurse de la începutul fazei de foc.
  final double time;

  const TankShotsPainter({required this.flights, required this.time});

  /// Cât timp rămâne vizibil efectul de impact după ce proiectilul ajunge.
  static const double impactDuration = 0.55;
  static const double damageTextDuration = 0.95;

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in flights) {
      final local = time - f.startAt;
      if (local < 0) continue;
      if (local < f.flightDuration) {
        _paintShell(canvas, f, local / f.flightDuration);
      } else {
        final since = local - f.flightDuration;
        if (since < impactDuration) _paintImpact(canvas, f, since / impactDuration);
        if (f.hit && since < damageTextDuration) _paintDamageText(canvas, f, since / damageTextDuration);
        if (!f.hit && since < damageTextDuration) _paintDodgeText(canvas, f, since / damageTextDuration);
      }
    }
  }

  /// Traiectoria e un arc, nu o linie: proiectilul urcă puțin la plecare și
  /// cade spre țintă. Cu tancurile așezate în grilă, o linie dreaptă între
  /// două cutii de pe același rând ar fi arătat ca un simplu chenar mișcător.
  Offset _pointAt(ShotFlight f, double t) {
    final straight = Offset.lerp(f.from, f.to, t)!;
    final arc = -sin(t * pi) * (f.from - f.to).distance * 0.16;
    return straight + Offset(0, arc);
  }

  void _paintShell(Canvas canvas, ShotFlight f, double t) {
    final pos = _pointAt(f, t);
    final tail = _pointAt(f, (t - 0.16).clamp(0.0, 1.0));

    final trail = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2
      ..shader = LinearGradient(
        colors: [f.color.withAlpha(0), f.color.withAlpha(190)],
      ).createShader(Rect.fromPoints(tail, pos));
    canvas.drawLine(tail, pos, trail);

    canvas.drawCircle(pos, 7.5, Paint()..color = f.color.withAlpha(60));
    canvas.drawCircle(pos, 3.6, Paint()..color = Colors.white);
    canvas.drawCircle(pos, 2.0, Paint()..color = f.color);
  }

  void _paintImpact(Canvas canvas, ShotFlight f, double t) {
    final fade = (1 - t);
    if (f.hit) {
      // inel de explozie + schije
      final r = 6 + t * 26;
      canvas.drawCircle(
        f.to,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5 * fade
          ..color = AppColors.orange.withAlpha((220 * fade).round()),
      );
      canvas.drawCircle(f.to, r * 0.55, Paint()..color = Colors.white.withAlpha((160 * fade * fade).round()));
      final spark = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.4 * fade
        ..color = AppColors.coin.withAlpha((230 * fade).round());
      for (var i = 0; i < 7; i++) {
        final a = i * (2 * pi / 7) + f.damage;
        canvas.drawLine(
          f.to + Offset(cos(a), sin(a)) * (r * 0.5),
          f.to + Offset(cos(a), sin(a)) * (r * 1.15),
          spark,
        );
      }
    } else {
      // ricoșeu: un arc subțire care sare mai departe, fără explozie
      canvas.drawCircle(
        f.to,
        6 + t * 16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * fade
          ..color = Colors.white.withAlpha((160 * fade).round()),
      );
    }
  }

  void _paintDamageText(Canvas canvas, ShotFlight f, double t) {
    _paintFloatingText(
      canvas,
      f.to,
      '-${f.damage}',
      t,
      AppColors.danger,
      fontSize: 17,
    );
  }

  void _paintDodgeText(Canvas canvas, ShotFlight f, double t) {
    _paintFloatingText(canvas, f.to, 'MISS', t, Colors.white70, fontSize: 12);
  }

  void _paintFloatingText(Canvas canvas, Offset at, String text, double t, Color color, {required double fontSize}) {
    final alpha = (255 * (1 - t * t)).round().clamp(0, 255);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color.withAlpha(alpha),
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: Colors.black.withAlpha(alpha), blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at + Offset(-tp.width / 2, -14 - t * 30));
  }

  @override
  bool shouldRepaint(covariant TankShotsPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.flights != flights;
}
