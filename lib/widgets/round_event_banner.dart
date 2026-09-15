import 'package:flutter/material.dart';

import '../core/lang.dart';
import '../core/powerups.dart';
import '../core/theme.dart';

/// Banda care anunță evenimentul rundei — aceeași în TOATE modurile
/// multiplayer, ca jucătorul să învețe o singură dată unde să se uite după
/// „ce e special runda asta".
///
/// Nu primește niciun `matchId`/`roundIndex`: evenimentul e calculat de
/// ecranul modului (vezi core/powerups.dart `roundEventFor`) și dat aici
/// gata ales. Așa widget-ul rămâne pur decorativ — aceeași graniță pe care
/// restul proiectului o ține între ecrane (UI+date) și widget-uri (doar
/// randare).
///
/// Se ascunde singură la [RoundEvent.none], deci apelantul o poate pune
/// necondiționat în arbore, fără `if` la fiecare loc de folosire.
class RoundEventBanner extends StatelessWidget {
  final RoundEvent event;

  /// Compactă = o singură linie, pentru ecranele care au deja bara de sus
  /// plină (Quizz Tanks, Scaunul Electric). Altfel titlu + explicație.
  final bool compact;

  const RoundEventBanner({super.key, required this.event, this.compact = false});

  @override
  Widget build(BuildContext context) {
    // AnimatedSwitcher, cheiat pe eveniment: banner-ul intră cu un mic
    // scale+fade în loc să apară brusc — cerința de „polish/aspect" din
    // trecerea a doua, aplicată o singură dată aici, deci se vede automat
    // în toate cele 5 moduri care folosesc widget-ul.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(anim), child: child),
      ),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (event == RoundEvent.none) return const SizedBox.shrink(key: ValueKey('none'));
    final title = roundEventTitles[event];
    final desc = roundEventDescriptions[event];
    if (title == null) return const SizedBox.shrink(key: ValueKey('none'));
    final color = _colorFor(event);

    return Padding(
      key: ValueKey(event),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 6 : 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withAlpha(70), color.withAlpha(28)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(170), width: 1.3),
        ),
        child: compact
            ? Text(
                tr(title.$1, title.$2),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr(title.$1, title.$2),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900),
                  ),
                  if (desc != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      tr(desc.$1, desc.$2),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  /// Culoarea urmează SENSUL evenimentului, nu modul: verde = ceva bun
  /// pentru toți, roșu = ceva periculos, portocaliu = mai mult/mai tare,
  /// mov = ceva ciudat. Fără asta, un banner roșu de „reparații" ar fi
  /// citit ca o amenințare.
  static Color _colorFor(RoundEvent e) => switch (e) {
        RoundEvent.fieldRepairs || RoundEvent.groundedFuse || RoundEvent.powerUpRain => AppColors.play,
        RoundEvent.suddenDeath || RoundEvent.overcharge || RoundEvent.asteroidStorm => AppColors.danger,
        RoundEvent.doubleOrNothing || RoundEvent.heavyShells => AppColors.orange,
        RoundEvent.battleFog || RoundEvent.lowGravity => AppColors.purple,
        RoundEvent.none => Colors.transparent,
      };
}
