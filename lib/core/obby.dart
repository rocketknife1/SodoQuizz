/// Regulile modului multiplayer **Obby** — o cursă de obstacole tip Roblox,
/// de la 2 la 6 personaje pe aceeași pistă, filmate din spate (3rd-person).
///
/// Runda, în TREI pași (spre deosebire de Astro Sodo, care are doar doi):
///   1. **Răspuns** — toți cei care n-au terminat încă văd aceeași întrebare
///      de cultură generală și au [obbyRoundSeconds] secunde. Cine are
///      [MatchPlayer.nextQuestionBonus] aprins din runda trecută vede doar 2
///      variante din 4.
///   2. **Alegere** ([RoundPhase.choosing]) — doar cei care au răspuns corect
///      aleg, în [obbyChoiceSeconds] secunde, pe care din cele
///      [obbyPlatformChoiceCount] plăci din fața lor sar. Una singură e
///      falsă (vezi [obbyFakePlatformIndex]). Faza se sare complet dacă
///      nimeni n-a răspuns corect.
///   3. **Deznodământ** ([RoundPhase.revealed]) — camera arată cine a sărit
///      cu bine (obstacol trecut + bonus la întrebarea următoare) și cine a
///      căzut prin placa falsă (niciun progres). Ține
///      [obbyRevealSeconds] înainte ca runda următoare să înceapă automat.
///
/// Meciul se termină fie când un personaj trece de ultimul obstacol
/// (victorie instantă), fie la epuizarea celor [obbyObstacleCount] runde,
/// caz în care clasamentul final se face după [obstaclesCleared]/scor —
/// vezi MultiplayerService.resolveObbyChoices.
library;

import 'stable_hash.dart';

/// Câte obstacole are pista — și, deci, câte întrebări are un meci întreg.
///
/// A fost 5 cât timp o rundă însemna doar „răspunzi corect, sari". De când
/// runda are și pasul de alegere a plăcii, o rundă ține ~22s în loc de ~15s,
/// deci numărul a fost ales ca meciul să rămână sub ~2 minute și jumătate.
const int obbyObstacleCount = 7;

/// Câți jucători încap într-o cameră de Obby — la fel ca Astro Sodo.
const int obbyMaxPlayers = 6;

/// Cât timp are fiecare rundă înainte ca cei ce n-au răspuns încă să fie
/// scorați automat ca greșit.
const int obbyRoundSeconds = 12;

/// Cât timp au cei care au răspuns corect ca să-și aleagă placa. Cine nu
/// alege deloc e tratat ca și cum ar fi nimerit placa falsă: fără progres.
/// Scurt intenționat — e o decizie de reflex, nu una de calcul.
const int obbyChoiceSeconds = 5;

/// Cât rămâne vizibilă scena de 3rd-person (săritura reușită sau căderea),
/// înainte ca runda următoare să înceapă automat.
const int obbyRevealSeconds = 5;

/// Câte plăci apar în fața jucătorului la pasul de alegere — trei, ca să se
/// mapeze natural pe stânga/centru/dreapta.
const int obbyPlatformChoiceCount = 3;

/// Câte din cele [obbyPlatformChoiceCount] plăci sunt false. Cu 1 din 3,
/// șansa de reușită e 2/3 — destul cât riscul să se simtă, fără ca progresul
/// să depindă mai mult de noroc decât de răspunsuri.
const int obbyFakePlatformCount = 1;

/// Puncte acordate pentru fiecare obstacol trecut — hrănește direct
/// [MatchPlayer.score] (vezi models/multiplayer_models.dart), la fel ca
/// [astroSodoPointsPerObstacle].
const int obbyPointsPerObstacle = 10;

/// Care din cele [obbyPlatformChoiceCount] plăci e falsă pentru jucătorul
/// [playerId], în runda [roundIndex] a meciului [matchId].
///
/// NU se scrie nicăieri și nu costă niciun drum până la server: fiecare
/// client îl calculează identic, pentru ORICE jucător de la masă (nu doar
/// pentru el însuși — scena de deznodământ trebuie să anime căderea tuturor).
/// Același principiu ca la amestecarea întrebărilor, vezi core/stable_hash.dart
/// pentru de ce nu merge nici `String.hashCode`, nici `Random(seed)`.
///
/// Sufixul `#platform` ține sămânța asta separată de cea folosită la
/// amestecarea variantelor de răspuns (`'$matchId#$roundIndex'`), ca cele
/// două să nu se poată corela.
///
/// Se calculează pe client, deci un client modificat ar putea afla dinainte
/// placa falsă — dar asta nu deschide nicio portiță nouă: răspunsurile
/// corecte ajung oricum în clar pe fiecare telefon (culture_questions.dart),
/// iar proiectul n-are Cloud Functions. Același model de încredere ca restul
/// multiplayer-ului.
int obbyFakePlatformIndex({
  required String matchId,
  required int roundIndex,
  required String playerId,
}) =>
    stableHash('$matchId#$roundIndex#$playerId#platform') % obbyPlatformChoiceCount;

/// A scăpat jucătorul cu bine de pe placa aleasă?
///
/// [chosenIndex] e `null` când n-a ales deloc (AFK în faza de alegere) —
/// tratat exact ca AFK în faza de răspuns: fără progres. Altfel, reușește
/// dacă a nimerit oricare placă în afară de cea falsă.
bool obbyChoiceIsSafe({
  required int? chosenIndex,
  required int fakeIndex,
}) {
  if (chosenIndex == null) return false;
  if (chosenIndex < 0 || chosenIndex >= obbyPlatformChoiceCount) return false;
  return chosenIndex != fakeIndex;
}

/// S-a terminat meciul după runda [roundIndex]?
///
/// Două motive, ambele deja folosite de resolverul de azi: cineva a trecut de
/// ultimul obstacol (victorie instantă), sau s-au epuizat rundele.
bool obbyMatchIsOver({
  required int roundIndex,
  required Iterable<int> obstaclesClearedPerPlayer,
}) {
  final anyFinished = obstaclesClearedPerPlayer.any((c) => c >= obbyObstacleCount);
  final outOfRounds = roundIndex + 1 >= obbyObstacleCount;
  return anyFinished || outOfRounds;
}
