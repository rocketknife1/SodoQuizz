import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/electric_chair.dart';

/// `chairVerdict` decide ce se intampla cu o victima de pe scaun — raspuns,
/// scut, soc perforant, reflexie. Pura, deci verificabila aici fara Firestore
/// si fara cinci jucatori.
void main() {
  ChairVerdict v({
    bool answered = false,
    bool shield = false,
    bool ally = false,
    bool piercing = false,
    bool reflect = false,
  }) =>
      chairVerdict(
        answeredCorrectly: answered,
        hasShield: shield,
        allyShielded: ally,
        anyAttackerPiercing: piercing,
        hasReflect: reflect,
      );

  test('raspuns corect => scapa', () {
    expect(v(answered: true), ChairVerdict.survived);
    // raspunsul bate orice, chiar si perforantul
    expect(v(answered: true, piercing: true), ChairVerdict.survived);
  });

  test('gresit, fara nimic => soc', () {
    expect(v(), ChairVerdict.shocked);
  });

  test('scut propriu sau de aliat => scapa', () {
    expect(v(shield: true), ChairVerdict.survived);
    expect(v(ally: true), ChairVerdict.survived);
  });

  test('soc perforant trece prin scut', () {
    expect(v(shield: true, piercing: true), ChairVerdict.shocked);
    expect(v(ally: true, piercing: true), ChairVerdict.shocked);
  });

  test('reflexie: gresit dar are reflect => se intoarce spre atacatori', () {
    expect(v(reflect: true), ChairVerdict.reflected);
  });

  test('scutul are prioritate fata de reflexie (scapa curat, fara sa loveasca inapoi)', () {
    expect(v(shield: true, reflect: true), ChairVerdict.survived);
  });

  test('perforant anuleaza scutul, dar reflexia tot prinde', () {
    expect(v(shield: true, reflect: true, piercing: true), ChairVerdict.reflected);
  });
}
