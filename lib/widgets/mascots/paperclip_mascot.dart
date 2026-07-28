import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/audio.dart';
import '../../core/theme.dart';
import '../../data/storage_service.dart';
import '../../screens/clippy_bonus_screen.dart';
import 'googly_eyes.dart';
import 'mascot_props.dart';
import 'mascot_sync.dart';

/// Opt gesturi unice: șase idle "de personalitate" (declanșate local,
/// aleatoriu) și două comune, sincronizate prin [MascotSync] cu celelalte
/// mascote de pe Home — [checkClock] (toate trei deodată) și [askHow] (câte
/// una, pe rând, cu un mesaj random).
enum _Gesture { stretch, hop, shimmy, spin, peek, bigBounce, checkClock, askHow }

const _localGestures = [
  _Gesture.stretch,
  _Gesture.hop,
  _Gesture.shimmy,
  _Gesture.spin,
  _Gesture.peek,
  _Gesture.bigBounce,
];

/// Mascotă decorativă în stil "Clippy" (asistentul din Windows XP): o
/// agrafă cu ochi jucăuși, care se leagănă în loc, cu câteva "planete"
/// mici orbitând în jur (temă spațială, ca restul aplicației) și un
/// repertoriu de gesturi idle care se schimbă periodic.
///
/// La fiecare ~15s (fără nicio notificare zgomotoasă) apare o pastilă
/// discretă, lipită de "fruntea" agrafei (se mișcă odată cu ea) — semn că
/// are pregătit un set de 3 întrebări aleatorii din toate categoriile, cu
/// recompensă ×1.25. Tap pe ea în starea asta te duce la [ClippyBonusScreen];
/// altfel, tap-ul e doar o reacție amuzantă (+ un mesaj cu timpul rămas).
///
/// Disponibilitatea e persistată (vezi [StorageService.isClippyReady]), nu
/// ținută doar în memoria widget-ului — altfel se pierdea la orice
/// recreare a lui Home (ex: schimbarea unui tab din bottom nav).
class PaperclipMascot extends StatefulWidget {
  final VoidCallback? onRewardsChanged;

  const PaperclipMascot({super.key, this.onRewardsChanged});

  @override
  State<PaperclipMascot> createState() => _PaperclipMascotState();
}

class _PaperclipMascotState extends State<PaperclipMascot> with TickerProviderStateMixin {
  late final AnimationController _idle;
  late final AnimationController _excite;
  late final AnimationController _gesture;
  late final AnimationController _speech;
  bool _excited = false;
  bool _questionReady = false;
  _Gesture? _currentGesture;
  String? _speechText;
  Timer? _readyPollTimer;
  Timer? _gestureTimer;
  StreamSubscription<MascotEvent>? _syncSub;
  final _random = Random();

  static const _planetColors = [Color(0xFF534AB7), Color(0xFF1D9E75), Color(0xFFFF7A1A)];

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();
    _excite = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
    _gesture = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _speech = AnimationController(vsync: this, duration: const Duration(milliseconds: 3800));
    _scheduleGesture();
    _refreshReady();
    MascotSync.ensureStarted();
    _syncSub = MascotSync.events.listen(_onSyncEvent);
  }

  void _onSyncEvent(MascotEvent event) {
    if (!mounted || _gesture.isAnimating || _speech.isAnimating) return;
    if (event.type == MascotEventType.checkClock) {
      _gestureTimer?.cancel();
      _playGesture(_Gesture.checkClock);
    } else if (event.type == MascotEventType.greet && event.target == MascotId.clippy) {
      _gestureTimer?.cancel();
      _playSpeech(event.message!);
    }
  }

  /// Citește disponibilitatea din storage (sursa de adevăr) și, dacă încă
  /// nu e gata, programează un timer LOCAL doar ca să reîmprospăteze UI-ul
  /// exact când expiră — corectitudinea nu depinde de acest timer (dacă se
  /// pierde odată cu widget-ul, următoarea verificare din storage tot arată
  /// corect starea).
  Future<void> _refreshReady() async {
    _readyPollTimer?.cancel();
    final ready = await StorageService.isClippyReady();
    if (!mounted) return;
    setState(() => _questionReady = ready);
    if (!ready) {
      final remaining = await StorageService.clippyReadyRemaining();
      if (!mounted) return;
      _readyPollTimer = Timer(remaining, _refreshReady);
    }
  }

  void _scheduleGesture() {
    _gestureTimer = Timer(Duration(milliseconds: 4200 + _random.nextInt(3600)), () {
      if (!mounted) return;
      var next = _localGestures[_random.nextInt(_localGestures.length)];
      while (next == _currentGesture && _localGestures.length > 1) {
        next = _localGestures[_random.nextInt(_localGestures.length)];
      }
      _playGesture(next);
    });
  }

  /// Rulează un gest (local sau declanșat de [MascotSync]) și, la final,
  /// reia programarea locală — indiferent de sursa care l-a pornit.
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

  /// La fel ca [_playGesture], dar pentru replici ("askHow") — folosește un
  /// controller separat de [_gesture], cu o durată calculată din lungimea
  /// mesajului (vezi [greetDisplayDuration]), ca textul să apuce să fie
  /// citit în loc să dispară odată cu scurtul gest de bâțâială al corpului.
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
    _readyPollTimer?.cancel();
    _gestureTimer?.cancel();
    _syncSub?.cancel();
    _idle.dispose();
    _excite.dispose();
    _gesture.dispose();
    _speech.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_excite.isAnimating) return;

    if (_questionReady) {
      Sfx.rewardPop();
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const ClippyBonusScreen()));
      widget.onRewardsChanged?.call();
      // dacă a ieșit fără să termine, notificarea rămâne validă — nu se
      // consumă/reprogramează decât când bonusul e efectiv terminat (vezi
      // ClippyBonusScreen, care apelează resetClippyCooldown la final).
      if (mounted) _refreshReady();
      return;
    }

    Sfx.tileSelect();
    setState(() => _excited = true);
    _excite.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _excited = false);
    });
    final remaining = await StorageService.clippyReadyRemaining();
    if (!mounted || remaining <= Duration.zero) return;
    final s = remaining.inSeconds + 1;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Clippy mai are nevoie de ${s}s'), duration: const Duration(milliseconds: 1200)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: SizedBox(
        width: 116,
        height: 116,
        child: AnimatedBuilder(
          animation: Listenable.merge([_idle, _excite, _gesture, _speech]),
          builder: (context, _) {
            final t = _idle.value * 2 * pi;
            final bob = sin(t) * 4;
            final wobble = sin(t * 0.8) * 0.09 + (_excited ? sin(_excite.value * pi * 6) * 0.35 * (1 - _excite.value) : 0);
            final exciteScale = _excited ? (1 - _excite.value) * 0.28 : 0.0;

            var gestureDy = 0.0;
            var gestureDx = 0.0;
            var gestureAngle = 0.0;
            var gestureScaleY = 1.0;
            if (_currentGesture != null) {
              final g = _currentGesture == _Gesture.askHow ? _speech.value : _gesture.value;
              switch (_currentGesture!) {
                case _Gesture.stretch:
                  gestureScaleY = 1 + sin(g * pi) * 0.32;
                  break;
                case _Gesture.hop:
                  gestureDy = -sin(g * pi * 2).abs() * 16;
                  break;
                case _Gesture.shimmy:
                  gestureDx = sin(g * pi * 7) * 9 * (1 - g);
                  break;
                case _Gesture.spin:
                  gestureAngle = g * 2 * pi;
                  break;
                case _Gesture.checkClock:
                  // se apleacă ușor, ca și cum și-ar scoate ceasul de după
                  // spate și s-ar uita la el, apoi revine.
                  gestureAngle = sin(g * pi) * -0.16;
                  gestureDy = sin(g * pi) * 4;
                  break;
                case _Gesture.askHow:
                  // legănare blândă continuă cât timp vorbește — pe toată
                  // durata mai lungă a replicii, nu doar o singură bâțâială.
                  gestureDy = -sin(g * pi * 10) * 4 * (1 - g * 0.35);
                  break;
                case _Gesture.peek:
                  // se apleacă într-o parte, ca și cum s-ar uita după colț,
                  // apoi revine — o singură leănare, nu oscilație repetată.
                  gestureAngle = sin(g * pi) * 0.4;
                  gestureDx = sin(g * pi) * 12;
                  break;
                case _Gesture.bigBounce:
                  // un singur salt mare, cu "aterizare" — se turtește puțin
                  // exact când atinge punctul de jos, ca un impact real.
                  gestureDy = -sin(g * pi) * 26;
                  gestureScaleY = 1 - (g > 0.82 ? sin((g - 0.82) / 0.18 * pi) * 0.28 : 0);
                  break;
              }
            }

            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < 3; i++) _buildPlanet(i, t),
                if (_currentGesture == _Gesture.checkClock)
                  Positioned(bottom: 4, right: 18, child: ClockProp(t: _gesture.value)),
                if (_currentGesture == _Gesture.askHow && _speechText != null)
                  Positioned(top: -14, child: MascotBubble(text: _speechText!, color: AppColors.purple, t: _speech.value)),
                // TOT ce ține de corpul agrafei (icon, ochi, notificare)
                // trece prin ACELEAȘI transformări (bob/wobble/gesturi) —
                // astfel notificarea rămâne "lipită" de ea, nu statică.
                Transform.translate(
                  offset: Offset(gestureDx, bob + gestureDy),
                  child: Transform.rotate(
                    angle: wobble + gestureAngle,
                    child: Transform(
                      alignment: Alignment.center,
                      // ignore: deprecated_member_use
                      transform: Matrix4.identity()..scale(1.0, gestureScaleY),
                      child: Transform.scale(
                        scale: 1 + exciteScale,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(
                              Icons.attach_file_rounded,
                              size: 72,
                              color: Color(0xFFD9D9F5),
                              shadows: [Shadow(color: Colors.black45, blurRadius: 7)],
                            ),
                            Positioned(top: 20, child: GooglyEyes(size: 11, excited: _excited)),
                            if (_questionReady) const Positioned(top: -6, left: 2, child: _NotificationBadge()),
                          ],
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

  Widget _buildPlanet(int i, double t) {
    final phase = i * (2 * pi / 3);
    final dir = i.isEven ? 1 : -1;
    final angle = t * dir + phase;
    const r = 48.0;
    final pos = Offset(cos(angle) * r, sin(angle) * r * 0.55);
    final color = _planetColors[i];
    return Positioned(
      left: 58 + pos.dx - 4,
      top: 58 + pos.dy - 4,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color.withAlpha(150), blurRadius: 4)],
        ),
      ),
    );
  }
}

class _NotificationBadge extends StatelessWidget {
  const _NotificationBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE24B4A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0B1229), width: 2),
        boxShadow: const [BoxShadow(color: Color(0xFFE24B4A), blurRadius: 6)],
      ),
      child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }
}
