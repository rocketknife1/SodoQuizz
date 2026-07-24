import 'dart:math';
import 'package:flutter/material.dart';

/// O categorie de joc reprezentată ca "planetă" — un orb cu gradient
/// radial în culoarea categoriei, un inel subțire (tip Saturn) și
/// iconița modului deasupra, plus titlu/subtitlu/progres dedesubt.
/// Înlocuiește vechiul [MenuTile] pătrat, păstrând aceeași logică de
/// tap/locked/progress/wood-banner — doar reprezentarea vizuală diferă.
class PlanetTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool locked;

  /// Text gravat pe o placă de lemn peste tile — pentru gamemoduri
  /// jucabile dar încă în lucru (ex. "ÎN CONSTRUCȚIE"), spre deosebire de
  /// [locked] care blochează complet tap-ul.
  final String? woodBanner;

  /// Progres de "măiestrie" (0..1) — procent din întrebările categoriei
  /// deja răspunse corect vreodată. Dacă e null, nu se arată bara/rangul.
  final double? progress;
  final String? rankLabel;

  const PlanetTile({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
    this.subtitle,
    this.locked = false,
    this.woodBanner,
    this.progress,
    this.rankLabel,
  });

  Color get _rim => locked ? Colors.white24 : _shade(color, -0.22);

  static Color _shade(Color c, double dl) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + dl).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (!locked)
                  Transform.rotate(
                    angle: -0.32,
                    child: FractionallySizedBox(
                      widthFactor: 1.5,
                      heightFactor: 0.5,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: color.withAlpha(110), width: 2),
                        ),
                      ),
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.35, -0.35),
                      radius: 0.95,
                      colors: locked
                          ? [Colors.white.withAlpha(45), Colors.white.withAlpha(25), Colors.white.withAlpha(10)]
                          : [_shade(color, 0.22), color, _shade(color, -0.28)],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                    border: Border.all(color: _rim, width: 1.5),
                    boxShadow: locked
                        ? null
                        : [BoxShadow(color: color.withAlpha(120), blurRadius: 18, spreadRadius: 1)],
                  ),
                  child: FractionallySizedBox(
                    widthFactor: 0.62,
                    heightFactor: 0.62,
                    child: Center(
                      child: Icon(
                        locked ? Icons.lock_rounded : icon,
                        color: Colors.white.withAlpha(locked ? 150 : 255),
                        size: 26,
                      ),
                    ),
                  ),
                ),
                if (woodBanner != null) _WoodBanner(text: woodBanner!),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withAlpha(locked ? 180 : 255),
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: Colors.white.withAlpha(35),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            if (rankLabel != null) ...[
              const SizedBox(height: 3),
              Text(rankLabel!, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ],
        ],
      ),
    );
  }
}

/// Placă de lemn peste planetă, ușor înclinată, cu textură desenată
/// (fibre + noduri), nituri în colțuri și text gravat — stil semn de
/// șantier "under construction". Portat neschimbat din vechiul MenuTile.
class _WoodBanner extends StatelessWidget {
  final String text;
  const _WoodBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      child: Transform.rotate(
        angle: -0.15,
        child: Container(
          width: 110,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF3E2712), width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(110), blurRadius: 6, offset: const Offset(0, 3))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(child: CustomPaint(painter: _WoodGrainPainter())),
              const Positioned(top: 3, left: 4, child: _Bolt()),
              const Positioned(top: 3, right: 4, child: _Bolt()),
              const Positioned(bottom: 3, left: 4, child: _Bolt()),
              const Positioned(bottom: 3, right: 4, child: _Bolt()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFEAD1A3),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    letterSpacing: 0.3,
                    shadows: [
                      Shadow(color: Color(0xFF2B1A0C), offset: Offset(1, 1)),
                      Shadow(color: Color(0x66FFE9C4), offset: Offset(-0.6, -0.6)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bolt extends StatelessWidget {
  const _Bolt();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5.5,
      height: 5.5,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2A2A2A),
        border: Border.all(color: Colors.black45, width: 0.6),
        boxShadow: const [BoxShadow(color: Colors.white30, blurRadius: 1, offset: Offset(-0.5, -0.5))],
      ),
    );
  }
}

/// Desenează fibra de lemn: gradient de bază + linii ondulate ca niște
/// striații, plus 2 noduri — determinist (seed fix), deci nu se
/// re-randomizează la fiecare rebuild.
class _WoodGrainPainter extends CustomPainter {
  const _WoodGrainPainter();

  static const _top = Color(0xFFB07A46);
  static const _bottom = Color(0xFF5A3A1B);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_top, _bottom],
        ).createShader(rect),
    );

    final rnd = Random(42);
    for (var i = 0; i < 14; i++) {
      final y0 = rnd.nextDouble() * size.height;
      final amp = 1.0 + rnd.nextDouble() * 3.5;
      final freq = 0.05 + rnd.nextDouble() * 0.12;
      final phase = rnd.nextDouble() * pi * 2;
      final shade = (rnd.nextDouble() - 0.5) * 60;
      final base = y0 < size.height / 2 ? _top : _bottom;
      final col = Color.fromARGB(
        90,
        (base.r * 255 + shade).clamp(0, 255).round(),
        (base.g * 255 + shade).clamp(0, 255).round(),
        (base.b * 255 + shade).clamp(0, 255).round(),
      );
      final path = Path();
      for (double x = 0; x <= size.width; x += 4) {
        final y = y0 + sin(x * freq + phase) * amp;
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 1.0);
    }

    final edgePaint = Paint()..color = Colors.black.withAlpha(70);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 2), edgePaint);
    canvas.drawRect(Rect.fromLTWH(0, size.height - 2, size.width, 2), edgePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
