import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/game_helpers.dart';
import 'package:guess_it/core/progression.dart';

/// Echilibrul economiei pe termen lung.
///
/// Cerința care a generat testul: "creștere organică, nu bruscă; să nu te
/// îneci în monede, nici să nu mori de foame după ele". Un multiplicator fix
/// nu poate satisface asta — e mereu greșit pentru cineva. Aici verificăm că
/// jucătorul de nivel 1 și cel de nivel 24 trăiesc în aceeași economie, doar
/// cu alte cifre pe ecran.
///
/// Cele două forțe care trebuie să rămână în echilibru:
///  • VENITUL crește cu NIVELUL ([economyGrowth]);
///  • TAXELE cresc cu AVEREA ([categoryEntryFee], [hintCoinCost]).
/// Dacă prima ar depăși-o pe a doua, banii s-ar acumula exponențial; invers,
/// jucătorii vechi ar fi tot mai săraci în termeni reali.
void main() {
  /// Venitul zilnic mediu în monede, din quest-uri, la un nivel dat —
  /// media pe cele 7 zile ale rotației, la revendicare completă.
  double dailyQuestCoins(int level) {
    var weekly = 0;
    for (var d = 0; d < 7; d++) {
      for (final q in todaysQuests(DateTime(2026, 8, 3 + d))) {
        weekly += q.coinRewardAt(level);
      }
    }
    return weekly / 7;
  }

  /// Averea la care se stabilizează un jucător care cheltuie ce câștigă —
  /// aproximăm cu câteva zile de venit ținute în portofel. Nu e o predicție
  /// exactă, ci ordinul de mărime care determină taxele.
  int settledWealth(int level) => (dailyQuestCoins(level) * 3).round();

  const levels = [1, 5, 10, 15, 24, 60];

  test('nimeni nu moare de foame: o zi de quest-uri acoperă mai multe sesiuni', () {
    for (final level in levels) {
      final income = dailyQuestCoins(level);
      final fee = categoryEntryFee(settledWealth(level));
      final sessions = income / fee;
      expect(sessions, greaterThan(6),
          reason: 'nivel $level: o zi de quest-uri ajunge doar pentru '
              '${sessions.toStringAsFixed(1)} intrări în categorie (taxă $fee)');
    }
  });

  test('nimeni nu se îneacă: o zi de quest-uri nu poate cumpăra tot magazinul', () {
    // Cheltuiala zilnică maximă posibilă (5 vieți + 3 pachete de hints) e în
    // jur de 2.750-3.800 de monede, vezi docs/economie_v3.md secțiunea 7.1.
    // Dacă o singură zi de quest-uri ar acoperi-o singură, restul economiei
    // (gameplay, Clippy, roată) ar deveni decorativ.
    const maxDailySpend = 2756;
    for (final level in levels) {
      expect(dailyQuestCoins(level), lessThan(maxDailySpend),
          reason: 'nivel $level: quest-urile singure acoperă toată cheltuiala zilei');
    }
  });

  test('puterea de cumpărare rămâne în aceeași bandă la orice nivel', () {
    // Miezul cerinței. Câte sesiuni de joc își permite dintr-o zi de
    // quest-uri un începător vs un veteran — raportul trebuie să rămână
    // aproape de 1, nu să favorizeze puternic pe unul dintre ei.
    final power = <int, double>{
      for (final level in levels)
        level: dailyQuestCoins(level) / categoryEntryFee(settledWealth(level))
    };
    final values = power.values.toList();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    expect(max / min, lessThan(1.6),
        reason: 'puterea de cumpărare variază prea mult între niveluri: $power');
  });

  test('creșterea venitului e mărginită — plafonul chiar plafonează', () {
    final atStart = dailyQuestCoins(1);
    final atCap = dailyQuestCoins(24);
    final wayPast = dailyQuestCoins(200);
    expect(atCap / atStart, closeTo(economyGrowthMax, 0.05),
        reason: 'venitul la plafon nu urmează curba');
    expect(wayPast, atCap, reason: 'peste nivelul 24 venitul tot mai crește');
  });

  test('hint-ul nu doare niciodată, indiferent de avere', () {
    // ATENȚIE la o formulare din docs/economie_v3.md secțiunea 3: acolo scrie
    // că "hint + răspuns corect e mereu profit net". E adevărat DOAR pentru
    // jucătorii săraci. La peste ~2.400 de monede hint-ul costă plafonul (89),
    // iar cel mai valoros răspuns din joc aduce 46 — deci pe hârtie e pierdere.
    //
    // Nu e un bug: la averea aia, 89 de monede sunt 1,8% din portofel, iar
    // valoarea reală a hint-ului e viața salvată și seria păstrată, nu
    // monedele. Proprietățile care CHIAR trebuie să țină sunt cele de mai jos.
    for (final wealth in [0, 173, 500, 1000, 5000, 50000]) {
      final cost = hintCoinCost(wealth);

      // 1. nu te bagă niciodată în datorie și nu te blochează
      expect(cost, lessThanOrEqualTo(wealth == 0 ? 0 : wealth));

      // 2. nu depășește niciodată o felie mică din avere
      if (wealth > 0) {
        expect(cost / wealth, lessThanOrEqualTo(hintCostWalletRatio + 0.001),
            reason: 'la $wealth monede hint-ul ia ${(cost / wealth * 100).toStringAsFixed(1)}% din avere');
      }

      // 3. cât timp banii chiar contează (sub plafon), hint-ul rămâne
      //    profitabil pe întrebările bune — asta e promisiunea din doc, în
      //    intervalul în care e adevărată
      if (cost < hintCostMax) {
        expect(cost, lessThanOrEqualTo(coinsForCorrectAnswer(1000)),
            reason: 'la $wealth monede, hint-ul ($cost) costă mai mult decât aduce cel mai bun răspuns');
      }
    }
  });

  test('planeta rămâne un premiu, nu un salariu', () {
    for (final level in levels) {
      final jackpot = planetJackpotReward(level);
      final daily = dailyQuestCoins(level);
      // Trei rulări perfecte (maximul absolut al unui ciclu de 12h, cu reclamă
      // și noroc total) nu trebuie să depășească o zi de quest-uri — altfel
      // planeta ar deveni sursa principală, nu un bonus.
      expect(planetRunsPerCycleWithAd * jackpot.coins, lessThan(daily * 1.5),
          reason: 'nivel $level: planeta plătește prea mult față de restul jocului');
      // ...dar nici să fie neglijabilă: o rulare reușită trebuie să conteze.
      expect(jackpot.coins, greaterThan(daily * 0.15),
          reason: 'nivel $level: recompensa planetei e prea mică pentru un cooldown de ${planetCooldownHours}h');
    }
  });
}
