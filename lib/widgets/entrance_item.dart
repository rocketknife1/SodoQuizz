import 'package:flutter/material.dart';

/// Fade + alunecare (de jos, sau lateral pentru [slideFrom]) + un mic
/// „supra-arc" la final — decupată dintr-un [AnimationController] comun
/// printr-un [Interval], așa apar elementele unui ecran în cascadă, nu toate
/// deodată. Refolosit pe toate ecranele din Multiplayer, ca intrarea să
/// simtă la fel peste tot (meniu, lobby, meci).
class EntranceItem extends StatelessWidget {
  final AnimationController controller;
  final Interval interval;
  final Widget child;
  /// -1 = alunecă din stânga, 1 = din dreapta, 0 (implicit) = de jos în sus.
  final double slideFrom;

  const EntranceItem({super.key, required this.controller, required this.interval, required this.child, this.slideFrom = 0});

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(parent: controller, curve: interval);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final t = anim.value;
        final fade = t.clamp(0.0, 1.0);
        final dx = slideFrom == 0 ? 0.0 : (1 - t) * 60 * slideFrom;
        final dy = slideFrom == 0 ? (1 - fade) * 24 : 0.0;
        return Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(dx, dy),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
