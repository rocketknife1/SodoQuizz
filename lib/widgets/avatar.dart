import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Avatarul jucătorului (poza reală, cu fallback pe o iconiță generică
/// dacă asset-ul lipsește) — folosit în header și în Profile.
///
/// Dacă [label] e dat (ex. inițiala unui alt jucător din multiplayer, care
/// n-are o poză reală disponibilă), arată un cerc colorat cu inițiala în loc
/// de poza locală a userului — comportamentul implicit rămâne neschimbat.
class Avatar extends StatelessWidget {
  final double size;
  final String? label;
  final Color? accentColor;
  const Avatar({super.key, this.size = 44, this.label, this.accentColor});

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.purple;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: size > 60 ? 3 : 2),
      ),
      clipBehavior: Clip.hardEdge,
      child: label != null
          ? Container(
              color: color.withAlpha(60),
              alignment: Alignment.center,
              child: Text(
                label!,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.4),
              ),
            )
          : Image.asset(
              userAvatarAsset,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: color.withAlpha(60),
                alignment: Alignment.center,
                child: Icon(Icons.person_rounded, color: Colors.white, size: size * 0.5),
              ),
            ),
    );
  }
}
