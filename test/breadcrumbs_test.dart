import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/breadcrumbs.dart';

/// Firimiturile sunt singura sursă din raport care spune CE FĂCEA omul
/// înainte să se strice ceva. Două lucruri trebuie să fie adevărate mereu:
/// să nu crească la infinit (ajung într-un document Firestore) și să păstreze
/// ULTIMELE acțiuni, nu primele — cele dinainte de eroare sunt cele utile.
void main() {
  setUp(Breadcrumbs.clearForTest);

  test('păstrează ordinea, cea mai veche prima', () {
    Breadcrumbs.drop('unu');
    Breadcrumbs.drop('doi');
    final s = Breadcrumbs.snapshot();
    expect(s.length, 2);
    expect(s[0], contains('unu'));
    expect(s[1], contains('doi'));
  });

  test('nu crește la infinit — inelul se golește pe la coadă', () {
    for (var i = 0; i < 500; i++) {
      Breadcrumbs.drop('actiunea $i');
    }
    final s = Breadcrumbs.snapshot();
    // Plafonul din breadcrumbs.dart. Dacă se schimbă acolo, se schimbă aici —
    // dar NU are voie să dispară: fără el, o buclă de erori ar umfla raportul
    // peste limita de 1 MB a unui document Firestore.
    expect(s.length, lessThanOrEqualTo(80));
  });

  test('păstrează ULTIMELE acțiuni, nu primele', () {
    for (var i = 0; i < 200; i++) {
      Breadcrumbs.drop('actiunea $i');
    }
    final s = Breadcrumbs.snapshot();
    expect(s.last, contains('actiunea 199'));
    expect(s.any((l) => l.contains('actiunea 0')), isFalse,
        reason: 'cele vechi trebuie aruncate, altele n-ar mai incapea');
  });

  test('fiecare firimitură are un moment relativ la pornire', () {
    Breadcrumbs.drop('ceva');
    // Formatul „[m:ss] text" — se citește dintr-o privire în panoul de admin.
    expect(Breadcrumbs.snapshot().single, matches(r'^\[\d+:\d{2}\] ceva$'));
  });

  test('timpii CRESC — regresie din primul raport real de pe telefon', () {
    // Bug real, prins pe 2026-09-05 uitându-mă la primul raport trimis:
    //   [0:05] intra: /
    //   [0:39] intra: ecran
    //   [0:00] a cerut raport      <- cea mai recentă, dar cu timpul cel mai mic
    // Momentele se calculau la CITIRE, față de un reper inițializat leneș de
    // Dart abia la primul `snapshot()`. Acum se îngheață la adăugare.
    var now = DateTime(2026, 1, 1, 12, 0, 0);
    Breadcrumbs.clock = () => now;

    Breadcrumbs.drop('prima');
    now = now.add(const Duration(seconds: 5));
    Breadcrumbs.drop('a doua');
    now = now.add(const Duration(seconds: 34));
    Breadcrumbs.drop('a treia');

    // Citirea se face mult mai târziu — exact ca în viața reală, unde
    // raportul se compune la minute după primele acțiuni.
    now = now.add(const Duration(minutes: 3));
    final s = Breadcrumbs.snapshot();

    expect(s[0], '[0:00] prima');
    expect(s[1], '[0:05] a doua');
    expect(s[2], '[0:39] a treia');
  });

  test('trece corect de un minut', () {
    var now = DateTime(2026, 1, 1, 12, 0, 0);
    Breadcrumbs.clock = () => now;
    Breadcrumbs.drop('start');
    now = now.add(const Duration(seconds: 75));
    Breadcrumbs.drop('mai tarziu');
    expect(Breadcrumbs.snapshot().last, '[1:15] mai tarziu');
  });
}
