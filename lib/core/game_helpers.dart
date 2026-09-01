import 'dart:math';
import 'package:flutter/material.dart';
import 'stable_hash.dart';

const int maxHintsPerQuestion = 3;

/// Claritatea imaginii, ca fracție 0..1, indexată DIRECT după numărul de
/// hint-uri folosite (index 0 = fără niciun hint). Începe deja foarte
/// clară (90%), ca poza să fie ușor de distins de la start, apoi crește
/// progresiv cu fiecare hint. Claritate 100% strictă doar după răspuns
/// (vezi [BlurImage.revealed]).
const List<double> hintExposureStages = [0.90, 0.93, 0.95, 0.97];
double get maxHintExposure => hintExposureStages.last;

/// Cât de "expusă" (clară) e imaginea, ca fracție 0..maxHintExposure —
/// indexată direct după [hintsUsed] (0 = fără hint = claritatea de start).
double resolveHintExposure(int hintsUsed) {
  final i = hintsUsed.clamp(0, hintExposureStages.length - 1);
  return hintExposureStages[i];
}

// ─── Costul unui hint ──────────────────────────────────────────────────────
// Înainte: 1 hint din stoc + ~20% din punctele întrebării scăzute din scorul
// de sesiune — un cost invizibil (scorul nu e o resursă pe care o ții), deci
// practic simbolic. Acum: 1 hint din stoc + o taxă REALĂ în monede, care
// scalează cu averea curentă.
//
// Proprietățile cerute la reproiectare:
//  • nu te lasă niciodată în pagubă — minimul (6) e sub recompensa oricărei
//    întrebări (12+ monede), deci hint + răspuns corect rămâne mereu profit
//    net; iar dacă ai mai puțin decât costul, plătești exact cât ai (nu
//    intri în datorie și nu ești blocat);
//  • nu doare — la plafon reprezintă 3,7% din avere;
//  • rămâne un cost real — 12 hint-uri pe zi la 1.000 de monede înseamnă
//    444 de monede, adică ~15% dintr-o zi de joc activ.

const double hintCostWalletRatio = 0.037;
const int hintCostMin = 6;
const int hintCostMax = 89;

int hintCoinCost(int coins) {
  final scaled =
      (coins * hintCostWalletRatio).round().clamp(hintCostMin, hintCostMax);
  return scaled > coins ? coins : scaled;
}

// ─── Multiplayer Clasic: cronometru, hint 50/50, penalizări ────────────────
// Modul Clasic din multiplayer nu avea nici limită de timp (meciul rula prin
// TOATE întrebările din joc, deci nu se termina niciodată de la sine), nici
// hint, nici vreo consecință pentru un răspuns greșit — se putea bate la
// nimereală în ecran fără să coste nimic.
//
// Acum: un singur minut, același pentru toți, iar fiecare acțiune are preț.
// Penalizările sunt PROCENT din valoarea întrebării, nu sume fixe: altfel a
// greși la o întrebare de 1000p ar costa exact cât la una de 200p, iar
// hint-ul pe întrebările mari ar fi fost aproape gratis.

const int multiplayerMatchSeconds = 60;

/// Câte hint-uri are fiecare jucător pe meci, maximum unul pe întrebare.
///
/// NU se scad din stocul de hint-uri al jucătorului și NU costă monede, spre
/// deosebire de modul solo — și e o decizie deliberată, nu o scăpare:
/// magazinul vinde hint-uri, iar într-un mod unde monedele chiar trec dintr-un
/// buzunar în altul prin pariuri, cine cumpără hint-uri ar câștiga sistematic
/// mai mult. Toată lumea intră în meci cu exact aceleași unelte; singurul preț
/// al hint-ului sunt punctele.
const int multiplayerHintsPerMatch = 2;

/// Costul în puncte al hint-ului 50/50 (ascunde două variante greșite).
/// Calibrat împreună cu [multiplayerWrongPenalty] astfel încât hint-ul să fie
/// rentabil DOAR sub ~70% siguranță pe răspuns: dacă știi răspunsul, hint-ul e
/// pierdere curată; dacă habar n-ai, te scoate din minus.
int multiplayerHintPenalty(int maxPoints) => (7 + maxPoints * 0.23).round();

/// Costul în puncte al unui răspuns greșit. La 4 variante, valoarea așteptată
/// a unei ghiciri oarbe rămâne ușor negativă (−15 puncte la o întrebare de
/// 200p), deci spam-ul pe butoane pierde — dar o greșeală sinceră nu îngroapă
/// meciul.
int multiplayerWrongPenalty(int maxPoints) => (13 + maxPoints * 0.37).round();

// ─── Recompensa unui răspuns corect ────────────────────────────────────────
// XP-ul NU mai e egal cu punctele întrebării (era 140-200 XP per răspuns,
// motivul real pentru care se ajungea la nivelul 5 în 16 răspunsuri corecte —
// vezi xpForLevel din progression.dart). Punctele rămân neschimbate: ele
// hrănesc în continuare scorul de sesiune, recordul și clasamentul.

int xpForCorrectAnswer(int maxPoints) => (4 + maxPoints * 0.033).round();

int coinsForCorrectAnswer(int maxPoints) => (3 + maxPoints * 0.043).round();

/// Multiplicator pe serie de răspunsuri corecte consecutive, aplicat ȘI pe
/// monede ȘI pe XP — plătește priceperea fără să ridice podeaua economiei
/// (cine greșește des rămâne exact pe baza de mai sus).
double streakMultiplier(int streak) {
  if (streak >= 12) return 1.79;
  if (streak >= 8) return 1.58;
  if (streak >= 5) return 1.34;
  if (streak >= 3) return 1.17;
  return 1.0;
}

// Quiz Nelimitat a fost ELIMINAT pe 2026-08-05, împreună cu ratele lui
// (0,58× / 0,19× peste 43 de corecte pe zi). Era singurul mod fără nicio
// limită: se putea juca la nesfârșit, deci plata pe întrebare trebuia ținută
// artificial sub baseline ca să nu devină cea mai bună sursă din joc doar
// prin volum. Planeta hologramelor (vezi progression.dart) i-a luat locul cu
// exact soluția opusă — rulări scurte, rare și bine plătite.

// ─── Cultură Generală ("Daily Challenge") ─────────────────────────────────
// Era de departe cea mai generoasă sursă din joc (690 monede + 1.380 XP + 10
// vieți pe zi, fără niciun risc). Rămâne cea mai bună pe minut — dar mult
// mai aproape de restul economiei.

const int cultureCoinsPerCorrect = 13;
const int cultureXpPerCorrect = 9;
const int cultureBatchCompletionCoins = 23;
const int cultureBatchCompletionXp = 31;

/// O viață bonus la fiecare [cultureCorrectPerLife] răspunsuri corecte, cel
/// mult [cultureMaxLivesPerDay] pe zi (înainte: 1 la 3 corecte, nelimitat).
const int cultureCorrectPerLife = 4;
const int cultureMaxLivesPerDay = 5;

const int cultureFullRateDailyCorrectCap = 27;
const int cultureFullRateDailyBatchCap = 3;
const int cultureReducedCoinsPerCorrect = 4;
const int cultureReducedXpPerCorrect = 3;

// ─── Clippy ────────────────────────────────────────────────────────────────
// Regula cerută explicit: o întrebare de la Clippy trebuie să plătească
// STRICT mai mult decât una din gameplay-ul normal (înainte plătea 0,85×,
// adică mai puțin). Rămâne totuși mic în valoare absolută — o rundă are doar
// 3 întrebări.
//
// Anti-farm-ul nu mai e o rată redusă după N runde, ci un plafon DUR:
// [clippyDailyPlayLimit] runde pe zi calendaristică, cu 5 minute de cooldown
// între ele (vezi StorageService.isClippyReady). Odată consumate, Clippy
// tace până după miezul nopții. Fiindcă plafonul dur (5) e sub pragul de
// rată plină ([clippyFullRateDailyRounds]), toate rundele zilei plătesc
// integral, iar [clippyReducedMultiplier] rămâne doar o plasă de siguranță.

const double clippyRewardMultiplier = 1.35;
const double clippyReducedMultiplier = 0.4;

/// Câte runde de bonus Clippy se pot juca într-o zi calendaristică — se
/// resetează la 00:00, nu la 24h de la prima rundă.
const int clippyDailyPlayLimit = 5;

const int clippyFullRateDailyRounds = clippyDailyPlayLimit;
const int clippyCompletionCoins = 23;

// ─── Higher or Lower (solo) ────────────────────────────────────────────────
// Singurul gamemod care nu acorda nici monede, nici XP. E un mod cu risc
// maxim (o singură greșeală termină seria), deci plătește progresiv cu
// lungimea seriei.

const int higherLowerMaxCoinsPerStep = 29;
const int higherLowerMaxXpPerStep = 17;

int higherLowerCoinsForStep(int streak) =>
    (3 + streak * 0.7).round().clamp(3, higherLowerMaxCoinsPerStep);

int higherLowerXpForStep(int streak) =>
    (2 + streak * 0.4).round().clamp(2, higherLowerMaxXpPerStep);

/// Punctele acordate la o întrebare (scor de sesiune / clasament / record) —
/// neschimbate față de economia veche.
int calculateSessionQuestionReward(int maxPoints, Random random) {
  final minimumReward = (maxPoints * 0.7).round().clamp(100, maxPoints);
  final maximumReward = maxPoints;
  if (minimumReward >= maximumReward) {
    return maximumReward;
  }
  return random.nextInt(maximumReward - minimumReward + 1) + minimumReward;
}

const double _maxBlurSigma = 34.0;

/// Sigma de blur pentru imaginea întrebării — blur foarte puternic la
/// început (aproape imposibil de distins ce e în poză), se limpezește
/// treptat cu fiecare hint, dar rămâne mereu vizibil neclar până se
/// răspunde.
double resolveBlurSigma(int hintsUsed, {required bool revealed}) {
  if (revealed) {
    return 0.0;
  }
  final exposure = resolveHintExposure(hintsUsed);
  final sigma = _maxBlurSigma * (1 - exposure);
  return sigma.clamp(_maxBlurSigma * (1 - maxHintExposure), _maxBlurSigma);
}

LinearGradient buildQuestionGradient(String seed, Color baseColor) {
  final accent = HSLColor.fromColor(baseColor)
      // stableHash: aceeasi intrebare trebuie sa arate la fel pe telefon si
      // in browser (vezi core/stable_hash.dart).
      .withHue((stableHash(seed) % 360).toDouble())
      .toColor();

  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      baseColor.withAlpha(230),
      accent.withAlpha(220),
      const Color(0xFF0F172A),
    ],
  );
}
