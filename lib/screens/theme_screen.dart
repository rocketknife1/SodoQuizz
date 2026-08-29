import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../widgets/pressable.dart';

/// Alegerea temei vizuale. Fiecare card e o previzualizare mică a paletei;
/// la atingere se aplică imediat — `MaterialApp` se reconstruiește (cheie
/// nouă, ca la limbă) și jocul reapare în tema nouă, din meniul principal.
class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final current = AppTheme.id.value;
    return Scaffold(
      backgroundColor: AppColors.bg,
      // Fără textură proprie aici: overlay-ul global (main.dart `_withThemeChrome`)
      // o pune deja peste tot ecranul.
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 2),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_rounded, color: AppColors.isLight ? Colors.black87 : Colors.white),
                    ),
                    Text(
                      tr('Temă', 'Theme'),
                      style: TextStyle(
                        color: AppColors.isLight ? Colors.black87 : Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                child: Text(
                  tr('Schimbă doar cum arată jocul — culori și textură. Nu atinge progresul.',
                      'Only changes how the game looks — colors and texture. Your progress is untouched.'),
                  style: TextStyle(color: AppColors.isLight ? Colors.black54 : Colors.white54, fontSize: 12.5, height: 1.35),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: kAppPalettes.length,
                  itemBuilder: (context, i) {
                    final p = kAppPalettes[i];
                    return _ThemeCard(
                      palette: p,
                      selected: p.id == current,
                      onTap: () async {
                        if (p.id == current) return;
                        await AppTheme.set(p.id);
                        // MaterialApp are cheie nouă acum → tot ce era pe
                        // stivă dispare, jocul reapare din meniu în tema nouă.
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeCard({required this.palette, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final onCard = AppColors.isLight ? Colors.black87 : Colors.white;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? palette.play : (AppColors.isLight ? Colors.black12 : Colors.white12),
            width: selected ? 2.4 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: palette.play.withValues(alpha: 0.35), blurRadius: 20, spreadRadius: -6)]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _MiniPreview(palette)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(palette.nameRo, palette.nameEn),
                      style: TextStyle(color: onCard, fontWeight: FontWeight.w800, fontSize: 13.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded, color: palette.play, size: 18)
                  else
                    Icon(Icons.circle_outlined, color: onCard.withValues(alpha: 0.25), size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Machetă în miniatură a unui ecran în paleta dată: fundal + textură +
/// câteva pastile de accent + un card + „moneda".
class _MiniPreview extends StatelessWidget {
  final AppPalette palette;
  const _MiniPreview(this.palette);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: palette.spaceGradient),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _MiniTexturePainter(palette)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _dot(palette.coin),
                    const SizedBox(width: 5),
                    _dot(palette.life),
                    const SizedBox(width: 5),
                    _dot(palette.gem),
                    const Spacer(),
                    _dot(palette.purple),
                  ],
                ),
                const Spacer(),
                _pill(palette.play, 1),
                const SizedBox(height: 6),
                _pill(palette.blue, 0.78),
                const SizedBox(height: 6),
                _pill(palette.orange, 0.6),
                const SizedBox(height: 10),
                Container(
                  height: 22,
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: (palette.isLight ? Colors.black : Colors.white).withValues(alpha: 0.10)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  Widget _pill(Color c, double widthFactor) => FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: Container(
          height: 13,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(7)),
        ),
      );
}

/// Versiune redusă a texturii, doar pentru card (fără să monteze overlay-ul
/// global).
class _MiniTexturePainter extends CustomPainter {
  final AppPalette palette;
  const _MiniTexturePainter(this.palette);

  @override
  void paint(Canvas canvas, Size size) {
    switch (palette.texture) {
      case ThemeTexture.scanlines:
        final line = Paint()..color = Colors.black.withValues(alpha: 0.16)..strokeWidth = 1;
        for (double y = 0; y < size.height; y += 3) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
      case ThemeTexture.dotGrid:
        final dot = Paint()..color = const Color(0xFF2A2620).withValues(alpha: 0.10);
        for (double y = 6; y < size.height; y += 12) {
          for (double x = 6; x < size.width; x += 12) {
            canvas.drawCircle(Offset(x, y), 0.9, dot);
          }
        }
      case ThemeTexture.blobs:
        for (final (i, c) in [palette.purple, palette.teal, palette.blue].indexed) {
          final ctr = Offset(size.width * (0.2 + i * 0.35), size.height * (0.3 + i * 0.2));
          canvas.drawCircle(
            ctr,
            size.shortestSide * 0.6,
            Paint()
              ..shader = RadialGradient(colors: [c.withValues(alpha: 0.14), c.withValues(alpha: 0)])
                  .createShader(Rect.fromCircle(center: ctr, radius: size.shortestSide * 0.6)),
          );
        }
      case ThemeTexture.aurora:
        for (final (i, c) in [palette.play, palette.blue, palette.purple].indexed) {
          final rect = Rect.fromLTWH(0, size.height * (0.15 + i * 0.25), size.width, size.height * 0.35);
          canvas.drawRect(
            rect,
            Paint()
              ..shader = LinearGradient(
                colors: [c.withValues(alpha: 0), c.withValues(alpha: 0.16), c.withValues(alpha: 0)],
              ).createShader(rect),
          );
        }
      case ThemeTexture.embers:
        for (var i = 0; i < 24; i++) {
          final o = Offset((i * 37 % size.width.toInt()).toDouble(), (i * 53 % size.height.toInt()).toDouble());
          canvas.drawCircle(o, 1.1, Paint()..color = palette.orange.withValues(alpha: 0.16));
        }
      case ThemeTexture.filigree:
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = palette.coin.withValues(alpha: 0.12);
        for (var k = 1; k <= 3; k++) {
          canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: 12.0 * k), 0, 1.6, false, p);
          canvas.drawArc(Rect.fromCircle(center: Offset(size.width, size.height), radius: 12.0 * k), 3.14, 1.6, false, p);
        }
    }
  }

  @override
  bool shouldRepaint(_MiniTexturePainter old) => old.palette.id != palette.id;
}
