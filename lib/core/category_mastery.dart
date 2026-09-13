import 'dart:math';

/// Măiestria pe o categorie de quiz (#4 retenție) — cât de „stăpân" ești pe
/// conținutul unei categorii, ca ea să devină progres, nu combustibil
/// consumabil („mai joc să termin categoria", nu „mai joc pentru monede").
///
/// Datele brute (întrebări văzute / corecte / cel mai lung streak per
/// categorie) stau în StorageService.categoryStats. Aici e doar regula: de la
/// ce cifre e „stăpânită" o categorie și cum se împarte drumul în trepte
/// pentru bara de progres.

/// Câte răspunsuri (repetările contează) într-o categorie + ce acuratețe
/// minimă = „stăpânită". Pragul e generos la număr, dar cere să și nimerești
/// — altfel s-ar putea „măcina" o categorie greșind la nesfârșit.
const int masterySeenTarget = 60;
const double masteryMinAccuracy = 0.6;

bool isCategoryMastered({required int seen, required int correct}) {
  if (seen < masterySeenTarget) return false;
  return correct / seen >= masteryMinAccuracy;
}

/// 0.0–1.0 — cât din drumul spre „stăpânită" e făcut. Media geometrică a
/// volumului (câte întrebări din prag) și a acurateței (din pragul minim):
/// dacă oricare e 0, progresul e 0; ambele trebuie să crească.
double masteryProgress({required int seen, required int correct}) {
  if (seen == 0) return 0;
  final volume = (seen / masterySeenTarget).clamp(0.0, 1.0);
  final acc = (correct / seen / masteryMinAccuracy).clamp(0.0, 1.0);
  return sqrt(volume * acc);
}

/// Treapta afișată (0–5) — doar pentru eticheta scurtă de lângă categorie.
int masteryTier({required int seen, required int correct}) {
  if (isCategoryMastered(seen: seen, correct: correct)) return 5;
  final p = masteryProgress(seen: seen, correct: correct);
  return (p * 5).floor().clamp(0, 4);
}

const List<String> masteryTierLabelsRo = [
  'Novice', 'Începător', 'Descurcăreț', 'Priceput', 'Avansat', 'Stăpân',
];
const List<String> masteryTierLabelsEn = [
  'Novice', 'Beginner', 'Getting there', 'Skilled', 'Advanced', 'Master',
];
