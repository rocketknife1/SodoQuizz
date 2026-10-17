import '../core/lang.dart';
import '../core/stable_hash.dart';
import 'culture_pool/arta.dart';
import 'culture_pool/diverse.dart';
import 'culture_pool/geografie.dart';
import 'culture_pool/istorie.dart';
import 'culture_pool/matematica.dart';
import 'culture_pool/muzica_film.dart';
import 'culture_pool/natura.dart';
import 'culture_pool/seed.dart';
import 'culture_pool/spatiu.dart';
import 'culture_pool/sport.dart';
import 'culture_pool/stiinta.dart';
import 'culture_pool/tehnologie.dart';

/// Întrebare de cultură generală — text simplu, fără imagine, 4 variante.
///
/// [question], [choices] și [answer] sunt textul CANONIC (română): toată
/// logica jocului (răspunsuri trimise în multiplayer, comparații, boți)
/// lucrează doar cu ele, ca un jucător pe engleză și unul pe română să poată
/// juca la aceeași masă. Pe ecran se afișează [text] și [label], care aleg
/// limba jucătorului.
class CultureQuestion {
  final String question;
  final List<String> choices;
  final String answer;
  final String? en;

  /// Aliniate pe index cu [choices]; null = la fel în engleză.
  final List<String>? choicesEn;

  const CultureQuestion({
    required this.question,
    required this.choices,
    required this.answer,
    this.en,
    this.choicesEn,
  });

  String get text => L10n.isEn && en != null ? en! : question;

  /// Varianta [choice] (canonică) în limba jucătorului.
  String label(String choice) {
    final translated = choicesEn;
    if (!L10n.isEn || translated == null) return choice;
    final i = choices.indexOf(choice);
    return i < 0 || i >= translated.length ? choice : translated[i];
  }

  /// Aceeași întrebare cu variantele în ordinea [order] (indici în [choices]).
  CultureQuestion reordered(List<int> order) => CultureQuestion(
        question: question,
        choices: [for (final i in order) choices[i]],
        answer: answer,
        en: en,
        choicesEn: choicesEn == null ? null : [for (final i in order) choicesEn![i]],
      );
}

const int cultureQuizQuestionCount = 10;
const int cultureSecondsPerQuestion = 12;

/// În sursă răspunsul corect e mereu primul; aici variantele se amestecă
/// determinist (aceeași ordine pe orice telefon și în browser), ca poziția
/// din fișier să nu ajungă niciodată pe ecran.
CultureQuestion _build(CultureSeed s) {
  final order = [for (var i = 0; i < s.choices.length; i++) i];
  stableShuffle(order, stableHash(s.ro));
  return CultureQuestion(
    question: s.ro,
    en: s.en,
    choices: s.choices,
    answer: s.choices.first,
    choicesEn: s.choicesEn,
  ).reordered(order);
}

/// Pool global unic de întrebări de cultură generală, cu întrebări din toată
/// lumea (nu centrat pe o țară), 11 teme × 50. Temele sunt doar structura
/// fișierelor sursă — jocul le amestecă pe toate.
final List<CultureQuestion> cultureQuestions = [
  for (final s in [
    ...poolGeografie,
    ...poolIstorie,
    ...poolStiinta,
    ...poolSpatiu,
    ...poolArta,
    ...poolMuzicaFilm,
    ...poolSport,
    ...poolNatura,
    ...poolTehnologie,
    ...poolDiverse,
    ...poolMatematica,
  ])
    _build(s),
];
