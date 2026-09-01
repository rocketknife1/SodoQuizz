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

  /// Viteza medie pe o FEREASTRA LARGA. `Curves.easeOut` e un [Cubic], care
  /// rezolva `x(s) = t` prin cautare binara cu toleranta 1e-3: iesirea e o
  /// scara cu trepte de ~0,0017, deci o diferenta finita fina masoara
  /// zgomotul de cuantizare, nu panta. Pe coada se masoara asa, nu cu
  /// [vitezaLa] (care ramane buna pe faza liniara, unde nu exista Bezier).
  double vitezaMedie(double a, double b) => (c.transform(b) - c.transform(a)) / (b - a);

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
    // Pragul e 1,2 (nu 1,5): viteza fazei liniare e determinata de potrivirea
    // cu panta cozii, iar pentru `Curves.easeOut` iese 1,3755. Pragul vechi de
    // 1,5 era calibrat pe constanta gresita 0,6612 (vezi recenzia din
    // 2026-09-01) — trecea tocmai fiindca roata mergea prea repede si apoi
    // frana sec. Ce apara testul e ca NU pleaca de la ~0, ca la `easeIn`.
    final vStart = vitezaLa(0.02);
    expect(vStart, greaterThan(1.2),
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
    for (var i = 35; i <= 90; i += 3) {
      final a = i / 100;
      final v = vitezaMedie(a, a + 0.09);
      expect(v, lessThanOrEqualTo(vFaza1 * 1.05),
          reason: 'pe [$a, ${a + 0.09}] roata merge mai repede decat in faza rapida');
    }
  });

  test('NU franeaza sec la trecerea dintre faze (recenzie 2026-09-01)', () {
    // Perechea testului de mai sus. Acela prinde doar panta de coada prea
    // MARE (accelerare). Constanta gresita 0,6612 producea exact opusul:
    // viteza cadea la ~45% fix la t=0,35 — o smucitura de franare pe care
    // niciun test n-o vedea.
    //
    // Se masoara pe FERESTRE LARGI, nu prin diferente fine: `Cubic` rezolva
    // x(s)=t prin cautare binara cu toleranta 1e-3, deci esantionarea fina
    // langa capat masoara zgomotul de cuantizare, nu panta.
    final inainte = vitezaMedie(0.25, 0.34);
    final dupa = vitezaMedie(0.36, 0.45);
    expect(dupa, greaterThan(inainte * 0.85),
        reason: 'viteza cade brusc la trecere: $inainte -> $dupa');
  });

  test('faza rapida chiar e cu viteza constanta', () {
    final probe = [0.05, 0.15, 0.25, 0.33].map(vitezaLa).toList();
    for (final v in probe) {
      expect(v, closeTo(probe.first, probe.first * 0.02),
          reason: 'prima faza trebuie sa fie liniara');
    }
  });
}
