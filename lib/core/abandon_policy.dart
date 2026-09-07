library;

/// Politica de abandon în multiplayer (#6 retenție).
///
/// Problema: un jucător care „își dă seama că pierde" închide aplicația, iar
/// adversarul rămâne agățat până la timeout. Fără nicio consecință, e mișcarea
/// optimă. Se leagă de filozofia anti-reluare (core/anti_replay / memoria
/// `guess-it-anti-replay`): dacă ai început, rezultatul contează.
///
/// Ce face:
///  - Ieșirea dintr-un meci încă `playing`, fără să-ți fi scris scorul final,
///    se înregistrează ca MECI PIERDUT (rating −[abandonRatingPenalty]).
///  - [abandonCooldownThreshold] abandonuri în [abandonWindow] → nu mai poți
///    intra în Meci Rapid [abandonCooldown]. Camerele cu cod rămân permise
///    (joci cu prietenii, nu strici coada publică).
///
/// Adversarul care ABANDONEAZĂ e deja gestionat: ecranul de rezultate așteaptă
/// maximum 12s scorul celuilalt, apoi decontează cu ce există (vezi
/// MultiplayerResultsScreen._awaitFinalScores) — deci supraviețuitorul câștigă
/// oricum. Aici se adaugă doar consecința pentru cel care pleacă.

const int abandonRatingPenalty = 12;
const int abandonCooldownThreshold = 3;
const Duration abandonWindow = Duration(hours: 1);
const Duration abandonCooldown = Duration(minutes: 10);

/// Cât timp de cooldown mai rămâne, dat fiind istoricul de abandonuri
/// ([timestamps], epoch ms) și [now]. `Duration.zero` dacă poți intra.
Duration abandonCooldownRemaining(List<int> timestamps, DateTime now) {
  final recent = timestamps
      .map((ms) => DateTime.fromMillisecondsSinceEpoch(ms))
      .where((t) => now.difference(t) < abandonWindow)
      .toList()
    ..sort();
  if (recent.length < abandonCooldownThreshold) return Duration.zero;
  // Cooldown-ul curge din momentul în care s-a atins pragul: al treilea
  // abandon în ordine cronologică (recent[2] la exact 3).
  final trigger = recent[abandonCooldownThreshold - 1];
  final ends = trigger.add(abandonCooldown);
  final left = ends.difference(now);
  return left.isNegative ? Duration.zero : left;
}
