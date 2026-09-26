import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/unknown_game.dart';

/// Tabla din „Unknown": drumul cu numere 1..60 care șerpuiește pe o insulă
/// plutitoare, ca tablele de Piticot din copilărie — rânduri de câte 6,
/// START jos, finalul sus, scări de lemn și șerpi desenați peste drum.
///
/// Tot ce se mișcă stă în [UnknownScene], pe care ecranul o modifică și o
/// repictează prin `repaint`, fără rebuild de widget la fiecare cadru.
/// Coordonatele sunt „de lume" ([unknownWorldW] × [unknownWorldH]); camera
/// ([UnknownScene.cam], [UnknownScene.zoom]) alege ce bucată se vede.

const double unknownWorldW = 1000;
const double unknownWorldH = 1320;
const Offset unknownWorldCenter = Offset(unknownWorldW / 2, unknownWorldH / 2);
const int _perRow = 6;

const List<Color> unknownPlayerColors = [
  Color(0xFF22C55E),
  Color(0xFF3B82F6),
  Color(0xFFFF7A1A),
  Color(0xFFB36BFF),
  Color(0xFFFF5FA2),
  Color(0xFF2EC4B6),
];

Color unknownTileColor(UnknownTile t) => switch (t) {
      UnknownTile.normal => const Color(0xFFFFE9A8),
      UnknownTile.ladder => const Color(0xFFFFE9A8),
      UnknownTile.snake => const Color(0xFFFFE9A8),
      UnknownTile.back3 => const Color(0xFFE24B4A),
      UnknownTile.trap => const Color(0xFF6B7280),
      UnknownTile.clover => const Color(0xFF22C55E),
      UnknownTile.chest => const Color(0xFFFFB020),
      UnknownTile.event => const Color(0xFF8B5CF6),
      UnknownTile.duel => const Color(0xFFFF7A1A),
      UnknownTile.shop => const Color(0xFF2EC4B6),
      UnknownTile.coins => const Color(0xFF3B82F6),
      UnknownTile.tax => const Color(0xFFB91C1C),
      UnknownTile.finish => const Color(0xFFFFD700),
    };

IconData? unknownTileIcon(UnknownTile t) => switch (t) {
      UnknownTile.back3 => Icons.undo_rounded,
      UnknownTile.trap => Icons.pause_rounded,
      UnknownTile.clover => Icons.shield_rounded,
      UnknownTile.chest => Icons.redeem_rounded,
      UnknownTile.event => Icons.question_mark_rounded,
      UnknownTile.duel => Icons.sports_kabaddi_rounded,
      UnknownTile.shop => Icons.storefront_rounded,
      UnknownTile.coins => Icons.add_circle_rounded,
      UnknownTile.tax => Icons.remove_circle_rounded,
      UnknownTile.finish => Icons.emoji_events_rounded,
      _ => null,
    };

/// Centrul câmpului [n] (0 = START, sub câmpul 1). Rândurile merg pe rând
/// stânga→dreapta și dreapta→stânga, cu o undă ușoară, ca drumul să pară
/// bătut, nu trasat cu rigla.
final List<Offset> unknownTileCenters = List.unmodifiable([
  for (var n = 0; n <= unknownFinish; n++) _tileCenter(n),
]);

Offset _tileCenter(int n) {
  if (n == 0) return const Offset(130, 1265);
  final i = n - 1;
  final row = i ~/ _perRow;
  final k = i % _perRow;
  final col = row.isEven ? k : _perRow - 1 - k;
  final x = 130 + col * 148.0 + sin(row * 1.7) * 12;
  final y = 1150 - row * 118.0 + sin(col * 1.3 + row) * 14;
  return Offset(x, y);
}

/// Punctul de pe corpul șarpelui [head] → coada lui, la [t] ∈ [0, 1].
/// Același drum și pentru desen, și pentru alunecarea pionului.
Offset unknownSnakePoint(int head, double t) {
  final a = unknownTileCenters[head];
  final b = unknownTileCenters[unknownSnakes[head]!];
  final d = b - a;
  final len = d.distance;
  final nrm = Offset(-d.dy / len, d.dx / len);
  final wave = sin(t * pi * 3) * 42 * (1 - t * 0.4);
  return a + d * t + nrm * wave;
}

class UnknownPawn {
  UnknownPawn({required this.id, required this.colorIndex, required this.initial, required this.tile})
      : pos = unknownTileCenters[tile];

  final String id;
  final int colorIndex;
  final String initial;
  int tile;
  Offset pos;
  double lift = 0;
  bool moving = false;
}

class UnknownFloater {
  UnknownFloater({required this.pos, required this.text, required this.color, required this.born, this.big = false});

  final Offset pos;
  final String text;
  final Color color;
  final double born;
  final bool big;
}

const double unknownFloaterLife = 2.4;

class UnknownScene {
  final Map<String, UnknownPawn> pawns = {};
  final List<UnknownFloater> floaters = [];
  String? activeId;
  double time = 0;
  Offset cam = unknownWorldCenter;
  double zoom = 1;
  Offset camTarget = unknownWorldCenter;
  double zoomTarget = 1;

  /// Câmpul pe care stă pionul, cu decalaj când sunt mai mulți pe același
  /// câmp — altfel s-ar suprapune perfect și n-ai ști cine unde e.
  Offset restingPos(UnknownPawn p) {
    final same = pawns.values.where((q) => !q.moving && q.tile == p.tile).toList()
      ..sort((a, b) => a.colorIndex.compareTo(b.colorIndex));
    final base = unknownTileCenters[p.tile];
    if (same.length <= 1) return base;
    final k = same.indexOf(p);
    final a = 2 * pi * k / same.length - pi / 2;
    return base + Offset(cos(a), sin(a)) * 26;
  }
}

class UnknownBoard extends StatelessWidget {
  const UnknownBoard({super.key, required this.scene, required this.repaint});

  final UnknownScene scene;
  final Listenable repaint;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BoardPainter(scene, repaint),
        size: Size.infinite,
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.s, Listenable repaint) : super(repaint: repaint);

  final UnknownScene s;

  static final Map<String, TextPainter> _glyphs = {};

  static TextPainter _text(String text, double size, Color color, {FontWeight weight = FontWeight.w900}) {
    final key = '$text|$size|${color.toARGB32()}|${weight.value}';
    return _glyphs.putIfAbsent(key, () {
      return TextPainter(
        text: TextSpan(text: text, style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1)),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  /// Iconițele sunt din fontul Material, nu emoji: pe web emoji-urile
  /// desenate pe canvas nu apar până nu se descarcă fontul lor.
  static TextPainter _icon(IconData icon, double size, Color color) {
    final key = 'icon${icon.codePoint}|$size|${color.toARGB32()}';
    return _glyphs.putIfAbsent(key, () {
      return TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(fontSize: size, color: color, fontFamily: icon.fontFamily, package: icon.fontPackage, height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  double get _bob => sin(s.time * 0.8) * 4;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = min(size.width / unknownWorldW, size.height / unknownWorldH) * s.zoom;
    // Camera nu iese de pe insulă: lângă margine, tabla se oprește la marginea
    // ecranului în loc să lase jumătate de ecran gol.
    double clampAxis(double v, double half, double lo, double hi) =>
        hi - lo <= 2 * half ? (lo + hi) / 2 : v.clamp(lo + half, hi - half);
    final cam = Offset(
      clampAxis(s.cam.dx, size.width / 2 / scale, 0, unknownWorldW),
      clampAxis(s.cam.dy, size.height / 2 / scale, 20, unknownWorldH + 40),
    );
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-cam.dx, -cam.dy + _bob);

    _island(canvas);
    _road(canvas);
    for (var n = 1; n <= unknownFinish; n++) {
      _tile(canvas, n);
    }
    _start(canvas);
    for (final e in unknownLadders.entries) {
      _ladder(canvas, e.key, e.value);
    }
    for (final head in unknownSnakes.keys) {
      _snake(canvas, head);
    }
    _pawns(canvas);
    _floaters(canvas);
    canvas.restore();
  }

  // ─── Insula ──────────────────────────────────────────────────────────

  void _island(Canvas canvas) {
    const rect = Rect.fromLTWH(16, 40, unknownWorldW - 32, unknownWorldH - 60);
    final top = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(150)));

    // Stânca de dedesubt și cascadele care se pierd în spațiu.
    canvas.drawPath(
      top.shift(const Offset(0, 44)),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 900),
          const Offset(0, unknownWorldH + 60),
          const [Color(0xFF6B5240), Color(0xFF2E2219)],
        ),
    );
    for (final x in const [210.0, 520.0, 800.0]) {
      final paint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(x, unknownWorldH - 20),
          Offset(x, unknownWorldH + 150),
          const [Color(0xCC7FD3FF), Color(0x007FD3FF)],
        )
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, unknownWorldH - 10), Offset(x, unknownWorldH + 140), paint);
      final flow = (s.time * 70 + x) % 120;
      canvas.drawCircle(Offset(x, unknownWorldH + flow), 5, Paint()..color = const Color(0x88FFFFFF));
    }

    canvas.drawPath(
      top,
      Paint()
        ..shader = ui.Gradient.radial(
          unknownWorldCenter,
          780,
          const [Color(0xFF63D685), Color(0xFF36A65D), Color(0xFF1F7A48)],
          const [0, 0.65, 1],
        ),
    );
    canvas.drawPath(
      top,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = const Color(0xFF7BE39A),
    );

    // Tufișuri printre rânduri, mereu în aceleași locuri.
    final rnd = Random(11);
    for (var i = 0; i < 26; i++) {
      final row = rnd.nextInt(10);
      final p = Offset(70 + rnd.nextDouble() * 860, 1150 - row * 118.0 - 59);
      final sway = sin(s.time * 1.3 + i) * 2;
      canvas.drawCircle(p + Offset(sway, 0), 13 + rnd.nextDouble() * 6, Paint()..color = const Color(0xFF1E8A4C));
      canvas.drawCircle(p + Offset(sway - 5, -5), 7, Paint()..color = const Color(0xFF3CC46E));
    }
  }

  // ─── Drumul, câmpurile, START ────────────────────────────────────────

  void _road(Canvas canvas) {
    final path = Path();
    for (var n = 0; n <= unknownFinish; n++) {
      final p = unknownTileCenters[n];
      if (n == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 50
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF8A6A3F),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 38
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFF2D59B),
    );
  }

  void _tile(Canvas canvas, int n) {
    final type = unknownTileAt(n);
    final c = unknownTileCenters[n];
    final color = unknownTileColor(type);
    final plain = type == UnknownTile.normal || type == UnknownTile.ladder || type == UnknownTile.snake;
    final r = type == UnknownTile.finish ? 56.0 : 44.0;

    if (type == UnknownTile.finish) {
      final pulse = 0.5 + 0.5 * sin(s.time * 3);
      canvas.drawCircle(
        c,
        r + 26 + 8 * pulse,
        Paint()..shader = ui.Gradient.radial(c, r + 34, const [Color(0x99FFD700), Color(0x00FFD700)]),
      );
    }
    canvas.drawCircle(c + const Offset(0, 6), r, Paint()..color = const Color(0x55000000));
    canvas.drawCircle(c, r, Paint()..color = plain ? const Color(0xFFB8860B) : Colors.white);
    canvas.drawCircle(
      c,
      r - 5,
      Paint()
        ..shader = ui.Gradient.radial(c - const Offset(10, 12), r + 8, [Color.lerp(color, Colors.white, 0.35)!, color]),
    );

    final icon = unknownTileIcon(type);
    final numberColor = plain ? const Color(0xFF3A2A12) : Colors.white;
    if (icon == null) {
      final tp = _text('$n', 32, numberColor);
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    } else {
      final tp = _text('$n', 22, numberColor);
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2 + 13));
      final ip = _icon(icon, type == UnknownTile.finish ? 34 : 24, numberColor);
      ip.paint(canvas, c - Offset(ip.width / 2, ip.height / 2 - 14));
    }
  }

  void _start(Canvas canvas) {
    final c = unknownTileCenters[0];
    final rect = Rect.fromCenter(center: c, width: 150, height: 58);
    canvas.drawRRect(RRect.fromRectAndRadius(rect.shift(const Offset(0, 6)), const Radius.circular(18)),
        Paint()..color = const Color(0x55000000));
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)), Paint()..color = const Color(0xFFE24B4A));
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.white,
    );
    final tp = _text('START', 26, Colors.white);
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  // ─── Scări și șerpi ──────────────────────────────────────────────────

  void _ladder(Canvas canvas, int from, int to) {
    final a = unknownTileCenters[from];
    final b = unknownTileCenters[to];
    final d = b - a;
    final len = d.distance;
    final dir = d / len;
    final side = Offset(-dir.dy, dir.dx) * 17;
    // Scara pleacă și ajunge puțin în interiorul câmpurilor, ca să se vadă
    // clar de unde până unde.
    final a2 = a + dir * 14;
    final b2 = b - dir * 14;
    final shadow = Paint()
      ..color = const Color(0x55000000)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a2 + side + const Offset(0, 6), b2 + side + const Offset(0, 6), shadow);
    canvas.drawLine(a2 - side + const Offset(0, 6), b2 - side + const Offset(0, 6), shadow);
    final rung = Paint()
      ..color = const Color(0xFFC98B4A)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final steps = (len / 34).floor();
    for (var i = 1; i < steps; i++) {
      final p = Offset.lerp(a2, b2, i / steps)!;
      canvas.drawLine(p + side, p - side, rung);
    }
    final rail = Paint()
      ..color = const Color(0xFF8B5A2B)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a2 + side, b2 + side, rail);
    canvas.drawLine(a2 - side, b2 - side, rail);
  }

  static const List<(Color, Color)> _snakeColors = [
    (Color(0xFF9B5DE5), Color(0xFFF15BB5)),
    (Color(0xFF00BBF9), Color(0xFF00F5D4)),
    (Color(0xFFEF476F), Color(0xFFFFD166)),
    (Color(0xFF06D6A0), Color(0xFF118AB2)),
    (Color(0xFFFF7A1A), Color(0xFFFFE066)),
    (Color(0xFF7B2CBF), Color(0xFF3CC46E)),
  ];

  void _snake(Canvas canvas, int head) {
    final idx = unknownSnakes.keys.toList().indexOf(head);
    final (c1, c2) = _snakeColors[idx % _snakeColors.length];
    const n = 36;
    // Corpul: segmente tot mai subțiri spre coadă, cu dungi alternante.
    for (var i = n - 1; i >= 0; i--) {
      final t0 = i / n;
      final t1 = (i + 1) / n;
      final p0 = unknownSnakePoint(head, t0);
      final p1 = unknownSnakePoint(head, t1);
      final w = 30 - 22 * t0;
      canvas.drawLine(
        p0 + const Offset(0, 5),
        p1 + const Offset(0, 5),
        Paint()
          ..color = const Color(0x44000000)
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        p0,
        p1,
        Paint()
          ..color = i.isEven ? c1 : Color.lerp(c1, c2, 0.6)!
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round,
      );
    }
    // Capul, cu ochi și limbă care se mișcă.
    final h = unknownSnakePoint(head, 0);
    final next = unknownSnakePoint(head, 0.05);
    final dir = (h - next) / (h - next).distance;
    final side = Offset(-dir.dy, dir.dx);
    final tongue = 16 + 6 * sin(s.time * 9 + idx);
    canvas.drawLine(
      h + dir * 18,
      h + dir * (18 + tongue),
      Paint()
        ..color = const Color(0xFFE11D48)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(h, 22, Paint()..color = c1);
    for (final sgn in const [-1.0, 1.0]) {
      final e = h + dir * 6 + side * 10 * sgn;
      canvas.drawCircle(e, 7, Paint()..color = Colors.white);
      canvas.drawCircle(e + dir * 2, 3.5, Paint()..color = Colors.black);
    }
  }

  // ─── Pionii ──────────────────────────────────────────────────────────

  void _pawns(Canvas canvas) {
    final list = s.pawns.values.toList()
      ..sort((a, b) {
        if (a.id == s.activeId) return 1;
        if (b.id == s.activeId) return -1;
        return a.pos.dy.compareTo(b.pos.dy);
      });
    for (final p in list) {
      final ground = p.moving ? p.pos : s.restingPos(p);
      final color = unknownPlayerColors[p.colorIndex % unknownPlayerColors.length];
      final idleBob = p.id == s.activeId && !p.moving ? sin(s.time * 6).abs() * 8 : 0.0;
      final lift = p.lift + idleBob;
      final body = ground - Offset(0, 34 + lift);

      final shadowW = 44 - min(lift, 60) * 0.3;
      canvas.drawOval(Rect.fromCenter(center: ground + const Offset(0, 4), width: shadowW, height: shadowW * 0.35),
          Paint()..color = const Color(0x77000000));

      if (p.id == s.activeId) {
        final r = 38 + 6 * sin(s.time * 5);
        canvas.drawCircle(
          ground,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..color = color.withAlpha(220),
        );
      }
      final bodyPath = Path()
        ..moveTo(body.dx - 20, body.dy + 34)
        ..quadraticBezierTo(body.dx - 18, body.dy + 7, body.dx - 7, body.dy)
        ..lineTo(body.dx + 7, body.dy)
        ..quadraticBezierTo(body.dx + 18, body.dy + 7, body.dx + 20, body.dy + 34)
        ..close();
      canvas.drawPath(bodyPath, Paint()..color = Color.lerp(color, Colors.black, 0.25)!);
      canvas.drawCircle(body, 23, Paint()..color = Colors.white);
      canvas.drawCircle(
        body,
        20,
        Paint()..shader = ui.Gradient.radial(body - const Offset(6, 7), 28, [Color.lerp(color, Colors.white, 0.4)!, color]),
      );
      final tp = _text(p.initial, 20, Colors.white);
      tp.paint(canvas, body - Offset(tp.width / 2, tp.height / 2));
    }
  }

  // ─── Textele care zboară (+3 🪙, 🪜 Scara!) ────────────────────────────

  void _floaters(Canvas canvas) {
    for (final f in s.floaters) {
      final age = s.time - f.born;
      if (age < 0 || age > unknownFloaterLife) continue;
      final t = age / unknownFloaterLife;
      final alpha = t < 0.75 ? 1.0 : (1 - t) / 0.25;
      final pos = f.pos - Offset(0, 80 + 90 * Curves.easeOut.transform(t));
      final size = (f.big ? 44.0 : 32.0) * (t < 0.1 ? 0.6 + t / 0.1 * 0.4 : 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: f.text,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w900,
            color: f.color.withAlpha((255 * alpha).round()),
            shadows: [Shadow(color: Colors.black.withAlpha((220 * alpha).round()), blurRadius: 6, offset: const Offset(0, 3))],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) => oldDelegate.s != s;
}
