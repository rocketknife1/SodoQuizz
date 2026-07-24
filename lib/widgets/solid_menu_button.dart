import 'package:flutter/material.dart';

/// Buton mare, solid, cu iconiță într-un cerc alb-transparent fixat la
/// marginea stângă și eticheta imediat după — încadrare left-aligned,
/// nu centrată ca un bloc (stilul de meniu tip "quiz app" din referință).
class SolidMenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final String? badge;
  final bool big;

  const SolidMenuButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
    this.big = false,
  });

  static Color _lighten(Color c, double dl) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + dl).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: big ? 18 : 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_lighten(color, 0.08), color],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: color.withAlpha(110), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withAlpha(50), shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: big ? 24 : 20),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: big ? 19 : 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.black.withAlpha(70), borderRadius: BorderRadius.circular(20)),
                child: Text(badge!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }
}
