import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/game_pause.dart';

/// GamePause îngheață cronometrele singleplayer cât e deschisă nota rapidă
/// a owner-ului — vezi OwnerNoteOverlay. Aici testăm doar comutatorul, nu
/// ecranele care îl citesc (acelea au propriile teste de timer).
void main() {
  tearDown(GamePause.instance.resume);

  test('incepe neinghetat', () {
    expect(GamePause.instance.isPaused, isFalse);
  });

  test('pause() / resume() comuta isPaused', () {
    GamePause.instance.pause();
    expect(GamePause.instance.isPaused, isTrue);
    GamePause.instance.resume();
    expect(GamePause.instance.isPaused, isFalse);
  });

  test('paused notifica ascultatorii la schimbare', () {
    var notifications = 0;
    GamePause.instance.paused.addListener(() => notifications++);
    GamePause.instance.pause();
    GamePause.instance.resume();
    expect(notifications, 2);
  });
}
