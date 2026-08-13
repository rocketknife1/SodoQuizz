/// **Camera de pe proiectil** („bullet cam") — ce vede DOAR cel care trage,
/// cât timp obuzul lui e în aer, în modul Quizz Tanks.
///
/// DE CE EXISTĂ, ȘI DE CE NUMAI PENTRU ȚINTAȘ: în arena obișnuită (vezi
/// MultiplayerTanksScreen) toate proiectilele rundei zboară deodată, ca niște
/// puncte mici între patru cutii. E limpede CE s-a întâmplat, dar nu se simte
/// nimic — iar lovitura ta, singurul lucru pe care l-ai decis tu în runda
/// aia, arată exact ca ale celorlalți. Camera asta ia ecranul cu totul, pentru
/// o secundă și jumătate, și îl pune pe jucător ÎN obuzul lui.
///
/// Ceilalți (cei care n-au tras, sau au fost doar ținte) rămân pe arenă și
/// văd tabloul întreg. Nimeni nu pierde informație: barele scad și epavele
/// explodează DUPĂ ce camera se retrage — vezi coregrafia din
/// MultiplayerTanksScreen, care întârzie anume scurgerea barelor până când
/// bullet cam-ul a ieșit din cadru.
///
/// NU DECIDE NIMIC. Ca tot restul modului, primește un rezultat deja scris în
/// Firestore (a lovit / a fost evitat, cu ce daune — vezi
/// MultiplayerService.resolveTanksRound) și doar îl pune în scenă. Evitarea
/// nu se „calculează" aici din animație; animația e cea care se pliază pe
/// rezultatul dat.
///
/// Totul e desenat din cod, ca restul artei jocului (tank_art.dart,
/// avatar_art.dart) — fără imagini noi în assets.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import 'tank_art.dart';

/// Cât rămâne camera pe obuz DUPĂ ce ajunge la țintă — timpul în care se vede
/// explozia sau, la evitare, rostogolirea pe lângă țintă și izbitura în
/// pământ.
///
/// Urcat de la 0,85 la 1,7 (dublu) la cererea explicită a userului, care a
/// văzut prima versiune live pe două ecrane și n-a apucat să citească nici
/// traiectoria, nici textul de deznodământ ("-24"/"EVITAT!") — totul se
/// termina înainte să se fixeze ochiul pe el. Toate fracțiunile din
/// [_TankPovPainter._paintOutcome]/[_paintReticle] sunt scrise ca FRACȚIE din
/// valoarea asta (vezi `_scale` din painter), nu în secunde absolute, tocmai
/// ca o modificare viitoare aici să nu lase vreo bucată din coregrafie în
/// urmă.
const double tankPovAftermath = 1.7;

/// Ultima fracțiune din [tankPovAftermath] în care camera se stinge spre
/// arenă, ca revenirea să nu fie o tăietură bruscă.
const double tankPovFade = 0.4;

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Suprapunerea care ține tot ecranul cât zboară obuzul jucătorului curent.
///
/// [time] e ceasul comun al fazei de foc (secunde de la începutul ei), același
/// din care se hrănește și arena — nu un controler propriu. Asta e important:
/// dacă bullet cam-ul și-ar ține singur timpul, impactul de aici și cel din
/// arenă ar putea cădea la momente diferite, iar bara de viață ar începe să
/// scadă înainte sau după explozie.
class TankPovView extends StatelessWidget {
  final double time;
  final double launchAt;
  final double impactAt;
  final bool hit;
  final int damage;

  /// Culoarea și starea țintei, ca tancul din cadru să fie chiar al ei —
  /// [targetDamageRatio] e 0 la un tanc intact, 1 la unul aproape mort (vezi
  /// [paintTankInto]).
  final Color targetColor;
  final String targetName;
  final int targetHp;
  final double targetDamageRatio;

  /// Culoarea celui care trage — apare pe conul obuzului din marginea de jos,
  /// singurul lucru din cadru care spune „ăsta e proiectilul TĂU".
  final Color shooterColor;

  /// **Duel** — ținta mea a tras, în aceeași rundă, chiar în mine. Cele două
  /// obuze pleacă deodată (vezi ShotFlight.lateral) și se întâlnesc la
  /// jumătatea drumului, deci în cadru apare un al doilea proiectil, venind
  /// din față.
  final bool duelIncoming;

  /// Duelul în care AMÂNDOI au ratat: obuzele nu mai ajung nicăieri, se
  /// izbesc între ele. Nu schimbă nimic din rezultat (două ratări rămân două
  /// ratări, cu zero daune — zarurile s-au aruncat o singură dată, în
  /// MultiplayerService.resolveTanksRound); schimbă doar CE se vede, și o
  /// face identic pe amândouă ecranele.
  final bool duelIntercepted;

  /// Cât am încasat eu însumi în runda asta, din toate direcțiile. Se scrie
  /// mic, sub deznodământ: cine e plecat în camera de pe obuz nu vede arena
  /// în clipa în care propria bară scade, iar fără rândul ăsta s-ar întoarce
  /// la o viață mai mică fără să știe de la ce.
  final int damageTaken;

  const TankPovView({
    super.key,
    required this.time,
    required this.launchAt,
    required this.impactAt,
    required this.hit,
    required this.damage,
    required this.targetColor,
    required this.targetName,
    required this.targetHp,
    required this.targetDamageRatio,
    required this.shooterColor,
    this.duelIncoming = false,
    this.duelIntercepted = false,
    this.damageTaken = 0,
  });

  /// Când se retrage camera, în ceasul fazei de foc. Ecranul are nevoie de
  /// cifra asta ca să știe până când ține suprapunerea și de când poate lăsa
  /// barele să scadă.
  static double endAtFor(double impactAt) => impactAt + tankPovAftermath;

  @override
  Widget build(BuildContext context) {
    final end = endAtFor(impactAt);
    final fadeStart = end - tankPovFade;
    final opacity = time > fadeStart ? ((end - time) / tankPovFade).clamp(0.0, 1.0) : 1.0;
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: CustomPaint(
          size: Size.infinite,
          painter: _TankPovPainter(
            time: time,
            launchAt: launchAt,
            impactAt: impactAt,
            hit: hit,
            damage: damage,
            targetColor: targetColor,
            targetName: targetName,
            targetHp: targetHp,
            targetDamageRatio: targetDamageRatio,
            shooterColor: shooterColor,
            duelIncoming: duelIncoming,
            duelIntercepted: duelIntercepted,
            damageTaken: damageTaken,
          ),
        ),
      ),
    );
  }
}

class _TankPovPainter extends CustomPainter {
  final double time;
  final double launchAt;
  final double impactAt;
  final bool hit;
  final int damage;
  final Color targetColor;
  final String targetName;
  final int targetHp;
  final double targetDamageRatio;
  final Color shooterColor;
  final bool duelIncoming;
  final bool duelIntercepted;
  final int damageTaken;

  const _TankPovPainter({
    required this.time,
    required this.launchAt,
    required this.impactAt,
    required this.hit,
    required this.damage,
    required this.targetColor,
    required this.targetName,
    required this.targetHp,
    required this.targetDamageRatio,
    required this.shooterColor,
    required this.duelIncoming,
    required this.duelIntercepted,
    required this.damageTaken,
  });

  /// Din ce fracțiune de zbor începe ținta să se ferească, la o evitare.
  /// Târziu intenționat: manevra trebuie să pară o scăpare în ultima clipă,
  /// nu o plimbare începută înainte să pleci de la tun.
  static const double _jukeFrom = 0.68;

  /// Factor de conversie: pragurile din [_paintReticle]/[_paintOutcome] au
  /// fost cronometrate (și văzute pe ecran, vezi golden tests) la un
  /// [tankPovAftermath] de 0,85s — dacă valoarea aia se schimbă, pragurile
  /// scrise ca secunde absolute s-ar scurta/lungi disproporționat față de
  /// restul coregrafiei. `_scale` le ține toate proporționale, indiferent
  /// cât de lung e [tankPovAftermath] azi.
  static const double _baselineAftermath = 0.85;
  double get _scale => tankPovAftermath / _baselineAftermath;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const baseHorizonFrac = 0.38;
    final baseHorizon = h * baseHorizonFrac;

    final flightSpan = max(impactAt - launchAt, 0.001);
    final p = ((time - launchAt) / flightSpan).clamp(0.0, 1.0);
    final after = time - impactAt; // negativ cât obuzul e încă în aer

    /// Cât de mult am trecut DE ținta pe lângă care am ratat. La o lovitură
    /// directă rămâne mereu 0 — acolo drumul se termină în explozie, nu
    /// continuă. La o ciocnire în aer rămâne tot 0: acolo drumul se termină
    /// la jumătate, obuzul nu ajunge niciodată lângă tanc.
    final passT = (!hit && !duelIntercepted && after > 0) ? (after / 0.5).clamp(0.0, 1.0) : 0.0;

    // Obuzul ratat nu rămâne suspendat în aer: se înclină spre pământ, deci
    // orizontul urcă și solul umple cadrul. Fără asta, după ratare camera
    // plutea peste un câmp gol și nu se înțelegea unde s-a dus proiectilul.
    final horizon = baseHorizon - passT * h * 0.46;

    // Partea în care sare ținta la evitare. Se alege din numele ei, ca să fie
    // aceeași la fiecare redesenare a cadrului (un Random ar fi făcut tancul
    // să tresară stânga-dreapta de 60 de ori pe secundă).
    final jukeDir = targetName.codeUnits.fold<int>(0, (a, b) => a + b).isEven ? 1.0 : -1.0;

    // Cât de aproape pare ținta. easeInQuart, nu liniar: la viteza unui obuz,
    // ținta stă mult timp mică la orizont și apoi umple cadrul dintr-odată.
    // După o ratare creșterea CONTINUĂ peste 1: treci la câțiva metri de ea,
    // deci blindajul ei mătură tot cadrul înainte să rămână în urmă.
    //
    // Într-o ciocnire în aer, `p` acoperă doar JUMĂTATE din drum (obuzul se
    // oprește la mijloc, vezi ShotFlight.travelDuration) — fără fracțiunea
    // asta, ținta ar crește ca și cum aș fi ajuns la ea, iar explozia ar
    // părea că se petrece pe blindajul ei, adică exact povestea greșită.
    final approach = Curves.easeInQuart.transform(p * (duelIntercepted ? 0.5 : 1.0));
    final grow = (approach + passT * 0.85).clamp(0.0, 2.0);
    final tankW = _lerp(w * 0.05, w * 1.5, grow);
    final cy = _lerp(baseHorizon + h * 0.012, baseHorizon + h * 0.30, approach) + passT * h * 0.5;

    // La o ciocnire în aer ținta NU se ferește: obuzul nici n-a ajuns până la
    // ea, deci n-a avut de ce. Ratarea are aici altă poveste.
    var juke = 0.0;
    if (!hit && !duelIntercepted) {
      juke = Curves.easeInCubic.transform(((p - _jukeFrom) / (1 - _jukeFrom)).clamp(0.0, 1.0));
      juke += passT * 0.55; // se depărtează în continuare, dar rămâne în cadru
    }
    final cx = w / 2 + juke * w * 0.5 * jukeDir;

    canvas.save();
    // După o evitare camera se rostogolește — e singurul fel în care „am
    // ratat" se simte fizic, nu doar se citește. Scara e legată de unghi, nu
    // aleasă din ochi: la o rotație de α, un dreptunghi acoperă cadrul abia
    // de la |cosα|+|sinα|, altfel colțurile rămân negre.
    if (!hit && !duelIntercepted && after > 0) {
      final tumble = (after / tankPovAftermath).clamp(0.0, 1.0);
      final angle = tumble * 0.42;
      canvas.translate(w / 2, h / 2);
      canvas.rotate(angle * -jukeDir);
      canvas.scale(cos(angle).abs() + sin(angle).abs() + 0.04);
      canvas.translate(-w / 2, -h / 2);
    }

    _paintSky(canvas, size, horizon);
    _paintGround(canvas, size, horizon, p, after);
    _paintTarget(canvas, size, cx, cy, tankW, p, after, jukeDir);
    if (duelIncoming) _paintIncoming(canvas, size, cx, cy, p);
    _paintSpeedLines(canvas, size, p, after);
    canvas.restore();

    _paintNoseCone(canvas, size, p);
    _paintReticle(canvas, size, cx, cy, tankW, p, after);
    if (after >= 0) _paintOutcome(canvas, size, cx, cy, after);
    _paintVignette(canvas, size, after);
    _paintHud(canvas, size, p, after);
  }

  // ─── Scena ──────────────────────────────────────────────────────────────

  void _paintSky(Canvas canvas, Size size, double horizon) {
    // La ratare orizontul urcă până iese din cadru (camera se înfige în
    // pământ) — de la un punct încolo nu mai e cer de desenat, iar un
    // dreptunghi cu înălțime negativă ar fi o pânză goală, nu o eroare
    // vizibilă: exact genul de lucru care trece de analyze și se vede abia pe
    // telefon.
    if (horizon <= 0) return;
    final rect = Rect.fromLTWH(0, 0, size.width, horizon);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF090818), Color(0xFF231A3C), Color(0xFF6A3A1E)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
    // haloul cald de la orizont — dă adâncime și scoate silueta țintei
    final glow = Rect.fromCircle(center: Offset(size.width / 2, horizon), radius: size.width * 0.5);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, horizon + 4),
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.orange.withAlpha(90), Colors.transparent],
        ).createShader(glow),
    );
  }

  /// Solul în perspectivă: raze care fug spre punctul de fugă și travee care
  /// vin spre privitor din ce în ce mai repede. Traveele sunt tot ce dă
  /// senzația de VITEZĂ — fără ele, o țintă care crește pare doar un desen
  /// care se mărește.
  void _paintGround(Canvas canvas, Size size, double horizon, double p, double after) {
    final w = size.width;
    final h = size.height;
    // vezi [_paintSky]: orizontul poate ieși din cadru pe sus, iar solul
    // trebuie atunci să acopere tot, nu să se deseneze dintr-un y negativ
    final top = horizon.clamp(-h, h);
    final rect = Rect.fromLTRB(0, top, w, h);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF43291A), Color(0xFF120D16)],
        ).createShader(rect),
    );

    final vp = Offset(w / 2, horizon);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withAlpha(16);
    for (var i = -7; i <= 7; i++) {
      canvas.drawLine(vp, Offset(w / 2 + i * w * 0.30, h), line);
    }

    // 1/z e perspectiva propriu-zisă: o travee la adâncimea z se desenează la
    // (h - horizon)/z sub orizont, deci cele apropiate se răresc singure.
    final phase = pow(p, 1.35).toDouble() * 22 + (after > 0 ? after * 7 : 0);
    for (var i = 0; i < 22; i++) {
      final z = i + 1 - (phase % 1.0);
      if (z <= 0.08) continue;
      final y = horizon + (h - horizon) / z;
      if (y > h + 2) continue;
      line
        ..color = Colors.white.withAlpha((30 / z).round().clamp(0, 42))
        ..strokeWidth = (2.4 / z).clamp(0.5, 2.4);
      canvas.drawLine(Offset(0, y), Offset(w, y), line);
    }
  }

  void _paintTarget(Canvas canvas, Size size, double cx, double cy, double tankW, double p, double after, double jukeDir) {
    // După o lovitură directă tancul dispare în minge de foc — n-are rost
    // desenat sub ea.
    if (hit && after > 0.06) return;
    final tankH = tankW * 0.62;

    // praful ridicat de manevra de evitare, în urma tancului
    if (!hit && p > _jukeFrom) {
      final dust = Paint()..color = const Color(0xFFC8A87E).withAlpha(70);
      for (var i = 0; i < 5; i++) {
        final back = cx - jukeDir * tankW * (0.55 + i * 0.30);
        canvas.drawCircle(Offset(back, cy + tankH * (0.42 - i * 0.03)), tankH * (0.16 + i * 0.07), dust);
      }
    }

    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + tankH * 0.54), width: tankW * 0.95, height: tankH * 0.20),
      Paint()..color = Colors.black.withAlpha(120),
    );
    paintTankInto(
      canvas,
      Rect.fromCenter(center: Offset(cx, cy), width: tankW, height: tankH),
      color: targetColor,
      // la evitare se vede că fuge: se uită încotro sare
      facingRight: jukeDir > 0,
      damage: targetDamageRatio,
    );
  }

  /// **Obuzul advers**, în duelurile în care ținta a tras, în aceeași clipă,
  /// chiar în mine. Pleacă din tancul aflat în cadru și vine spre cameră.
  ///
  /// Cele două proiectile se întâlnesc la jumătatea drumului — momentul e
  /// garantat, nu nimerit din ochi: duelurile primesc același [launchAt] și
  /// aceeași durată de zbor (vezi MultiplayerTanksScreen._ensureFlights), deci
  /// „la jumătate" înseamnă exact aceeași clipă pe amândouă telefoanele.
  ///
  /// Dacă amândoi ratează, jumătatea drumului e chiar capătul zborului meu
  /// ([ShotFlight.travelDuration]) și obuzele se izbesc frontal; dacă e
  /// vorba de daune, trec unul pe lângă altul și fiecare își vede mai departe
  /// propria lovitură.
  void _paintIncoming(Canvas canvas, Size size, double cx, double cy, double p) {
    final w = size.width;
    final h = size.height;
    final meetP = duelIntercepted ? 1.0 : 0.5;
    if (p > meetP) return; // m-a depășit deja; ce urmează e treaba arenei
    final q = (p / meetP).clamp(0.0, 1.0);
    final e = Curves.easeInQuart.transform(q);

    // La încrucișare trece pe STÂNGA mea. Nu e o alegere de stil: în arenă
    // fiecare obuz e împins spre dreapta lui (vezi ShotFlight.lateral), deci
    // cel care vine din față apare inevitabil pe partea cealaltă. Amândoi
    // jucătorii văd astfel aceeași scenă, în oglindă.
    final pass = duelIntercepted ? Offset(w * 0.5, h * 0.82) : Offset(-w * 0.06, h * 1.02);
    final from = Offset(cx, cy);
    final pos = Offset.lerp(from, pass, e)!;
    final r = _lerp(w * 0.006, duelIntercepted ? w * 0.15 : w * 0.085, e);

    final tail = Offset.lerp(from, pass, Curves.easeInQuart.transform((q - 0.12).clamp(0.0, 1.0)))!;
    canvas.drawLine(
      tail,
      pos,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * 0.85
        ..shader = LinearGradient(
          colors: [targetColor.withAlpha(0), targetColor.withAlpha(205)],
        ).createShader(Rect.fromPoints(tail, pos)),
    );
    canvas.drawCircle(pos, r * 2.2, Paint()..color = targetColor.withAlpha(60));
    canvas.drawCircle(pos, r, Paint()..color = Colors.white);
    canvas.drawCircle(pos, r * 0.55, Paint()..color = targetColor);
  }

  void _paintSpeedLines(Canvas canvas, Size size, double p, double after) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w / 2, h * 0.5);
    final strength = Curves.easeIn.transform(p) + (after > 0 && !hit ? 0.4 : 0.0);
    if (strength <= 0.02) return;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 30; i++) {
      final a = i * (2 * pi / 30) + (i % 7) * 0.21;
      final r0 = w * (0.30 + ((i * 37) % 60) / 130);
      final len = w * (0.09 + 0.28 * strength) * (0.5 + ((i * 13) % 50) / 100);
      paint
        ..strokeWidth = 1.1 + 1.9 * strength.clamp(0.0, 1.0)
        ..color = Colors.white.withAlpha((70 * strength).round().clamp(0, 120));
      final d = Offset(cos(a), sin(a));
      canvas.drawLine(c + d * r0, c + d * (r0 + len), paint);
    }
  }

  /// Vârful obuzului, în marginea de jos a cadrului. E singurul reper care
  /// spune de unde privești: fără el, scena ar putea fi la fel de bine o
  /// cameră care plutește, nu proiectilul tău.
  void _paintNoseCone(Canvas canvas, Size size, double p) {
    final w = size.width;
    final h = size.height;
    // vibrează ușor cu viteza — un obuz nu zboară pe șine
    final wobble = sin(p * 34) * 2.2 * p;
    final path = Path()
      ..moveTo(w * 0.30, h + 2)
      ..lineTo(w * 0.40 + wobble, h * 0.875)
      ..quadraticBezierTo(w * 0.5 + wobble, h * 0.845, w * 0.60 + wobble, h * 0.875)
      ..lineTo(w * 0.70, h + 2)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF080A12).withAlpha(240));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = shooterColor.withAlpha(170),
    );
    // sclipirea de pe vârf
    canvas.drawCircle(
      Offset(w * 0.5 + wobble, h * 0.862),
      3.2,
      Paint()..color = shooterColor.withAlpha(220),
    );
  }

  /// Vizorul. La lovitură rămâne lipit de țintă; la evitare rămâne în urmă
  /// și se face roșu — „am pierdut ținta" se vede înainte să scrie nimic.
  void _paintReticle(Canvas canvas, Size size, double cx, double cy, double tankW, double p, double after) {
    if (hit && after > 0.05 * _scale) return;
    // După ce am trecut pe lângă ea, vizorul nu mai are ce ține: un chenar
    // gol plutind peste câmp arăta a element uitat pe ecran, nu a ratare.
    if (!hit && after > 0.12 * _scale) return;
    // La o ciocnire în aer nu pierd ținta — obuzul nici n-apucă să ajungă la
    // ea; vizorul rămâne blocat până în clipa izbiturii.
    final losingLock = !hit && !duelIntercepted && p > _jukeFrom;
    final lockX = hit ? cx : _lerp(size.width / 2, cx, 0.34);
    final half = (tankW * 0.62).clamp(40.0, size.width * 0.42);
    final color = losingLock ? AppColors.danger : AppColors.orange;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = color.withAlpha(losingLock ? 235 : 190);

    final rect = Rect.fromCenter(center: Offset(lockX, cy), width: half * 2, height: half * 1.5);
    const armFrac = 0.28;
    final ax = rect.width * armFrac;
    final ay = rect.height * armFrac;
    for (final corner in [
      (rect.topLeft, 1.0, 1.0),
      (rect.topRight, -1.0, 1.0),
      (rect.bottomLeft, 1.0, -1.0),
      (rect.bottomRight, -1.0, -1.0),
    ]) {
      final (o, dx, dy) = corner;
      canvas.drawLine(o, o + Offset(ax * dx, 0), paint);
      canvas.drawLine(o, o + Offset(0, ay * dy), paint);
    }

    // crucea din centrul cadrului rămâne acolo unde ochește tunul
    final cross = Paint()
      ..strokeWidth = 1.4
      ..color = Colors.white.withAlpha(90);
    final ccx = size.width / 2;
    final ccy = cy;
    canvas.drawLine(Offset(ccx - 16, ccy), Offset(ccx - 5, ccy), cross);
    canvas.drawLine(Offset(ccx + 5, ccy), Offset(ccx + 16, ccy), cross);
    canvas.drawLine(Offset(ccx, ccy - 16), Offset(ccx, ccy - 5), cross);
    canvas.drawLine(Offset(ccx, ccy + 5), Offset(ccx, ccy + 16), cross);

    if (losingLock && after < 0) {
      _label(canvas, Offset(size.width / 2, cy - half * 0.95), tr('ȚINTĂ ÎN MIȘCARE', 'TARGET EVADING'), 12, AppColors.danger);
    }
  }

  // ─── Deznodământul ──────────────────────────────────────────────────────

  void _paintOutcome(Canvas canvas, Size size, double cx, double cy, double after) {
    final w = size.width;
    final h = size.height;
    _paintTakenLine(canvas, size, after);

    // Ciocnirea celor două obuze, chiar în fața camerei. Se desenează ÎNAINTEA
    // celorlalte două deznodăminte fiindcă le înlocuiește pe amândouă: n-a
    // fost nici lovitură, nici fereală a țintei — proiectilele s-au anulat
    // între ele la mijlocul câmpului.
    if (duelIntercepted) {
      final t = (after / (0.80 * _scale)).clamp(0.0, 1.0);
      final fade = 1 - t;
      final at = Offset(w / 2, h * 0.62);
      final flash = (1 - after / (0.18 * _scale)).clamp(0.0, 1.0);
      if (flash > 0) {
        canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withAlpha((240 * flash).round()));
      }
      final r = w * (0.12 + 0.85 * Curves.easeOutCubic.transform(t));
      // Mingea de foc poartă AMBELE culori — a mea și a lui — ca ciocnirea să
      // se citească drept întâlnirea a două obuze, nu drept o explozie
      // oarecare în mijlocul câmpului.
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withAlpha((250 * fade).round()),
              shooterColor.withAlpha((215 * fade).round()),
              targetColor.withAlpha((185 * fade).round()),
              Colors.transparent,
            ],
            stops: const [0.0, 0.30, 0.60, 1.0],
          ).createShader(Rect.fromCircle(center: at, radius: r)),
      );
      canvas.drawCircle(
        at,
        r * 1.12,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7 * fade
          ..color = Colors.white.withAlpha((210 * fade).round()),
      );
      // schije aruncate în lături — două obuze care se izbesc frontal nu lasă
      // în urmă decât fier stropit în evantai
      final spark = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.6 * fade;
      for (var i = 0; i < 14; i++) {
        final a = i * (2 * pi / 14) + 0.3;
        final d = Offset(cos(a), sin(a));
        spark.color = (i.isEven ? shooterColor : targetColor).withAlpha((235 * fade).round());
        canvas.drawLine(at + d * (r * 0.5), at + d * (r * 1.35), spark);
      }
      _label(canvas, Offset(w / 2, h * 0.26 - t * 26), 'MISS', 70, Colors.white, alpha: fade);
      _label(canvas, Offset(w / 2, h * 0.26 + 52 - t * 26), tr('OBUZ CONTRA OBUZ', 'SHELL MEETS SHELL'), 18, AppColors.orange, alpha: fade);
      _label(
        canvas,
        Offset(w / 2, h * 0.26 + 78 - t * 26),
        tr('$targetName trăgea în tine în aceeași clipă', '$targetName was firing back at the very same moment'),
        13,
        Colors.white70,
        alpha: fade,
        weight: FontWeight.w600,
        letterSpacing: 0,
      );
      return;
    }

    if (hit) {
      // 1. bliț alb, foarte scurt — ochiul „orbit" de propria lovitură
      final flash = (1 - after / (0.16 * _scale)).clamp(0.0, 1.0);
      if (flash > 0) {
        canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withAlpha((235 * flash).round()));
      }
      // 2. mingea de foc
      final t = (after / (0.72 * _scale)).clamp(0.0, 1.0);
      final fade = 1 - t;
      final r = w * (0.10 + 0.90 * Curves.easeOutCubic.transform(t));
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withAlpha((250 * fade).round()),
              AppColors.coin.withAlpha((235 * fade).round()),
              AppColors.orange.withAlpha((185 * fade).round()),
              Colors.transparent,
            ],
            stops: const [0.0, 0.26, 0.58, 1.0],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
      );
      // 3. inelul de șoc
      canvas.drawCircle(
        Offset(cx, cy),
        r * 1.14,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 * fade
          ..color = Colors.white.withAlpha((200 * fade).round()),
      );
      // 4. schije
      final spark = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.4 * fade
        ..color = AppColors.coin.withAlpha((230 * fade).round());
      for (var i = 0; i < 11; i++) {
        final a = i * (2 * pi / 11) + damage;
        final d = Offset(cos(a), sin(a));
        canvas.drawLine(Offset(cx, cy) + d * (r * 0.55), Offset(cx, cy) + d * (r * 1.25), spark);
      }
      // driftul în pixeli e legat de `t` (0→1), nu de `after` direct: altfel,
      // la un [_scale] mai mare, textul ar pluti mult mai sus doar fiindcă
      // animația durează mai mult în secunde, nu fiindcă ar trebui să se miște
      // mai departe.
      _label(canvas, Offset(w / 2, h * 0.30 - t * 34), '-$damage', 68, AppColors.danger, alpha: fade);
      _label(canvas, Offset(w / 2, h * 0.30 + 50 - t * 34), tr('LOVITURĂ DIRECTĂ', 'DIRECT HIT'), 19, AppColors.orange, alpha: fade);
      return;
    }

    // Evitare: obuzul trece pe lângă tanc și se îngroapă în pământ. Praful
    // din marginea de jos e izbitura — camera fiind chiar obuzul, „unde a
    // căzut" nu se poate arăta altfel decât prin ce sare în cadru.
    final t = (after / tankPovAftermath).clamp(0.0, 1.0);
    final fade = 1 - t;
    // Izbitura în pământ. Camera FIIND obuzul, „unde a căzut" nu se poate
    // arăta decât prin ce sare în cadru — un val de praf care urcă din
    // marginea de jos și umple ecranul chiar înainte ca totul să se stingă.
    if (after > 0.26 * _scale) {
      final burst = ((after - 0.26 * _scale) / (0.40 * _scale)).clamp(0.0, 1.0);
      final spread = Curves.easeOutCubic.transform(burst);
      final dust = Paint();
      for (var i = 0; i < 11; i++) {
        // evantai în SUS din marginea de jos: unghiurile pornesc de la -π/2.
        // (Pornite de la π, toate ieșeau cu cos ≈ -1, deci praful pleca lateral
        // în afara cadrului în loc să se ridice în fața camerei.)
        final a = -pi / 2 + (i - 5) * 0.19;
        final d = Offset(cos(a), sin(a));
        // Fiecare bulgăre are raza și viteza lui, altfel cele unsprezece
        // cercuri egale se citesc ca un șirag de bile, nu ca un nor.
        final jitter = ((i * 41) % 17) / 17;
        canvas.drawCircle(
          Offset(w / 2, h * 1.06) + d * (w * (0.52 + jitter * 0.34) * spread),
          w * (0.09 + 0.20 * spread) * (0.7 + jitter * 0.7),
          dust..color = const Color(0xFFD8BC95).withAlpha(((150 + jitter * 90) * (1 - burst * 0.55)).round()),
        );
      }
    }
    _label(canvas, Offset(w / 2, h * 0.33), tr('EVITAT!', 'DODGED!'), 46, Colors.white, alpha: fade);
    _label(
      canvas,
      Offset(w / 2, h * 0.33 + 40),
      tr('$targetName s-a ferit în ultima clipă', '$targetName slipped the shot at the last moment'),
      13,
      Colors.white70,
      alpha: fade,
      weight: FontWeight.w600,
      letterSpacing: 0,
    );
  }

  /// „AI ÎNCASAT -X" — cât am pierdut EU în runda asta, indiferent de la cine.
  ///
  /// Rândul ăsta e singurul care leagă camera de restul rundei: cât sunt
  /// plecat pe obuz, arena continuă fără mine, iar dacă m-a lovit cineva aș
  /// reveni la o bară mai scurtă fără nicio explicație. Apare mai târziu
  /// decât textul mare și stă jos, ca să nu se bată cu el.
  void _paintTakenLine(Canvas canvas, Size size, double after) {
    if (damageTaken <= 0) return;
    final show = (after - 0.30 * _scale) / (0.22 * _scale);
    if (show <= 0) return;
    final fade = (1 - (after / tankPovAftermath).clamp(0.0, 1.0)) * show.clamp(0.0, 1.0);
    _label(
      canvas,
      Offset(size.width / 2, size.height * 0.79),
      tr('AI ÎNCASAT  -$damageTaken', 'YOU TOOK  -$damageTaken'),
      15,
      AppColors.danger,
      alpha: fade,
    );
  }

  // ─── Cadranul ───────────────────────────────────────────────────────────

  /// Se subțiază în deznodământ, la amândouă capetele: peste explozie ar
  /// stinge tocmai mingea de foc, iar peste ratare ar înghiți praful care
  /// urcă din marginea de jos — adică fix cele două cadre pentru care există
  /// tot efectul.
  void _paintVignette(Canvas canvas, Size size, double after) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, Colors.black.withAlpha(after >= 0 ? 105 : 175)],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
  }

  /// Cifrele din colțuri: nume de țintă, distanță care scade, viața ei. Nu e
  /// doar atmosferă — distanța e singurul lucru care spune cât mai ai de
  /// zburat, într-un cadru în care totul se apropie deodată.
  void _paintHud(Canvas canvas, Size size, double p, double after) {
    final w = size.width;
    final h = size.height;
    final dim = after > 0 ? (1 - (after / tankPovAftermath).clamp(0.0, 1.0)) : 1.0;
    if (dim <= 0.02) return;

    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = AppColors.orange.withAlpha((110 * dim).round());
    const pad = 14.0;
    const len = 22.0;
    final frame = Rect.fromLTRB(pad, pad + 8, w - pad, h - pad - 8);
    for (final corner in [
      (frame.topLeft, 1.0, 1.0),
      (frame.topRight, -1.0, 1.0),
      (frame.bottomLeft, 1.0, -1.0),
      (frame.bottomRight, -1.0, -1.0),
    ]) {
      final (o, dx, dy) = corner;
      canvas.drawLine(o, o + Offset(len * dx, 0), bracket);
      canvas.drawLine(o, o + Offset(0, len * dy), bracket);
    }

    _label(canvas, Offset(w / 2, pad + 26), tr('ȚINTĂ: ${targetName.toUpperCase()}', 'TARGET: ${targetName.toUpperCase()}'), 13, AppColors.orange, alpha: dim);
    // Avertismentul de duel, cât obuzele sunt încă în aer: fără el, obuzul
    // care vine din față ar putea trece drept un efect de fundal, iar
    // ciocnirea de la mijloc ar pica din senin.
    if (duelIncoming && after < 0) {
      _label(canvas, Offset(w / 2, pad + 46), tr('DUEL — trage și el în tine', 'DUEL — they are firing back'), 11.5, AppColors.danger, alpha: dim);
    }
    final metres = ((1 - p) * 420).round();
    _label(canvas, Offset(w * 0.20, h - pad - 30), '${metres}m', 17, Colors.white, alpha: dim);
    _label(canvas, Offset(w * 0.80, h - pad - 30), '$targetHp HP', 17, TankHpBar.hpColor(targetHp), alpha: dim);
  }

  /// Vezi [paintBattleLabel] — textele celor două camere trebuie să arate la
  /// fel, deci desenul lor stă la comun în tank_art.dart.
  void _label(
    Canvas canvas,
    Offset center,
    String text,
    double fontSize,
    Color color, {
    double alpha = 1,
    FontWeight weight = FontWeight.w900,
    double letterSpacing = 1.5,
  }) =>
      paintBattleLabel(canvas, center, text, fontSize, color,
          alpha: alpha, weight: weight, letterSpacing: letterSpacing);

  @override
  bool shouldRepaint(covariant _TankPovPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.hit != hit || oldDelegate.impactAt != impactAt;
}
