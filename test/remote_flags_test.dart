import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/remote_flags.dart';

/// `isTooOld` decide dacă cineva mai poate juca. O greșeală aici blochează
/// TOȚI jucătorii, deci regula de aur e: la orice nu înțelege, NU blochează.
void main() {
  bool tooOld(String current, String minimum) =>
      RemoteFlags.isTooOld(current: current, minimum: minimum);

  group('compară numeric, nu alfabetic', () {
    test('mai vechi decât minimul → blocat', () {
      expect(tooOld('1.0.1', '1.0.2'), isTrue);
      expect(tooOld('1.0.0', '2.0.0'), isTrue);
      expect(tooOld('1.2.9', '1.3.0'), isTrue);
    });

    test('egal sau mai nou → merge', () {
      expect(tooOld('1.0.2', '1.0.2'), isFalse);
      expect(tooOld('1.0.3', '1.0.2'), isFalse);
      expect(tooOld('2.0.0', '1.9.9'), isFalse);
    });

    test('1.10.0 e mai NOU decât 1.9.9 (comparația de text ar greși)', () {
      expect(tooOld('1.10.0', '1.9.9'), isFalse);
      expect(tooOld('1.9.9', '1.10.0'), isTrue);
    });

    test('numărul de build de după + nu contează', () {
      expect(tooOld('1.0.2+6', '1.0.2'), isFalse);
      expect(tooOld('1.0.1+99', '1.0.2'), isTrue);
    });
  });

  group('la orice nelămurire, NU blochează', () {
    test('minim gol = nicio constrângere', () {
      expect(tooOld('1.0.0', ''), isFalse);
      expect(tooOld('1.0.0', '   '), isFalse);
    });

    test('versiune proprie necunoscută', () {
      expect(tooOld('', '9.9.9'), isFalse);
    });

    test('text greșit în consolă nu are voie sa blocheze jocul', () {
      expect(tooOld('1.0.0', 'curand'), isFalse);
      expect(tooOld('1.0.0', '1.0.x'), isFalse);
      expect(tooOld('1.0.0', '1.2.3.4'), isFalse);
    });
  });

  test('versiuni scurte se completează cu zero', () {
    expect(tooOld('1.0.0', '1.1'), isTrue);
    expect(tooOld('2', '1.9.9'), isFalse);
  });
}
