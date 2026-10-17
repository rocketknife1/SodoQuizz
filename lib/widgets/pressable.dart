import 'package:flutter/material.dart';

import '../core/haptics.dart';

/// Orice element apăsabil care se „strânge" ușor sub deget și revine —
/// feedback tactil vizual, nu doar o culoare care se schimbă. Extras ca
/// widget separat fiindcă exact același gest e folosit acum pe plăcile din
/// Multiplayer, pe cardurile de categorie și pe rândurile din Setări.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// Cât de mult se strânge la apăsare. Implicit discret — un card mare are
  /// nevoie de mai puțin decât un buton mic ca să se simtă la fel.
  final double scale;

  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.97});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    // fără strângere dacă telefonul are animațiile reduse
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final onTap = widget.onTap;
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              Haptics.tap();
              onTap();
            },
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down && !still ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Un număr care „numără” până la valoarea nouă când se schimbă (monedele
/// cresc sub ochii tăi după o rundă). La prima afișare apare direct, fără
/// animație — altfel fiecare întoarcere pe ecran ar număra de la zero.
class CountUpText extends StatelessWidget {
  const CountUpText(this.value, {super.key, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: value.toDouble(), end: value.toDouble()),
      duration: still ? Duration.zero : const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        '${v.round()}',
        // cifrele egale ca lățime: numărul nu „tremură” cât numără
        style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}
