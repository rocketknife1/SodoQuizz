/// **Scena scaunului** — deznodământul unei runde de Scaunul Electric, jucat
/// pe rând pentru fiecare victimă: scaunul, cu victima pe el și casca cu
/// electrozi; o secundă de tensiune în care scânteile se tot înteţesc; apoi
/// verdictul. La „a picat": fulgere care coboară în cască, bliț alb, cadrul
/// care se zguduie și o inimă care se sparge. La „a scăpat": scânteile se
/// sting, iar un inel verde se desface în jurul lui.
///
/// NU DECIDE NIMIC: verdictele sunt deja scrise în Firestore
/// (`roundChairOutcomes`, vezi MultiplayerService.resolveElectricChairRound).
/// [time] vine din controlerul ecranului; totul e o funcție de el.
///
/// Desenat din cod, ca restul artei jocului — fără imagini noi în assets.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import '../core/electric_chair.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import 'tank_art.dart' show paintBattleLabel;

/// O victimă a rundei, cu verdictul deja știut.
class ChairShowdownVerdict {
  final String name;
  final Color color;
  final bool survived;

  /// Viețile de DUPĂ verdict — la „a picat" inima care se sparge e a
  /// (livesAfter + 1)-a.
  final int livesAfter;
  final String question;
  final String answer;
  final bool isMe;

  const ChairShowdownVerdict({
    required this.name,
    required this.color,
    required this.survived,
    required this.livesAfter,
    required this.question,
    required this.answer,
    this.isMe = false,
  });
}

class ElectricChairShowdown extends StatelessWidget {
  final double time;
  final List<ChairShowdownVerdict> verdicts;

  /// Avatarul fiecărei victime, așezat pe scaun. Primit gata construit, ca
  /// scena să nu depindă de cum se desenează avatarele.
  final List<Widget> avatars;

  const ElectricChairShowdown({super.key, required this.time, required this.verdicts, required this.avatars});

  @override
  Widget build(BuildContext context) {
    if (verdicts.isEmpty) return const SizedBox.shrink();
    final seg = electricChairSegmentSeconds(verdicts.length);
    final local = time - electricChairShowdownLead;
    final idx = (local / seg).floor().clamp(0, verdicts.length - 1);
    final t = (local - idx * seg).clamp(0.0, seg + 10); // ultima victimă rămâne în cadru
    final v = verdicts[idx];

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      final seat = Offset(w / 2, h * 0.58);
      final avatarSize = min(w * 0.27, h * 0.2);
      final shock = !v.survived && t >= electricChairVerdictAt;
      final shake = shock && t - electricChairVerdictAt < 0.5
          ? Offset(sin(time * 90) * 7, cos(time * 71) * 4) * (1 - (t - electricChairVerdictAt) / 0.5)
          : Offset.zero;
      // tremurul victimei: mic cât e tensiune, violent la șoc
      final jitter = t < electricChairVerdictAt
          ? Offset(sin(time * 55) * 1.5 * (t / electricChairVerdictAt), 0)
          : shock && t - electricChairVerdictAt < 0.9
              ? Offset(sin(time * 120) * 5, cos(time * 97) * 3)
              : Offset.zero;

      return Transform.translate(
        offset: shake,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ChairPainter(time: time, t: t, v: v, seat: seat, avatarSize: avatarSize),
              ),
            ),
            Positioned(
              left: seat.dx - avatarSize / 2 + jitter.dx,
              top: seat.dy - avatarSize * 1.18 + jitter.dy,
              width: avatarSize,
              height: avatarSize,
              child: ColorFiltered(
                // la șoc avatarul se albește o clipă, ca prins în bliț
                colorFilter: ColorFilter.mode(
                  Colors.white.withAlpha(shock ? (200 * (1 - ((t - electricChairVerdictAt) / 0.35).clamp(0.0, 1.0))).round() : 0),
                  BlendMode.srcATop,
                ),
                child: avatars[idx],
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ChairOverlayPainter(time: time, t: t, v: v, seat: seat, avatarSize: avatarSize, index: idx, count: verdicts.length)),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _ChairPainter extends CustomPainter {
  final double time;
  final double t;
  final ChairShowdownVerdict v;
  final Offset seat;
  final double avatarSize;
  _ChairPainter({required this.time, required this.t, required this.v, required this.seat, required this.avatarSize});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final s = avatarSize;

    // lumina de deasupra: un con palid, ca într-o cameră întunecată
    final cone = Path()
      ..moveTo(seat.dx - s * 0.2, 0)
      ..lineTo(seat.dx + s * 0.2, 0)
      ..lineTo(seat.dx + s * 1.6, seat.dy + s * 0.9)
      ..lineTo(seat.dx - s * 1.6, seat.dy + s * 0.9)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withAlpha(40), Colors.white.withAlpha(6)],
        ).createShader(Rect.fromLTWH(0, 0, w, seat.dy + s)),
    );
    // podeaua
    canvas.drawOval(
      Rect.fromCenter(center: seat + Offset(0, s * 0.95), width: s * 3.2, height: s * 0.5),
      Paint()..color = Colors.black.withAlpha(120),
    );

    const wood = Color(0xFF5A3A22);
    const woodDark = Color(0xFF3A2414);
    final p = Paint();
    // spătarul
    p.color = woodDark;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: seat - Offset(0, s * 0.62), width: s * 1.35, height: s * 1.55), Radius.circular(s * 0.12)),
      p,
    );
    p.color = wood;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: seat - Offset(0, s * 0.62), width: s * 1.15, height: s * 1.40), Radius.circular(s * 0.10)),
      p,
    );
    // picioarele
    p.color = woodDark;
    for (final dx in [-0.58, 0.48]) {
      canvas.drawRect(Rect.fromLTWH(seat.dx + dx * s, seat.dy + s * 0.12, s * 0.12, s * 0.78), p);
    }
    // șezutul și brațele, cu curelele de piele
    p.color = wood;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: seat + Offset(0, s * 0.08), width: s * 1.55, height: s * 0.26), Radius.circular(s * 0.06)), p);
    for (final side in [-1.0, 1.0]) {
      final arm = Rect.fromCenter(center: seat + Offset(side * s * 0.78, -s * 0.18), width: s * 0.22, height: s * 0.62);
      p.color = wood;
      canvas.drawRRect(RRect.fromRectAndRadius(arm, Radius.circular(s * 0.05)), p);
      p.color = const Color(0xFF1E1410);
      canvas.drawRect(Rect.fromCenter(center: arm.center, width: s * 0.26, height: s * 0.07), p);
    }

    // cutia de curent, în dreapta, cu cablul spre cască
    final box = Rect.fromCenter(center: seat + Offset(s * 1.75, s * 0.35), width: s * 0.55, height: s * 0.75);
    p.color = const Color(0xFF3B4150);
    canvas.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(s * 0.05)), p);
    final lamp = t < electricChairVerdictAt ? (0.5 + 0.5 * sin(time * 20)) : 1.0;
    p.color = (v.survived && t >= electricChairVerdictAt ? AppColors.play : AppColors.danger).withAlpha((120 + 135 * lamp).round());
    canvas.drawCircle(box.center - Offset(0, box.height * 0.25), s * 0.07, p);
    final helmet = seat - Offset(0, s * 1.28);
    final cable = Path()
      ..moveTo(box.center.dx, box.top)
      ..quadraticBezierTo(box.center.dx, helmet.dy - s * 0.6, helmet.dx + s * 0.1, helmet.dy - s * 0.18);
    canvas.drawPath(
      cable,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.05
        ..color = const Color(0xFF15181F),
    );
  }

  @override
  bool shouldRepaint(covariant _ChairPainter old) => old.time != time || old.v != v;
}

/// Ce stă PESTE avatar: casca, scânteile, fulgerele, blițul, inimile și
/// textele.
class _ChairOverlayPainter extends CustomPainter {
  final double time;
  final double t;
  final ChairShowdownVerdict v;
  final Offset seat;
  final double avatarSize;
  final int index;
  final int count;
  _ChairOverlayPainter({
    required this.time,
    required this.t,
    required this.v,
    required this.seat,
    required this.avatarSize,
    required this.index,
    required this.count,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final s = avatarSize;
    final helmet = seat - Offset(0, s * 1.28);
    final verdictT = t - electricChairVerdictAt;

    // casca metalică
    final p = Paint()..color = const Color(0xFF8C93A3);
    canvas.drawArc(Rect.fromCenter(center: helmet + Offset(0, s * 0.12), width: s * 0.95, height: s * 0.7), pi, pi, true, p);
    p.color = const Color(0xFF5E6472);
    canvas.drawRect(Rect.fromCenter(center: helmet + Offset(0, s * 0.12), width: s * 1.0, height: s * 0.08), p);

    // tensiunea: scântei mici în jurul căștii, tot mai dese
    if (verdictT < 0) {
      final k = (t / electricChairVerdictAt).clamp(0.0, 1.0);
      final n = (3 + k * 9).round();
      final frame = (time * 24).floor();
      final rnd = Random(frame * 31 + index);
      // aura de sub cască, tot mai albastră cât crește tensiunea
      canvas.drawCircle(helmet, s * (0.55 + 0.15 * k), Paint()
        ..color = const Color(0xFF6FB8FF).withAlpha((70 * k).round())
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
      final spark = Paint()
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFB9E4FF).withAlpha((140 + 110 * k).round());
      for (var i = 0; i < n; i++) {
        final a = rnd.nextDouble() * pi;
        final from = helmet + Offset(cos(a) * s * 0.48, -sin(a) * s * 0.3);
        final to = from + Offset(cos(a) * s * (0.1 + rnd.nextDouble() * 0.18), -sin(a) * s * (0.1 + rnd.nextDouble() * 0.2));
        canvas.drawLine(from, to, spark);
      }
      paintBattleLabel(canvas, Offset(w / 2, h * 0.10), v.isMe ? tr('TU EȘTI PE SCAUN…', 'YOU ARE ON THE CHAIR…') : tr('${v.name.toUpperCase()} PE SCAUN…', '${v.name.toUpperCase()} ON THE CHAIR…'),
          17, AppColors.orange, letterSpacing: 1.2);
    }

    if (verdictT >= 0 && !v.survived) {
      // fulgere: câteva ramuri în zig-zag din cer în cască, redesenate la
      // fiecare cadru nou, ca să pâlpâie
      if (verdictT < 0.9) {
        final frame = (time * 18).floor();
        final rnd = Random(frame * 17 + index);
        final alpha = (255 * (1 - verdictT / 0.9)).round();
        for (var b = 0; b < 3; b++) {
          final path = Path();
          var x = helmet.dx + (rnd.nextDouble() - 0.5) * w * 0.7;
          var y = 0.0;
          path.moveTo(x, y);
          final steps = 7;
          for (var i = 1; i <= steps; i++) {
            final f = i / steps;
            x = _lerp(x, helmet.dx, 0.35) + (rnd.nextDouble() - 0.5) * s * 0.5 * (1 - f);
            y = helmet.dy * f;
            path.lineTo(x, y);
          }
          canvas.drawPath(path, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9
            ..color = const Color(0xFF6FB8FF).withAlpha((alpha * 0.35).round())
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
          canvas.drawPath(path, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = Colors.white.withAlpha(alpha));
        }
        // arcuri care îmbrățișează victima
        final arc = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFFB9E4FF).withAlpha(alpha);
        for (var i = 0; i < 4; i++) {
          final r = Rect.fromCenter(center: seat - Offset(0, s * 0.6), width: s * (1.2 + i * 0.15), height: s * (1.6 + i * 0.1));
          canvas.drawArc(r, rnd.nextDouble() * 2 * pi, 1.2, false, arc);
        }
      }
      // blițul
      final flash = (1 - verdictT / 0.18).clamp(0.0, 1.0);
      if (flash > 0) canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withAlpha((230 * flash).round()));
      // fum ușor care se ridică din cască
      final puff = Paint();
      for (var i = 0; i < 6; i++) {
        final rise = ((verdictT * 0.6 + i * 0.17) % 1.0);
        puff.color = const Color(0xFF6B6570).withAlpha((110 * (1 - rise)).round());
        canvas.drawCircle(helmet - Offset(sin(i * 2.1) * s * 0.15, s * (0.2 + rise * 1.1)), s * (0.08 + rise * 0.14), puff);
      }
    }

    if (verdictT >= 0 && v.survived) {
      // scânteile se sting; un inel verde se desface în jurul victimei
      final k = (verdictT / 0.7).clamp(0.0, 1.0);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * (1 - k) + 1
        ..color = AppColors.play.withAlpha((220 * (1 - k)).round());
      canvas.drawCircle(seat - Offset(0, s * 0.6), s * (0.7 + k * 1.2), ring);
    }

    // verdictul și viețile
    if (verdictT >= 0) {
      final pop = Curves.elasticOut.transform((verdictT / 0.6).clamp(0.0, 1.0));
      final label = v.survived ? tr('A SCĂPAT!', 'SURVIVED!') : tr('⚡ −1 VIAȚĂ', '⚡ −1 LIFE');
      canvas.save();
      canvas.translate(w / 2, h * 0.11);
      canvas.scale(0.6 + 0.4 * pop);
      paintBattleLabel(canvas, Offset.zero, label, 34, v.survived ? AppColors.play : AppColors.danger);
      canvas.restore();
      paintBattleLabel(canvas, Offset(w / 2, h * 0.11 + 34), v.isMe ? tr('tu', 'you') : v.name, 14, Colors.white, alpha: pop.clamp(0.0, 1.0));
    }

    _paintHearts(canvas, size, verdictT);

    // întrebarea și răspunsul corect, jos
    paintBattleLabel(canvas, Offset(w / 2, seat.dy + s * 1.25), v.question, 12, Colors.white70,
        weight: FontWeight.w600, letterSpacing: 0);
    if (verdictT >= 0) {
      paintBattleLabel(canvas, Offset(w / 2, seat.dy + s * 1.25 + 20), '→ ${v.answer}', 13, AppColors.coin);
    }
    if (count > 1) {
      paintBattleLabel(canvas, Offset(w / 2, h - 12), '${index + 1} / $count', 11, Colors.white38, weight: FontWeight.w700);
    }
  }

  /// Rândul de inimi de sub scaun: la „a picat", ultima se sparge în două.
  void _paintHearts(Canvas canvas, Size size, double verdictT) {
    final before = v.survived ? v.livesAfter : v.livesAfter + 1;
    final total = max(before, 1);
    const gap = 17.0;
    final y = seat.dy + avatarSize * 1.25 - 26;
    final x0 = size.width / 2 - (total - 1) * gap / 2;
    for (var i = 0; i < total; i++) {
      final at = Offset(x0 + i * gap, y);
      final breaking = !v.survived && i == total - 1 && verdictT >= 0;
      if (!breaking) {
        paintBattleLabel(canvas, at, '♥', 15, AppColors.danger, weight: FontWeight.w900, letterSpacing: 0);
        continue;
      }
      final k = (verdictT / 0.8).clamp(0.0, 1.0);
      if (k >= 1) continue;
      final a = 1 - k;
      paintBattleLabel(canvas, at + Offset(-8 * k, 14 * k * k), '♥', 15, AppColors.danger.withAlpha((255 * a).round()), weight: FontWeight.w900, letterSpacing: 0);
      paintBattleLabel(canvas, at + Offset(8 * k, 18 * k * k), '♥', 15, const Color(0xFF7A1E2A).withAlpha((255 * a).round()), weight: FontWeight.w900, letterSpacing: 0);
    }
  }

  @override
  bool shouldRepaint(covariant _ChairOverlayPainter old) => old.time != time || old.v != v;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
