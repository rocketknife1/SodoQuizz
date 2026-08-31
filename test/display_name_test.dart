import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/display_name.dart';

void main() {
  group('resolveDisplayName', () {
    test('numele pus de admin bate tot', () {
      expect(
        resolveDisplayName(forcedName: 'Andrei', chosenName: 'AlesDeMine', googleName: 'Nume Google'),
        'Andrei',
      );
    });

    test('numele ales de jucator bate contul Google', () {
      expect(
        resolveDisplayName(forcedName: '', chosenName: 'AlesDeMine', googleName: 'Nume Google'),
        'AlesDeMine',
      );
    });

    test('fara nume ales, ramane cel din contul Google', () {
      expect(
        resolveDisplayName(forcedName: '', chosenName: '', googleName: 'Nume Google'),
        'Nume Google',
      );
    });

    test('Guest fara nimic: intoarce gol, apelantul cade pe numele local', () {
      expect(resolveDisplayName(forcedName: '', chosenName: '', googleName: ''), '');
    });

    test('spatiile nu tin loc de nume ales', () {
      expect(
        resolveDisplayName(forcedName: '', chosenName: '   ', googleName: 'Nume Google'),
        'Nume Google',
      );
    });
  });
}
