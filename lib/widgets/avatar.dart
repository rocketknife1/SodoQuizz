import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Avatarul jucătorului (poza reală, cu fallback pe o iconiță generică
/// dacă asset-ul lipsește) — folosit în header și în Profile.
class Avatar extends StatelessWidget {
  final double size;
  const Avatar({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.purple, width: size > 60 ? 3 : 2),
      ),
      clipBehavior: Clip.hardEdge,
      child: Image.asset(
        userAvatarAsset,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: AppColors.purple.withAlpha(60),
          alignment: Alignment.center,
          child: Icon(Icons.person_rounded, color: Colors.white, size: size * 0.5),
        ),
      ),
    );
  }
}
