import 'dart:collection';

// ─── Urma de firimituri: ce s-a întâmplat ÎNAINTE de eroare ───────────────
//
// Un raport de eroare care spune doar „a crăpat la linia 412" e aproape
// inutil: nu știi ce făcea omul, de unde venea, ce încercase. Firimiturile
// sunt jurnalul rulant al ultimelor acțiuni — ecrane deschise, butoane
// apăsate, cereri picate — păstrat DOAR în memorie.
//
// De ce în memorie și nu trimise pe rând: o firimitură nu costă nimic (o
// linie într-o listă mărginită), deci se poate pune în mult mai multe locuri
// decât un raport de rețea. Când chiar se strică ceva, jurnalul e deja scris.
//
// Se golește la fiecare pornire — asta e intenția: interesează ce s-a
// întâmplat în sesiunea în care a apărut problema, nu istoria contului.

class _Crumb {
  /// Momentul, calculat CÂND SE ADAUGĂ, nu când se citește lista.
  ///
  /// Prima versiune îl calcula la citire, față de un `_start` inițializat
  /// leneș de Dart — adică abia la primul `snapshot()`. Ieșeau timpi în
  /// dezordine („0:39" urmat de „0:00" pentru o acțiune mai recentă),
  /// exact pe primul raport real trimis de pe telefon. Momentul aparține
  /// firimiturii, deci se îngheață odată cu ea.
  final String at;
  final String what;
  const _Crumb(this.at, this.what);
}

class Breadcrumbs {
  Breadcrumbs._();

  /// Cât ține inelul. 80 acoperă câteva minute de joc real, iar la ~60 de
  /// caractere pe intrare înseamnă sub 5 KB — destul de puțin cât să încapă
  /// întreg într-un document Firestore, alături de restul raportului.
  static const int _max = 80;

  static final Queue<_Crumb> _ring = Queue<_Crumb>();

  /// Ceasul, ca testele să poată controla trecerea timpului. În aplicație e
  /// mereu `DateTime.now`.
  static DateTime Function() clock = DateTime.now;

  /// Momentul primei firimituri — reperul față de care se măsoară restul.
  /// Setat EXPLICIT la prima adăugare, nu lăsat pe inițializarea leneșă.
  static DateTime? _start;

  /// Notează o acțiune. [what] trebuie să fie scurt și concret: „ecran: Joc",
  /// „raspuns corect", „firestore: permission-denied la profil".
  ///
  /// NU pune aici text scris de jucător, nume, sau conținut de mesaje —
  /// raportul ajunge în baza de date și nu are de ce să conțină date
  /// personale peste ce există deja.
  static void drop(String what) {
    final now = clock();
    _start ??= now;
    _ring.addLast(_Crumb(_format(now.difference(_start!)), what));
    while (_ring.length > _max) {
      _ring.removeFirst();
    }
  }

  /// Firimiturile, ca linii gata de citit, cele mai vechi întâi.
  /// Formatul „[m:ss] ce" se citește dintr-o privire în panoul de admin.
  static List<String> snapshot() =>
      [for (final c in _ring) '[${c.at}] ${c.what}'];

  static String _format(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Doar pentru teste — starea globală trebuie să poată fi resetată.
  static void clearForTest() {
    _ring.clear();
    _start = null;
    clock = DateTime.now;
  }
}
