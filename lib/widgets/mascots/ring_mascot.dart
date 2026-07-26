import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/audio.dart';
import '../../core/theme.dart';
import '../../data/storage_service.dart';
import '../wheel_spin_dialog.dart';
import 'googly_eyes.dart';
import 'mascot_props.dart';
import 'mascot_sync.dart';

/// Opt gesturi unice: șase idle "de personalitate" (declanșate local,
/// aleatoriu, peste legănarea continuă de fundal) și două comune,
/// sincronizate prin [MascotSync] cu celelalte mascote de pe Home —
/// [checkClock] (toate trei deodată) și [askHow] (câte una, pe rând).
enum _RingGesture { spinBurst, bounce, colorFlash, squish, peekTilt, shiver, checkClock, askHow }

const _localGestures = [
  _RingGesture.spinBurst,
  _RingGesture.bounce,
  _RingGesture.colorFlash,
  _RingGesture.squish,
  _RingGesture.peekTilt,
  _RingGesture.shiver,
];

/// A doua mascotă decorativă, aceeași "specie" ca PaperclipMascot (ochi
/// jucăuși, personalitate proprie) dar cu alt corp — un inel cu margine
/// colorată, tip smart-ring — și o funcție reală: deschide Roata norocului
/// (vezi [WheelSpinDialog]), o dată la 24h. Când nu e disponibil spin-ul,
/// tap-ul face doar reacția decorativă + arată timpul rămas.
class RingMascot extends StatefulWidget {
  final VoidCallback? onRewardsChanged;

  const RingMascot({super.key, this.onRewardsChanged});

  @override
  State<RingMascot> createState() => _RingMascotState();
}

class _RingMascotState extends State<RingMascot> with TickerProviderStateMixin {
  late final AnimationController _idle;
  late final AnimationController _excite;
  late final AnimationController _gesture;
  bool _excited = false;
  bool _ready = false;
  bool _checked = false;
  _RingGesture? _currentGesture;
  String? _speechText;
  Timer? _gestureTimer;
  StreamSubscription<MascotEvent>? _syncSub;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _excite = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
    _gesture = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _refreshReady();
    _scheduleGesture();
    MascotSync.ensureStarted();
    _syncSub = MascotSync.events.listen(_onSyncEvent);
  }

  void _onSyncEvent(MascotEvent event) {
    if (!mounted || _gesture.isAnimating) return;
    if (event.type == MascotEventType.checkClock) {
      _gestureTimer?.cancel();
      _playGesture(_RingGesture.checkClock);
    } else if (event.type == MascotEventType.greet && event.target == MascotId.ring) {
      _gestureTimer?.cancel();
      _playGesture(_RingGesture.askHow, message: event.message);
    }
  }

  void _scheduleGesture() {
    _gestureTimer = Timer(Duration(milliseconds: 4600 + _random.nextInt(3800)), () {
      if (!mounted) return;
      var next = _localGestures[_random.nextInt(_localGestures.length)];
      while (next == _currentGesture && _localGestures.length > 1) {
        next = _localGestures[_random.nextInt(_localGestures.length)];
      }
      _playGesture(next);
    });
  }

  void _playGesture(_RingGesture gesture, {String? message}) {
    setState(() {
      _currentGesture = gesture;
      _speechText = message;
    });
    _gesture.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _currentGesture = null;
        _speechText = null;
      });
      _scheduleGesture();
    });
  }

  Future<void> _refreshReady() async {
    final ready = await StorageService.canSpinRing();
    if (!mounted) return;
    setState(() {
      _ready = ready;
      _checked = true;
    });
  }

  @override
  void dispose() {
    _gestureTimer?.cancel();
    _syncSub?.cancel();
    _idle.dispose();
    _excite.dispose();
    _gesture.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_excite.isAnimating) return;
    if (_ready) {
      Sfx.rewardPop();
      setState(() => _excited = true);
      await _excite.forward(from: 0);
      if (mounted) setState(() => _excited = false);
      if (!mounted) return;
      await WheelSpinDialog.show(context);
      widget.onRewardsChanged?.call();
      await _refreshReady();
      return;
    }

    Sfx.tileSelect();
    setState(() => _excited = true);
    _excite.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _excited = false);
    });
    if (_checked) {
      final remaining = await StorageService.ringSpinTimeRemaining();
      if (!mounted) return;
      final h = remaining.inHours;
      final m = remaining.inMinutes % 60;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Roata norocului revine în ${h}h ${m}min')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: SizedBox(
        width: 78,
        height: 78,
        child: AnimatedBuilder(
          animation: Listenable.merge([_idle, _excite, _gesture]),
          builder: (context, _) {
            final pulse = (sin(_idle.value * 2 * pi) + 1) / 2;
            final tilt = sin(_idle.value * 2 * pi * 0.5) * 0.07;
            final rimSpin = _idle.value * 2 * pi;
            final ripple = _excite.value;
            final exciteScale = _excited ? (1 - ripple) * 0.22 : 0.0;

            var gestureDx = 0.0;
            var gestureDy = 0.0;
            var gestureAngle = 0.0;
            var gestureScaleX = 1.0;
            var gestureScaleY = 1.0;
            var extraSpin = 0.0;
            var flash = 0.0;
            if (_currentGesture != null) {
              final g = _gesture.value;
              switch (_currentGesture!) {
                case _RingGesture.spinBurst:
                  // un tur rapid suplimentar, peste rotația continuă a rama.
                  extraSpin = g * 4 * pi;
                  break;
                case _RingGesture.bounce:
                  gestureDy = -sin(g * pi * 2).abs() * 14;
                  break;
                case _RingGesture.colorFlash:
                  // rama se aprinde scurt, ca un semnal luminos.
                  flash = sin(g * pi);
                  break;
                case _RingGesture.squish:
                  gestureScaleX = 1 + sin(g * pi) * 0.22;
                  gestureScaleY = 1 - sin(g * pi) * 0.18;
                  break;
                case _RingGesture.peekTilt:
                  gestureAngle = sin(g * pi) * 0.5;
                  gestureDx = sin(g * pi) * 10;
                  break;
                case _RingGesture.shiver:
                  gestureDx = sin(g * pi * 11) * 4 * (1 - g);
                  break;
                case _RingGesture.checkClock:
                  gestureAngle = sin(g * pi) * -0.14;
                  gestureDy = sin(g * pi) * 3;
                  break;
                case _RingGesture.askHow:
                  gestureDy = -sin(g * pi * 3) * 4 * (1 - g * 0.6);
                  break;
              }
            }

            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: (_ready ? 0.22 + pulse * 0.28 : 0.1 + pulse * 0.1).clamp(0.0, 1.0),
                  child: Container(
                    width: 60 + pulse * 14,
                    height: 60 + pulse * 14,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: _ready ? const Color(0xFFFFC542) : const Color(0xFF534AB7)),
                  ),
                ),
                if (ripple > 0)
                  Opacity(
                    opacity: (1 - ripple).clamp(0.0, 1.0),
                    child: Container(
                      width: 48 + ripple * 46,
                      height: 48 + ripple * 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                if (_currentGesture == _RingGesture.checkClock)
                  Positioned(bottom: -4, right: 4, child: ClockProp(t: _gesture.value)),
                if (_currentGesture == _RingGesture.askHow && _speechText != null)
                  Positioned(top: -26, child: MascotBubble(text: _speechText!, color: AppColors.purple, t: _gesture.value)),
                Transform.translate(
                  offset: Offset(gestureDx, gestureDy),
                  child: Transform.rotate(
                    angle: tilt + gestureAngle,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..scale(gestureScaleX, gestureScaleY),
                      child: Transform.scale(
                        scale: 1 + exciteScale,
                        child: CustomPaint(
                          size: const Size(56, 56),
                          painter: _RingPainter(rimAngle: rimSpin + extraSpin, dimmed: !_ready, flash: flash),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_ready)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE24B4A),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF1A1A2E), width: 2),
                      ),
                    ),
                  ),
                Positioned(top: 22, child: GooglyEyes(size: 8, excited: _excited)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double rimAngle;
  final bool dimmed;
  final double flash;
  const _RingPainter({required this.rimAngle, required this.dimmed, this.flash = 0});

  static const _rimColors = [
    Color(0xFF534AB7),
    Color(0xFF1D9E75),
    Color(0xFFFFC542),
    Color(0xFFFF7A1A),
    Color(0xFFE24B4A),
    Color(0xFF534AB7),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;

    var colors = dimmed ? _rimColors.map((c) => c.withAlpha(90)).toList() : _rimColors;
    if (flash > 0) {
      colors = colors.map((c) => Color.lerp(c, Colors.white, flash * 0.65)!).toList();
    }

    if (flash > 0) {
      canvas.drawCircle(
        center,
        radius + 6 * flash,
        Paint()..color = Colors.white.withAlpha((flash * 90).round()),
      );
    }

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..shader = SweepGradient(colors: colors, transform: GradientRotation(rimAngle)).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, rim);

    final core = Paint()..color = const Color(0xFF15152A);
    canvas.drawCircle(center, radius - 5.5, core);

    final shine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withAlpha(60);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius - 5.5), -2.6, 1.0, false, shine);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.rimAngle != rimAngle || oldDelegate.dimmed != dimmed || oldDelegate.flash != flash;
}
