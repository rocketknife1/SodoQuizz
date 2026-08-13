/// **Camera de apărare** — ce vede, în modul Quizz Tanks, jucătorul care NU
/// trage în runda curentă, dar are un obuz pe drum spre el.
///
/// DE CE EXISTĂ: până acum, faza de foc avea un singur erou — țintașul, care
/// pleca în camera de pe obuz (widgets/tank_pov.dart) și trăia lovitura din
/// interior. Cel care greșise întrebarea rămânea pe arenă și vedea un punct
/// mic apropiindu-se de cutia lui, apoi o bară care scade. Adică exact
/// jucătorul care tocmai pierdea ceva primea cea mai plictisitoare imagine
/// din rundă. Camera asta îl pune ÎN SPATELE propriului tanc: obuzul vine
/// spre el, crește în cadru, iar în ultima clipă ori îl izbește, ori tancul
/// smucește de pe loc și obuzul se îngroapă în locul gol rămas în urmă.
///
/// NU DECIDE NIMIC, ca tot restul modului: primește tragerile deja rezolvate
/// în Firestore (vezi MultiplayerService.resolveTanksRound) și doar le pune
/// în scenă. „Fereala" nu se calculează din animație — animația e cea care se
/// pliază pe rezultatul dat.
///
/// Ritmurile (cât ține deznodământul, cât durează stingerea spre arenă) sunt
/// ÎMPRUMUTATE de la camera de pe obuz — [tankPovAftermath] și [tankPovFade] —
/// fiindcă cele două camere arată același eveniment din două părți: dacă una
/// s-ar retrage mai devreme decât cealaltă, cei doi jucători s-ar întoarce pe
/// arenă în momente diferite ale aceleiași runde.
///
/// Totul e desenat din cod, ca restul artei jocului (tank_art.dart,
/// tank_pov.dart) — fără imagini noi în assets.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import '../core/lang.dart';
import '../core/tanks.dart';
import '../core/theme.dart';
import 'tank_art.dart';
import 'tank_pov.dart';

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Un obuz care vine spre mine, cu deznodământul lui deja știut. Timpii sunt
/// secunde în ceasul fazei de foc, aceleași cu ale arenei și ale camerei de
/// pe obuz (vezi ShotFlight).
class IncomingShell {
  final double launchAt;
  final double impactAt;
  final bool hit;
  final int damage;

  /// Culoarea celui care trage — aceeași cu a proiectilului lui din arenă,
  /// ca „cine m-a lovit" să se citească din culoare, nu doar din nume.
  final Color color;
  final String shooterName;

  /// De unde vine, pe orizontală: -1 = din stânga, +1 = din dreapta, 0 = din
  /// față. Se calculează din poziția reală a atacatorului în grila arenei
  /// (vezi MultiplayerTanksScreen), ca privirea să se potrivească cu ce
  /// tocmai s-a văzut acolo — un obuz care vine din dreapta trebuie să vină
  /// de la tancul care chiar stă în dreapta ta.
  final double lane;

  const IncomingShell({
    required this.launchAt,
    required this.impactAt,
    required this.hit,
    required this.damage,
    required this.color,
    required this.shooterName,
    this.lane = 0,
  });
}

/// Suprapunerea care ține tot ecranul cât vin obuzele spre mine.
///
/// [time] e ceasul comun al fazei de foc (secunde de la începutul ei),
/// același din care se hrănește și arena — nu un controler propriu, exact ca
/// la [TankPovView] și din același motiv: două ceasuri ar face ca impactul de
/// aici și cel din arenă să cadă la momente diferite.
class TankDefenceView extends StatelessWidget {
  final double time;
  final List<IncomingShell> shells;

  /// Tancul din cadru e chiar al meu: culoarea, viața de la începutul rundei
  /// (din care iese și cât de ars arată blindajul) și numele, din care se
  /// alege partea în care smucește la fereală — un Random ar fi făcut tancul
  /// să tresară stânga-dreapta de 60 de ori pe secundă.
  final Color myColor;
  final String myName;
  final int myHp;

  const TankDefenceView({
    super.key,
    required this.time,
    required this.shells,
    required this.myColor,
    required this.myName,
    required this.myHp,
  });

  /// Când se retrage camera, în ceasul fazei de foc. Ecranul are nevoie de
  /// cifra asta ca să știe până când ține suprapunerea.
  static double endAtFor(List<IncomingShell> shells) {
    if (shells.isEmpty) return 0;
    return shells.map((s) => s.impactAt).reduce(max) + tankPovAftermath;
  }

  @override
  Widget build(BuildContext context) {
    if (shells.isEmpty) return const SizedBox.shrink();
    final end = endAtFor(shells);
    final fadeStart = end - tankPovFade;
    final opacity = time > fadeStart ? ((end - time) / tankPovFade).clamp(0.0, 1.0) : 1.0;
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: CustomPaint(
          size: Size.infinite,
          painter: _TankDefencePainter(
            time: time,
            shells: shells,
            myColor: myColor,
            myName: myName,
            myHp: myHp,
          ),
        ),
      ),
    );
  }
}

class _TankDefencePainter extends CustomPainter {
  final double time;
  final List<IncomingShell> shells;
  final Color myColor;
  final String myName;
  final int myHp;

  const _TankDefencePainter({
    required this.time,
    required this.shells,
    required this.myColor,
    required this.myName,
    required this.myHp,
  });

  /// Cu cât ÎNAINTE de impact pleacă tancul de pe loc, la o fereală. Trebuie
  /// să fie o smucitură în ultima clipă: dacă ar porni mai devreme, n-ar mai
  /// arăta a scăpare, ci a plimbare începută înainte să se tragă.
  static const double _dodgeLead = 0.34;

  /// Cât durează smucitura propriu-zisă.
  static const double _dodgeSpan = 0.62;

  static const double _horizonFrac = 0.42;

  /// Vezi [_TankPovPainter._scale] din tank_pov.dart: pragurile din
  /// deznodământ au fost cronometrate la un [tankPovAftermath] de 0,85s, deci
  /// se scriu ca fracțiuni din el, nu în secunde absolute.
  static const double _baselineAftermath = 0.85;
  double get _scale => tankPovAftermath / _baselineAftermath;

  /// Partea în care smucește tancul, aleasă din nume ca să fie aceeași la
  /// fiecare redesenare a cadrului.
  double get _dodgeDir => myName.codeUnits.fold<int>(0, (a, b) => a + b).isEven ? 1.0 : -1.0;

  // ─── Geometria scenei ───────────────────────────────────────────────────

  Offset _tankBase(Size size) => Offset(size.width * 0.5, size.height * 0.84);

  /// Unde stă tancul la clipa [t], față de locul lui din cadru. Fiecare obuz
  /// ratat îl mai împinge o dată: la două ratări în aceeași rundă nu se poate
  /// fugi „de pe același loc" de două ori.
  Offset _tankShift(Size size, double t) {
    var dx = 0.0;
    var dy = 0.0;
    for (final s in shells) {
      if (s.hit) continue;
      final since = t - (s.impactAt - _dodgeLead);
      if (since <= 0) continue;
      final e = Curves.easeOutCubic.transform((since / _dodgeSpan).clamp(0.0, 1.0));
      dx += _dodgeDir * size.width * 0.30 * e;
      // urcă puțin în cadru = se depărtează de cameră; fără asta, saltul
      // lateral arată ca o alunecare pe gheață, nu ca un tanc care pleacă
      dy -= size.height * 0.035 * e;
    }
    return Offset(dx.clamp(-size.width * 0.36, size.width * 0.36), dy);
  }

  /// Zguduitura din blindaj la o lovitură încasată, cu tot cu cadru. Scurtă
  /// și mică: peste 0,3 secunde ar deveni greață, nu impact.
  Offset _shake(Size size) {
    var strength = 0.0;
    for (final s in shells) {
      if (!s.hit) continue;
      final since = time - s.impactAt;
      if (since >= 0 && since < 0.30) {
        strength = max(strength, (1 - since / 0.30) * (s.damage / tanksDamageMax).clamp(0.3, 1.0));
      }
    }
    if (strength <= 0) return Offset.zero;
    return Offset(sin(time * 84) * size.width * 0.022 * strength, cos(time * 67) * size.height * 0.012 * strength);
  }

  /// Locul de unde pleacă un obuz: tancul atacatorului, mic, la orizont.
  Offset _shooterAt(Size size, IncomingShell s) => Offset(
        size.width * (0.5 + s.lane * 0.33),
        size.height * _horizonFrac - size.height * 0.012,
      );

  /// Unde ajunge obuzul. La o lovitură urmărește tancul până la capăt; la o
  /// ratare rămâne țintit pe locul în care tancul se afla ÎNAINTE să smucească
  /// — ăsta e tot rostul ferelii, iar dacă obuzul ar coti după el, ratarea ar
  /// arăta ca o eroare de desen.
  Offset _aimAt(Size size, IncomingShell s) {
    final base = _tankBase(size);
    final at = s.hit ? s.impactAt : s.impactAt - _dodgeLead - 0.05;
    return base + _tankShift(size, at) + Offset(0, size.height * 0.01);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * _horizonFrac;
    final shift = _tankShift(size, time);
    // Camera urmărește tancul, dar mai încet decât fuge el: așa rămâne în
    // cadru fără să pară că scena e lipită de el.
    final pan = shift.dx * 0.35;
    final shake = _shake(size);

    canvas.save();
    canvas.translate(shake.dx, shake.dy);

    _paintSky(canvas, size, horizon);
    _paintGround(canvas, size, horizon);

    canvas.save();
    canvas.translate(-pan, 0);
    for (final s in shells) {
      _paintShooter(canvas, size, s);
    }
    _paintDodgeSmoke(canvas, size);
    _paintMyTank(canvas, size, shift);
    for (final s in shells) {
      _paintShell(canvas, size, s);
    }
    for (final s in shells) {
      _paintImpact(canvas, size, s);
    }
    canvas.restore();
    canvas.restore();

    _paintThreatGlow(canvas, size);
    _paintOutcome(canvas, size);
    _paintHud(canvas, size);
  }

  // ─── Scena ──────────────────────────────────────────────────────────────

  void _paintSky(Canvas canvas, Size size, double horizon) {
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
    final glow = Rect.fromCircle(center: Offset(size.width / 2, horizon), radius: size.width * 0.5);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, horizon + 4),
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.orange.withAlpha(90), Colors.transparent],
        ).createShader(glow),
    );
  }

  /// Solul: raze spre punctul de fugă și travee orizontale. Spre deosebire de
  /// camera de pe obuz, aici NU se mișcă — camera stă pe loc, în spatele unui
  /// tanc oprit, iar un sol care fuge ar fi sugerat că mă deplasez.
  void _paintGround(Canvas canvas, Size size, double horizon) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTRB(0, horizon, w, h);
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
    // 1/z, ca la tank_pov: traveele apropiate se răresc singure
    for (var i = 0; i < 16; i++) {
      final z = i + 1.0;
      final y = horizon + (h - horizon) / z;
      if (y > h + 2) continue;
      line
        ..color = Colors.white.withAlpha((30 / z).round().clamp(0, 42))
        ..strokeWidth = (2.4 / z).clamp(0.5, 2.4);
      canvas.drawLine(Offset(0, y), Offset(w, y), line);
    }

    // cratere, împrăștiate determinist — urme de rundele trecute
    final crater = Paint();
    for (var i = 0; i < 7; i++) {
      final z = 1.4 + ((i * 29) % 40) / 9;
      final y = horizon + (h - horizon) / z;
      final x = w * (0.10 + ((i * 47) % 100) / 122);
      final r = (w * 0.05) / z * 2.2;
      crater.color = Colors.black.withAlpha(70);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: r * 2.4, height: r), crater);
    }
  }

  /// Tancul care trage în mine, mic la orizont, cu flacăra de la gura tunului
  /// în clipa plecării. E singurul lucru din cadru care spune DE UNDE vine
  /// obuzul înainte să apuce să crească.
  void _paintShooter(Canvas canvas, Size size, IncomingShell s) {
    if (time > s.impactAt + 0.5) return;
    final at = _shooterAt(size, s);
    final tankW = size.width * 0.13;
    final tankH = tankW * 0.62;
    canvas.drawOval(
      Rect.fromCenter(center: at + Offset(0, tankH * 0.52), width: tankW * 0.9, height: tankH * 0.18),
      Paint()..color = Colors.black.withAlpha(110),
    );
    paintTankInto(
      canvas,
      Rect.fromCenter(center: at, width: tankW, height: tankH),
      color: s.color,
      // se uită spre mine: cel din stânga cadrului are țeava spre dreapta
      facingRight: s.lane <= 0,
    );

    final since = time - s.launchAt;
    if (since < 0 || since > 0.22) return;
    final f = 1 - since / 0.22;
    final muzzle = at + Offset(tankW * (s.lane <= 0 ? 0.52 : -0.52), -tankH * 0.06);
    canvas.drawCircle(muzzle, tankW * 0.24 * f, Paint()..color = AppColors.coin.withAlpha((235 * f).round()));
    canvas.drawCircle(muzzle, tankW * 0.42 * f, Paint()..color = AppColors.orange.withAlpha((110 * f).round()));
  }

  /// Fumul rămas în locul din care a plecat tancul. Nu e decor: e singurul
  /// lucru care arată CĂ a plecat de pe loc — fără el, tancul pare doar mutat
  /// în altă parte a cadrului.
  void _paintDodgeSmoke(Canvas canvas, Size size) {
    for (final s in shells) {
      if (s.hit) continue;
      final since = time - (s.impactAt - _dodgeLead);
      if (since <= 0) continue;
      final life = (since / (_dodgeSpan + 0.7)).clamp(0.0, 1.0);
      if (life >= 1) continue;
      final from = _tankBase(size) + _tankShift(size, s.impactAt - _dodgeLead);
      final puff = Paint();
      for (var i = 0; i < 7; i++) {
        // fiecare rotocol pornește puțin mai târziu decât cel dinainte, deci
        // norul se întinde în urma tancului în loc să apară dintr-odată
        final delay = i * 0.055;
        final age = ((since - delay) / (_dodgeSpan + 0.55)).clamp(0.0, 1.0);
        if (age <= 0) continue;
        final spread = Curves.easeOutCubic.transform(age);
        final at = from +
            Offset(
              _dodgeDir * size.width * (0.02 + i * 0.030) * (0.5 + spread),
              -size.height * 0.012 * spread * (1 + i * 0.16),
            );
        puff.color = const Color(0xFFC8B49B).withAlpha(((105 - i * 9) * (1 - age)).round().clamp(0, 120));
        canvas.drawCircle(at, size.width * (0.030 + i * 0.008) * (0.6 + spread * 0.9), puff);
      }
    }
  }

  void _paintMyTank(Canvas canvas, Size size, Offset shift) {
    // După o lovitură directă tancul rămâne în cadru (nu e distrus neapărat),
    // dar dispare o clipă sub mingea de foc — desenat înainte de ea.
    final tankW = size.width * 0.50;
    final tankH = tankW * 0.72;
    final center = _tankBase(size) + shift;

    canvas.drawOval(
      Rect.fromCenter(center: center + Offset(0, tankH * 0.50), width: tankW * 0.98, height: tankH * 0.16),
      Paint()..color = Colors.black.withAlpha(130),
    );
    paintTankRearInto(
      canvas,
      Rect.fromCenter(center: center, width: tankW, height: tankH),
      color: myColor,
      damage: 1 - (myHp / tanksMaxHp),
    );
  }

  /// Obuzul care vine spre mine: mic la orizont, apoi umple cadrul. Creșterea
  /// e easeInQuart, nu liniară — la viteza unui obuz, ultimii metri se fac
  /// într-o clipă, iar o apropiere uniformă ar arăta a balon, nu a proiectil.
  void _paintShell(Canvas canvas, Size size, IncomingShell s) {
    final span = max(s.impactAt - s.launchAt, 0.001);
    final q = (time - s.launchAt) / span;
    if (q < 0 || q > 1) return;
    final from = _shooterAt(size, s);
    final to = _aimAt(size, s);
    final e = Curves.easeInQuart.transform(q.clamp(0.0, 1.0));
    final pos = Offset.lerp(from, to, e)!;
    final r = _lerp(size.width * 0.008, size.width * 0.055, e);

    // dâra: unde era cu o fracțiune de secundă în urmă
    final tailE = Curves.easeInQuart.transform((q - 0.13).clamp(0.0, 1.0));
    final tail = Offset.lerp(from, to, tailE)!;
    canvas.drawLine(
      tail,
      pos,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * 0.8
        ..shader = LinearGradient(
          colors: [s.color.withAlpha(0), s.color.withAlpha(200)],
        ).createShader(Rect.fromPoints(tail, pos)),
    );

    canvas.drawCircle(pos, r * 2.1, Paint()..color = s.color.withAlpha(55));
    canvas.drawCircle(pos, r, Paint()..color = Colors.white);
    canvas.drawCircle(pos, r * 0.55, Paint()..color = s.color);
  }

  void _paintImpact(Canvas canvas, Size size, IncomingShell s) {
    final after = time - s.impactAt;
    if (after < 0) return;
    final at = _aimAt(size, s);
    final w = size.width;

    if (s.hit) {
      final t = (after / (0.72 * _scale)).clamp(0.0, 1.0);
      if (t >= 1) return;
      final fade = 1 - t;
      final r = w * (0.10 + 0.62 * Curves.easeOutCubic.transform(t));
      canvas.drawCircle(
        at,
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
          ).createShader(Rect.fromCircle(center: at, radius: r)),
      );
      canvas.drawCircle(
        at,
        r * 1.16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 * fade
          ..color = Colors.white.withAlpha((200 * fade).round()),
      );
      final spark = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.4 * fade
        ..color = AppColors.coin.withAlpha((230 * fade).round());
      for (var i = 0; i < 11; i++) {
        final a = i * (2 * pi / 11) + s.damage;
        final d = Offset(cos(a), sin(a));
        canvas.drawLine(at + d * (r * 0.55), at + d * (r * 1.25), spark);
      }
      return;
    }

    // Ratare: obuzul se îngroapă în pământ, exact în locul gol lăsat de tanc.
    final t = (after / (0.75 * _scale)).clamp(0.0, 1.0);
    if (t >= 1) return;
    final spread = Curves.easeOutCubic.transform(t);
    final dust = Paint();
    for (var i = 0; i < 10; i++) {
      // evantai în sus și în lateral din punctul de cădere
      final a = -pi / 2 + (i - 4.5) * 0.24;
      final d = Offset(cos(a), sin(a));
      final jitter = ((i * 41) % 17) / 17;
      dust.color = const Color(0xFFD8BC95).withAlpha(((165 + jitter * 70) * (1 - t)).round().clamp(0, 235));
      canvas.drawCircle(
        at + d * (w * (0.16 + jitter * 0.16) * spread),
        w * (0.028 + 0.052 * spread) * (0.7 + jitter * 0.7),
        dust,
      );
    }
    // craterul proaspăt, sub praf
    canvas.drawOval(
      Rect.fromCenter(center: at, width: w * 0.20 * (0.4 + spread), height: w * 0.07 * (0.4 + spread)),
      Paint()..color = Colors.black.withAlpha((150 * (1 - t)).round()),
    );
  }

  // ─── Cadranul și deznodământul ──────────────────────────────────────────

  /// Pulsul roșu dinspre margini cât obuzul e în aer: singurul lucru care
  /// spune „ai ceva pe drum" înainte ca proiectilul să fie destul de mare cât
  /// să se vadă. Se stinge la impact — de acolo încolo vorbește explozia.
  void _paintThreatGlow(Canvas canvas, Size size) {
    var strength = 0.0;
    for (final s in shells) {
      final span = max(s.impactAt - s.launchAt, 0.001);
      final q = (time - s.launchAt) / span;
      if (q < 0 || q > 1) continue;
      strength = max(strength, q * q);
    }
    final rect = Offset.zero & size;
    // vinieta de bază, ca la camera de pe obuz — ține ochiul în mijloc
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, Colors.black.withAlpha(160)],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
    if (strength <= 0.02) return;
    final pulse = 0.55 + 0.45 * sin(time * 13);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, AppColors.danger.withAlpha((105 * strength * pulse).round().clamp(0, 140))],
          stops: const [0.42, 1.0],
        ).createShader(rect),
    );
  }

  /// Textul mare de deznodământ, al ULTIMULUI obuz ajuns. La două lovituri în
  /// aceeași rundă, cifrele s-ar suprapune dacă le-am ține pe toate pe ecran;
  /// așa, fiecare impact rescrie mesajul, iar totalul se vede oricum pe bara
  /// de viață când se retrage camera.
  void _paintOutcome(Canvas canvas, Size size) {
    IncomingShell? last;
    for (final s in shells) {
      if (time < s.impactAt) continue;
      if (last == null || s.impactAt > last.impactAt) last = s;
    }
    if (last == null) return;
    final after = time - last.impactAt;
    final t = (after / tankPovAftermath).clamp(0.0, 1.0);
    final fade = 1 - t;
    final w = size.width;
    final h = size.height;

    if (last.hit) {
      // Blițul alb al loviturii încasate — mai scurt și mai slab decât cel de
      // pe camera de pe obuz: acolo albul E deznodământul (ai lovit tu), aici
      // el acoperă tocmai mingea de foc care se ridică din propriul blindaj,
      // adică singurul lucru pe care omul are ce să-l vadă.
      final flash = (1 - after / (0.10 * _scale)).clamp(0.0, 1.0);
      if (flash > 0) {
        canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withAlpha((185 * flash).round()));
      }
      paintBattleLabel(canvas, Offset(w / 2, h * 0.24 - t * 30), '-${last.damage}', 68, AppColors.danger, alpha: fade);
      paintBattleLabel(
        canvas,
        Offset(w / 2, h * 0.24 + 50 - t * 30),
        tr('TE-A LOVIT ${last.shooterName.toUpperCase()}', '${last.shooterName.toUpperCase()} HIT YOU'),
        18,
        AppColors.orange,
        alpha: fade,
      );
      return;
    }

    // Fereala. Textul e cel cerut, cuvânt cu cuvânt: e replica tancului, nu
    // un raport de sistem — de-aia stă cu ghilimele și cu literă mică.
    paintBattleLabel(canvas, Offset(w / 2, h * 0.24), tr('Ha, m-a ratat!', 'Ha, missed me!'), 40, AppColors.play, alpha: fade);
    paintBattleLabel(
      canvas,
      Offset(w / 2, h * 0.24 + 38),
      tr('${last.shooterName} a tras în locul gol', '${last.shooterName} shot the empty ground'),
      13,
      Colors.white70,
      alpha: fade,
      weight: FontWeight.w600,
      letterSpacing: 0,
    );
  }

  /// Cifrele din colțuri: cine trage în mine, cât mai are obuzul de zburat,
  /// viața mea. Roșu, nu portocaliu ca la camera de pe obuz — aici nu
  /// țintesc, sunt ținta.
  void _paintHud(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // se stinge odată cu ultimul impact: după el, tot ce contează e textul
    // mare din mijloc
    final lastImpact = shells.map((s) => s.impactAt).reduce(max);
    final dim = time > lastImpact ? (1 - ((time - lastImpact) / tankPovAftermath).clamp(0.0, 1.0)) : 1.0;
    if (dim <= 0.02) return;

    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = AppColors.danger.withAlpha((120 * dim).round());
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

    final names = <String>{for (final s in shells) s.shooterName}.join(', ');
    paintBattleLabel(
      canvas,
      Offset(w / 2, pad + 26),
      shells.length > 1
          ? tr('SUB FOC: $names', 'INCOMING: $names')
          : tr('TRAGE ÎN TINE: ${names.toUpperCase()}', 'SHOOTING AT YOU: ${names.toUpperCase()}'),
      13,
      AppColors.danger,
      alpha: dim,
    );

    // distanța celui mai apropiat obuz încă în aer
    var nearest = 1.0;
    for (final s in shells) {
      final span = max(s.impactAt - s.launchAt, 0.001);
      final q = (time - s.launchAt) / span;
      if (q < 0 || q > 1) continue;
      nearest = min(nearest, 1 - q);
    }
    if (nearest < 1) {
      paintBattleLabel(canvas, Offset(w * 0.20, h - pad - 30), '${(nearest * 420).round()}m', 17, Colors.white, alpha: dim);
    }
    paintBattleLabel(canvas, Offset(w * 0.80, h - pad - 30), '$myHp HP', 17, TankHpBar.hpColor(myHp), alpha: dim);
  }

  @override
  bool shouldRepaint(covariant _TankDefencePainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.shells != shells;
}
