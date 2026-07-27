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
  'Hai să batem un record!',
  'Îmi place energia ta azi.',
  'Ce categorie joci acum?',
  'Nu uita de streak-ul zilnic!',
  'Eu tot aștept aici, pe tine.',
  'Gata de o rundă rapidă?',
  'Mi-e dor de un quiz bun.',
  'Tu știi cel mai mult, nu eu.',
];

/// Cât timp rămâne vizibilă o replică "greet", ca să apuce cineva să o
/// citească — proporțional cu lungimea textului (mesajele mai lungi stau
/// mai mult), nu o durată fixă și scurtă ca gesturile pur decorative.
Duration greetDisplayDuration(String message) =>
    Duration(milliseconds: (2600 + message.length * 55).clamp(3000, 5500));

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
  static MascotId? _lastGreetTarget;
  static String? _lastGreetMessage;

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

  /// Interval scurtat față de varianta inițială (era 20-45s) — cu 3 mascote
  /// care își împart evenimentul, fiecare ajungea să "vorbească" prea rar.
  /// Evită și repetarea aceleiași ținte sau a aceluiași mesaj de două ori
  /// la rând, ca ciclul să nu pară monoton.
  static Timer _scheduleGreet() {
    return Timer(Duration(seconds: 14 + _random.nextInt(18)), () {
      var target = MascotId.values[_random.nextInt(MascotId.values.length)];
      while (target == _lastGreetTarget && MascotId.values.length > 1) {
        target = MascotId.values[_random.nextInt(MascotId.values.length)];
      }
      var message = mascotGreetLines[_random.nextInt(mascotGreetLines.length)];
      while (message == _lastGreetMessage && mascotGreetLines.length > 1) {
        message = mascotGreetLines[_random.nextInt(mascotGreetLines.length)];
      }
      _lastGreetTarget = target;
      _lastGreetMessage = message;
      _controller.add(MascotEvent(MascotEventType.greet, target: target, message: message));
      _greetTimer = _scheduleGreet();
    });
  }
}
