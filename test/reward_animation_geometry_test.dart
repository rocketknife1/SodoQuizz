import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/widgets/coin_reward_overlay.dart';
import 'package:guess_it/widgets/wheel_spin_dialog.dart';

/// Regresii pentru două bug-uri vizuale reale, documentate în cod dar fără
/// test care să le păzească de reapariție.
void main() {
  group('wheelTargetAngle (Roata norocului)', () {
    test('aduce segmentul cerut exact sub ac, fără offset -pi/2 suplimentar', () {
      const segmentCount = 8;
      final segmentAngle = 2 * pi / segmentCount;
      for (var i = 0; i < segmentCount; i++) {
        final angle = wheelTargetAngle(i, segmentCount);
        // Bug-ul vechi era `-pi/2 - (i+0.5)*segmentAngle` — un offset -pi/2
        // în plus față de formula corectă. Verificăm explicit că nu mai e
        // acolo, nu doar că formula "pare" corectă.
        final buggyAngle = -pi / 2 - (i + 0.5) * segmentAngle;
        expect(angle, isNot(closeTo(buggyAngle, 1e-9)));
        expect(angle, closeTo(-(i + 0.5) * segmentAngle, 1e-9));
      }
    });
  });

  group('trailUnitCount (dâra de simboluri la recompensă)', () {
    test('nu depășește niciodată plafonul, indiferent cât de mare e recompensa', () {
      expect(trailUnitCount(1), 1);
      expect(trailUnitCount(3), 3);
      expect(trailUnitCount(5), 5);
      // 6 simboluri a fost exact pragul bug-ului "traseu invizibil" —
      // plafonul trebuie să oprească strict înainte de el.
      expect(trailUnitCount(6), lessThanOrEqualTo(5));
      expect(trailUnitCount(999), lessThanOrEqualTo(5));
    });

    test('minim un simbol chiar și la o recompensă de 0', () {
      expect(trailUnitCount(0), 1);
    });
  });
}
