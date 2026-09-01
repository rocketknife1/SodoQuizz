import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/widgets/wheel_spin_dialog.dart';

/// Curba roții norocului. Un jucător a raportat că roata „nu se simte
/// plăcut": varianta veche folosea `Curves.easeIn` pe prima fază, adică
/// pornea de la viteză ZERO — pe 4,6 secunde, roata abia se târa la început.
/// Testele de aici apără forma corectă.
void main() {
  const c = suspenseWheelCurveForTest;

  double vitezaLa(double t, [double h = 0.0005]) =>
      (c.transform((t + h).clamp(0.0, 1.0)) - c.transform((t - h).clamp(0.0, 1.0))) / (2 * h);

  test('porneste la 0 si ajunge exact la 1', () {
    expect(c.transform(0), closeTo(0, 1e-9));
    expect(c.transform(1), closeTo(1, 1e-9));
  });

  test('e monotona — roata nu se intoarce niciodata inapoi', () {
    var prev = -1.0;
    for (var i = 0; i <= 200; i++) {
      final v = c.transform(i / 200);
      expect(v, greaterThanOrEqualTo(prev), reason: 'a scazut la t=${i / 200}');
      prev = v;
    }
  });

  test('PLEACA CU VITEZA MAXIMA, nu de la zero (bug-ul raportat)', () {
    final vStart = vitezaLa(0.02);
    expect(vStart, greaterThan(1.5),
        reason: 'cu easeIn viteza initiala era ~0 si roata se simtea moale');
  });

  test('incetineste vizibil spre final', () {
    expect(vitezaLa(0.95), lessThan(vitezaLa(0.10) / 4),
        reason: 'suspansul vine din decelerare');
  });

  test('roata NU accelereaza niciodata dupa pornire', () {
    // Cerinta reala nu e "viteza identica de o parte si de alta a tranzitiei"
    // (curbele Bezier isi schimba derivata prea repede ca sa aiba sens la
    // esantionare fina), ci: o roata pocnita cu degetul incetineste, nu
    // accelereaza. O crestere de viteza la mijloc s-ar vedea ca o smucitura.
    final vFaza1 = vitezaLa(0.20); // in mijlocul fazei liniare
    for (var i = 36; i <= 99; i++) {
      final v = vitezaLa(i / 100);
      expect(v, lessThanOrEqualTo(vFaza1 * 1.02),
          reason: 'la t=${i / 100} roata merge mai repede decat in faza rapida');
    }
  });

  test('faza rapida chiar e cu viteza constanta', () {
    final probe = [0.05, 0.15, 0.25, 0.33].map(vitezaLa).toList();
    for (final v in probe) {
      expect(v, closeTo(probe.first, probe.first * 0.02),
          reason: 'prima faza trebuie sa fie liniara');
    }
  });
}
