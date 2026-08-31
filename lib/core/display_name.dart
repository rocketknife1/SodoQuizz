/// Care nume se vede, când există mai multe surse.
///
/// Ordinea, și de ce:
///
///  1. `forcedName` — numele pus de administrator din panoul de Admin. Nu e o
///     pedeapsă și nu blochează nimic: jucătorul își poate pune oricând
///     altceva, moment în care numele impus se șterge (vezi
///     PlayerProfileService.releaseMyForcedName). Există doar ca redenumirea
///     să ȚINĂ până atunci — fără el, primul heartbeat al jucătorului i-ar
///     rescrie numele din identitatea locală și redenumirea s-ar evapora
///     singură în câteva minute.
///  2. numele ales chiar de jucător;
///  3. numele din contul Google, ca simplă valoare de pornire.
///
/// Șir gol înseamnă „nicio sursă" — apelantul cade atunci pe numele local
/// generat (vezi StorageService.getDisplayName).
///
/// E deliberat o funcție PURĂ, fără citiri de disc: sursele se citesc de
/// apelant. Așa se poate testa fiecare combinație fără SharedPreferences,
/// iar regula stă într-un singur loc în tot proiectul.
String resolveDisplayName({
  required String forcedName,
  required String chosenName,
  required String googleName,
}) {
  if (forcedName.trim().isNotEmpty) return forcedName.trim();
  if (chosenName.trim().isNotEmpty) return chosenName.trim();
  return googleName.trim();
}
