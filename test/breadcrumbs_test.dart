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
}
