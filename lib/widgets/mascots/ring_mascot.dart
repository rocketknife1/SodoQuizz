import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/audio.dart';
import '../../core/lang.dart';
import '../../core/eco_mode.dart';
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
  late final AnimationController _speech;
  bool _excited = false;
  bool _ready = false;
  bool _checked = false;
  _RingGesture? _currentGesture;
  String? _speechText;
  Timer? _gestureTimer;
  Timer? _countdownTicker;
  Duration? _remaining;
  StreamSubscription<MascotEvent>? _syncSub;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _idle = EcoAnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _excite = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
    _gesture = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _speech = AnimationController(vsync: this, duration: const Duration(milliseconds: 3800));
    _refreshReady();
    _scheduleGesture();
    MascotSync.ensureStarted();
    _syncSub = MascotSync.events.listen(_onSyncEvent);
  }

  void _onSyncEvent(MascotEvent event) {
    if (!mounted || _gesture.isAnimating || _speech.isAnimating) return;
    if (event.type == MascotEventType.checkClock) {
      _gestureTimer?.cancel();
      _playGesture(_RingGesture.checkClock);
    } else if (event.type == MascotEventType.greet && event.target == MascotId.ring) {
      _gestureTimer?.cancel();
      _playSpeech(event.message!);
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

  /// La fel ca [_playGesture], dar pentru replici ("askHow") — controller
  /// separat de [_gesture], cu durată calculată din lungimea mesajului
  /// (vezi [greetDisplayDuration]), ca textul să apuce să fie citit.
  void _playSpeech(String message) {
    _speech.duration = greetDisplayDuration(message);
    setState(() {
      _currentGesture = _RingGesture.askHow;
      _speechText = message;
    });
    _speech.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _currentGesture = null;
        _speechText = null;
      });
      _scheduleGesture();
    });
  }

  /// Verifică disponibilitatea și pornește/oprește numărătoarea inversă
  /// afișată permanent sub mascotă (vezi [_buildLabel]) — nu mai depinde de
  /// un tap ca să afle cât a mai rămas, se vede tot timpul.
  Future<void> _refreshReady() async {
    final ready = await StorageService.canSpinRing();
    if (!mounted) return;
    setState(() {
      _ready = ready;
      _checked = true;
    });
    _countdownTicker?.cancel();
    if (ready) {
      setState(() => _remaining = null);
      return;
    }
    final remaining = await StorageService.ringSpinTimeRemaining();
    if (!mounted) return;
    setState(() => _remaining = remaining);
    _startCountdown();
  }

  /// Decrementează local, din secundă în secundă, fără să mai interogheze
  /// storage-ul la fiecare tick — la zero, reverifică o dată (flip la ready).
  void _startCountdown() {
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final next = (_remaining ?? Duration.zero) - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        timer.cancel();
        _refreshReady();
        return;
      }
      setState(() => _remaining = next);
    });
  }

  @override
  void dispose() {
    _gestureTimer?.cancel();
    _countdownTicker?.cancel();
    _syncSub?.cancel();
    _idle.dispose();
    _excite.dispose();
    _gesture.dispose();
    _speech.dispose();
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

    // fără mai vreun mesaj (snackbar) — timpul rămas se vede deja permanent
    // sub mascotă (vezi [_buildLabel]), tap-ul doar mai declanșează reacția.
    Sfx.tileSelect();
    setState(() => _excited = true);
    _excite.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _excited = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRing(),
          const SizedBox(height: 3),
          _buildLabel(),
        ],
      ),
    );
  }

  /// Eticheta permanentă de sub mascotă — numele + numărătoarea inversă cât
  /// timp roata nu e disponibilă, sau doar numele (fără timer) când e gata.
  /// Înlocuiește vechiul snackbar (feedback tranzitoriu) cu unul mereu vizibil.
  Widget _buildLabel() {
    const labelStyle = TextStyle(color: Colors.white54, fontSize: 7.5, fontWeight: FontWeight.w700, letterSpacing: 0.3);
    if (_ready) {
      return Text(tr('ROATA NOROCULUI', 'LUCKY WHEEL'), style: TextStyle(color: AppColors.hint, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.3));
    }
    if (!_checked) {
      return Text(tr('ROATA NOROCULUI', 'LUCKY WHEEL'), style: labelStyle);
    }
    final r = _remaining ?? Duration.zero;
    final h = r.inHours.toString().padLeft(2, '0');
    final m = (r.inMinutes % 60).toString().padLeft(2, '0');
    final s = (r.inSeconds % 60).toString().padLeft(2, '0');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr('ROATA NOROCULUI', 'LUCKY WHEEL'), style: labelStyle),
        Text('$h:$m:$s', style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _buildRing() {
    return SizedBox(
      width: 78,
      height: 78,
      child: AnimatedBuilder(
          animation: Listenable.merge([_idle, _excite, _gesture, _speech]),
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
              final g = _currentGesture == _RingGesture.askHow ? _speech.value : _gesture.value;
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
                  // legănare blândă continuă cât timp vorbește — pe toată
                  // durata mai lungă a replicii, nu doar o singură bâțâială.
                  gestureDy = -sin(g * pi * 10) * 3.5 * (1 - g * 0.35);
                  break;
              }
            }

            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // alfa amestecată direct în culoare — nu Opacity() peste un
                // Container, ca să nu ceară un strat offscreen nou la fiecare
                // cadru din bucla continuă de idle (rulează cât timp Home e
                // deschis, deci orice cost per-frame se simte constant).
                Container(
                  width: 60 + pulse * 14,
                  height: 60 + pulse * 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (_ready ? const Color(0xFFFFC542) : const Color(0xFF534AB7))
                        .withAlpha(((_ready ? 0.22 + pulse * 0.28 : 0.1 + pulse * 0.1).clamp(0.0, 1.0) * 255).round()),
                  ),
                ),
                if (ripple > 0)
                  Container(
                    width: 48 + ripple * 46,
                    height: 48 + ripple * 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withAlpha(((1 - ripple).clamp(0.0, 1.0) * 255).round()), width: 2),
                    ),
                  ),
                if (_currentGesture == _RingGesture.checkClock)
                  Positioned(bottom: -4, right: 4, child: ClockProp(t: _gesture.value)),
                if (_currentGesture == _RingGesture.askHow && _speechText != null)
                  Positioned(top: -26, child: MascotBubble(text: _speechText!, color: AppColors.purple, t: _speech.value)),
                Transform.translate(
                  offset: Offset(gestureDx, gestureDy),
                  child: Transform.rotate(
                    angle: tilt + gestureAngle,
                    child: Transform(
                      alignment: Alignment.center,
                      // ignore: deprecated_member_use
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
