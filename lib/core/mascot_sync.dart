import 'dart:async';
import 'dart:math';

/// Cele trei mascote decorative de pe Home (inelul, Clippy și marțianul de
/// Discord) — folosit ca să direcționăm evenimentele comune către mascota
/// potrivită (sau către toate, pentru gestul sincronizat cu ceasul).
enum MascotId { ring, clippy, martian }

enum MascotEventType { checkClock, greet }

class MascotEvent {
  final MascotEventType type;
  /// null pentru [MascotEventType.checkClock] = toate cele trei mascote.
  final MascotId? target;
  final String? message;
  const MascotEvent(this.type, {this.target, this.message});
}

const mascotGreetLines = [
  'Ce mai faci?',
  'Cum mai e ziua?',
  'Ești gata de un quiz?',
  'Salut! 👋',
  'Baftă la joc!',
  'Ai învățat ceva nou azi?',
];

/// Mic "dispecer" global, comun celor trei mascote de pe Home — pornește o
/// singură dată (idempotent, apelat din initState-ul fiecăreia) și emite
/// periodic, pe intervale aleatorii, două tipuri de evenimente decorative:
/// "toate trei se uită la ceas" (sincronizat) și "una dintre ele te
/// întreabă ceva" (câte o mascotă random, pe rând). Fiecare mascotă
/// ascultă și reacționează doar dacă evenimentul o privește și nu e deja
/// în mijlocul propriului ei gest.
class MascotSync {
  MascotSync._();

  static final _controller = StreamController<MascotEvent>.broadcast();
  static Stream<MascotEvent> get events => _controller.stream;
  static final _random = Random();
  static Timer? _clockTimer;
  static Timer? _greetTimer;

  static void ensureStarted() {
    _clockTimer ??= _scheduleClock();
    _greetTimer ??= _scheduleGreet();
  }

  static Timer _scheduleClock() {
    return Timer(Duration(seconds: 40 + _random.nextInt(35)), () {
      _controller.add(const MascotEvent(MascotEventType.checkClock));
      _clockTimer = _scheduleClock();
    });
  }

  static Timer _scheduleGreet() {
    return Timer(Duration(seconds: 20 + _random.nextInt(25)), () {
      final target = MascotId.values[_random.nextInt(MascotId.values.length)];
      final message = mascotGreetLines[_random.nextInt(mascotGreetLines.length)];
      _controller.add(MascotEvent(MascotEventType.greet, target: target, message: message));
      _greetTimer = _scheduleGreet();
    });
  }
}
