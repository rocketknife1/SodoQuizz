/// Regulile modului multiplayer **Scaunul Electric** — până la
/// [electricChairPlayerCount] jucători, vieți individuale, iar cine
/// răspunde corect la propria întrebare capătă dreptul să pună pe altcineva
/// pe scaun.
///
/// Runda, în patru pași:
///   1. **Răspuns** — toți cei rămași în viață văd aceeași întrebare și au
///      [electricChairAnswerSeconds] secunde. Cine răspunde corect capătă
///      dreptul de a alege o victimă.
///   2. **Alegere** — fiecare care a răspuns corect alege, în
///      [electricChairTargetSeconds] secunde, PE CINE pune pe scaun și CU CE
///      întrebare (una din patru oferite, vezi ecranul) — alegerea
///      întrebării contează la fel de mult ca alegerea victimei: cu cât
///      întrebarea e mai grea, cu atât victima riscă mai mult.
///   3. **Scaunul** — fiecare victimă răspunde, în [electricChairSeconds]
///      secunde, la întrebarea care i-a fost aleasă.
///   4. Cine răspunde corect scapă neatins. Cine greșește — sau nu apucă să
///      răspundă — pierde o viață. La zero vieți e eliminat, dar rămâne la
///      masă ca spectator, exact ca la celelalte moduri cu eliminare.
///
/// DACĂ ACEEAȘI VICTIMĂ E ALEASĂ DE MAI MULȚI DEODATĂ (posibil — fiecare
/// atacator alege independent), victima NU trece mai multe teste: se
/// combină într-unul singur, cu întrebarea celui cu uid-ul cel mai mic
/// dintre atacatori (departajaj determinist, ca toți clienții să aleagă
/// aceeași întrebare). Dacă victima greșește, TOȚI atacatorii care au ales-o
/// primesc credit — n-are sens să se certe cine "a nimerit-o cu adevărat"
/// când amândoi au tras la sorți aceeași sfoară.
///
/// `score` NU decide singur clasamentul final. PRIMA încercare (scrisă în
/// aceeași sesiune) acorda puncte de supraviețuire în FIECARE rundă direct
/// în `score`, mizând pe faptul că ponderea per-rundă domina orice punct de
/// acțiune posibil într-o rundă. Revizuirea a găsit greșeala: un jucător
/// foarte activ, eliminat MAI DEVREME, tot putea depăși la scor pe cineva
/// care a supraviețuit doar câteva runde în plus — diferența se acumulează
/// pe TOT meciul, nu pe o rundă (vezi test/electric_chair_test.dart pentru
/// contraexemplul exact). Corecția: `score` rămâne un scor mic, de acțiune
/// pură (răspunsuri + șocuri + apărări reușite — aceeași scară ca la Quizz
/// Tanks, bun pentru XP), iar cine a rezistat mai mult se ține separat, în
/// [MatchPlayer.eliminatedAtRound]. Clasamentul final (vezi
/// MultiplayerResultsScreen) sortează după [electricChairRankKey], NU după
/// `score` brut — acolo se combină cele două într-o cheie care GARANTEAZĂ
/// ordinea "ultimul rămas în viață", fără să umfle scorul folosit pentru XP.
library;

import 'multiplayer_round.dart';
import 'powerups.dart';

/// Câți jucători încap într-o cameră de Scaunul Electric. Urcat de la 5 la
/// 10 la cererea explicită a userului (toate modurile trebuie să accepte
/// 10) — lista de victime posibile și cea de spectatori de pe scaun sunt
/// deja liste derulabile (vezi MultiplayerElectricChairScreen), deci
/// generalizează fără nicio schimbare de layout.
const int electricChairPlayerCount = 10;

/// Vieți de start ale fiecărui jucător. La zero, eliminat (spectator).
const int electricChairMaxLives = 8;

/// Cât are fiecare la dispoziție ca să răspundă la propria întrebare —
/// comun tuturor modurilor cu rundă sincronizată, vezi
/// core/multiplayer_round.dart.
const int electricChairAnswerSeconds = sharedRoundAnswerSeconds;

/// Cât durează alegerea: victimă + una din patru întrebări pentru ea.
const int electricChairTargetSeconds = 14;

/// Cât are victima la dispoziție ca să răspundă la întrebarea aleasă pentru
/// ea. Puțin mai scurt decât [electricChairAnswerSeconds] — miza e mai mare
/// (o viață), dar întrebarea nu e mai grea decât una obișnuită, deci nu
/// merită mai mult timp de citit.
const int electricChairSeconds = 10;

/// Câte întrebări i se oferă unui atacator din care să aleagă UNA pentru
/// victima lui.
const int electricChairCandidateCount = 4;

/// Cât ține ecranul de deznodământ (cine a scăpat, cine a picat la scaun)
/// înainte ca runda următoare să înceapă automat.
const int electricChairRevealSeconds = 5;

/// Varianta scurtă, când nimeni n-a fost pus pe scaun (nimeni n-a răspuns
/// corect la propria întrebare) — n-are ce se anima, doar răspunsul corect
/// de citit.
const int electricChairEmptyRevealSeconds = 3;

int electricChairRevealSecondsFor({required bool anyoneTested}) =>
    anyoneTested ? electricChairRevealSeconds : electricChairEmptyRevealSeconds;

/// Plafon de runde, ca un meci în care nimeni nu mai nimerește nimic să nu
/// rămână agățat la nesfârșit.
const int electricChairMaxRounds = 40;

/// Punct pentru răspunsul corect la PROPRIA întrebare — se acordă indiferent
/// dacă atacatorul apucă să și aleagă o victimă, ca să nu descurajeze pe
/// nimeni să răspundă corect doar fiindcă n-are pe cine ținti (ex. doar doi
/// rămași).
const int electricChairPointsPerAnswer = 1;

/// Punct pentru un atacator al cărui șoc a reușit (victima a greșit
/// întrebarea aleasă de el). Dacă mai mulți au ales aceeași victimă și ea a
/// greșit, TOȚI primesc acest punct — vezi comentariul din capul fișierului.
const int electricChairPointsPerShock = 2;

/// Punct pentru victima care a scăpat (a răspuns corect întrebării alese
/// pentru ea).
const int electricChairPointsPerDefense = 1;

/// Maximul teoretic de puncte de ACȚIUNE pe care le poate primi UN SINGUR
/// jucător într-o SINGURĂ rundă — nu doar [electricChairPointsPerAnswer] +
/// [electricChairPointsPerShock]: un jucător poate fi ȘI atacator (a ales pe
/// altcineva) ȘI victimă (a fost ales de altcineva) în ACEEAȘI rundă, deci
/// se pot aduna toate trei. Ținut ca o cifră proprie, nu recalculat pe
/// undeva, ca [electricChairRankKeyRoundWeight] să nu rămână în urmă dacă
/// vreuna din cele trei constante de mai sus se schimbă.
const int electricChairMaxActionPointsPerRound =
    electricChairPointsPerAnswer + electricChairPointsPerShock + electricChairPointsPerDefense;

/// Ponderea unei runde de supraviețuire în [electricChairRankKey] — TREBUIE
/// să depășească [electricChairMaxActionPointsPerRound] înmulțit cu
/// [electricChairMaxRounds] (maximul absolut de puncte de acțiune
/// acumulabile într-un meci întreg), nu doar punctele unei singure runde:
/// altfel un jucător foarte activ, eliminat cu o rundă mai devreme, tot ar
/// putea prinde din urmă pe cineva care a rezistat doar puțin mai mult —
/// vezi comentariul din capul fișierului. Rotunjită generos în sus (1000),
/// ca marja să rămână confortabilă chiar dacă vreuna din constantele de mai
/// sus urcă.
const int electricChairRankKeyRoundWeight = 1000;

/// Cheia de clasare finală a unui jucător — folosită de
/// MultiplayerResultsScreen ÎN LOC de `score` brut, ca sortarea să respecte
/// GARANTAT regula modului ("ultimul rămas în viață" pe primul loc),
/// indiferent cât de activ a fost oricine în timpul meciului.
///
/// [eliminated] + [eliminatedAtRound] vin direct din [MatchPlayer]; pentru
/// cineva încă în viață la finalul meciului (fie CÂȘTIGĂTORUL, fie unul din
/// mai mulți supraviețuitori dacă s-a atins [electricChairMaxRounds]),
/// rundele „supraviețuite" se citesc ca maximul posibil — a rezistat cel
/// puțin atât.
///
/// [score] intră DOAR ca departajaj în interiorul aceleiași runde de
/// eliminare (de-aia ponderea rundei trebuie să domine orice sumă posibilă
/// de scor, nu doar valoarea lui într-o rundă).
int electricChairRankKey({
  required bool eliminated,
  required int eliminatedAtRound,
  required int score,
}) {
  final roundsSurvived = eliminated ? eliminatedAtRound : electricChairMaxRounds;
  return roundsSurvived * electricChairRankKeyRoundWeight + score;
}

// ─── Deznodământul unei victime de pe scaun (logica pură) ───────────────────

/// Ce i se întâmplă unei victime când i se închide testul de pe scaun.
enum ChairVerdict {
  /// A răspuns corect (sau a fost apărată de un scut) — scapă neatinsă,
  /// primește puncte de apărare.
  survived,

  /// A greșit — pierde viață/vieți (scaunul, [RoundEvent.overcharge]).
  shocked,

  /// Are [PowerUp.reflect]: scapă, dar șocul se întoarce spre atacatori —
  /// fiecare pierde o viață, iar victima NU ia puncte de apărare
  /// (n-a răspuns, doar a avut noroc de power-up).
  reflected,
}

/// Decide verdictul unei victime, PUR — vezi
/// MultiplayerService.resolveElectricChairRound pentru cine aplică efectiv
/// vieți/puncte pe baza lui.
///
///  - [answeredCorrectly] — a nimerit răspunsul de pe scaun.
///  - [hasShield] — [PowerUp.shield] propriu activ runda asta.
///  - [allyShielded] — sub [PowerUp.allyShield] pus de altcineva.
///  - [anyAttackerPiercing] — vreun atacator din test are
///    [PowerUp.piercingShock] (trece prin orice scut).
///  - [hasReflect] — [PowerUp.reflect] propriu.
ChairVerdict chairVerdict({
  required bool answeredCorrectly,
  required bool hasShield,
  required bool allyShielded,
  required bool anyAttackerPiercing,
  required bool hasReflect,
}) {
  if (answeredCorrectly) return ChairVerdict.survived;
  if (!anyAttackerPiercing && (hasShield || allyShielded)) return ChairVerdict.survived;
  if (hasReflect) return ChairVerdict.reflected;
  return ChairVerdict.shocked;
}
