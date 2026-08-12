import 'dart:async';
import 'dart:math';

import '../../core/eco_mode.dart';
import '../../core/lang.dart';

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

/// Getter, nu constantă: replicile se traduc, iar o listă `const` nu poate
/// chema tr(). Se citește oricum o dată la fiecare replică rostită.
List<String> get mascotGreetLines => [
      tr('Ce mai faci?', 'How are you doing?'),
      tr('Cum mai e ziua?', 'How is your day going?'),
      tr('Ești gata de un quiz?', 'Ready for a quiz?'),
      tr('Salut! 👋', 'Hi there! 👋'),
      tr('Baftă la joc!', 'Good luck out there!'),
      tr('Ai învățat ceva nou azi?', 'Learned anything new today?'),
      tr('Hai să batem un record!', 'Let us beat a record!'),
      tr('Îmi place energia ta azi.', 'I like your energy today.'),
      tr('Ce categorie joci acum?', 'Which category are you playing?'),
      tr('Nu uita de streak-ul zilnic!', 'Do not forget your daily streak!'),
      tr('Eu tot aștept aici, pe tine.', 'I am still here, waiting for you.'),
      tr('Gata de o rundă rapidă?', 'Up for a quick round?'),
      tr('Mi-e dor de un quiz bun.', 'I miss a good quiz.'),
      tr('Tu știi cel mai mult, nu eu.', 'You know the most here, not me.'),
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

  /// Pornește dispecerul — dar NU în Modul Eco, unde gesturile și replicile
  /// mascotelor sunt exact genul de mișcare pe care modul o oprește: pur
  /// decorative, la câteva zeci de secunde, fiecare cu 3-4 secunde de cadre
  /// desenate la 60 fps. Fără oprirea asta, meniul principal tot se trezea
  /// periodic din repaus, chiar cu buclele infinite oprite.
  ///
  /// Ascultă comutatorul, deci pornirea/oprirea modului se aplică pe loc, fără
  /// repornirea jocului.
  static void ensureStarted() {
    EcoMode.enabled.removeListener(_applyEco);
    EcoMode.enabled.addListener(_applyEco);
    if (EcoMode.on) return;
    _clockTimer ??= _scheduleClock();
    _greetTimer ??= _scheduleGreet();
  }

  static void _applyEco() {
    if (EcoMode.on) {
      _clockTimer?.cancel();
      _clockTimer = null;
      _greetTimer?.cancel();
      _greetTimer = null;
    } else {
      _clockTimer ??= _scheduleClock();
      _greetTimer ??= _scheduleGreet();
    }
  }

  /// Doar pentru teste widget: MascotSync e un dispecer global, pornit o
  /// singură dată și menit să ruleze la nesfârșit (fiecare timer se
  /// reprogramează singur) - `flutter test` marchează orice timer încă
  /// pending la finalul testului ca eroare, așa că testele care montează o
  /// mascotă trebuie să oprească explicit dispecerul înainte să se termine.
  static void resetForTest() {
    _clockTimer?.cancel();
    _clockTimer = null;
    _greetTimer?.cancel();
    _greetTimer = null;
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
