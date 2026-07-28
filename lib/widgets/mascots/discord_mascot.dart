import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/audio.dart';
import '../../core/theme.dart';
import 'googly_eyes.dart';
import 'mascot_props.dart';
import 'mascot_sync.dart';

const _discordInviteUrl = 'https://discord.gg/5d5b65ffM';
const _discordBlurple = Color(0xFF5865F2);
const _martianGreen = Color(0xFF3BC17A);

// cât timp e vizibil balonul "Visit us!" din ciclul lui, și de câte ori mai
// mult stă ascuns — cerut explicit: câteva secunde vizibil, dublu ascuns.
// Peste durata maximă a replicilor "askHow" ale celorlalte mascote (vezi
// greetDisplayDuration, 3.0-5.5s), ca balonul de Discord să rămână vizibil
// clar mai mult decât mesajele lor.
const _bubbleVisibleSeconds = 6;
const _bubbleHiddenSeconds = _bubbleVisibleSeconds * 2;

/// Opt gesturi unice: șase idle "de personalitate" (declanșate local,
/// aleatoriu, peste legănarea continuă de fundal) și două comune,
/// sincronizate prin [MascotSync] cu celelalte mascote de pe Home —
/// [checkClock] (toate trei deodată) și [askHow] (câte una, pe rând).
enum _Gesture { hop, spin, antennaeBig, squish, peekLean, shiver, checkClock, askHow }

const _localGestures = [
  _Gesture.hop,
  _Gesture.spin,
  _Gesture.antennaeBig,
  _Gesture.squish,
  _Gesture.peekLean,
  _Gesture.shiver,
];

/// A treia mascotă decorativă, tot din "familia" agrafei și inelului
/// (aceiași ochi jucăuși, aceeași idee de legănare continuă), dar cu corp
/// de mic marțian verde, cu antene — și o "vorbă" deasupra capului care
/// invită spre serverul de Discord al jocului, vizibilă ciclic (apare
/// câteva secunde, pulsând, apoi dispare de două ori mai mult). Spre
/// deosebire de celelalte două, tap-ul nu are cooldown: duce mereu direct
/// la invitație, după un mic sunet de răsplată.
class DiscordMascot extends StatefulWidget {
  const DiscordMascot({super.key});

  @override
  State<DiscordMascot> createState() => _DiscordMascotState();
}

class _DiscordMascotState extends State<DiscordMascot> with TickerProviderStateMixin {
  late final AnimationController _idle;
  late final AnimationController _excite;
  late final AnimationController _gesture;
  late final AnimationController _speech;
  late final AnimationController _bubbleCycle;
  bool _excited = false;
  _Gesture? _currentGesture;
  String? _speechText;
  Timer? _gestureTimer;
  StreamSubscription<MascotEvent>? _syncSub;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _excite = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _gesture = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _speech = AnimationController(vsync: this, duration: const Duration(milliseconds: 3800));
    _bubbleCycle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: _bubbleVisibleSeconds + _bubbleHiddenSeconds),
    )..repeat();
    _scheduleGesture();
    MascotSync.ensureStarted();
    _syncSub = MascotSync.events.listen(_onSyncEvent);
  }

  void _onSyncEvent(MascotEvent event) {
    if (!mounted || _gesture.isAnimating || _speech.isAnimating) return;
    if (event.type == MascotEventType.checkClock) {
      _gestureTimer?.cancel();
      _playGesture(_Gesture.checkClock);
    } else if (event.type == MascotEventType.greet && event.target == MascotId.martian) {
      _gestureTimer?.cancel();
      _playSpeech(event.message!);
    }
  }

  void _scheduleGesture() {
    _gestureTimer = Timer(Duration(milliseconds: 4000 + _random.nextInt(3800)), () {
      if (!mounted) return;
      var next = _localGestures[_random.nextInt(_localGestures.length)];
      while (next == _currentGesture && _localGestures.length > 1) {
        next = _localGestures[_random.nextInt(_localGestures.length)];
      }
      _playGesture(next);
    });
  }

  void _playGesture(_Gesture gesture, {String? message}) {
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
      _currentGesture = _Gesture.askHow;
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

  @override
  void dispose() {
    _gestureTimer?.cancel();
    _syncSub?.cancel();
    _idle.dispose();
    _excite.dispose();
    _gesture.dispose();
    _speech.dispose();
    _bubbleCycle.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_excite.isAnimating) return;
    Sfx.rewardPop();
    setState(() => _excited = true);
    _excite.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _excited = false);
    });
    final uri = Uri.parse(_discordInviteUrl);
    unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: SizedBox(
        width: 92,
        height: 118,
        child: AnimatedBuilder(
          animation: Listenable.merge([_idle, _excite, _gesture, _speech, _bubbleCycle]),
          builder: (context, _) {
            final t = _idle.value * 2 * pi;
            final bob = sin(t) * 3;
            final sway = sin(t * 0.7) * 0.06;
            final antennaWag = sin(t * 1.6) * 0.18;
            final ripple = _excite.value;
            final exciteScale = _excited ? sin(ripple * pi) * 0.18 : 0.0;

            var gestureDx = 0.0;
            var gestureDy = 0.0;
            var gestureAngle = 0.0;
            var gestureScaleX = 1.0;
            var gestureScaleY = 1.0;
            var extraAntennaWag = 0.0;
            var extraSpin = 0.0;
            if (_currentGesture != null) {
              final g = _currentGesture == _Gesture.askHow ? _speech.value : _gesture.value;
              switch (_currentGesture!) {
                case _Gesture.hop:
                  gestureDy = -sin(g * pi * 2).abs() * 16;
                  break;
                case _Gesture.spin:
                  extraSpin = g * 2 * pi;
                  break;
                case _Gesture.antennaeBig:
                  extraAntennaWag = sin(g * pi * 8) * 0.55 * (1 - g);
                  break;
                case _Gesture.squish:
                  gestureScaleX = 1 + sin(g * pi) * 0.22;
                  gestureScaleY = 1 - sin(g * pi) * 0.2;
                  break;
                case _Gesture.peekLean:
                  gestureAngle = sin(g * pi) * 0.32;
                  gestureDx = sin(g * pi) * 11;
                  break;
                case _Gesture.shiver:
                  gestureDx = sin(g * pi * 11) * 4 * (1 - g);
                  break;
                case _Gesture.checkClock:
                  gestureAngle = sin(g * pi) * -0.16;
                  gestureDy = sin(g * pi) * 4;
                  break;
                case _Gesture.askHow:
                  // legănare blândă continuă cât timp vorbește — pe toată
                  // durata mai lungă a replicii, nu doar o singură bâțâială.
                  gestureDy = -sin(g * pi * 10) * 4 * (1 - g * 0.35);
                  break;
              }
            }

            // ciclul balonului fix "Visit us!": vizibil câteva secunde (cu
            // puls), apoi invizibil de două ori mai mult — se întrerupe cât
            // timp rulează un gest care ocupă aceeași zonă (ceas/replică).
            final cycle = _bubbleCycle.value;
            final visibleFrac = _bubbleVisibleSeconds / (_bubbleVisibleSeconds + _bubbleHiddenSeconds);
            double ctaOpacity;
            double ctaPulse;
            if (cycle < visibleFrac) {
              final vt = cycle / visibleFrac;
              final fadeIn = (vt / 0.12).clamp(0.0, 1.0);
              final fadeOut = ((1 - vt) / 0.12).clamp(0.0, 1.0);
              ctaOpacity = min(fadeIn, fadeOut);
              ctaPulse = 1 + sin(vt * pi * 4) * 0.08;
            } else {
              ctaOpacity = 0;
              ctaPulse = 1;
            }
            final ctaHidden = _currentGesture == _Gesture.checkClock || _currentGesture == _Gesture.askHow;

            return Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  child: Transform.translate(
                    offset: Offset(0, bob * 0.6),
                    child: !ctaHidden
                        ? Opacity(
                            opacity: ctaOpacity,
                            child: Transform.scale(
                              scale: ctaPulse,
                              child: const MascotBubble(text: 'Visit us!', color: _discordBlurple),
                            ),
                          )
                        : (_currentGesture == _Gesture.askHow && _speechText != null
                            ? MascotBubble(text: _speechText!, color: AppColors.purple, t: _speech.value)
                            : const SizedBox.shrink()),
                  ),
                ),
                if (_currentGesture == _Gesture.checkClock)
                  Positioned(bottom: 56, right: 6, child: ClockProp(t: _gesture.value)),
                Positioned(
                  bottom: 0,
                  child: Transform.translate(
                    offset: Offset(gestureDx, -bob + gestureDy),
                    child: Transform.rotate(
                      angle: sway + gestureAngle + extraSpin,
                      child: Transform(
                        alignment: Alignment.center,
                        // ignore: deprecated_member_use
                        transform: Matrix4.identity()..scale(gestureScaleX, gestureScaleY),
                        child: Transform.scale(
                          scale: 1 + exciteScale,
                          child: _buildBody(antennaWag + extraAntennaWag),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(double antennaWag) {
    return SizedBox(
      width: 64,
      height: 74,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // antene, cu bilă în vârf, care se leagănă ușor
          _buildAntenna(dx: -12, angle: -0.35 + antennaWag),
          _buildAntenna(dx: 12, angle: 0.35 + antennaWag),
          // corpul marțian — o "picătură" verde, mai lată la bază
          Positioned(
            top: 14,
            child: Container(
              width: 58,
              height: 60,
              decoration: BoxDecoration(
                color: _martianGreen,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 4))],
              ),
            ),
          ),
          const Positioned(top: 28, child: GooglyEyes(size: 12)),
          // insignă pe piept, cu iconul de Discord — semn discret al
          // "misiunii" mascotei, fără să domine desenul.
          Positioned(
            bottom: 12,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(color: _discordBlurple, shape: BoxShape.circle),
              child: const Icon(Icons.discord_rounded, color: Colors.white, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAntenna({required double dx, required double angle}) {
    return Positioned(
      top: -2,
      child: Transform.translate(
        offset: Offset(dx, 0),
        child: Transform.rotate(
          angle: angle,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _martianGreen,
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
                ),
              ),
              Container(width: 2.5, height: 20, color: _martianGreen),
            ],
          ),
        ),
      ),
    );
  }
}
