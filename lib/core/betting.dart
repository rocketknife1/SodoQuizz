/// Sistemul de pariuri de la meciurile multiplayer.
///
/// Intrarea într-un meci costă acum două lucruri:
///  1. o **taxă fixă** ([multiplayerEntryFee]) — iese complet din economie
///     (sink anti-inflație), se întoarce integral doar dacă meciul nu apucă
///     să înceapă;
///  2. un **pariu ales de jucător**, între [minBetPercent] și [maxBetPercent]
///     din monedele rămase după taxă — pariurile tuturor formează pool-ul
///     care se reîmparte la final.
///
/// Multiplayer-ul devine astfel redistribuire între jucători, nu o sursă nouă
/// de bani: singurele monede "din partea casei" rămase sunt bonusul de primă
/// victorie a zilei (vezi progression.dart).
library;

import 'dart:math';

/// Taxa fixă, aceeași pentru orice intrare în meci — inclusiv Join Online,
/// care înainte era gratuit. Cerința: "oricine poate intra când plătește taxa
/// minimă", diferențele se fac apoi din procentul pariat.
const int multiplayerEntryFee = 37;

/// Pariul minim absolut, ca 5% dintr-un portofel mic să nu însemne 2 monede.
/// Împreună cu taxa, pragul real de intrare e [multiplayerMinimumBankroll].
const int minBetAmount = 23;
const int multiplayerMinimumBankroll = multiplayerEntryFee + minBetAmount;

const double minBetPercent = 0.05;
const double maxBetPercent = 0.85;

/// Mărimea de masă la care sunt calibrate valorile de bază de mai jos — masa
/// "standard" din simulările din docs/economie_v3.md, secțiunea 8.4.
const int referenceTableSize = 7;

/// Cât din pool se ia ca rake — al doilea sink al sistemului. Scade pe mesele
/// mari ([betRakeFor]): la 20 de jucători, 3,5% dintr-un pool de 20 de mize e
/// o ardere mult mai mare în absolut decât la 7, iar modul e gândit să fie
/// jucat des, în grup. Rămâne constanta de referință pentru o masă de
/// [referenceTableSize].
const double betRakeBase = 0.035;
const double betRakeMin = 0.013;

double betRakeFor(int players) => players <= 0
    ? betRakeBase
    : (betRakeBase * referenceTableSize / players)
        .clamp(betRakeMin, betRakeBase);

/// Împărțirea pool-ului net: partea de MIZĂ se distribuie după cât ai pariat
/// (ponderat cu performanța și riscul), partea de LOC se distribuie EXCLUSIV
/// după clasament, indiferent cât ai pariat. A doua parte e cea care face ca
/// un jucător mic, care rezistă până la final la o masă cu cineva care a
/// pariat mult și a pierdut, să plece cu de câteva ori miza lui.
///
/// Partea de LOC scade însă pe mesele mari, și ăsta e motivul: ea e un
/// transfer dinspre jumătatea de jos înspre vârf, iar concentrarea ei (41% pe
/// primul loc) devine apăsătoare cu cât masa e mai numeroasă. La 20 de
/// jucători cu cota fixă de 20%, jucătorul din mijlocul plutonului ieșea
/// sistematic pe 0,79× miza la FIECARE meci — insuportabil pentru un mod
/// gândit să fie jucat des. Cu cota scalată ajunge la 0,89×, iar locul 1
/// rămâne peste 2×, fiindcă pool-ul crește oricum cu numărul de jucători.
const double placementPotShareBase = 0.20;
const double placementPotShareMin = 0.09;

double placementPotShareFor(int players) => players <= 0
    ? placementPotShareBase
    : (placementPotShareBase * referenceTableSize / players)
        .clamp(placementPotShareMin, placementPotShareBase);

double stakePotShareFor(int players) => 1.0 - placementPotShareFor(players);

/// Cât de mult poate depăși un singur pariu nivelul mesei: plafonul e
/// mediana pariurilor × [tableCapMedianMultiple], iar surplusul NU se
/// pierde — se întoarce în portofel la decontare, separat de câștig (vezi
/// [BetPayouts.refunds]), fiindcă masa se cunoaște abia când se știe cine
/// chiar a jucat până la final.
///
/// Fără el, cineva cu 50.000 de monede ar putea pune 30.000 la o masă de
/// începători și ar recupera sistematic majoritatea pool-ului doar pentru că
/// a pus cei mai mulți bani. Cu el, mărimea mesei decide cât se poate juca la
/// masa aia — exact ca la "table stakes" în poker.
const double tableCapMedianMultiple = 7.3;

/// Ponderea de performanță: chiar și ultimul clasat păstrează [_perfFloor]
/// din greutate (nu pleacă niciodată cu zero din potul de miză), iar primul
/// ajunge la 1,0.
const double _perfFloor = 0.34;

/// Bonusul de risc: cine pariază procentul minim (5%) primește 0,766, cine
/// pariază maximul (85%) primește 1,182 — deci riscul asumat crește
/// recompensa potențială cu până la ~54% relativ.
const double _riskBase = 0.74;
const double _riskSlope = 0.52;

/// Ladder-ul potului de loc, trunchiat la numărul real de jucători și
/// renormalizat — vezi [placementShares].
const List<double> _placementLadder = [0.41, 0.24, 0.15, 0.09, 0.06, 0.03, 0.02];

/// Cu cât scade cota fiecărui loc dincolo de ultima treaptă scrisă explicit.
/// Înainte, orice loc de la al 8-lea încolo primea 0,01 — o valoare PLATĂ,
/// deci într-o cameră de 11 jucători locurile 8-11 valorau exact la fel și
/// nu mai exista niciun motiv să lupți pentru locul 9 în loc de 11. Coada
/// geometrică păstrează fiecare poziție distinctă, oricât de mare e masa.
const double _placementTailDecay = 0.83;

/// Pariul implicit al unui jucător nou (procent), undeva la mijlocul
/// intervalului, ca slider-ul să pornească de la ceva rezonabil.
const double defaultBetPercent = 0.23;

/// Cât reprezintă [percent] din monedele rămase după taxa fixă, plafonat
/// inferior la [minBetAmount] și superior la ce își poate permite jucătorul.
int betAmountFor({required int coins, required double percent}) {
  final afterFee = coins - multiplayerEntryFee;
  if (afterFee < minBetAmount) return 0;
  final raw = (afterFee * percent.clamp(minBetPercent, maxBetPercent)).round();
  return raw.clamp(minBetAmount, afterFee);
}

/// Datele de care are nevoie calculul de plată pentru un singur jucător.
/// [performance] e 0..1 (1 = cel mai bun de la masă) și e calculat diferit pe
/// moduri: în Clasic din scor raportat la scorul maxim, în Higher or Lower
/// din poziția de eliminare — vezi [BetPayouts.compute].
class BetEntry {
  final String playerId;
  final int bet;
  final double betPercent;
  final double performance;

  /// Locul final, 1 = primul. Egalitățile primesc același loc; ladder-ul de
  /// mai jos e indexat pe poziția din clasamentul sortat, nu pe [place], ca
  /// suma cotelor să rămână 1 chiar și la egalitate.
  final int place;

  const BetEntry({
    required this.playerId,
    required this.bet,
    required this.betPercent,
    required this.performance,
    required this.place,
  });
}

/// Cotele potului de loc pentru [playerCount] jucători — primele
/// [playerCount] trepte din ladder, renormalizate ca să însumeze 1.
List<double> placementShares(int playerCount) {
  if (playerCount <= 0) return const [];
  final raw = <double>[
    for (var i = 0; i < playerCount; i++)
      i < _placementLadder.length
          ? _placementLadder[i]
          : _placementLadder.last *
              pow(_placementTailDecay, i - _placementLadder.length + 1),
  ];
  final total = raw.fold<double>(0, (sum, v) => sum + v);
  return [for (final v in raw) v / total];
}

/// Performanța (0..1, unde 1 = cel mai bun de la masă) a fiecărui scor dintr-un
/// meci Clasic, în ordinea în care vin [scores].
///
/// De ce nu mai e simplu `scor / scorMaxim`: de când un răspuns greșit scade
/// puncte (vezi multiplayerWrongPenalty), scorul poate ieși NEGATIV, iar
/// raportul direct ar da performanță negativă — tăiată apoi la 0, deci cine a
/// terminat pe −400 ar fi tratat identic cu cine a terminat pe 0.
///
/// Soluția e o singură translație: dacă cineva e pe minus, TOATE scorurile se
/// ridică cu atât cât să aducem ultimul la zero, apoi se împarte la fel ca
/// înainte. Deliberat NU e o normalizare min-max clasică: aceea ar întinde
/// diferențe minuscule pe tot intervalul (o masă de 2.000 / 1.900 / 1.850 ar
/// ieși 1,0 / 0,5 / 0,0), pe când translația lasă mesele fără scoruri negative
/// exact cum se comportau înainte (1,0 / 0,95 / 0,93) și repară strict cazul
/// nou.
List<double> classicPerformances(List<int> scores) {
  if (scores.isEmpty) return const [];
  final worst = scores.reduce(min);
  final offset = worst < 0 ? -worst : 0;
  final top = scores.reduce(max) + offset;
  // toți la egalitate (inclusiv toți pe zero sau toți pe același minus):
  // nimeni n-a fost mai bun ca altul, deci nimeni nu pierde din potul de miză.
  if (top <= 0) return List.filled(scores.length, 1.0);
  return [for (final s in scores) (s + offset) / top];
}

double _riskFactor(double betPercent) =>
    _riskBase + _riskSlope * betPercent.clamp(minBetPercent, maxBetPercent);

double _perfFactor(double performance) =>
    _perfFloor + (1 - _perfFloor) * performance.clamp(0.0, 1.0);

/// Rezultatul complet al decontării unui meci — plata fiecărui jucător, plus
/// cifrele afișabile (pool, rake, plafonul mesei).
class BetPayouts {
  /// Cât primește fiecare jucător, pe id.
  final Map<String, int> payouts;

  /// Pariul EFECTIV al fiecărui jucător (după plafonul mesei).
  final Map<String, int> effectiveBets;

  /// Partea din pariu care a depășit plafonul mesei și se întoarce intactă,
  /// pe lângă [payouts] — n-a participat niciodată la pool.
  final Map<String, int> refunds;

  final int pool;
  final int poolNet;
  final int tableCap;

  const BetPayouts({
    required this.payouts,
    required this.effectiveBets,
    required this.refunds,
    required this.pool,
    required this.poolNet,
    required this.tableCap,
  });

  /// Cât se creditează efectiv în portofel unui jucător: câștigul din pool
  /// plus surplusul returnat de plafonul mesei.
  int totalCreditFor(String playerId) =>
      (payouts[playerId] ?? 0) + (refunds[playerId] ?? 0);

  /// Plafonul mesei pentru un set de pariuri: mediana × [tableCapMedianMultiple].
  /// Se calculează la START (când se știe cine chiar joacă), nu la intrarea în
  /// lobby.
  static int tableCapFor(List<int> bets) {
    if (bets.isEmpty) return 0;
    final sorted = List.of(bets)..sort();
    final mid = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2;
    return max(minBetAmount, (median * tableCapMedianMultiple).round());
  }

  /// Decontarea finală. [entries] trebuie să conțină TOȚI jucătorii care au
  /// pornit meciul, sortați descrescător după performanță (poziția din listă
  /// dă treapta din ladder-ul de loc).
  ///
  /// Sub 2 jucători nu există pool: fiecare își primește miza înapoi (un meci
  /// cu un singur om nu e un pariu).
  static BetPayouts compute(List<BetEntry> entries) {
    if (entries.isEmpty) {
      return const BetPayouts(
          payouts: {},
          effectiveBets: {},
          refunds: {},
          pool: 0,
          poolNet: 0,
          tableCap: 0);
    }
    if (entries.length < 2) {
      final only = entries.first;
      return BetPayouts(
        payouts: {only.playerId: only.bet},
        effectiveBets: {only.playerId: only.bet},
        refunds: {only.playerId: 0},
        pool: only.bet,
        poolNet: only.bet,
        tableCap: only.bet,
      );
    }

    final cap = tableCapFor([for (final e in entries) e.bet]);
    final effective = {
      for (final e in entries) e.playerId: min(e.bet, cap),
    };
    final refunds = {
      for (final e in entries) e.playerId: e.bet - effective[e.playerId]!,
    };
    final pool = effective.values.fold<int>(0, (sum, v) => sum + v);
    final poolNet = (pool * (1 - betRakeFor(entries.length))).round();
    final stakePot = poolNet * stakePotShareFor(entries.length);
    final placementPot = poolNet * placementPotShareFor(entries.length);
    final shares = placementShares(entries.length);

    var weightTotal = 0.0;
    final weights = <String, double>{};
    for (final e in entries) {
      final w = effective[e.playerId]! *
          _perfFactor(e.performance) *
          _riskFactor(e.betPercent);
      weights[e.playerId] = w;
      weightTotal += w;
    }

    final payouts = <String, int>{};
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final fromStake =
          weightTotal > 0 ? stakePot * (weights[e.playerId]! / weightTotal) : 0.0;
      final fromPlacement = placementPot * shares[i];
      payouts[e.playerId] = (fromStake + fromPlacement).round();
    }

    return BetPayouts(
      payouts: payouts,
      effectiveBets: effective,
      refunds: refunds,
      pool: pool,
      poolNet: poolNet,
      tableCap: cap,
    );
  }
}

/// Estimare afișată ÎNAINTE de meci ("dacă termini primul, poți lua ~X"),
/// presupunând că restul mesei pariază la fel ca tine. Deliberat conservativă
/// — un pariu mult peste nivelul mesei nu poate aduce randamentul de aici,
/// tocmai din cauza plafonului și a formei sublineare a împărțirii.
int estimateTopPayout({required int bet, required double betPercent, required int players}) {
  if (bet <= 0 || players < 2) return bet;
  final entries = <BetEntry>[
    for (var i = 0; i < players; i++)
      BetEntry(
        playerId: '$i',
        bet: bet,
        betPercent: betPercent,
        performance: 1 - i / (players - 1),
        place: i + 1,
      ),
  ];
  return BetPayouts.compute(entries).payouts['0'] ?? bet;
}
