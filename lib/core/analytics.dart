import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

// ─── Analytics: PUȚINE evenimente, alese ──────────────────────────────────
//
// Tentația la analytics e să trimiți tot „ca să avem". Aia nu e măsurare, e
// colectare — umple consola, îngreunează formularul Data safety și nu
// răspunde la nicio întrebare. Aici sunt doar evenimentele care răspund la
// întrebările care chiar contează după lansare:
//
//   „intră lumea și se întoarce?"      → retenția D1/D7, calculată automat
//                                         de Firebase din first_open + sesiuni
//   „ajung să joace, sau se pierd?"    → gameStarted vs gameFinished
//   „ce moduri sunt de fapt folosite?" → parametrul `mod`
//   „economia se mișcă?"               → categoryUnlocked, wheelSpun
//
// Reperele publice pentru un joc: D1 sănătos e 25-33%, D7 e 6-14%. Sub 20%
// la D1 se repară onboarding-ul înaintea oricărui alt lucru.
//
// PE WEB MERGE (spre deosebire de Crashlytics), deci acoperă și browserul.
//
// ATENȚIE la Data safety: din clipa în care astea pleacă de pe telefon,
// formularul din Play Console trebuie retrimis. Nu se trimite nimic personal
// aici — doar ce mod a jucat cineva, nu cine.

class Analytics {
  Analytics._();
  static final Analytics instance = Analytics._();

  FirebaseAnalytics? _a;

  /// Se apelează după `Firebase.initializeApp`. Dacă pică, aplicația merge
  /// mai departe fără măsurători — un joc nu are voie să nu pornească
  /// fiindcă n-a mers analytics.
  void init() {
    try {
      _a = FirebaseAnalytics.instance;
    } catch (e) {
      debugPrint('Analytics.init a esuat: $e');
    }
  }

  /// Observatorul care numără automat ecranele vizitate. Se pune o singură
  /// dată, pe `MaterialApp.navigatorObservers` — fără el ar trebui adăugată
  /// o linie în fiecare din cele 33 de ecrane.
  FirebaseAnalyticsObserver? get observer =>
      _a == null ? null : FirebaseAnalyticsObserver(analytics: _a!);

  void _log(String name, [Map<String, Object>? params]) {
    final a = _a;
    if (a == null) return;
    // Nu `await`: o măsurătoare nu are voie să încetinească jocul, iar dacă
    // pică nu se schimbă nimic pentru jucător.
    a.logEvent(name: name, parameters: params).catchError((Object e) {
      debugPrint('Analytics.$name a esuat: $e');
    });
  }

  /// La singleplayer, categoria ESTE modul (`gameModeId`: cartoon, logouri,
  /// matematica...), deci un singur parametru — nu doi identici.
  void gameStarted(String categorie) =>
      _log('joc_start', {'categorie': categorie});

  void gameFinished({
    required String categorie,
    required int corecte,
    required int total,
  }) =>
      _log('joc_final',
          {'categorie': categorie, 'corecte': corecte, 'total': total});

  void categoryUnlocked(String categorie) =>
      _log('categorie_deblocata', {'categorie': categorie});

  void multiplayerStarted(String mod) => _log('mp_start', {'mod': mod});

  void multiplayerFinished({required String mod, required bool castigat}) =>
      _log('mp_final', {'mod': mod, 'castigat': castigat ? 1 : 0});

  void wheelSpun() => _log('roata_rotita');

  void planetRun() => _log('planeta_rulare');
}
