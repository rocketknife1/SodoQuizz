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

/// Textul mare de pe camerele cinematice ale modului („-24", „EVITAT!",
/// „Ha, m-a ratat!"), centrat pe [center] și cu umbră, ca să rămână lizibil
/// și peste o explozie albă.
///
/// Stă aici, la comun, fiindcă îl folosesc amândouă camerele (tank_pov.dart
/// și tank_defence.dart) și textele lor trebuie să arate IDENTIC: sunt același
/// eveniment văzut din două părți, iar dacă „MISS"-ul țintașului ar avea alt
/// corp de literă decât „m-a ratat"-ul țintei, cei doi jucători ar avea
/// impresia că li s-a întâmplat altceva.
void paintBattleLabel(
  Canvas canvas,
  Offset center,
  String text,
  double fontSize,
  Color color, {
  double alpha = 1,
  FontWeight weight = FontWeight.w900,
  double letterSpacing = 1.5,
}) {
  final a = (255 * alpha).round().clamp(0, 255);
  if (a <= 0) return;
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color.withAlpha(a),
        fontSize: fontSize,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        shadows: [Shadow(color: Colors.black.withAlpha((a * 0.85).round()), blurRadius: 12)],
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: 640);
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

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

/// Desenează un tanc într-un dreptunghi dat, pe o pânză oarecare.
///
/// Extras din [_TankPainter] ca funcție publică fiindcă îl mai folosește un
/// desen care NU e un widget: camera de pe proiectil (widgets/tank_pov.dart)
/// are nevoie de exact același tanc, dar desenat la scara dictată de distanță,
/// în mijlocul unei scene în perspectivă. Un widget n-ar fi încăput acolo, iar
/// un al doilea desen de tanc s-ar fi depărtat de ăsta la prima modificare.
void paintTankInto(
  Canvas canvas,
  Rect rect, {
  required Color color,
  bool facingRight = true,
  bool destroyed = false,
  double damage = 0,
}) {
  canvas.save();
  canvas.translate(rect.left, rect.top);
  _paintTankBody(
    canvas,
    rect.size,
    color: color,
    facingRight: facingRight,
    destroyed: destroyed,
    damage: damage.clamp(0.0, 1.0),
  );
  canvas.restore();
}

/// Același tanc, dar văzut DIN SPATE — silueta din camera de apărare
/// (widgets/tank_defence.dart), unde jucătorul stă în spatele propriului
/// blindaj și se uită peste turelă la obuzul care vine spre el.
///
/// DE CE UN AL DOILEA DESEN, ȘI NU O ROTIRE A CELUI DIN PROFIL: [paintTankInto]
/// desenează o siluetă plată, bună pentru arenă și pentru ținta din zare, dar
/// din spate se văd exact lucrurile pe care profilul nu le are — cele două
/// șenile în perspectivă, placa din spate, tobele de eșapament — iar țeava
/// dispare aproape complet, fiindcă arată în direcția în care privim. Un
/// desen întors pe orizontală ar fi rămas tot un profil.
///
/// [rect] e cutia în care intră tancul; raportul bun e o înălțime cam 0,72
/// din lățime. [damage] 0 = intact, 1 = aproape mort (arsuri pe placă).
void paintTankRearInto(
  Canvas canvas,
  Rect rect, {
  required Color color,
  double damage = 0,
}) {
  final w = rect.width;
  final h = rect.height;
  final d = damage.clamp(0.0, 1.0);

  canvas.save();
  canvas.translate(rect.left, rect.top);

  final hull = Color.lerp(color, Colors.black, 0.22)!;
  final deck = Color.lerp(color, Colors.white, 0.10)!;
  final turret = Color.lerp(color, Colors.white, 0.06)!;
  const tracks = Color(0xFF232838);
  final paint = Paint()..style = PaintingStyle.fill;

  // umbra de sub tanc, turtită — fără ea, tancul plutește peste sol
  paint.color = Colors.black.withAlpha(120);
  canvas.drawOval(Rect.fromLTRB(w * 0.02, h * 0.88, w * 0.98, h * 1.04), paint);

  // Șenilele, ușor în evantai spre privitor: din spate se văd amândouă, iar
  // depărtarea dintre ele jos e tot ce dă perspectiva scenei.
  for (final side in [true, false]) {
    final path = Path();
    if (side) {
      path
        ..moveTo(w * 0.13, h * 0.44)
        ..lineTo(w * 0.30, h * 0.44)
        ..lineTo(w * 0.27, h * 0.99)
        ..lineTo(w * 0.03, h * 0.99)
        ..close();
    } else {
      path
        ..moveTo(w * 0.70, h * 0.44)
        ..lineTo(w * 0.87, h * 0.44)
        ..lineTo(w * 0.97, h * 0.99)
        ..lineTo(w * 0.73, h * 0.99)
        ..close();
    }
    paint.color = tracks;
    canvas.drawPath(path, paint);
    // zalele: linii orizontale care se răresc spre depărtare
    final link = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.018
      ..color = Colors.black.withAlpha(150);
    for (var i = 0; i < 7; i++) {
      final y = h * (0.48 + i * 0.075);
      final spread = (y / h - 0.44) * 0.30;
      if (side) {
        canvas.drawLine(Offset(w * (0.13 - spread), y), Offset(w * (0.30 - spread * 0.2), y), link);
      } else {
        canvas.drawLine(Offset(w * (0.70 + spread * 0.2), y), Offset(w * (0.87 + spread), y), link);
      }
    }
  }

  // placa din spate a corpului, trapez (mai lată jos = privim ușor de sus)
  paint.color = hull;
  canvas.drawPath(
    Path()
      ..moveTo(w * 0.19, h * 0.46)
      ..lineTo(w * 0.81, h * 0.46)
      ..lineTo(w * 0.85, h * 0.92)
      ..lineTo(w * 0.15, h * 0.92)
      ..close(),
    paint,
  );

  // capacul motorului, luminat — banda care separă corpul de turelă
  paint.color = deck;
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.20, h * 0.41, w * 0.80, h * 0.50), Radius.circular(h * 0.03)),
    paint,
  );

  // tobe de eșapament + fumul cald de deasupra lor: singurul semn că motorul
  // merge, adică singurul lucru „viu" dintr-un desen altfel simetric
  paint.color = const Color(0xFF171B27);
  for (final x in [0.28, 0.66]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(w * x, h * 0.52, w * (x + 0.06), h * 0.70), Radius.circular(h * 0.03)),
      paint,
    );
  }

  // lumini de poziție în colțurile de jos
  paint.color = AppColors.orange.withAlpha(150);
  canvas.drawCircle(Offset(w * 0.21, h * 0.86), h * 0.022, paint);
  canvas.drawCircle(Offset(w * 0.79, h * 0.86), h * 0.022, paint);

  // turela, văzută din spate: o cutie rotunjită peste corp
  paint.color = turret;
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.33, h * 0.14, w * 0.67, h * 0.45), Radius.circular(h * 0.09)),
    paint,
  );
  paint.color = Colors.white.withAlpha(40);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.36, h * 0.16, w * 0.64, h * 0.21), Radius.circular(h * 0.025)),
    paint,
  );

  // Țeava, puternic scurtată: arată în direcția în care privim, deci din ea
  // se vede aproape numai gura tunului, peste turelă.
  paint.color = Color.lerp(color, Colors.black, 0.42)!;
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.455, h * 0.02, w * 0.545, h * 0.20), Radius.circular(h * 0.03)),
    paint,
  );
  canvas.drawCircle(Offset(w * 0.5, h * 0.045), h * 0.055, paint);
  paint.color = Colors.black.withAlpha(170);
  canvas.drawCircle(Offset(w * 0.5, h * 0.045), h * 0.028, paint);

  // arsuri, proporționale cu viața pierdută — tancul se citește avariat și
  // fără să te uiți la bară
  if (d > 0.35) {
    paint.color = Colors.black.withAlpha((90 * ((d - 0.35) / 0.65)).round().clamp(0, 130));
    canvas.drawCircle(Offset(w * 0.36, h * 0.66), h * 0.11, paint);
    canvas.drawCircle(Offset(w * 0.62, h * 0.56), h * 0.07, paint);
  }

  canvas.restore();
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
  void paint(Canvas canvas, Size size) => _paintTankBody(
        canvas,
        size,
        color: color,
        facingRight: facingRight,
        destroyed: destroyed,
        damage: damage,
      );

  @override
  bool shouldRepaint(covariant _TankPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.facingRight != facingRight ||
      oldDelegate.destroyed != destroyed ||
      oldDelegate.damage != damage;
}

void _paintTankBody(
  Canvas canvas,
  Size size, {
  required Color color,
  required bool facingRight,
  required bool destroyed,
  required double damage,
}) {
  {
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
              // Diviziuni din 25 în 25 HP. Nu sunt decor: o bară netedă se
              // citește doar ca „cam pe jumătate", pe când segmentele spun
              // dintr-o privire câte lovituri mai suportă tancul — o lovitură
              // reușită ia cam un segment (vezi tanksDamageMin/Max).
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _HpTicksPainter(height: height)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HpTicksPainter extends CustomPainter {
  final double height;
  const _HpTicksPainter({required this.height});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withAlpha(90)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = size.width * (i / 4);
      canvas.drawLine(Offset(x, size.height * 0.18), Offset(x, size.height * 0.82), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HpTicksPainter oldDelegate) => oldDelegate.height != height;
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

  /// **Duel** — cei doi și-au ales țintă unul pe altul în aceeași rundă, deci
  /// pleacă DEODATĂ (același [startAt], vezi
  /// MultiplayerTanksScreen._ensureFlights).
  ///
  /// [lateral] e deplasarea, în pixeli, PERPENDICULAR pe traiectorie. Cele
  /// două obuze ale unui duel merg pe același segment în sensuri opuse;
  /// fără ea s-ar suprapune perfect la jumătatea drumului și s-ar citi ca un
  /// singur proiectil care clipește, nu ca doi care se încrucișează. Normala
  /// se întoarce odată cu sensul, deci ACEEAȘI valoare pozitivă îi trimite
  /// pe cei doi în părți opuse — fiecare trece „pe dreapta lui".
  final double lateral;

  /// Amândoi au ratat, deci niciun obuz n-are unde ajunge: se izbesc între
  /// ele la jumătatea drumului. NU e o regulă de joc — zarurile rămân cele
  /// aruncate o singură dată în MultiplayerService.resolveTanksRound, iar
  /// daunele sunt zero în ambele variante. E doar punerea în scenă a două
  /// ratări simultane, care altfel s-ar fi terminat în două ricoșeuri fără
  /// nicio legătură între ele.
  final bool intercepted;

  /// Care dintre cele două obuze ale unei ciocniri desenează blițul comun și
  /// scrie „MISS”. Fără el, textul și explozia s-ar desena de două ori peste
  /// ele însele, ieșind de două ori mai opace decât restul rundei.
  final bool meetLead;

  /// **Reflexie** — obuzul lovește un tanc cu [PowerUp.reflect], ricoșează
  /// din scutul lui și se întoarce ÎN TRĂGĂTOR. [to] rămâne reflectorul
  /// (unde ricoșează, la jumătatea zborului), iar aici e trăgătorul, unde
  /// obuzul ajunge și explodează. Un singur zbor pentru tot drumul dus-întors,
  /// ca ochiul să vadă că e ACELAȘI proiectil care se întoarce, nu două.
  final Offset? reflectBackTo;

  const ShotFlight({
    required this.from,
    required this.to,
    required this.hit,
    required this.damage,
    required this.startAt,
    required this.color,
    this.flightDuration = 0.42,
    this.lateral = 0,
    this.intercepted = false,
    this.meetLead = false,
    this.reflectBackTo,
  });

  bool get isReflected => reflectBackTo != null;

  /// Fracțiunea din zbor la care obuzul atinge reflectorul și cotește înapoi.
  static const double reflectPivot = 0.5;

  /// Cât zboară până se oprește — la o ciocnire în aer, jumătate de drum.
  double get travelDuration => intercepted ? flightDuration * 0.5 : flightDuration;

  /// Unde se termină drumul: tancul țintă, punctul de ciocnire, sau — la o
  /// reflexie — înapoi în trăgător.
  Offset get landing => intercepted
      ? pointAt(0.5)
      : (reflectBackTo ?? to);

  /// Clipa în care se oprește proiectilul — impact, ricoșeu sau ciocnire.
  /// Tot restul coregrafiei (sunet, bare care scad, camerele cinematice) se
  /// leagă de ea, deci ciocnirea trebuie să scurteze chiar valoarea asta, nu
  /// doar desenul.
  double get impactAt => startAt + travelDuration;

  /// Poziția pe traiectorie la fracțiunea [t] din drumul COMPLET (0 = tun,
  /// 1 = țintă). Arc, nu linie: cu tancurile așezate în grilă, o linie
  /// dreaptă între două cutii de pe același rând ar fi arătat ca un simplu
  /// chenar mișcător.
  ///
  /// Stă pe model, nu în painter, fiindcă din ea se calculează și punctul de
  /// ciocnire ([landing]) — două formule separate s-ar fi despărțit la prima
  /// modificare a arcului, iar obuzele s-ar fi „izbit" pe lângă ele.
  Offset pointAt(double t) {
    // Reflexie: două arce lipite — trăgător→reflector până la [reflectPivot],
    // reflector→trăgător după. Aceeași formulă de arc pe fiecare bucată.
    if (reflectBackTo != null) {
      final back = reflectBackTo!;
      if (t <= reflectPivot) {
        return _arc(from, to, t / reflectPivot);
      }
      return _arc(to, back, (t - reflectPivot) / (1 - reflectPivot));
    }
    final d = to - from;
    final dist = d.distance;
    var p = Offset.lerp(from, to, t)! + Offset(0, -sin(t * pi) * dist * 0.16);
    if (lateral != 0 && dist > 0.001) {
      p += Offset(-d.dy, d.dx) / dist * lateral;
    }
    return p;
  }

  static Offset _arc(Offset a, Offset b, double t) {
    final dist = (b - a).distance;
    return Offset.lerp(a, b, t)! + Offset(0, -sin(t * pi) * dist * 0.16);
  }
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
      if (local < f.travelDuration) {
        // fracțiunea din drumul COMPLET: un obuz interceptat se oprește la
        // jumătate, deci parcurge tot 0→0,5 din traiectorie, nu 0→1.
        final frac = local / f.flightDuration;
        _paintShell(canvas, f, frac);
        // Reflexie: în clipa în care obuzul atinge reflectorul, un inel de
        // scut care ricoșează — semnul vizibil că nu l-a lovit, l-a întors.
        if (f.isReflected) {
          final since = (frac - ShotFlight.reflectPivot) / 0.22;
          if (since >= 0 && since < 1) _paintReflectBounce(canvas, f, since);
        }
      } else {
        final since = local - f.travelDuration;
        if (since < impactDuration) _paintImpact(canvas, f, since / impactDuration);
        if (f.hit && since < damageTextDuration) _paintDamageText(canvas, f, since / damageTextDuration);
        // La o ciocnire în aer scrie unul singur pentru amândoi: „MISS” apare
        // acolo unde s-au izbit obuzele, nu de două ori peste el însuși.
        if (!f.hit && since < damageTextDuration && (!f.intercepted || f.meetLead)) {
          _paintDodgeText(canvas, f, since / damageTextDuration);
        }
      }
    }
  }

  void _paintShell(Canvas canvas, ShotFlight f, double t) {
    final pos = f.pointAt(t);
    final tail = f.pointAt((t - 0.16).clamp(0.0, 1.0));

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
    if (f.intercepted) {
      _paintClash(canvas, f, t, fade);
      return;
    }
    // La o reflexie, explozia e în TRĂGĂTOR (f.landing), nu în reflector.
    final at = f.landing;
    if (f.hit) {
      // inel de explozie + schije
      final r = 6 + t * 26;
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5 * fade
          ..color = AppColors.orange.withAlpha((220 * fade).round()),
      );
      canvas.drawCircle(at, r * 0.55, Paint()..color = Colors.white.withAlpha((160 * fade * fade).round()));
      final spark = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.4 * fade
        ..color = AppColors.coin.withAlpha((230 * fade).round());
      for (var i = 0; i < 7; i++) {
        final a = i * (2 * pi / 7) + f.damage;
        canvas.drawLine(
          at + Offset(cos(a), sin(a)) * (r * 0.5),
          at + Offset(cos(a), sin(a)) * (r * 1.15),
          spark,
        );
      }
    } else {
      // ricoșeu: un arc subțire care sare mai departe, fără explozie
      canvas.drawCircle(
        at,
        6 + t * 16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * fade
          ..color = Colors.white.withAlpha((160 * fade).round()),
      );
    }
  }

  /// Inelul de scut care apare când un obuz reflectat atinge reflectorul și
  /// cotește înapoi — un arc concentric în alb-albastru, ca „a lovit ceva
  /// tare și a sărit", nu ca o explozie.
  void _paintReflectBounce(Canvas canvas, ShotFlight f, double t) {
    final fade = 1 - t;
    for (var k = 0; k < 2; k++) {
      canvas.drawCircle(
        f.to,
        8 + t * 22 + k * 6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (2.6 - k) * fade
          ..color = (k == 0 ? Colors.white : const Color(0xFF7EC8FF))
              .withAlpha((200 * fade).round()),
      );
    }
  }

  /// Ciocnirea a două obuze care se ratau oricum amândouă. Fiecare din cele
  /// două zboruri își desenează inelul în culoarea lui — așa se vede din
  /// prima că s-au întâlnit DOUĂ proiectile, nu că a explodat unul singur în
  /// mijlocul câmpului — dar blițul alb și schijele le pune doar unul
  /// ([ShotFlight.meetLead]), altfel ar ieși de două ori mai aprinse decât
  /// orice alt impact al rundei.
  void _paintClash(Canvas canvas, ShotFlight f, double t, double fade) {
    final at = f.landing;
    final r = 5 + t * 30;
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 * fade
        ..color = f.color.withAlpha((235 * fade).round()),
    );
    if (!f.meetLead) return;
    canvas.drawCircle(at, r * 0.42, Paint()..color = Colors.white.withAlpha((210 * fade * fade).round()));
    final spark = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2 * fade
      ..color = Colors.white.withAlpha((200 * fade).round());
    for (var i = 0; i < 8; i++) {
      final a = i * (2 * pi / 8) + 0.4;
      final d = Offset(cos(a), sin(a));
      canvas.drawLine(at + d * (r * 0.6), at + d * (r * 1.5), spark);
    }
  }

  void _paintDamageText(Canvas canvas, ShotFlight f, double t) {
    _paintFloatingText(
      canvas,
      f.landing,
      '-${f.damage}',
      t,
      AppColors.danger,
      fontSize: 17,
    );
  }

  /// „MISS” stă unde s-a oprit obuzul: pe tanc la un ricoșeu obișnuit, în
  /// aer la o ciocnire între două obuze.
  void _paintDodgeText(Canvas canvas, ShotFlight f, double t) {
    _paintFloatingText(
      canvas,
      f.landing,
      'MISS',
      t,
      f.intercepted ? Colors.white : Colors.white70,
      fontSize: f.intercepted ? 15 : 12,
    );
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
