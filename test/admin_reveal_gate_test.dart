import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/admin_reveal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => adminAnswerReveal.value = false);

  test('toggle-ul pornit dar fara cont de admin => marcajul NU se arata', () {
    // In test nu exista Firebase, deci AuthService.currentUser intoarce null
    // (are try/catch). `adminAnswerRevealOn` cere AMANDOUA: pref + email.
    // Chiar cu flag-ul fortat pe true, un non-admin nu vede nimic.
    adminAnswerReveal.value = true;
    expect(adminAnswerRevealOn, isFalse,
        reason: 'pref-ul singur nu ajunge — marcajul e pentru admin, nu pentru oricine');
  });

  test('toggle-ul oprit => marcajul NU se arata', () {
    adminAnswerReveal.value = false;
    expect(adminAnswerRevealOn, isFalse);
  });
}
