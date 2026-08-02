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

/// Cât din pool se ia ca rake — al doilea sink al sistemului, proporțional cu
/// mărimea mizelor de la masă (deci mesele mari ard mai mult).
const double betRake = 0.035;

/// Împărțirea pool-ului net: partea de MIZĂ se distribuie după cât ai pariat
/// (ponderat cu performanța și riscul), partea de LOC se distribuie EXCLUSIV
/// după clasament, indiferent cât ai pariat. A doua parte e cea care face ca
/// un jucător mic, care rezistă până la final la o masă cu cineva care a
/// pariat mult și a pierdut, să plece cu de câteva ori miza lui.
const double stakePotShare = 0.80;
const double placementPotShare = 1.0 - stakePotShare;

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
      i < _placementLadder.length ? _placementLadder[i] : 0.01,
  ];
  final total = raw.fold<double>(0, (sum, v) => sum + v);
  return [for (final v in raw) v / total];
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
    final poolNet = (pool * (1 - betRake)).round();
    final stakePot = poolNet * stakePotShare;
    final placementPot = poolNet * placementPotShare;
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
