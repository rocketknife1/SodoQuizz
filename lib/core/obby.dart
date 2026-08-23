/// Regulile modului multiplayer **Obby** — o cursă de obstacole tip Roblox,
/// de la 2 la 6 personaje pe aceeași pistă, filmate din spate (3rd-person).
///
/// Runda, în TREI pași:
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

/// Câți jucători încap într-o cameră de Obby.
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
/// [MatchPlayer.score] (vezi models/multiplayer_models.dart).
const int obbyPointsPerObstacle = 10;

/// Monede acordate INSTANT, în telefon, la fiecare răspuns corect — din
/// planul de viitor (punctul 4): recompensa vizibilă DOAR la finalul
/// meciului nu se simte, la 13-20 ani miza imediată motivează mai mult decât
/// progresul pe termen lung. Complet separată de miza/premiile meciului
/// ([MultiplayerService.recordCompletedMatch] etc.) — nu atinge economia
/// mizelor, doar balanța locală a jucătorului, exact ca o recompensă de
/// quest. Mică intenționat (nu 10x mai mare ca o monedă de quest ușor):
/// se adună pe durata unui meci întreg (7 runde), nu e menită să înlocuiască
/// vreo altă sursă de venit.
const int obbyInstantCoinsPerCorrect = 2;

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

/// Cele două variante care rămân pe ecran când jucătorul are bonusul aprins
/// ([MatchPlayer.nextQuestionBonus], câștigat sărind pe o placă bună în runda
/// precedentă): răspunsul corect plus UNA singură dintre cele greșite.
///
/// Se calculează pe client, determinist, la fel ca [obbyFakePlatformIndex] —
/// nu se scrie nimic în Firestore. Sufixul `#bonus` ține sămânța separată
/// atât de cea a plăcii false, cât și de cea a amestecării variantelor, ca
/// din una să nu se poată deduce alta.
///
/// Ancorat pe [playerId] dinadins: doi jucători cu bonus în aceeași rundă
/// rămân, de regulă, cu variante greșite diferite, deci nu-și pot spune unul
/// altuia care e răspunsul „prin eliminare".
///
/// Dacă [correctAnswer] nu e în [choices] (n-ar trebui să se întâmple), se
/// întorc toate variantele neatinse: mai bine o întrebare fără bonus decât
/// una din care lipsește răspunsul bun.
List<String> obbyBonusChoices({
  required List<String> choices,
  required String correctAnswer,
  required String matchId,
  required int roundIndex,
  required String playerId,
}) {
  if (!choices.contains(correctAnswer)) return List.of(choices);
  final wrong = choices.where((c) => c != correctAnswer).toList();
  if (wrong.isEmpty) return List.of(choices);
  final seed = stableHash('$matchId#$roundIndex#$playerId#bonus');
  final kept = [correctAnswer, wrong[seed % wrong.length]];
  stableShuffle(kept, seed);
  return kept;
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

// ─── Evenimente de rundă ────────────────────────────────────────────────
//
// Din planul de viitor (PLAN_DE_VIITOR.md, punctul 3): bucla "răspunzi →
// alegi → sari" devine previzibilă după 3-4 meciuri, chiar dacă are trei
// pași — creierul memorează tiparul, nu evenimentul. Cele două de mai jos
// sunt pilotul cerut acolo, pe Obby: rup tiparul FĂRĂ niciun câmp nou în
// Firestore, calculate determinist pe client, la fel ca placa falsă.
//
// Nu se pot suprapune pe aceeași rundă: [obbyIsComebackRound] e ancorat pe
// un singur index fix (penultima rundă), iar [obbyIsDoubleRound] îl
// exclude explicit, ca ultimele două runde ale unui meci să nu adune două
// reguli speciale deodată — exact acolo unde jucătorii sunt deja concentrați
// pe rezultatul final, nu e locul unde vrei să introduci ȘI o mecanică nouă.

/// Runda [roundIndex] a meciului [matchId] e o "rundă dublă"? Cine sare cu
/// bine trece DOUĂ obstacole deodată, nu unul — vezi
/// MultiplayerService.resolveObbyChoices, unde se aplică efectiv.
///
/// Exclusă din prima rundă (nimeni n-are încă senzația jocului, deci un
/// bonus dublu ar trece neobservat) și din ultimele două (finalul rămâne
/// previzibil ca regulă de bază — [obbyIsComebackRound] e evenimentul
/// special de acolo). Șansă 1 din 3 pe fiecare rundă eligibilă.
bool obbyIsDoubleRound({
  required String matchId,
  required int roundIndex,
}) {
  if (roundIndex <= 0 || roundIndex >= obbyObstacleCount - 2) return false;
  return stableHash('$matchId#$roundIndex#doubleround') % 3 == 0;
}

/// Penultima rundă a meciului — momentul "a doua șansă" din plan: oricine e
/// pe ultimul loc la începutul acestei runde primește automat bonusul de
/// alegere (2 variante din 4, [obbyBonusChoices]) la runda AGL, indiferent
/// cum a ieșit placa lui în runda asta. Vezi
/// MultiplayerService.resolveObbyChoices pentru cum se acordă.
///
/// Un singur index fix, nu probabilistic: evenimentul trebuie să se întâmple
/// mereu, ca ultimul din clasament să aibă mereu o șansă reală înainte de
/// runda finală — o monedă aruncată aici ar fi însemnat că, la ghinion, nimeni
/// nu-l mai prinde din urmă niciodată.
bool obbyIsComebackRound({required int roundIndex}) => roundIndex == obbyObstacleCount - 2;

/// Cine e "ultimul din clasament" la [obbyIsComebackRound] — cei cu cel mai
/// puțin [obstaclesCleared] dintre jucătorii încă activi ([obstaclesCleared]
/// sub [obbyObstacleCount]). Poate întoarce mai mulți id-uri deodată (toți
/// legați la egalitate) — niciunul din ei nu are voie să rămână fără șansă
/// doar fiindcă altcineva a fost tras la sorți primul.
///
/// [activePlayers] sunt perechi (id, obstaclesCleared) — funcția nu citește
/// Firestore, ca să rămână testabilă pur, la fel ca restul fișierului.
List<String> obbyLastPlaceIds(Iterable<(String, int)> activePlayers) {
  final active = activePlayers.where((p) => p.$2 < obbyObstacleCount).toList();
  if (active.isEmpty) return const [];
  final minCleared = active.map((p) => p.$2).reduce((a, b) => a < b ? a : b);
  return [for (final p in active) if (p.$2 == minCleared) p.$1];
}
