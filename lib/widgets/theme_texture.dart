import 'dart:math';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/theme.dart';

/// Textura discretă a temei active, întinsă peste TOT ecranul (sub tot ce e
/// interactiv, `IgnorePointer`). Montată o singură dată, în `main.dart`, în
/// `builder`-ul lui `MaterialApp` — la fel ca umbra Modului Eco.
///
/// E deliberat statică (fără animație): un `CustomPaint` care se repictează
/// la fiecare cadru ar ține aplicația trează exact ca buclele pe care Modul
/// Eco le oprește. Textura dă „materialul" temei; mișcarea o dau widgeturile
/// din ecran.
class ThemeTextureOverlay extends StatelessWidget {
  const ThemeTextureOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.palette;
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _ThemeTexturePainter(palette),
          isComplex: true,
          willChange: false,
        ),
      ),
    );
  }
}

class _ThemeTexturePainter extends CustomPainter {
  final AppPalette palette;
  const _ThemeTexturePainter(this.palette);

  @override
  void paint(Canvas canvas, Size size) {
    switch (palette.texture) {
      case ThemeTexture.blobs:
        _blobs(canvas, size);
      case ThemeTexture.scanlines:
        _scanlines(canvas, size);
      case ThemeTexture.filigree:
        _filigree(canvas, size);
      case ThemeTexture.dotGrid:
        _dotGrid(canvas, size);
      case ThemeTexture.aurora:
        _aurora(canvas, size);
      case ThemeTexture.embers:
        _embers(canvas, size);
    }
  }

  // ── Splasshy: pete mari de cerneală difuză ──────────────────────────────
  void _blobs(Canvas canvas, Size size) {
    final rnd = Random(7);
    final tints = [palette.purple, palette.teal, palette.blue, palette.play];
    for (var i = 0; i < 5; i++) {
      final c = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final r = size.shortestSide * (0.28 + rnd.nextDouble() * 0.35);
      final tint = tints[i % tints.length];
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [tint.withValues(alpha: 0.10), tint.withValues(alpha: 0.0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
  }

  // ── Neon Arcade: scanline-uri + grilă slabă ─────────────────────────────
  void _scanlines(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final grid = Paint()
      ..color = palette.blue.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
  }

  // ── Obsidian: filigran subțire în colțuri ──────────────────────────────
  void _filigree(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = palette.coin.withValues(alpha: 0.07);
    void corner(Offset o, double sx, double sy) {
      for (var k = 1; k <= 4; k++) {
        final path = Path()..moveTo(o.dx, o.dy + sy * 26.0 * k);
        path.quadraticBezierTo(
          o.dx + sx * 22.0 * k, o.dy + sy * 14.0 * k,
          o.dx + sx * 30.0 * k, o.dy - sy * 6.0 * k,
        );
        path.quadraticBezierTo(
          o.dx + sx * 40.0 * k, o.dy - sy * 26.0 * k,
          o.dx + sx * 64.0 * k, o.dy - sy * 20.0 * k,
        );
        canvas.drawPath(path, p);
      }
    }
    corner(const Offset(0, 0), 1, 1);
    corner(Offset(size.width, 0), -1, 1);
    corner(Offset(0, size.height), 1, -1);
    corner(Offset(size.width, size.height), -1, -1);
  }

  // ── Paper: grilă fină de puncte de cerneală ────────────────────────────
  void _dotGrid(Canvas canvas, Size size) {
    final dot = Paint()..color = const Color(0xFF2A2620).withValues(alpha: 0.06);
    for (double y = 12; y < size.height; y += 22) {
      for (double x = 12; x < size.width; x += 22) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
  }

  // ── Aurora: benzi diagonale moi ───────────────────────────────────────
  void _aurora(Canvas canvas, Size size) {
    final bands = [palette.play, palette.blue, palette.purple];
    for (var i = 0; i < bands.length; i++) {
      final t = (i + 1) / (bands.length + 1);
      final rect = Rect.fromLTWH(0, size.height * (t - 0.28), size.width, size.height * 0.5);
      canvas.save();
      canvas.translate(0, size.height * (i.isEven ? -0.04 : 0.04));
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              bands[i].withValues(alpha: 0.0),
              bands[i].withValues(alpha: 0.12),
              bands[i].withValues(alpha: 0.0),
            ],
          ).createShader(rect),
      );
      canvas.restore();
    }
  }

  // ── Ember Dusk: scântei calde împrăștiate ──────────────────────────────
  void _embers(Canvas canvas, Size size) {
    final rnd = Random(11);
    final tints = [palette.orange, palette.coin, palette.life];
    for (var i = 0; i < 90; i++) {
      final o = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final r = 0.6 + rnd.nextDouble() * 2.2;
      final tint = tints[i % tints.length];
      canvas.drawCircle(o, r, Paint()..color = tint.withValues(alpha: 0.10 + rnd.nextDouble() * 0.10));
    }
  }

  @override
  bool shouldRepaint(_ThemeTexturePainter old) => old.palette.id != palette.id;
}

/// Fundal complet al unui ecran = gradientul temei + textura ei, într-un
/// singur widget. Ecranele noi îl pot folosi în loc să repete
/// `Container(decoration: BoxDecoration(gradient: AppColors.bgGradient))`.
class ThemedBackground extends StatelessWidget {
  final Widget child;
  final bool space;
  const ThemedBackground({super.key, required this.child, this.space = false});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: space ? AppColors.spaceGradient : AppColors.bgGradient,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [const ThemeTextureOverlay(), child],
      ),
    );
  }
}
