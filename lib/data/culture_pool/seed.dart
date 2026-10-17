/// O întrebare de cultură generală așa cum e scrisă în sursă, în română și
/// engleză. Varianta corectă e MEREU prima din [choices] — ordinea de pe
/// ecran se amestecă la construcție (vezi culture_questions.dart), deci
/// poziția din sursă nu ajunge niciodată la jucător.
class CultureSeed {
  const CultureSeed(this.ro, this.en, this.choices, [this.choicesEn]);

  final String ro;
  final String en;
  final List<String> choices;

  /// Aliniate pe index cu [choices]; null = la fel în engleză (nume, cifre).
  final List<String>? choicesEn;
}
