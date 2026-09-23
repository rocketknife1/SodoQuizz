import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/lang.dart';

/// Cât rămâne răspunsul pe ecran înainte de trecerea automată. La corect
/// ajunge cât să vezi poza clară și verdele; la greșit e mai mult, fiindcă
/// atunci chiar ai ce învăța din varianta bună.
const Duration autoAdvanceAfterCorrect = Duration(milliseconds: 1200);
const Duration autoAdvanceAfterWrong = Duration(milliseconds: 2500);

/// Bara subțire care se umple până la trecerea automată la întrebarea
/// următoare — arată că jocul merge singur mai departe și că un tap grăbește
/// trecerea. Cheia trebuie să se schimbe la fiecare întrebare, ca bara să
/// pornească de la zero.
class AutoAdvanceBar extends StatelessWidget {
  final Duration duration;
  final bool correct;
  const AutoAdvanceBar({super.key, required this.duration, required this.correct});

  @override
  Widget build(BuildContext context) {
    final color = correct ? const Color(0xFF1D9E75) : const Color(0xFFE24B4A);
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: duration,
          builder: (context, v, _) => ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 4,
              backgroundColor: Colors.white.withAlpha(20),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tr('Atinge ca să treci mai departe', 'Tap to continue'),
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }
}

class NextButton extends StatelessWidget {
  final VoidCallback onTap;
  const NextButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Sfx.next();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1D9E75),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1D9E75).withAlpha((0.35 * 255).round()),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          tr('Următoarea întrebare →', 'Next question →'),
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
