import 'package:flutter/material.dart';

/// Formula de nivel/XP: curbă pătratică, nu liniară — primele niveluri sunt
/// rapide (motivante pentru un jucător nou), apoi progresia încetinește
/// plăcut, fără să devină vreodată imposibilă (vezi documentul de
/// reproiectare a economiei). XP-ul câștigat la o întrebare corectă =
/// punctele obținute la acea întrebare (vezi calculateAwardedPoints din
/// game_helpers.dart).
///
/// XP necesar ca să treci de la nivelul [level] la [level] + 1.
int xpForLevel(int level) => 250 + 60 * level * level;

int levelForXp(int xp) {
  var level = 1;
  var remaining = xp;
  while (remaining >= xpForLevel(level)) {
    remaining -= xpForLevel(level);
    level++;
  }
  return level;
}

int xpIntoCurrentLevel(int xp) {
  var level = 1;
  var remaining = xp;
  while (remaining >= xpForLevel(level)) {
    remaining -= xpForLevel(level);
    level++;
  }
  return remaining;
}

double levelProgress(int xp) =>
    xpIntoCurrentLevel(xp) / xpForLevel(levelForXp(xp));

/// XP total necesar ca să AJUNGI la [level] (pornind de la 0) — folosit la
/// migrarea de pe curba veche și la calculul reward-urilor de Level Up.
int cumulativeXpForLevel(int level) {
  var total = 0;
  for (var l = 1; l < level; l++) {
    total += xpForLevel(l);
  }
  return total;
}

/// Recompensa acordată la finalizarea unui nivel — colectată manual din
/// bara de XP (vezi StorageService.claimAllPendingLevelRewards), nu
/// acordată automat. Nivelul 1 (start) nu are reward — primul e la nivelul 2.
class LevelReward {
  final int coins;
  final int hints;
  final int hearts;
  final int gems;
  const LevelReward(
      {this.coins = 0, this.hints = 0, this.hearts = 0, this.gems = 0});

  bool get isEmpty => coins == 0 && hints == 0 && hearts == 0 && gems == 0;
}

/// Compoziție variată, nu doar monede: hints la fiecare 3 niveluri, o viață
/// bonus la fiecare 4, gems la fiecare 10 (plus un bonus în plus la
/// multipli de 25) — ca fiecare colectare să pară o mică surpriză, nu doar
/// un număr care crește.
LevelReward levelReward(int level) {
  if (level <= 1) return const LevelReward();
  final coins = 60 + 25 * level;
  final hints = level % 3 == 0 ? 2 : 0;
  final hearts = level % 4 == 0 ? 1 : 0;
  var gems = level % 10 == 0 ? 10 : 0;
  if (level % 25 == 0) gems += 25;
  return LevelReward(coins: coins, hints: hints, hearts: hearts, gems: gems);
}

/// Recompensa acordată la fiecare 10 întrebări răspunse într-o sesiune de
/// joc dintr-o categorie (vezi GameScreen) — [milestone] = 1 la a 10-a
/// întrebare, 2 la a 20-a etc. Viața (mereu +1) nu e în model, se acordă
/// separat de apelant. Progresivă (crește cu fiecare milestone din aceeași
/// sesiune) — gems abia de la milestone 3 (30 de întrebări), ca semn că ai
/// "ajuns departe", nu de la primul prag.
class GameModeMilestoneReward {
  final int coins;
  final int xp;
  final int gems;
  const GameModeMilestoneReward(
      {required this.coins, required this.xp, required this.gems});
}

GameModeMilestoneReward gameModeMilestoneReward(int milestone) {
  return GameModeMilestoneReward(
    coins: 30 * milestone,
    xp: 80 * milestone,
    gems: milestone >= 3 ? (milestone - 2) * 3 : 0,
  );
}

// ─── Taxă de intrare la categorii solo ────────────────────────────────────
// La intrarea într-o categorie (vezi categories_screen.dart._enterCategory)
// se plătește o taxă fixă în monede; la ieșire (game over, "Ai terminat
// toate întrebările", butonul înapoi din joc SAU back-ul telefonului — vezi
// GameScreen._settleExitReward), recompensa depinde STRICT de câte răspunsuri
// CORECTE ai dat în acea sesiune, nu de cât de departe ai ajuns (progres
// real, nu doar întrebări văzute). Higher or Lower și multiplayer NU sunt
// afectate — doar categoriile solo obișnuite, la cererea explicită a userului.

/// Taxă fixă, aceeași pentru orice categorie — simplu de înțeles și de
/// echilibrat, spre deosebire de un preț variabil pe dificultate/tier.
const int categoryEntryFee = 15;

/// Recompensa la ieșire, în 3 trepte pe numărul de răspunsuri corecte din
/// sesiune: sub 4 corecte — doar jumătate din taxă înapoi (ai intrat dar
/// n-ai făcut progres real); 4-7 corecte — taxa întreagă înapoi (ai "recuperat
/// investiția"); 8+ corecte — taxa plus un bonus de 50% (progres solid,
/// merită mai mult decât un simplu refund).
int categoryExitReward(int correctCount) {
  if (correctCount >= 8) return (categoryEntryFee * 1.5).round();
  if (correctCount >= 4) return categoryEntryFee;
  return (categoryEntryFee * 0.5).round();
}

/// Un quest zilnic: progresul se ține în [StorageService], definiția
/// (țintă, recompensă) e statică aici. [metricKey] leagă variante de
/// dificultate diferită ale aceleiași acțiuni (ex: correct_5/10/15) de UN
/// singur contor de progres persistat — implicit egal cu [id] dacă nu se
/// specifică altul. Recompensa poate combina oricâte din cele 4 resurse
/// (monede, gems, vieți, hints, mereu cel puțin 2) — XP se acordă mereu, în
/// plus, ca progres de bază spre nivel.
class Quest {
  final String id;
  final String title;
  final int target;
  final String metricKey;
  final int coinReward;
  final int xpReward;
  final int gemReward;
  final int heartReward;
  final int hintReward;
  final IconData icon;

  const Quest({
    required this.id,
    required this.title,
    required this.target,
    String? metricKey,
    this.coinReward = 0,
    this.xpReward = 0,
    this.gemReward = 0,
    this.heartReward = 0,
    this.hintReward = 0,
    required this.icon,
  }) : metricKey = metricKey ?? id;
}

// ─── Catalogul de quest-uri (70 în total) ──────────────────────────────────
// Împărțit pe 3 nivele de dificultate — nivelul e doar o organizare a
// codului sursă (nu un câmp reținut pe Quest). TOATE sunt afișate/active în
// fiecare zi (vezi [todaysQuests], fără rotație, la cerere explicită) —
// progresul fiecăruia se resetează totuși zilnic. Gems și vieți (singurele
// 2 resurse cu adăugare NEplafonată) rămân concentrate pe doar ~5, respectiv
// ~6 quest-uri din cele 70, ca să nu explodeze inflația chiar dacă toate
// quest-urile sunt revendicabile în aceeași zi.

const List<Quest> _easyQuests = [
  Quest(
      id: 'answer_1',
      title: 'Răspunde la prima întrebare a zilei',
      target: 1,
      metricKey: 'answer_count',
      coinReward: 10,
      xpReward: 15,
      hintReward: 1,
      icon: Icons.play_circle_fill_rounded),
  Quest(
      id: 'correct_5',
      title: 'Răspunde corect la 5 întrebări',
      target: 5,
      metricKey: 'correct_count',
      coinReward: 18,
      xpReward: 20,
      hintReward: 1,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'answer_10',
      title: 'Răspunde la 10 întrebări (corect sau greșit)',
      target: 10,
      metricKey: 'answer_count',
      coinReward: 18,
      xpReward: 22,
      hintReward: 1,
      icon: Icons.playlist_add_check_rounded),
  Quest(
      id: 'play_2_modes',
      title: 'Joacă în 2 gamemoduri diferite',
      target: 2,
      metricKey: 'modes_played',
      coinReward: 15,
      xpReward: 20,
      hintReward: 2,
      icon: Icons.grid_view_rounded),
  Quest(
      id: 'use_hints_3',
      title: 'Folosește 3 hint-uri',
      target: 3,
      metricKey: 'hints_used',
      coinReward: 12,
      xpReward: 15,
      gemReward: 1,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'no_hint_3',
      title: 'Ghicește corect 3 întrebări fără niciun hint',
      target: 3,
      metricKey: 'no_hint_correct',
      coinReward: 20,
      xpReward: 25,
      hintReward: 1,
      icon: Icons.visibility_off_rounded),
  Quest(
      id: 'earn_60_coins',
      title: 'Strânge 60 de monede jucând',
      target: 60,
      metricKey: 'coins_earned',
      coinReward: 15,
      xpReward: 18,
      hintReward: 1,
      icon: Icons.savings_rounded),
  Quest(
      id: 'streak_3',
      title: 'Obține o serie de 3 răspunsuri corecte la rând',
      target: 1,
      metricKey: 'streak_hit_3',
      coinReward: 18,
      xpReward: 25,
      hintReward: 1,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'daily_challenge_done',
      title: 'Termină Daily Challenge de azi',
      target: 1,
      coinReward: 20,
      xpReward: 28,
      hintReward: 1,
      icon: Icons.bolt_rounded),
  Quest(
      id: 'culture_correct_5',
      title: 'Răspunde corect la 5 întrebări de Cultură Generală',
      target: 5,
      metricKey: 'culture_quiz_correct',
      coinReward: 15,
      xpReward: 20,
      hintReward: 1,
      icon: Icons.public_rounded),
  Quest(
      id: 'clippy_done_1',
      title: 'Termină un bonus de la Clippy',
      target: 1,
      metricKey: 'clippy_done',
      coinReward: 12,
      xpReward: 18,
      hintReward: 1,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'unlimited_correct_10',
      title: 'Răspunde corect la 10 întrebări în Quiz Nelimitat',
      target: 10,
      metricKey: 'unlimited_quiz_correct',
      coinReward: 15,
      xpReward: 20,
      hintReward: 1,
      icon: Icons.all_inclusive_rounded),
  Quest(
      id: 'wheel_spin_1',
      title: 'Învârte Roata norocului',
      target: 1,
      coinReward: 12,
      xpReward: 15,
      hintReward: 1,
      icon: Icons.casino_rounded),
  Quest(
      id: 'claim_daily_lives',
      title: 'Revendică recompensa zilnică de vieți',
      target: 1,
      coinReward: 15,
      xpReward: 15,
      hintReward: 1,
      icon: Icons.favorite_rounded),
  Quest(
      id: 'hint_buy_1',
      title: 'Cumpără un pachet de hints din Magazin',
      target: 1,
      coinReward: 10,
      xpReward: 15,
      heartReward: 1,
      icon: Icons.storefront_rounded),
  Quest(
      id: 'heart_buy_1',
      title: 'Cumpără o viață din Magazin',
      target: 1,
      coinReward: 10,
      xpReward: 15,
      hintReward: 2,
      icon: Icons.storefront_rounded),
  Quest(
      id: 'answer_5',
      title: 'Răspunde la 5 întrebări (corect sau greșit)',
      target: 5,
      metricKey: 'answer_count',
      coinReward: 15,
      xpReward: 18,
      hintReward: 1,
      icon: Icons.playlist_add_check_rounded),
  Quest(
      id: 'answer_3',
      title: 'Răspunde la 3 întrebări (corect sau greșit)',
      target: 3,
      metricKey: 'answer_count',
      coinReward: 12,
      xpReward: 14,
      hintReward: 1,
      icon: Icons.playlist_add_check_rounded),
  Quest(
      id: 'correct_3',
      title: 'Răspunde corect la 3 întrebări',
      target: 3,
      metricKey: 'correct_count',
      coinReward: 12,
      xpReward: 15,
      hintReward: 1,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'earn_30_coins',
      title: 'Strânge 30 de monede jucând',
      target: 30,
      metricKey: 'coins_earned',
      coinReward: 10,
      xpReward: 15,
      hintReward: 1,
      icon: Icons.savings_rounded),
  Quest(
      id: 'earn_45_coins',
      title: 'Strânge 45 de monede jucând',
      target: 45,
      metricKey: 'coins_earned',
      coinReward: 13,
      xpReward: 17,
      hintReward: 1,
      icon: Icons.savings_rounded),
  Quest(
      id: 'use_hints_1',
      title: 'Folosește 1 hint',
      target: 1,
      metricKey: 'hints_used',
      coinReward: 10,
      xpReward: 12,
      hintReward: 1,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'use_hints_2',
      title: 'Folosește 2 hint-uri',
      target: 2,
      metricKey: 'hints_used',
      coinReward: 11,
      xpReward: 14,
      hintReward: 1,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'no_hint_1',
      title: 'Ghicește corect o întrebare fără niciun hint',
      target: 1,
      metricKey: 'no_hint_correct',
      coinReward: 12,
      xpReward: 15,
      hintReward: 1,
      icon: Icons.visibility_off_rounded),
  Quest(
      id: 'culture_correct_3',
      title: 'Răspunde corect la 3 întrebări de Cultură Generală',
      target: 3,
      metricKey: 'culture_quiz_correct',
      coinReward: 12,
      xpReward: 15,
      hintReward: 1,
      icon: Icons.public_rounded),
  Quest(
      id: 'culture_batches_1',
      title: 'Termină un lot de Cultură Generală',
      target: 1,
      metricKey: 'culture_quiz_batches',
      coinReward: 13,
      xpReward: 16,
      hintReward: 1,
      icon: Icons.public_rounded),
  Quest(
      id: 'unlimited_correct_5',
      title: 'Răspunde corect la 5 întrebări în Quiz Nelimitat',
      target: 5,
      metricKey: 'unlimited_quiz_correct',
      coinReward: 12,
      xpReward: 15,
      hintReward: 1,
      icon: Icons.all_inclusive_rounded),
  Quest(
      id: 'play_1_mode',
      title: 'Joacă într-un gamemod, oricare',
      target: 1,
      metricKey: 'modes_played',
      coinReward: 10,
      xpReward: 12,
      hintReward: 1,
      icon: Icons.grid_view_rounded),
];

const List<Quest> _mediumQuests = [
  Quest(
      id: 'correct_10',
      title: 'Răspunde corect la 10 întrebări',
      target: 10,
      metricKey: 'correct_count',
      coinReward: 30,
      xpReward: 40,
      hintReward: 2,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'answer_20',
      title: 'Răspunde la 20 de întrebări (corect sau greșit)',
      target: 20,
      metricKey: 'answer_count',
      coinReward: 32,
      xpReward: 42,
      hintReward: 2,
      icon: Icons.playlist_add_check_rounded),
  Quest(
      id: 'play_3_modes',
      title: 'Joacă în 3 gamemoduri diferite',
      target: 3,
      metricKey: 'modes_played',
      coinReward: 28,
      xpReward: 38,
      hintReward: 2,
      icon: Icons.grid_view_rounded),
  Quest(
      id: 'use_hints_6',
      title: 'Folosește 6 hint-uri',
      target: 6,
      metricKey: 'hints_used',
      coinReward: 28,
      xpReward: 32,
      gemReward: 1,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'no_hint_6',
      title: 'Ghicește corect 6 întrebări fără niciun hint',
      target: 6,
      metricKey: 'no_hint_correct',
      coinReward: 35,
      xpReward: 45,
      hintReward: 2,
      icon: Icons.visibility_off_rounded),
  Quest(
      id: 'earn_150_coins',
      title: 'Strânge 150 de monede jucând',
      target: 150,
      metricKey: 'coins_earned',
      coinReward: 30,
      xpReward: 35,
      hintReward: 1,
      icon: Icons.savings_rounded),
  Quest(
      id: 'streak_5',
      title: 'Obține o serie de 5 răspunsuri corecte la rând',
      target: 1,
      metricKey: 'streak_hit_5',
      coinReward: 32,
      xpReward: 45,
      heartReward: 1,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'streak_3_twice',
      title: 'Obține o serie de 3 răspunsuri corecte, de 2 ori azi',
      target: 2,
      metricKey: 'streak_hit_3',
      coinReward: 25,
      xpReward: 35,
      hintReward: 2,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'culture_correct_10',
      title: 'Răspunde corect la 10 întrebări de Cultură Generală',
      target: 10,
      metricKey: 'culture_quiz_correct',
      coinReward: 30,
      xpReward: 40,
      hintReward: 1,
      icon: Icons.public_rounded),
  Quest(
      id: 'culture_batches_2',
      title: 'Termină 2 loturi de Cultură Generală',
      target: 2,
      metricKey: 'culture_quiz_batches',
      coinReward: 25,
      xpReward: 35,
      heartReward: 1,
      hintReward: 2,
      icon: Icons.public_rounded),
  Quest(
      id: 'clippy_done_2',
      title: 'Termină 2 bonusuri de la Clippy',
      target: 2,
      metricKey: 'clippy_done',
      coinReward: 22,
      xpReward: 32,
      hintReward: 2,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'unlimited_correct_25',
      title: 'Răspunde corect la 25 de întrebări în Quiz Nelimitat',
      target: 25,
      metricKey: 'unlimited_quiz_correct',
      coinReward: 30,
      xpReward: 40,
      hintReward: 2,
      icon: Icons.all_inclusive_rounded),
  Quest(
      id: 'level_up_1',
      title: 'Revendică o recompensă de nivel',
      target: 1,
      coinReward: 25,
      gemReward: 1,
      hintReward: 1,
      icon: Icons.military_tech_rounded),
  Quest(
      id: 'spend_any_1',
      title: 'Cheltuie monede sau gems în Magazin',
      target: 1,
      xpReward: 25,
      heartReward: 1,
      hintReward: 1,
      icon: Icons.shopping_cart_rounded),
  Quest(
      id: 'answer_15',
      title: 'Răspunde la 15 întrebări (corect sau greșit)',
      target: 15,
      metricKey: 'answer_count',
      coinReward: 24,
      xpReward: 32,
      hintReward: 2,
      icon: Icons.playlist_add_check_rounded),
  Quest(
      id: 'answer_25',
      title: 'Răspunde la 25 de întrebări (corect sau greșit)',
      target: 25,
      metricKey: 'answer_count',
      coinReward: 32,
      xpReward: 45,
      hintReward: 2,
      icon: Icons.playlist_add_check_rounded),
  Quest(
      id: 'hints_used_10',
      title: 'Folosește 10 hint-uri',
      target: 10,
      metricKey: 'hints_used',
      coinReward: 26,
      xpReward: 35,
      hintReward: 1,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'no_hint_10',
      title: 'Ghicește corect 10 întrebări fără niciun hint',
      target: 10,
      metricKey: 'no_hint_correct',
      coinReward: 30,
      xpReward: 40,
      hintReward: 2,
      icon: Icons.visibility_off_rounded),
  Quest(
      id: 'earn_250_coins',
      title: 'Strânge 250 de monede jucând',
      target: 250,
      metricKey: 'coins_earned',
      coinReward: 28,
      xpReward: 35,
      hintReward: 1,
      icon: Icons.savings_rounded),
  Quest(
      id: 'culture_correct_15',
      title: 'Răspunde corect la 15 întrebări de Cultură Generală',
      target: 15,
      metricKey: 'culture_quiz_correct',
      coinReward: 28,
      xpReward: 38,
      hintReward: 2,
      icon: Icons.public_rounded),
  Quest(
      id: 'unlimited_correct_35',
      title: 'Răspunde corect la 35 de întrebări în Quiz Nelimitat',
      target: 35,
      metricKey: 'unlimited_quiz_correct',
      coinReward: 28,
      xpReward: 38,
      hintReward: 2,
      icon: Icons.all_inclusive_rounded),
  Quest(
      id: 'clippy_done_3',
      title: 'Termină 3 bonusuri de la Clippy',
      target: 3,
      metricKey: 'clippy_done',
      coinReward: 25,
      xpReward: 35,
      hintReward: 2,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'hint_pack_bought_2',
      title: 'Cumpără 2 pachete de hints din Magazin',
      target: 2,
      metricKey: 'hint_pack_bought',
      coinReward: 24,
      xpReward: 32,
      hintReward: 2,
      icon: Icons.storefront_rounded),
  Quest(
      id: 'heart_bought_2',
      title: 'Cumpără 2 vieți din Magazin',
      target: 2,
      metricKey: 'heart_bought',
      coinReward: 24,
      xpReward: 32,
      hintReward: 2,
      icon: Icons.storefront_rounded),
  Quest(
      id: 'shop_spend_2',
      title: 'Cheltuie de 2 ori în Magazin sau la Deblocare',
      target: 2,
      metricKey: 'shop_spend',
      coinReward: 22,
      xpReward: 30,
      hintReward: 2,
      icon: Icons.shopping_cart_rounded),
  Quest(
      id: 'streak_5_twice',
      title: 'Obține o serie de 5 răspunsuri corecte, de 2 ori azi',
      target: 2,
      metricKey: 'streak_hit_5',
      coinReward: 30,
      xpReward: 42,
      hintReward: 2,
      icon: Icons.local_fire_department_rounded),
];

const List<Quest> _hardQuests = [
  Quest(
      id: 'correct_15',
      title: 'Răspunde corect la 15 întrebări',
      target: 15,
      metricKey: 'correct_count',
      coinReward: 55,
      xpReward: 70,
      gemReward: 2,
      hintReward: 2,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'streak_8',
      title: 'Obține o serie de 8 răspunsuri corecte la rând',
      target: 1,
      metricKey: 'streak_hit_8',
      coinReward: 60,
      xpReward: 90,
      gemReward: 2,
      heartReward: 1,
      hintReward: 2,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'earn_300_coins',
      title: 'Strânge 300 de monede jucând',
      target: 300,
      metricKey: 'coins_earned',
      coinReward: 50,
      xpReward: 65,
      heartReward: 1,
      hintReward: 3,
      icon: Icons.savings_rounded),
  Quest(
      id: 'clippy_perfect_1',
      title: 'Termină un bonus de la Clippy perfect (3/3)',
      target: 1,
      coinReward: 40,
      xpReward: 55,
      hintReward: 3,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'unlock_batch_1',
      title: 'Deblochează un lot nou de întrebări',
      target: 1,
      coinReward: 80,
      xpReward: 60,
      hintReward: 3,
      icon: Icons.lock_open_rounded),
  Quest(
      id: 'play_4_modes',
      title: 'Joacă în 4 gamemoduri diferite',
      target: 4,
      metricKey: 'modes_played',
      coinReward: 55,
      xpReward: 75,
      hintReward: 2,
      icon: Icons.grid_view_rounded),
  Quest(
      id: 'culture_batches_3',
      title: 'Termină 3 loturi de Cultură Generală',
      target: 3,
      metricKey: 'culture_quiz_batches',
      coinReward: 50,
      xpReward: 70,
      hintReward: 2,
      icon: Icons.public_rounded),
  Quest(
      id: 'claim_3_quests_today',
      title: 'Revendică alte 3 quest-uri azi',
      target: 3,
      metricKey: 'quests_claimed_today',
      coinReward: 60,
      xpReward: 80,
      hintReward: 2,
      icon: Icons.flag_rounded),
  Quest(
      id: 'correct_20',
      title: 'Răspunde corect la 20 de întrebări',
      target: 20,
      metricKey: 'correct_count',
      coinReward: 58,
      xpReward: 75,
      hintReward: 2,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'answer_40',
      title: 'Răspunde la 40 de întrebări (corect sau greșit)',
      target: 40,
      metricKey: 'answer_count',
      coinReward: 55,
      xpReward: 70,
      hintReward: 2,
      icon: Icons.playlist_add_check_rounded),
  Quest(
      id: 'streak_10',
      title: 'Obține o serie de 10 răspunsuri corecte la rând',
      target: 1,
      metricKey: 'streak_hit_10',
      coinReward: 65,
      xpReward: 85,
      hintReward: 3,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'earn_500_coins',
      title: 'Strânge 500 de monede jucând',
      target: 500,
      metricKey: 'coins_earned',
      coinReward: 55,
      xpReward: 70,
      hintReward: 2,
      icon: Icons.savings_rounded),
  Quest(
      id: 'play_5_modes',
      title: 'Joacă în 5 gamemoduri diferite',
      target: 5,
      metricKey: 'modes_played',
      coinReward: 60,
      xpReward: 80,
      hintReward: 2,
      icon: Icons.grid_view_rounded),
  Quest(
      id: 'unlimited_correct_60',
      title: 'Răspunde corect la 60 de întrebări în Quiz Nelimitat',
      target: 60,
      metricKey: 'unlimited_quiz_correct',
      coinReward: 58,
      xpReward: 75,
      hintReward: 2,
      icon: Icons.all_inclusive_rounded),
  Quest(
      id: 'clippy_perfect_2',
      title: 'Termină un bonus de la Clippy perfect (3/3), de 2 ori azi',
      target: 2,
      metricKey: 'clippy_perfect',
      coinReward: 50,
      xpReward: 70,
      hintReward: 3,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'claim_5_quests_today',
      title: 'Revendică alte 5 quest-uri azi',
      target: 5,
      metricKey: 'quests_claimed_today',
      coinReward: 70,
      xpReward: 90,
      hintReward: 3,
      icon: Icons.flag_rounded),
];

/// Toate quest-urile din joc (70) — sursă pentru [questById] și pentru
/// afișarea "din X quest-uri în total" pe ecranul de Quests. Vezi
/// [todaysQuests] pentru care dintre ele sunt active azi.
const List<Quest> allQuests = [
  ..._easyQuests,
  ..._mediumQuests,
  ..._hardQuests
];

Quest questById(String id) => allQuests.firstWhere((q) => q.id == id);

/// Quest-urile active AZI — la cerere explicită, TOATE cele 70, fără
/// rotație/subset zilnic (nu mai există o selecție parțială de afișat).
/// Progresul fiecăruia tot se resetează zilnic (chei de storage scoped pe
/// dată) — doar setul AFIȘAT nu mai variază de la o zi la alta.
List<Quest> todaysQuests([DateTime? now]) => allQuests;

/// O realizare permanentă: spre deosebire de [Quest] (zilnic, se resetează),
/// progresul unei realizări e cumulativ pe viață — o dată revendicată,
/// rămâne revendicată pentru totdeauna. Recompensele sunt DELIBERAT mult mai
/// mari decât un quest zilnic (chiar și unul greu) — o realizare cere efort
/// cumulat pe termen lung, nu o sesiune de joc, deci trebuie să se simtă pe
/// măsură, nu ca "încă un quest".
class Achievement {
  final String id;
  final String title;
  final String description;
  final int target;
  final int coinReward;
  final int xpReward;
  final int gemReward;
  final int heartReward;
  final int hintReward;
  final IconData icon;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    this.coinReward = 0,
    this.xpReward = 0,
    this.gemReward = 0,
    this.heartReward = 0,
    this.hintReward = 0,
    required this.icon,
  });
}

/// Numărul de gamemoduri deblocate (folosit de "all_modes" mai jos) — ține-l
/// sincronizat manual cu numărul de intrări `locked: false` din gamemodes.dart.
const int unlockedGameModeCount = 14;

const List<Achievement> achievements = [
  Achievement(
    id: 'correct_50',
    title: 'Cunoscător',
    description: '50 de răspunsuri corecte, vreodată',
    target: 50,
    coinReward: 150,
    xpReward: 300,
    hintReward: 5,
    icon: Icons.check_circle_rounded,
  ),
  Achievement(
    id: 'correct_150',
    title: 'Expert',
    description: '150 de răspunsuri corecte, vreodată',
    target: 150,
    coinReward: 350,
    xpReward: 700,
    gemReward: 5,
    hintReward: 8,
    icon: Icons.verified_rounded,
  ),
  Achievement(
    id: 'correct_400',
    title: 'Maestru al cunoașterii',
    description: '400 de răspunsuri corecte, vreodată',
    target: 400,
    coinReward: 800,
    xpReward: 1600,
    gemReward: 20,
    heartReward: 3,
    hintReward: 15,
    icon: Icons.workspace_premium_rounded,
  ),
  Achievement(
    id: 'level_5',
    title: 'În ascensiune',
    description: 'Ajungi la nivelul 5',
    target: 5,
    coinReward: 200,
    gemReward: 3,
    hintReward: 3,
    icon: Icons.trending_up_rounded,
  ),
  Achievement(
    id: 'level_15',
    title: 'Veteran',
    description: 'Ajungi la nivelul 15',
    target: 15,
    coinReward: 500,
    gemReward: 10,
    heartReward: 2,
    hintReward: 8,
    icon: Icons.military_tech_rounded,
  ),
  Achievement(
    id: 'all_modes',
    title: 'Exploratorul',
    description: 'Joacă în toate gamemodurile deblocate',
    target: unlockedGameModeCount,
    coinReward: 350,
    xpReward: 600,
    gemReward: 8,
    hintReward: 5,
    icon: Icons.explore_rounded,
  ),
  Achievement(
    id: 'hints_50',
    title: 'Detectivul',
    description: 'Folosește 50 de hint-uri în total',
    target: 50,
    coinReward: 180,
    xpReward: 350,
    hintReward: 5,
    icon: Icons.tips_and_updates_rounded,
  ),
  Achievement(
    id: 'quests_25',
    title: 'Muncitor harnic',
    description: 'Revendică 25 de quest-uri zilnice',
    target: 25,
    coinReward: 400,
    xpReward: 700,
    gemReward: 12,
    heartReward: 2,
    hintReward: 5,
    icon: Icons.flag_rounded,
  ),
  Achievement(
    id: 'daily_10',
    title: 'Rutina de zi',
    description: 'Termină Daily Challenge de 10 ori',
    target: 10,
    coinReward: 300,
    xpReward: 550,
    gemReward: 5,
    hintReward: 5,
    icon: Icons.bolt_rounded,
  ),
  Achievement(
    id: 'starter_pack_bought',
    title: 'Susținător',
    description: 'Cumpără Pachetul de Start din Magazin',
    target: 1,
    coinReward: 500,
    xpReward: 1000,
    gemReward: 50,
    heartReward: 10,
    hintReward: 20,
    icon: Icons.diamond_rounded,
  ),
];
