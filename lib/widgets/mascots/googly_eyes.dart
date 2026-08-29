import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// Doi ochi jucăuși (cerc alb + pupilă neagră) care își mută privirea din
/// când în când, aleatoriu — folosiți de mascotele decorative de pe Home
/// (agrafa, inelul). [excited] îi mărește temporar, ca reacție la tap.
class GooglyEyes extends StatefulWidget {
  final double size;
  final bool excited;

  const GooglyEyes({super.key, this.size = 9, this.excited = false});

  @override
  State<GooglyEyes> createState() => _GooglyEyesState();
}

class _GooglyEyesState extends State<GooglyEyes> {
  Offset _pupil = Offset.zero;
  Timer? _lookTimer;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _scheduleLook();
  }

  void _scheduleLook() {
    _lookTimer = Timer(Duration(milliseconds: 1400 + _random.nextInt(2200)), () {
      if (!mounted) return;
      final angle = _random.nextDouble() * 2 * pi;
      final dist = _random.nextDouble() * 0.5;
      setState(() => _pupil = Offset(cos(angle) * dist, sin(angle) * dist));
      _scheduleLook();
    });
  }

  @override
  void dispose() {
    _lookTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eyeSize = widget.size * (widget.excited ? 1.3 : 1.0);
    return AnimatedScale(
      scale: widget.excited ? 1.3 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _eye(eyeSize),
          SizedBox(width: eyeSize * 0.4),
          _eye(eyeSize),
        ],
      ),
    );
  }

  Widget _eye(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Align(
        alignment: Alignment(_pupil.dx, widget.excited ? -0.3 : _pupil.dy),
        child: Container(
          width: size * 0.5,
          height: size * 0.5,
          margin: EdgeInsets.all(size * 0.1),
          decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
