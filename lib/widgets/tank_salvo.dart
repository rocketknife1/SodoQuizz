/// **Camera de bombardament** — ce vede, în Quizz Tanks, fiecare dintre
/// atacatorii unei ținte pe care trag două sau mai multe tancuri deodată.
///
/// Aceeași scenă ca [TankDefenceView] (widgets/tank_defence.dart), întoarsă:
/// acolo victima stă în spatele propriului tanc și vede obuzele venind de la
/// orizont; aici atacatorul stă în spatele TUNULUI LUI, victima e în fața
/// lui, în câmp, iar ceilalți atacatori sunt pe flancuri, fiecare cu tancul și
/// numele lui. Toate obuzele pleacă, în arc, spre același tanc: fiecare
/// lovitură explodează pe blindajul lui și își scrie dauna în culoarea celui
/// care a tras; la fiecare ratare victima smucește de pe loc și lasă fum în
/// urmă, exact ca în camera ei.
///
/// Victima și atacatorii văd ACELAȘI eveniment, în aceeași secundă: momentele
/// vin din planul comun al rundei (core/tanks.dart, buildTankAttackPlan), iar
/// [time] e ceasul fazei de foc, același din care se hrănesc arena și celelalte
/// camere. NU DECIDE NIMIC: loviturile sunt deja rezolvate în Firestore (vezi
/// MultiplayerService.resolveTanksRound).
///
/// Desenat din cod, ca restul artei jocului (tank_art.dart, tank_pov.dart).
library;

import 'dart:math';

import 'package:flutter/material.dart';
import '../core/lang.dart';
import '../core/tanks.dart';
import '../core/theme.dart';
import 'battlefield_backdrop.dart';
import 'tank_art.dart';

/// Un obuz al bombardamentului, cu deznodământul deja știut.
class SalvoShell {
  final String attackerId;
  final String attackerName;
  final Color color;
  final double launchAt;
  final double impactAt;
  final bool hit;
  final int damage;

  /// Oprit de scutul victimei — nu evitat.
  final bool blocked;

  /// Întors de Reflexie: se întoarce și lovește atacatorul, nu victima.
  final bool reflected;
  final bool megaRocket;

  const SalvoShell({
    required this.attackerId,
    required this.attackerName,
    required this.color,
    required this.launchAt,
    required this.impactAt,
    required this.hit,
    required this.damage,
    this.blocked = false,
    this.reflected = false,
    this.megaRocket = false,
  });

  bool get dodged => !hit && !blocked && !reflected;
}

class TankSalvoView extends StatelessWidget {
  final double time;
  final double startAt;
  final double endAt;
  final String victimName;
  final Color victimColor;

  /// Viața victimei la începutul scenei — bara coboară de aici, lovitură cu
  /// lovitură.
  final int victimHpStart;
  final bool victimDestroyed;
  final List<SalvoShell> shells;

  /// Cine privește: tancul lui e cel din prim-plan, văzut din spate.
  final String myId;
  final Color myColor;
  final int myHp;

  const TankSalvoView({
    super.key,
    required this.time,
    required this.startAt,
    required this.endAt,
    required this.victimName,
    required this.victimColor,
    required this.victimHpStart,
    required this.victimDestroyed,
    required this.shells,
    required this.myId,
    required this.myColor,
    required this.myHp,
  });

  static const double _fadeIn = 0.25;
  static const double _fadeOut = 0.4;

  @override
  Widget build(BuildContext context) {
    if (time < startAt || time >= endAt || shells.isEmpty) return const SizedBox.shrink();
    final opacity = min(((time - startAt) / _fadeIn).clamp(0.0, 1.0), ((endAt - time) / _fadeOut).clamp(0.0, 1.0));
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: CustomPaint(size: Size.infinite, painter: _SalvoPainter(this)),
      ),
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

Offset _bezier(Offset p0, Offset p1, Offset p2, double u) {
  final a = Offset.lerp(p0, p1, u)!;
  final b = Offset.lerp(p1, p2, u)!;
  return Offset.lerp(a, b, u)!;
}

class _SalvoPainter extends CustomPainter {
  final TankSalvoView v;
  _SalvoPainter(this.v);

  static const double _horizonFrac = 0.40;

  /// Aceleași ritmuri ca fereala din camera de apărare (tank_defence.dart):
  /// smucitura pornește cu o clipă înainte de impact și durează puțin.
  static const double _dodgeLead = 0.34;
  static const double _dodgeSpan = 0.62;

  double get t => v.time;

  List<String> get _attackers {
    final out = <String>[];
    for (final s in v.shells) {
      if (!out.contains(s.attackerId)) out.add(s.attackerId);
    }
    return out;
  }

  double get _jukeDir => v.victimName.codeUnits.fold<int>(0, (a, b) => a + b).isEven ? 1.0 : -1.0;

  /// Obuzele evitate, în ordinea impactului: fiecare împinge victima încă o
  /// dată, pe rând în părți opuse — cu cinci obuze pe drum, un tanc care ar
  /// fugi mereu în aceeași parte ar ieși din cadru.
  List<SalvoShell> get _dodges =>
      [for (final s in v.shells) if (s.dodged) s]..sort((a, b) => a.impactAt.compareTo(b.impactAt));

  // ─── Geometria ──────────────────────────────────────────────────────────

  // Victima stă mai departe decât atacatorii de pe flancuri, deci și mai
  // mică decât primul lor rând — altfel perspectiva s-ar citi pe dos.
  Offset _victimBase(Size size) => Offset(size.width / 2, size.height * _horizonFrac + size.height * 0.11);
  double _victimW(Size size) => size.width * 0.28;

  Offset _victimShift(Size size, double at) {
    var dx = 0.0;
    var dy = 0.0;
    final ds = _dodges;
    for (var k = 0; k < ds.length; k++) {
      final since = at - (ds[k].impactAt - _dodgeLead);
      if (since <= 0) continue;
      final e = Curves.easeOutCubic.transform((since / _dodgeSpan).clamp(0.0, 1.0));
      final dir = k.isEven ? _jukeDir : -_jukeDir;
      dx += dir * size.width * 0.17 * e;
      dy -= size.height * 0.008 * e;
    }
    return Offset(dx.clamp(-size.width * 0.24, size.width * 0.24), dy);
  }

  /// Unde cade obuzul: pe blindaj la lovitură (și la scut, pe dom), iar la
  /// ratare pe locul în care victima era ÎNAINTE să smucească — tot rostul
  /// ferelii.
  Offset _aimAt(Size size, SalvoShell s) {
    final at = s.dodged ? s.impactAt - _dodgeLead - 0.05 : s.impactAt;
    final vw = _victimW(size);
    return _victimBase(size) + _victimShift(size, at) - Offset(0, vw * 0.62 * (s.dodged ? -0.1 : 0.45));
  }

  Rect _myRect(Size size) {
    final w = size.width * 0.46;
    final h = w * 0.72;
    return Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.87), width: w, height: h);
  }

  /// Ceilalți atacatori, pe flancuri, la adâncimi diferite: primul rând mai
  /// aproape de cameră (mai mare), următoarele spre orizont.
  Map<String, Rect> _flankRects(Size size) {
    final w = size.width;
    final h = size.height;
    final horizon = h * _horizonFrac;
    final others = [for (final id in _attackers) if (id != v.myId) id];
    final out = <String, Rect>{};
    for (var j = 0; j < others.length; j++) {
      final side = j.isEven ? -1.0 : 1.0;
      final row = j ~/ 2;
      final depth = (0.30 - row * 0.085).clamp(0.08, 0.30); // cât sub orizont
      final y = horizon + h * depth;
      final aw = w * (0.10 + depth * 0.55);
      final ah = aw * 0.62;
      final x = (w / 2 + side * w * (0.36 - row * 0.03)).clamp(aw / 2 + 6, w - aw / 2 - 6);
      out[others[j]] = Rect.fromCenter(center: Offset(x, y - ah / 2), width: aw, height: ah);
    }
    return out;
  }

  Offset _muzzleOf(Size size, String id, Map<String, Rect> flanks) {
    if (id == v.myId) {
      final r = _myRect(size);
      return Offset(r.center.dx, r.top + r.height * 0.045);
    }
    final r = flanks[id];
    if (r == null) return Offset(size.width / 2, size.height);
    final facingRight = r.center.dx < size.width / 2;
    return Offset(facingRight ? r.right : r.left, r.top + r.height * 0.25);
  }

  int get _hpNow {
    var hp = v.victimHpStart;
    for (final s in v.shells) {
      if (s.hit && !s.reflected && t >= s.impactAt) hp -= s.damage;
    }
    return hp.clamp(0, tanksMaxHp);
  }

  double get _lastImpact => v.shells.map((s) => s.impactAt).reduce(max);

  // ─── Desenul ────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * _horizonFrac;
    final flanks = _flankRects(size);
    final shake = _shake(size);

    canvas.save();
    canvas.translate(shake.dx, shake.dy);
    if (!BattlefieldBackdrop.paint(canvas, size, horizon)) {
      _paintSky(canvas, size, horizon);
      _paintGround(canvas, size, horizon);
    }
    _paintVictimSmoke(canvas, size);
    _paintVictim(canvas, size);
    for (final e in flanks.entries) {
      _paintFlankTank(canvas, size, e.key, e.value);
    }
    for (final s in v.shells) {
      _paintShell(canvas, size, s, flanks);
    }
    for (final s in v.shells) {
      _paintImpact(canvas, size, s, flanks);
    }
    if (_attackers.contains(v.myId)) _paintMyTank(canvas, size);
    canvas.restore();

    _paintVignette(canvas, size);
    _paintLabels(canvas, size, flanks);
    _paintHud(canvas, size);
  }

  Offset _shake(Size size) {
    var strength = 0.0;
    for (final s in v.shells) {
      if (!s.hit && !s.reflected) continue;
      final since = t - s.impactAt;
      if (since >= 0 && since < 0.25) {
        strength = max(strength, (1 - since / 0.25) * (s.damage / tanksDamageMax).clamp(0.3, 1.0));
      }
    }
    if (strength <= 0) return Offset.zero;
    return Offset(sin(t * 84) * size.width * 0.012 * strength, cos(t * 67) * size.height * 0.007 * strength);
  }

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
      Paint()..shader = RadialGradient(colors: [AppColors.orange.withAlpha(90), Colors.transparent]).createShader(glow),
    );
  }

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
    for (var i = 0; i < 16; i++) {
      final z = i + 1.0;
      final y = horizon + (h - horizon) / z;
      if (y > h + 2) continue;
      line
        ..color = Colors.white.withAlpha((30 / z).round().clamp(0, 42))
        ..strokeWidth = (2.4 / z).clamp(0.5, 2.4);
      canvas.drawLine(Offset(0, y), Offset(w, y), line);
    }
    final crater = Paint()..color = Colors.black.withAlpha(70);
    for (var i = 0; i < 7; i++) {
      final z = 1.4 + ((i * 29) % 40) / 9;
      final y = horizon + (h - horizon) / z;
      final x = w * (0.10 + ((i * 47) % 100) / 122);
      final r = (w * 0.05) / z * 2.2;
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: r * 2.4, height: r), crater);
    }
  }

  /// Fumul lăsat în urmă la fiecare smucitură — la fel ca în camera
  /// victimei, ca amândouă părțile să vadă același „a scăpat".
  void _paintVictimSmoke(Canvas canvas, Size size) {
    final ds = _dodges;
    for (var k = 0; k < ds.length; k++) {
      final since = t - (ds[k].impactAt - _dodgeLead);
      if (since <= 0) continue;
      final dir = k.isEven ? _jukeDir : -_jukeDir;
      final from = _victimBase(size) + _victimShift(size, ds[k].impactAt - _dodgeLead);
      final puff = Paint();
      for (var i = 0; i < 6; i++) {
        final age = ((since - i * 0.05) / (_dodgeSpan + 0.6)).clamp(0.0, 1.0);
        if (age <= 0 || age >= 1) continue;
        final spread = Curves.easeOutCubic.transform(age);
        final at = from +
            Offset(-dir * size.width * (0.015 + i * 0.022) * (0.5 + spread),
                -size.height * 0.01 * spread * (1 + i * 0.2));
        puff.color = const Color(0xFFC8B49B).withAlpha(((100 - i * 10) * (1 - age)).round().clamp(0, 120));
        canvas.drawCircle(at, size.width * (0.022 + i * 0.006) * (0.6 + spread * 0.9), puff);
      }
    }
  }

  void _paintVictim(Canvas canvas, Size size) {
    final vw = _victimW(size);
    final vh = vw * 0.62;
    var c = _victimBase(size) + _victimShift(size, t);
    // zguduitura blindajului la fiecare lovitură
    for (final s in v.shells) {
      if (!s.hit || s.reflected) continue;
      final since = t - s.impactAt;
      if (since >= 0 && since < 0.25) {
        final k = (1 - since / 0.25) * (s.damage / tanksDamageMax);
        c += Offset(sin(t * 90) * 6 * k, cos(t * 70) * 3 * k);
      }
    }
    final wrecked = v.victimDestroyed && t >= _lastImpact + 0.25;
    canvas.drawOval(
      Rect.fromCenter(center: c + Offset(0, vh * 0.02), width: vw * 0.95, height: vh * 0.18),
      Paint()..color = Colors.black.withAlpha(120),
    );
    paintTankInto(
      canvas,
      Rect.fromCenter(center: c - Offset(0, vh / 2), width: vw, height: vh),
      color: v.victimColor,
      facingRight: _jukeDir > 0,
      destroyed: wrecked,
      damage: 1 - _hpNow / tanksMaxHp,
    );
    if (wrecked) {
      // coloana de fum a epavei
      final since = t - _lastImpact - 0.25;
      final puff = Paint();
      for (var i = 0; i < 8; i++) {
        final rise = (since * 0.8 + i * 0.13) % 1.0;
        puff.color = const Color(0xFF3A3340).withAlpha((150 * (1 - rise)).round());
        canvas.drawCircle(
            c - Offset(sin(i * 1.7) * vw * 0.06, vh * (0.6 + rise * 1.6)), vw * (0.06 + rise * 0.10), puff);
      }
    }
  }

  void _paintFlankTank(Canvas canvas, Size size, String id, Rect r) {
    final s = v.shells.firstWhere((x) => x.attackerId == id);
    final facingRight = r.center.dx < size.width / 2;
    var burned = 0.0;
    for (final x in v.shells) {
      if (x.attackerId == id && x.reflected && t >= x.impactAt) burned = x.damage / tanksMaxHp;
    }
    canvas.drawOval(
      Rect.fromCenter(center: Offset(r.center.dx, r.bottom), width: r.width * 0.95, height: r.height * 0.2),
      Paint()..color = Colors.black.withAlpha(110),
    );
    // reculul, la tragere
    final since = t - s.launchAt;
    final recoil = since >= 0 && since < 0.25 ? (1 - since / 0.25) * r.width * 0.06 : 0.0;
    paintTankInto(canvas, r.shift(Offset(facingRight ? -recoil : recoil, 0)),
        color: s.color, facingRight: facingRight, damage: burned);
  }

  void _paintMyTank(Canvas canvas, Size size) {
    final r = _myRect(size);
    var kick = 0.0;
    for (final s in v.shells) {
      if (s.attackerId != v.myId) continue;
      final since = t - s.launchAt;
      if (since >= 0 && since < 0.3) kick = max(kick, 1 - since / 0.3);
    }
    paintTankRearInto(canvas, r.shift(Offset(0, kick * r.height * 0.06)),
        color: v.myColor, damage: 1 - v.myHp / tanksMaxHp);
  }

  void _paintShell(Canvas canvas, Size size, SalvoShell s, Map<String, Rect> flanks) {
    _paintMuzzleFlash(canvas, size, s, flanks);
    if (t < s.launchAt || t >= s.impactAt) return;
    final muzzle = _muzzleOf(size, s.attackerId, flanks);
    final aim = _aimAt(size, s);
    final ctrl = Offset((muzzle.dx + aim.dx) / 2, min(muzzle.dy, aim.dy) - size.height * 0.10);
    final mine = s.attackerId == v.myId;
    final flight = s.impactAt - s.launchAt;
    // la reflexie: dus în prima parte a drumului, întors în a doua
    final outEnd = s.reflected ? s.launchAt + flight * 0.55 : s.impactAt;

    Offset posAt(double tt) {
      if (tt <= outEnd) {
        final u = ((tt - s.launchAt) / (outEnd - s.launchAt)).clamp(0.0, 1.0);
        // al meu pleacă spre adâncime: repede la început, apoi se tot
        // micșorează — ceilalți trec prin cadru din lateral
        return _bezier(muzzle, ctrl, aim, mine ? Curves.easeOutQuad.transform(u) : u);
      }
      final u = ((tt - outEnd) / (s.impactAt - outEnd)).clamp(0.0, 1.0);
      return _bezier(aim, ctrl.translate(0, size.height * 0.05), muzzle, Curves.easeInQuad.transform(u));
    }

    double radiusAt(double tt) {
      final base = size.width * (s.megaRocket ? 0.018 : 0.012);
      if (!mine) return base;
      final u = ((tt - s.launchAt) / (outEnd - s.launchAt)).clamp(0.0, 1.0);
      return _lerp(size.width * (s.megaRocket ? 0.05 : 0.035), base, Curves.easeOutQuad.transform(u));
    }

    final pos = posAt(t);
    final r = radiusAt(t);
    // dâra
    for (var q = 6; q >= 1; q--) {
      final tt = t - q * 0.03;
      if (tt < s.launchAt) continue;
      final a = (1 - q / 7) * 0.7;
      canvas.drawCircle(posAt(tt), radiusAt(tt) * (1 - q * 0.08), Paint()..color = s.color.withAlpha((200 * a).round()));
    }
    canvas.drawCircle(pos, r * 2.2, Paint()..color = s.color.withAlpha(60));
    canvas.drawCircle(pos, r, Paint()..color = Colors.white);
    canvas.drawCircle(pos, r * 0.55, Paint()..color = s.color);
  }

  void _paintMuzzleFlash(Canvas canvas, Size size, SalvoShell s, Map<String, Rect> flanks) {
    final since = t - s.launchAt;
    if (since < 0 || since > 0.22) return;
    final f = 1 - since / 0.22;
    final at = _muzzleOf(size, s.attackerId, flanks);
    final big = s.attackerId == v.myId ? 2.2 : 1.0;
    canvas.drawCircle(at, size.width * 0.03 * big * f, Paint()..color = AppColors.coin.withAlpha((235 * f).round()));
    canvas.drawCircle(at, size.width * 0.055 * big * f, Paint()..color = AppColors.orange.withAlpha((110 * f).round()));
  }

  void _paintImpact(Canvas canvas, Size size, SalvoShell s, Map<String, Rect> flanks) {
    final after = t - s.impactAt;
    if (after < 0) return;
    final w = size.width;
    final at = s.reflected ? _muzzleOf(size, s.attackerId, flanks) : _aimAt(size, s);

    if (s.blocked) {
      final k = (after / 0.8).clamp(0.0, 1.0);
      if (k >= 1) return;
      final fade = 1 - k;
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(
          at,
          w * (0.04 + 0.12 * Curves.easeOutCubic.transform(k)) + i * 6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (4 - i * 1.2) * fade
            ..color = (i == 0 ? Colors.white : const Color(0xFF7EC8FF)).withAlpha((220 * fade).round()),
        );
      }
      return;
    }

    if (s.hit || s.reflected) {
      final k = (after / 0.9).clamp(0.0, 1.0);
      if (k >= 1) return;
      final fade = 1 - k;
      final r = w * ((s.megaRocket ? 0.08 : 0.05) + 0.20 * Curves.easeOutCubic.transform(k));
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
      final spark = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.6 * fade
        ..color = AppColors.coin.withAlpha((230 * fade).round());
      for (var i = 0; i < 9; i++) {
        final a = i * (2 * pi / 9) + s.damage;
        final d = Offset(cos(a), sin(a));
        canvas.drawLine(at + d * (r * 0.55), at + d * (r * 1.2), spark);
      }
      return;
    }

    // ratare: obuzul se îngroapă în locul gol lăsat de victimă
    final k = (after / 0.9).clamp(0.0, 1.0);
    if (k >= 1) return;
    final spread = Curves.easeOutCubic.transform(k);
    final dust = Paint();
    for (var i = 0; i < 9; i++) {
      final a = -pi / 2 + (i - 4) * 0.26;
      final d = Offset(cos(a), sin(a));
      final jitter = ((i * 41) % 17) / 17;
      dust.color = const Color(0xFFD8BC95).withAlpha(((160 + jitter * 70) * (1 - k)).round().clamp(0, 230));
      canvas.drawCircle(
          at + d * (w * (0.07 + jitter * 0.07) * spread), w * (0.016 + 0.03 * spread) * (0.7 + jitter * 0.7), dust);
    }
  }

  void _paintVignette(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, Colors.black.withAlpha(150)],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
  }

  /// Cine cu cât: deasupra fiecărui atacator, deznodământul obuzului lui; pe
  /// victimă, cifrele loviturilor care urcă, în culoarea celui care a tras.
  void _paintLabels(Canvas canvas, Size size, Map<String, Rect> flanks) {
    for (final e in flanks.entries) {
      final s = v.shells.firstWhere((x) => x.attackerId == e.key);
      paintBattleLabel(canvas, Offset(e.value.center.dx, e.value.top - 10), s.attackerName, 11.5, Colors.white,
          letterSpacing: 0.4);
    }
    final vw = _victimW(size);
    final victimTop = _victimBase(size) + _victimShift(size, t) - Offset(0, vw * 0.62);
    final my = _myRect(size);
    var lane = 0;
    for (final s in v.shells) {
      final since = t - s.impactAt;
      if (since < 0) continue;
      final a = (since / 0.15).clamp(0.0, 1.0);
      final mine = s.attackerId == v.myId;
      final flank = flanks[s.attackerId];
      final Offset? over = mine
          ? Offset(my.center.dx, my.top - 18)
          : flank != null
              ? Offset(flank.center.dx, flank.top - 26)
              : null;
      if (over != null) {
        final String text;
        final Color color;
        if (s.reflected) {
          text = tr('ÎNTORS −${s.damage}', 'BACK −${s.damage}');
          color = AppColors.danger;
        } else if (s.hit) {
          text = '−${s.damage}';
          color = s.color;
        } else if (s.blocked) {
          text = tr('BLOCAT', 'BLOCKED');
          color = const Color(0xFF7EC8FF);
        } else {
          text = tr('EVITAT', 'DODGED');
          color = Colors.white70;
        }
        paintBattleLabel(canvas, over, text, mine ? 17 : 12.5, color, alpha: a);
      }
      if (s.hit && !s.reflected && since < 1.3) {
        final dx = const [0.0, -0.3, 0.3][lane % 3] * vw;
        final fade = since < 0.9 ? 1.0 : 1 - (since - 0.9) / 0.4;
        paintBattleLabel(canvas, victimTop + Offset(dx, -14 - since * 40), '−${s.damage}', 28, s.color, alpha: fade);
        lane++;
      }
    }
  }

  void _paintHud(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final n = _attackers.length;
    final hp = _hpNow;
    paintBattleLabel(
        canvas,
        Offset(w / 2, h * 0.06),
        tr('$n TANCURI PE ${v.victimName.toUpperCase()}', '$n TANKS ON ${v.victimName.toUpperCase()}'),
        16,
        AppColors.orange,
        letterSpacing: 1.4);

    // bara victimei, sub titlu: se golește lovitură cu lovitură
    final barW = w * 0.56;
    final bar = Rect.fromLTWH(w / 2 - barW / 2, h * 0.06 + 20, barW, 9);
    canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(5)), Paint()..color = Colors.white.withAlpha(34));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(bar.left, bar.top, barW * hp / tanksMaxHp, bar.height), const Radius.circular(5)),
      Paint()..color = TankHpBar.hpColor(hp),
    );
    paintBattleLabel(canvas, Offset(w / 2, bar.bottom + 14), '${v.victimName} · $hp HP', 12, Colors.white,
        weight: FontWeight.w800, letterSpacing: 0.3);

    final settle = t - _lastImpact - 0.35;
    if (settle < 0) return;
    final a = (settle / 0.3).clamp(0.0, 1.0);
    final total = v.victimHpStart - hp;
    final String text;
    final Color color;
    if (v.victimDestroyed) {
      text = tr('DISTRUS!', 'WRECKED!');
      color = AppColors.danger;
    } else if (total > 0) {
      text = '−$total HP';
      color = AppColors.danger;
    } else {
      text = tr('A SCĂPAT!', 'GOT AWAY!');
      color = AppColors.play;
    }
    paintBattleLabel(canvas, Offset(w / 2, h * 0.24), text, 44, color, alpha: a);
  }

  @override
  bool shouldRepaint(covariant _SalvoPainter old) => old.v.time != v.time || old.v.shells != v.shells;
}
