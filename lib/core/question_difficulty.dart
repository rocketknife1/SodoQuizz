import 'lang.dart';

/// Dificultatea unei întrebări, ESTIMATĂ DIN DATE — nu setată manual.
///
/// De ce nu manual: 1494 de întrebări, iar „mi se pare grea" e subiectiv și
/// des greșit. Așa că se derivă din
/// acuratețea reală a jucătorilor (95% corect → ușoară … 15% → extremă),
/// ajustată cu timpul mediu de răspuns, apoi corectate manual cazurile
/// bizare din Admin.
///
/// Semnalul se strânge în `question_stats/{id}` (vezi
/// data/question_stats_service.dart), alimentat din partidele single-player
/// (modul „învață conținutul" — cel mai curat, fără presiune de timp ca în
/// multiplayer). Sub [difficultyMinSample] răspunsuri, întrebarea e
/// `necalibrat` — nu inventăm o etichetă din 3 răspunsuri.

enum QuestionDifficulty { necalibrat, usoara, medie, grea, extrema }

/// Sub atâtea răspunsuri strânse, nu se dă nicio etichetă.
const int difficultyMinSample = 30;

/// Pragurile de acuratețe (procent corect) între trepte:
/// ~95% → ușoară, ~70% → medie, ~40% → grea, ~15% → extremă. Pragurile
/// efective sunt la mijlocul intervalelor.
const double _accEasy = 0.82; // ≥ → ușoară
const double _accMedium = 0.55; // ≥ → medie
const double _accHard = 0.28; // ≥ → grea; sub → extremă

/// Timp mediu de răspuns (ms) peste care o întrebare „se simte grea" chiar
/// dacă acuratețea o pune la limită — nudge cu o treaptă în sus. Sub pragul
/// rapid, nudge în jos.
const int _slowMs = 11000;
const int _fastMs = 3500;

/// [avgMs] = timpul mediu de la afișare la răspuns (orice răspuns, nu doar
/// corect). 0 dacă nu s-a măsurat — atunci nu se aplică niciun nudge.
QuestionDifficulty difficultyFromStats({
  required int shown,
  required int correct,
  required double avgMs,
}) {
  if (shown < difficultyMinSample) return QuestionDifficulty.necalibrat;
  final acc = correct / shown;
  var d = acc >= _accEasy
      ? QuestionDifficulty.usoara
      : acc >= _accMedium
          ? QuestionDifficulty.medie
          : acc >= _accHard
              ? QuestionDifficulty.grea
              : QuestionDifficulty.extrema;

  // Nudge pe timp — o singură treaptă, doar dacă e măsurat.
  if (avgMs > 0) {
    if (avgMs >= _slowMs && d.index < QuestionDifficulty.extrema.index) {
      d = QuestionDifficulty.values[d.index + 1];
    } else if (avgMs <= _fastMs && d.index > QuestionDifficulty.usoara.index) {
      d = QuestionDifficulty.values[d.index - 1];
    }
  }
  return d;
}

(String ro, String en) difficultyLabel(QuestionDifficulty d) => switch (d) {
      QuestionDifficulty.necalibrat => ('Necalibrat', 'Not calibrated'),
      QuestionDifficulty.usoara => ('Ușoară', 'Easy'),
      QuestionDifficulty.medie => ('Medie', 'Medium'),
      QuestionDifficulty.grea => ('Grea', 'Hard'),
      QuestionDifficulty.extrema => ('Extremă', 'Extreme'),
    };

String difficultyLabelTr(QuestionDifficulty d) {
  final (ro, en) = difficultyLabel(d);
  return tr(ro, en);
}
