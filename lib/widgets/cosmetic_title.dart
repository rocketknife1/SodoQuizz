import 'package:flutter/material.dart';

import '../core/cosmetics.dart';
import '../core/lang.dart';

/// Titlul cosmetic al unui jucător - un rand mic sub nume, oriunde apare
/// numele (profil, clasament, meci, prieteni). Gol pentru `novice` (titlul
/// implicit n-are ce arata).
class CosmeticTitle extends StatelessWidget {
  final String titleId;
  final double fontSize;
  final TextAlign align;

  const CosmeticTitle({
    super.key,
    required this.titleId,
    this.fontSize = 11,
    this.align = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final t = titleFromId(titleId);
    if (t == PlayerTitle.novice) return const SizedBox.shrink();
    final (ro, en) = titleLabel(t);
    return Text(
      tr(ro, en),
      textAlign: align,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white.withAlpha(150),
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }
}
