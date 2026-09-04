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
  final DateTime cand;
  final String ce;
  const _Crumb(this.cand, this.ce);
}

class Breadcrumbs {
  Breadcrumbs._();

  /// Cât ține inelul. 80 acoperă câteva minute de joc real, iar la ~60 de
  /// caractere pe intrare înseamnă sub 5 KB — destul de puțin cât să încapă
  /// întreg într-un document Firestore, alături de restul raportului.
  static const int _max = 80;

  static final Queue<_Crumb> _ring = Queue<_Crumb>();

  /// Momentul pornirii, ca timpii din raport să fie relativi („la 0:42 de la
  /// pornire"), nu ore absolute care nu spun nimic.
  static final DateTime _start = DateTime.now();

  /// Notează o acțiune. [ce] trebuie să fie scurt și concret: „ecran: Joc",
  /// „raspuns corect", „firestore: permission-denied la profil".
  ///
  /// NU pune aici text scris de jucător, nume, sau conținut de mesaje —
  /// raportul ajunge în baza de date și nu are de ce să conțină date
  /// personale peste ce există deja.
  static void drop(String ce) {
    _ring.addLast(_Crumb(DateTime.now(), ce));
    while (_ring.length > _max) {
      _ring.removeFirst();
    }
  }

  /// Firimiturile, ca linii gata de citit, cele mai vechi întâi.
  /// Formatul „[m:ss] ce" se citește dintr-o privire în panoul de admin.
  static List<String> snapshot() => [
        for (final c in _ring) '[${_relativ(c.cand)}] ${c.ce}',
      ];

  static String _relativ(DateTime t) {
    final d = t.difference(_start);
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Doar pentru teste — starea globală trebuie să poată fi resetată între ele.
  static void clearForTest() => _ring.clear();
}
