import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/chat_filter.dart';

/// Filtrul de chat se testează aici fiindcă amândouă felurile lui de a greși
/// sunt scumpe și tăcute:
///  - dacă lasă să treacă ocolirile evidente (litere alungite, puncte între
///    litere, cifre în loc de litere), răspunsul „avem moderare de chat" din
///    Content rating devine neadevărat;
///  - dacă taie cuvinte nevinovate, un chat de quiz în care nu poți întreba
///    ce POPULAȚIE are un oraș e mai rău decât unul needucat.
/// A doua categorie e cea care s-a și rupt o dată în timpul scrierii, de-aia
/// are aici mai multe cazuri decât prima.
void main() {
  group('cenzurare', () {
    test('cuvântul simplu e acoperit complet', () {
      expect(censorChatMessage('esti o pizda'), 'esti o *****');
    });

    test('diacriticele nu ajută la ocolire', () {
      expect(containsProfanity('ce pizdă'), isTrue);
      expect(containsProfanity('cacăt'), isTrue);
    });

    test('literele alungite nu ajută la ocolire', () {
      expect(censorChatMessage('puuulaaa'), '********');
    });

    test('punctele și spațiile dintre litere nu ajută la ocolire', () {
      expect(censorChatMessage('p.u.l.a'), '*******');
      expect(containsProfanity('f u c k'), isTrue);
    });

    test('cifrele în loc de litere nu ajută la ocolire, în ambele citiri', () {
      expect(containsProfanity('p1zda'), isTrue); // 1 citit ca „i"
      expect(containsProfanity('pu1a'), isTrue); // 1 citit ca „l"
      expect(containsProfanity('sh17'), isTrue);
      expect(containsProfanity('f4ggot'), isTrue);
    });

    test('majusculele nu ajută la ocolire', () {
      expect(containsProfanity('FUCK'), isTrue);
    });

    test('terminațiile lipite intră tot sub cenzură', () {
      expect(censorChatMessage('pizdele'), '*******');
      expect(containsProfanity('curvele'), isTrue);
    });

    test('restul mesajului rămâne neatins, cu diacritice cu tot', () {
      expect(censorChatMessage('bună, ce faci?'), 'bună, ce faci?');
      expect(censorChatMessage('hai fuck acum'), 'hai **** acum');
    });
  });

  group('cuvinte nevinovate care NU trebuie atinse', () {
    // Fiecare conține, ca șir de litere, o rădăcină din listă — exact tipul de
    // cuvânt pe care un filtru scris naiv îl taie.
    const nevinovate = [
      'care e populatia Romaniei',
      'ce populație are Clujul',
      'apa e curata',
      'nu merge curentul',
      'ne vedem in curte',
      'am mancat curcan',
      'asasinarea lui Cezar',
      'clasa a opta',
      'am dat pass',
      'romanul lui Dickens',
      'imi place struguri si grape juice',
      'informatii utile',
      'mă ții minte?',
      'copulă gramaticală',
      // Instrumentul muzical — diferă de injurie printr-un singur „g", exact
      // distincția pe care colapsarea literelor repetate ar fi ștears-o.
      'la fagot si oboi',
    ];

    for (final text in nevinovate) {
      test('„$text" rămâne întreg', () {
        expect(censorChatMessage(text), text);
      });
    }
  });

  group('sanitizeChatMessage', () {
    test('taie spațiile de la capete și aduce rândurile la unul singur', () {
      expect(sanitizeChatMessage('  salut\n\n  toata lumea  '), 'salut toata lumea');
    });

    test('limitează lungimea', () {
      final lung = 'a' * (chatMessageMaxLength + 50);
      expect(sanitizeChatMessage(lung).length, chatMessageMaxLength);
    });

    test('cenzurează înainte de trimitere', () {
      expect(sanitizeChatMessage('  ce PIZDA  '), 'ce *****');
    });

    test('mesajul gol rămâne gol', () {
      expect(sanitizeChatMessage('   '), '');
    });
  });
}
