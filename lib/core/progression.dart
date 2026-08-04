import 'dart:math';

import 'package:flutter/material.dart';

/// Formula de nivel/XP: curbă mixtă pătratică+cubică, deliberat mai severă
/// decât cea veche (`250 + 60·L²`). Motivul real pentru care se ajungea la
/// nivelul 5 în câteva minute nu era însă curba, ci faptul că XP-ul acordat
/// la o întrebare era EGAL cu punctele ei (140-200 XP per răspuns corect) —
/// vezi [xpForCorrectAnswer] din game_helpers.dart, care rupe acea legătură
/// (11-37 XP per răspuns). Cele două schimbări împreună mută nivelul 5 de la
/// ~16 răspunsuri corecte la 2-3 sesiuni complete de joc.
///
/// XP necesar ca să treci de la nivelul [level] la [level] + 1.
int xpForLevel(int level) => 145 + 58 * level * level + 4 * level * level * level;

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

/// Compoziție variată, nu doar monede: hints la fiecare 3 niveluri, vieți la
/// fiecare 4, gems la fiecare 5 (plus un bonus în plus la multipli de 25).
/// Valorile sunt mai mari decât în economia veche fiindcă un nivel e acum
/// mult mai rar — vezi [xpForLevel].
LevelReward levelReward(int level) {
  if (level <= 1) return const LevelReward();
  final coins = 47 + 34 * level;
  final hints = level % 3 == 0 ? 3 : 0;
  final hearts = level % 4 == 0 ? 2 : 0;
  var gems = level % 5 == 0 ? 7 : 0;
  if (level % 25 == 0) gems += 23;
  return LevelReward(coins: coins, hints: hints, hearts: hearts, gems: gems);
}

/// Recompensa acordată la fiecare 10 întrebări răspunse într-o sesiune de
/// joc dintr-o categorie (vezi GameScreen) — [milestone] = 1 la a 10-a
/// întrebare, 2 la a 20-a etc. Viața nu e în model, se acordă separat de
/// apelant (acum doar la milestone-urile pare, nu la fiecare — vezi
/// [milestoneGrantsLife]). Progresivă, dar cu o pantă mult mai mică decât
/// înainte (era 30·m monede / 80·m XP).
class GameModeMilestoneReward {
  final int coins;
  final int xp;
  final int gems;
  const GameModeMilestoneReward(
      {required this.coins, required this.xp, required this.gems});
}

GameModeMilestoneReward gameModeMilestoneReward(int milestone) {
  return GameModeMilestoneReward(
    coins: 23 + 19 * milestone,
    xp: 17 + 13 * milestone,
    gems: milestone >= 3 ? milestone - 2 : 0,
  );
}

/// Viața bonus vine acum la fiecare al doilea milestone (20, 40, 60 de
/// întrebări), nu la fiecare — o sesiune lungă nu mai era practic niciodată
/// în pericol să rămână fără vieți.
bool milestoneGrantsLife(int milestone) => milestone % 2 == 0;

// ─── Taxă de intrare la categorii solo ────────────────────────────────────
// La intrarea într-o categorie (vezi categories_screen.dart._enterCategory)
// se plătește o taxă în monede; la ieșire (game over, "Ai terminat toate
// întrebările", butonul înapoi din joc SAU back-ul telefonului — vezi
// GameScreen._settleExitReward), recompensa depinde STRICT de câte răspunsuri
// CORECTE ai dat în acea sesiune.
//
// Spre deosebire de varianta veche (taxă fixă, 15 monede), taxa SCALEAZĂ cu
// averea curentă: e principalul sink care crește odată cu venitul, ca banii
// să nu se acumuleze exponențial la jucătorii vechi. Plafoanele o țin
// rezonabilă în ambele capete (un începător plătește 13, un jucător bogat
// niciodată mai mult de 174).

const int categoryEntryFeeMin = 13;
const int categoryEntryFeeMax = 174;
const double categoryEntryFeeRatio = 0.021;

int categoryEntryFee(int coins) => (coins * categoryEntryFeeRatio)
    .round()
    .clamp(categoryEntryFeeMin, categoryEntryFeeMax);

/// Recompensa la ieșire, în 4 trepte pe numărul de răspunsuri corecte din
/// sesiune, raportate la taxa efectiv plătită ([feePaid], nu la taxa de
/// acum — averea s-a schimbat între timp). Sub 4 corecte nu se mai întoarce
/// nimic (înainte se dădea jumătate înapoi doar pentru că ai intrat), iar
/// pragul de profit e mutat la 15 corecte: o sesiune bună aduce +30%, nu
/// +50% la 8 întrebări.
int categoryExitReward(int correctCount, int feePaid) {
  if (correctCount >= 15) return (feePaid * 1.3).round();
  if (correctCount >= 8) return feePaid;
  if (correctCount >= 4) return (feePaid * 0.6).round();
  return 0;
}

// ─── Recompensa de la finalul unui meci multiplayer ───────────────────────
// Monedele NU mai vin de aici: la final se împarte pool-ul de pariuri (vezi
// core/betting.dart) — un meci multiplayer e acum redistribuire între
// jucători, nu o sursă nouă de bani. XP-ul rămâne o recompensă normală,
// recalibrată pe noua scară (un răspuns corect solo dă 11-37 XP).

const int multiplayerWinXpBonus = 47;
const int multiplayerParticipationXpBonus = 13;

/// Bonus fix, o dată pe zi, la prima victorie multiplayer a zilei — vezi
/// StorageService.canClaimFirstWinOfDay. Singurele monede "din partea casei"
/// rămase în multiplayer, exact ca să existe un motiv să joci primul meci.
const int multiplayerFirstWinBonusCoins = 137;
const int multiplayerFirstWinBonusXp = 89;

/// XP-ul de la finalul unui meci. Partea din scor nu poate scădea sub zero:
/// de când un răspuns greșit costă puncte în modul Clasic (vezi
/// multiplayerWrongPenalty), scorul poate ieși negativ, iar fără garda asta un
/// meci foarte prost i-ar fi ȘTERS jucătorului XP câștigat în altă parte —
/// sub −1.084 de puncte, funcția întorcea un număr negativ care ajungea direct
/// în StorageService.addXp. Un meci slab nu aduce mare lucru, dar nu ia înapoi.
int multiplayerXpForScore(int score, {required bool won}) {
  final fromScore = (score * 0.012).round();
  return (fromScore < 0 ? 0 : fromScore) +
      (won ? multiplayerWinXpBonus : multiplayerParticipationXpBonus);
}

/// Un quest zilnic: progresul se ține în [StorageService], definiția
/// (țintă, recompensă) e statică aici. [metricKey] leagă variante de
/// dificultate diferită ale aceleiași acțiuni (ex: correct_5/10/15) de UN
/// singur contor de progres persistat — implicit egal cu [id] dacă nu se
/// specifică altul.
///
/// Gems NU mai sunt un câmp per quest: se derivă din [tier] (vezi
/// [Quest.gemReward]), fiindcă acum FIECARE quest dă gems — 1 la cele
/// ușoare, 2 la cele medii, 4 la cele grele. Fără plafon ar însemna 60+
/// gems pe zi la un jucător care revendică 30 de quest-uri, de-aia există
/// [dailyQuestGemCap].
enum QuestTier { easy, medium, hard }

class Quest {
  final String id;
  final String title;
  final int target;
  final String metricKey;
  final QuestTier tier;
  final int _baseCoinReward;
  final int _baseXpReward;
  final int _baseHeartReward;
  final int _baseHintReward;
  final IconData icon;

  const Quest({
    required this.id,
    required this.title,
    required this.target,
    required this.tier,
    String? metricKey,
    int coinReward = 0,
    int xpReward = 0,
    int heartReward = 0,
    int hintReward = 0,
    required this.icon,
  })  : metricKey = metricKey ?? id,
        _baseCoinReward = coinReward,
        _baseXpReward = xpReward,
        _baseHeartReward = heartReward,
        _baseHintReward = hintReward;

  // Valorile scrise în catalog sunt cele de BAZĂ, calibrate pe vremea când
  // toate cele 71 de quest-uri erau active simultan. De când e rotație
  // zilnică (vezi [todaysQuests] — ~10 quest-uri pe zi), fiecare quest
  // rămas trebuie să plătească proporțional mai mult, altfel venitul zilnic
  // din quest-uri s-ar prăbuși de ~7 ori. Multiplicatorii se aplică AICI, o
  // singură dată, ca să nu trebuiască rescrise 71 de intrări la fiecare
  // recalibrare.

  int get coinReward => (_baseCoinReward * questCoinRewardMultiplier).round();
  int get xpReward => (_baseXpReward * questXpRewardMultiplier).round();
  int get heartReward => (_baseHeartReward * questHeartRewardMultiplier).round();
  int get hintReward => (_baseHintReward * questHintRewardMultiplier).round();

  /// Gems acordate de acest quest, dedus din dificultate. Ținta e explicită:
  /// o SĂPTĂMÂNĂ de joc, cu puțină străduință și puțin noroc, să adune cât
  /// costă deblocarea unei categorii noi (34 gems, vezi
  /// [questionUnlockGemsPrice]) — nu o categorie pe zi.
  ///
  /// De-aia quest-urile ușoare nu mai dau gems deloc: o săptămână întreagă
  /// înseamnă 27 de quest-uri medii (1 gem) + 16 grele (2 gems) = maximum 59
  /// dacă le termini absolut pe toate, ceea ce nu se întâmplă — un jucător
  /// realist ajunge pe la 30-40, adică fix o categorie pe săptămână.
  ///
  /// Cantitatea EFECTIV primită poate fi mai mică (0) dacă s-a atins deja
  /// [dailyQuestGemCap] azi, vezi StorageService.grantQuestGems.
  int get gemReward => switch (tier) {
        QuestTier.easy => 0,
        QuestTier.medium => 1,
        QuestTier.hard => 2,
      };
}

/// Multiplicatorii de recompensă aplicați peste valorile din catalog (vezi
/// comentariul din [Quest]). Monedele/XP-ul cresc de 3×, fiindcă numărul de
/// quest-uri revendicabile pe zi a scăzut de la ~30 (dintr-un pool de 71,
/// toate active) la ~10. Hint-urile cresc mai puțin (plafon de stoc la 26,
/// vezi StorageService) și vieţile cel mai puțin — sunt resursa care
/// controlează cât poți juca, deci cea mai sensibilă la inflație.
const double questCoinRewardMultiplier = 3.0;
const double questXpRewardMultiplier = 3.0;
const double questHintRewardMultiplier = 1.5;
const double questHeartRewardMultiplier = 2.0;

/// Câte gems pot veni în total din quest-uri într-o zi calendaristică. Peste
/// plafon, quest-ul se revendică normal (monede/XP/hints/vieți), doar partea
/// de gems e 0. Cea mai bogată zi din rotație dă 10 gems revendicată integral
/// (4 medii + 3 grele), deci plafonul de 13 nu retează niciodată un jucător
/// cinstit — există strict ca "Revendică x2" (care dublează și gems-ul) să nu
/// poată transforma o săptămână de gems într-una singură.
const int dailyQuestGemCap = 13;

// ─── Catalogul de quest-uri (71 în total) ──────────────────────────────────
// Împărțit pe 3 nivele de dificultate ([QuestTier], care determină și gems-ul
// acordat). NU toate sunt active în aceeași zi: [todaysQuests] le împarte
// într-o rotație săptămânală de ~10 pe zi. Progresul fiecăruia se resetează
// oricum zilnic.

const List<Quest> _easyQuests = [
  Quest(
      id: 'answer_1',
      title: 'Răspunde la prima întrebare a zilei',
      target: 1,
      metricKey: 'answer_count',
      tier: QuestTier.easy,
      coinReward: 9,
      xpReward: 8,
      hintReward: 1,
      icon: Icons.play_circle_fill_rounded),
  Quest(
      id: 'correct_5',
      title: 'Răspunde corect la 5 întrebări',
      target: 5,
      metricKey: 'correct_count',
      tier: QuestTier.easy,
      coinReward: 15,
      xpReward: 10,
      hintReward: 1,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'answer_10',
      title: 'Răspunde la 10 întrebări (corect sau greșit)',
      target: 10,
      metricKey: 'answer_count',
      tier: QuestTier.easy,
      coinReward: 15,
      xpReward: 11,
      hintReward: 1,
      icon: Icons.playlist_add_check_rounded),
  Quest(
      id: 'play_2_modes',
      title: 'Joacă în 2 gamemoduri diferite',
      target: 2,
      metricKey: 'modes_played',
      tier: QuestTier.easy,
      coinReward: 13,
      xpReward: 10,
      hintReward: 2,
      icon: Icons.grid_view_rounded),
  Quest(
      id: 'use_hints_3',
      title: 'Folosește 3 hint-uri',
      target: 3,
      metricKey: 'hints_used',
      tier: QuestTier.easy,
      coinReward: 11,
      xpReward: 8,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'no_hint_3',
      title: 'Ghicește corect 3 întrebări fără niciun hint',
      target: 3,
      metricKey: 'no_hint_correct',
      tier: QuestTier.easy,
      coinReward: 17,
      xpReward: 12,
      hintReward: 1,
      icon: Icons.visibility_off_rounded),
  Quest(
      id: 'earn_60_coins',
      title: 'Strânge 60 de monede jucând',
      target: 60,
      metricKey: 'coins_earned',
      tier: QuestTier.easy,
      coinReward: 13,
      xpReward: 9,
      hintReward: 1,
      icon: Icons.savings_rounded),
  Quest(
      id: 'streak_3',
      title: 'Obține o serie de 3 răspunsuri corecte la rând',
      target: 1,
      metricKey: 'streak_hit_3',
      tier: QuestTier.easy,
      coinReward: 15,
      xpReward: 12,
      hintReward: 1,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'daily_challenge_done',
      title: 'Termină Daily Challenge de azi',
      target: 1,
      tier: QuestTier.easy,
      coinReward: 17,
      xpReward: 13,
      hintReward: 1,
      icon: Icons.bolt_rounded),
  Quest(
      id: 'culture_correct_5',
      title: 'Răspunde corect la 5 întrebări de Cultură Generală',
      target: 5,
      metricKey: 'culture_quiz_correct',
      tier: QuestTier.easy,
      coinReward: 13,
      xpReward: 10,
      hintReward: 1,
      icon: Icons.public_rounded),
  Quest(
      id: 'clippy_done_1',
      title: 'Termină un bonus de la Clippy',
      target: 1,
      metricKey: 'clippy_done',
      tier: QuestTier.easy,
      coinReward: 11,
      xpReward: 9,
      hintReward: 1,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'unlimited_correct_10',
      title: 'Răspunde corect la 10 întrebări în Quiz Nelimitat',
      target: 10,
      metricKey: 'unlimited_quiz_correct',
      tier: QuestTier.easy,
      coinReward: 13,
      xpReward: 10,
      hintReward: 1,
      icon: Icons.all_inclusive_rounded),
  Quest(
      id: 'wheel_spin_1',
      title: 'Învârte Roata norocului',
      target: 1,
      metricKey: 'wheel_spin',
      tier: QuestTier.easy,
      coinReward: 11,
      xpReward: 8,
      hintReward: 1,
      icon: Icons.casino_rounded),
  Quest(
      id: 'claim_daily_lives',
      title: 'Revendică recompensa zilnică de vieți',
      target: 1,
      metricKey: 'daily_lives_claimed',
      tier: QuestTier.easy,
      coinReward: 13,
      xpReward: 8,
      hintReward: 1,
      icon: Icons.favorite_rounded),
  Quest(
      id: 'hint_buy_1',
      title: 'Cumpără un pachet de hints din Magazin',
      target: 1,
      metricKey: 'hint_pack_bought',
      tier: QuestTier.easy,
      coinReward: 9,
      xpReward: 8,
      heartReward: 1,
      icon: Icons.storefront_rounded),
  Quest(
      id: 'heart_buy_1',
      title: 'Cumpără o viață din Magazin',
      target: 1,
      metricKey: 'heart_bought',
      tier: QuestTier.easy,
      coinReward: 9,
      xpReward: 8,
      hintReward: 2,
      icon: Icons.storefront_rounded),
  Quest(
      id: 'answer_5',
      title: 'Răspunde la 5 întrebări (corect sau greșit)',
      target: 5,
      metricKey: 'answer_count',
      tier: QuestTier.easy,
      coinReward: 13,
      xpReward: 9,
      hintReward: 1,
      icon: Icons.playlist_add_check_rounded),
  Quest(
      id: 'answer_3',
      title: 'Răspunde la 3 întrebări (corect sau greșit)',
      target: 3,
      metricKey: 'answer_count',
      tier: QuestTier.easy,
      coinReward: 11,
      xpReward: 8,
      hintReward: 1,
      icon: Icons.playlist_add_check_rounded),
  Quest(
      id: 'correct_3',
      title: 'Răspunde corect la 3 întrebări',
      target: 3,
      metricKey: 'correct_count',
      tier: QuestTier.easy,
      coinReward: 11,
      xpReward: 8,
      hintReward: 1,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'earn_30_coins',
      title: 'Strânge 30 de monede jucând',
      target: 30,
      metricKey: 'coins_earned',
      tier: QuestTier.easy,
      coinReward: 9,
      xpReward: 8,
      hintReward: 1,
      icon: Icons.savings_rounded),
  Quest(
      id: 'earn_45_coins',
      title: 'Strânge 45 de monede jucând',
      target: 45,
      metricKey: 'coins_earned',
      tier: QuestTier.easy,
      coinReward: 11,
      xpReward: 9,
      hintReward: 1,
      icon: Icons.savings_rounded),
  Quest(
      id: 'use_hints_1',
      title: 'Folosește 1 hint',
      target: 1,
      metricKey: 'hints_used',
      tier: QuestTier.easy,
      coinReward: 9,
      xpReward: 7,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'use_hints_2',
      title: 'Folosește 2 hint-uri',
      target: 2,
      metricKey: 'hints_used',
      tier: QuestTier.easy,
      coinReward: 9,
      xpReward: 8,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'no_hint_1',
      title: 'Ghicește corect o întrebare fără niciun hint',
      target: 1,
      metricKey: 'no_hint_correct',
      tier: QuestTier.easy,
      coinReward: 11,
      xpReward: 8,
      hintReward: 1,
      icon: Icons.visibility_off_rounded),
  Quest(
      id: 'culture_correct_3',
      title: 'Răspunde corect la 3 întrebări de Cultură Generală',
      target: 3,
      metricKey: 'culture_quiz_correct',
      tier: QuestTier.easy,
      coinReward: 11,
      xpReward: 8,
      hintReward: 1,
      icon: Icons.public_rounded),
  Quest(
      id: 'culture_batches_1',
      title: 'Termină un lot de Cultură Generală',
      target: 1,
      metricKey: 'culture_quiz_batches',
      tier: QuestTier.easy,
      coinReward: 11,
      xpReward: 9,
      hintReward: 1,
      icon: Icons.public_rounded),
  Quest(
      id: 'unlimited_correct_5',
      title: 'Răspunde corect la 5 întrebări în Quiz Nelimitat',
      target: 5,
      metricKey: 'unlimited_quiz_correct',
      tier: QuestTier.easy,
      coinReward: 11,
      xpReward: 8,
      hintReward: 1,
      icon: Icons.all_inclusive_rounded),
  Quest(
      id: 'play_1_mode',
      title: 'Joacă într-un gamemod, oricare',
      target: 1,
      metricKey: 'modes_played',
      tier: QuestTier.easy,
      coinReward: 9,
      xpReward: 7,
      hintReward: 1,
      icon: Icons.grid_view_rounded),
];

const List<Quest> _mediumQuests = [
  Quest(
      id: 'correct_10',
      title: 'Răspunde corect la 10 întrebări',
      target: 10,
      metricKey: 'correct_count',
      tier: QuestTier.medium,
      coinReward: 29,
      xpReward: 24,
      hintReward: 2,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'answer_20',
      title: 'Răspunde la 20 de întrebări (corect sau greșit)',
      target: 20,
      metricKey: 'answer_count',
      tier: QuestTier.medium,
      coinReward: 31,
      xpReward: 25,
      hintReward: 2,
      icon: Icons.playlist_add_check_rounded),
  Quest(
      id: 'play_3_modes',
      title: 'Joacă în 3 gamemoduri diferite',
      target: 3,
      metricKey: 'modes_played',
      tier: QuestTier.medium,
      coinReward: 27,
      xpReward: 23,
      hintReward: 2,
      icon: Icons.grid_view_rounded),
  Quest(
      id: 'use_hints_6',
      title: 'Folosește 6 hint-uri',
      target: 6,
      metricKey: 'hints_used',
      tier: QuestTier.medium,
      coinReward: 27,
      xpReward: 20,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'no_hint_6',
      title: 'Ghicește corect 6 întrebări fără niciun hint',
      target: 6,
      metricKey: 'no_hint_correct',
      tier: QuestTier.medium,
      coinReward: 34,
      xpReward: 27,
      hintReward: 2,
      icon: Icons.visibility_off_rounded),
  Quest(
      id: 'earn_150_coins',
      title: 'Strânge 150 de monede jucând',
      target: 150,
      metricKey: 'coins_earned',
      tier: QuestTier.medium,
      coinReward: 29,
      xpReward: 22,
      hintReward: 1,
      icon: Icons.savings_rounded),
  Quest(
      id: 'streak_5',
      title: 'Obține o serie de 5 răspunsuri corecte la rând',
      target: 1,
      metricKey: 'streak_hit_5',
      tier: QuestTier.medium,
      coinReward: 31,
      xpReward: 27,
      heartReward: 1,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'streak_3_twice',
      title: 'Obține o serie de 3 răspunsuri corecte, de 2 ori azi',
      target: 2,
      metricKey: 'streak_hit_3',
      tier: QuestTier.medium,
      coinReward: 24,
      xpReward: 22,
      hintReward: 2,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'culture_correct_10',
      title: 'Răspunde corect la 10 întrebări de Cultură Generală',
      target: 10,
      metricKey: 'culture_quiz_correct',
      tier: QuestTier.medium,
      coinReward: 29,
      xpReward: 24,
      hintReward: 1,
      icon: Icons.public_rounded),
  Quest(
      id: 'culture_batches_2',
      title: 'Termină 2 loturi de Cultură Generală',
      target: 2,
      metricKey: 'culture_quiz_batches',
      tier: QuestTier.medium,
      coinReward: 24,
      xpReward: 22,
      heartReward: 1,
      hintReward: 2,
      icon: Icons.public_rounded),
  Quest(
      id: 'clippy_done_2',
      title: 'Termină 2 bonusuri de la Clippy',
      target: 2,
      metricKey: 'clippy_done',
      tier: QuestTier.medium,
      coinReward: 21,
      xpReward: 20,
      hintReward: 2,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'unlimited_correct_25',
      title: 'Răspunde corect la 25 de întrebări în Quiz Nelimitat',
      target: 25,
      metricKey: 'unlimited_quiz_correct',
      tier: QuestTier.medium,
      coinReward: 29,
      xpReward: 24,
      hintReward: 2,
      icon: Icons.all_inclusive_rounded),
  Quest(
      id: 'level_up_1',
      title: 'Revendică o recompensă de nivel',
      target: 1,
      metricKey: 'level_reward_claimed',
      tier: QuestTier.medium,
      coinReward: 24,
      xpReward: 19,
      hintReward: 1,
      icon: Icons.military_tech_rounded),
  Quest(
      id: 'spend_any_1',
      title: 'Cheltuie monede sau gems în Magazin',
      target: 1,
      metricKey: 'shop_spend',
      tier: QuestTier.medium,
      xpReward: 16,
      heartReward: 1,
      hintReward: 1,
      icon: Icons.shopping_cart_rounded),
  Quest(
      id: 'answer_15',
      title: 'Răspunde la 15 întrebări (corect sau greșit)',
      target: 15,
      metricKey: 'answer_count',
      tier: QuestTier.medium,
      coinReward: 23,
      xpReward: 20,
      hintReward: 2,
      icon: Icons.playlist_add_check_rounded),
  Quest(
      id: 'answer_25',
      title: 'Răspunde la 25 de întrebări (corect sau greșit)',
      target: 25,
      metricKey: 'answer_count',
      tier: QuestTier.medium,
      coinReward: 31,
      xpReward: 27,
      hintReward: 2,
      icon: Icons.playlist_add_check_rounded),
  Quest(
      id: 'hints_used_10',
      title: 'Folosește 10 hint-uri',
      target: 10,
      metricKey: 'hints_used',
      tier: QuestTier.medium,
      coinReward: 25,
      xpReward: 22,
      hintReward: 1,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'no_hint_10',
      title: 'Ghicește corect 10 întrebări fără niciun hint',
      target: 10,
      metricKey: 'no_hint_correct',
      tier: QuestTier.medium,
      coinReward: 29,
      xpReward: 24,
      hintReward: 2,
      icon: Icons.visibility_off_rounded),
  Quest(
      id: 'earn_250_coins',
      title: 'Strânge 250 de monede jucând',
      target: 250,
      metricKey: 'coins_earned',
      tier: QuestTier.medium,
      coinReward: 27,
      xpReward: 22,
      hintReward: 1,
      icon: Icons.savings_rounded),
  Quest(
      id: 'culture_correct_15',
      title: 'Răspunde corect la 15 întrebări de Cultură Generală',
      target: 15,
      metricKey: 'culture_quiz_correct',
      tier: QuestTier.medium,
      coinReward: 27,
      xpReward: 23,
      hintReward: 2,
      icon: Icons.public_rounded),
  Quest(
      id: 'unlimited_correct_35',
      title: 'Răspunde corect la 35 de întrebări în Quiz Nelimitat',
      target: 35,
      metricKey: 'unlimited_quiz_correct',
      tier: QuestTier.medium,
      coinReward: 27,
      xpReward: 23,
      hintReward: 2,
      icon: Icons.all_inclusive_rounded),
  Quest(
      id: 'clippy_done_3',
      title: 'Termină 3 bonusuri de la Clippy',
      target: 3,
      metricKey: 'clippy_done',
      tier: QuestTier.medium,
      coinReward: 24,
      xpReward: 22,
      hintReward: 2,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'hint_pack_bought_2',
      title: 'Cumpără 2 pachete de hints din Magazin',
      target: 2,
      metricKey: 'hint_pack_bought',
      tier: QuestTier.medium,
      coinReward: 23,
      xpReward: 20,
      hintReward: 2,
      icon: Icons.storefront_rounded),
  Quest(
      id: 'heart_bought_2',
      title: 'Cumpără 2 vieți din Magazin',
      target: 2,
      metricKey: 'heart_bought',
      tier: QuestTier.medium,
      coinReward: 23,
      xpReward: 20,
      hintReward: 2,
      icon: Icons.storefront_rounded),
  Quest(
      id: 'shop_spend_2',
      title: 'Cheltuie de 2 ori în Magazin sau la Deblocare',
      target: 2,
      metricKey: 'shop_spend',
      tier: QuestTier.medium,
      coinReward: 21,
      xpReward: 19,
      hintReward: 2,
      icon: Icons.shopping_cart_rounded),
  Quest(
      id: 'streak_5_twice',
      title: 'Obține o serie de 5 răspunsuri corecte, de 2 ori azi',
      target: 2,
      metricKey: 'streak_hit_5',
      tier: QuestTier.medium,
      coinReward: 29,
      xpReward: 25,
      hintReward: 2,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'mp_bet_1',
      title: 'Joacă un meci multiplayer cu pariu',
      target: 1,
      metricKey: 'mp_bet_played',
      tier: QuestTier.medium,
      coinReward: 26,
      xpReward: 23,
      hintReward: 1,
      icon: Icons.casino_rounded),
];

const List<Quest> _hardQuests = [
  Quest(
      id: 'correct_15',
      title: 'Răspunde corect la 15 întrebări',
      target: 15,
      metricKey: 'correct_count',
      tier: QuestTier.hard,
      coinReward: 51,
      xpReward: 42,
      hintReward: 2,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'streak_8',
      title: 'Obține o serie de 8 răspunsuri corecte la rând',
      target: 1,
      metricKey: 'streak_hit_8',
      tier: QuestTier.hard,
      coinReward: 54,
      xpReward: 54,
      heartReward: 1,
      hintReward: 2,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'earn_300_coins',
      title: 'Strânge 300 de monede jucând',
      target: 300,
      metricKey: 'coins_earned',
      tier: QuestTier.hard,
      coinReward: 48,
      xpReward: 39,
      heartReward: 1,
      hintReward: 3,
      icon: Icons.savings_rounded),
  Quest(
      id: 'clippy_perfect_1',
      title: 'Termină un bonus de la Clippy perfect (3/3)',
      target: 1,
      metricKey: 'clippy_perfect',
      tier: QuestTier.hard,
      coinReward: 41,
      xpReward: 33,
      hintReward: 3,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'unlock_batch_1',
      title: 'Deblochează un lot nou de întrebări',
      target: 1,
      metricKey: 'question_batch_unlocked',
      tier: QuestTier.hard,
      coinReward: 67,
      xpReward: 36,
      hintReward: 3,
      icon: Icons.lock_open_rounded),
  Quest(
      id: 'play_4_modes',
      title: 'Joacă în 4 gamemoduri diferite',
      target: 4,
      metricKey: 'modes_played',
      tier: QuestTier.hard,
      coinReward: 51,
      xpReward: 45,
      hintReward: 2,
      icon: Icons.grid_view_rounded),
  Quest(
      id: 'culture_batches_3',
      title: 'Termină 3 loturi de Cultură Generală',
      target: 3,
      metricKey: 'culture_quiz_batches',
      tier: QuestTier.hard,
      coinReward: 48,
      xpReward: 42,
      hintReward: 2,
      icon: Icons.public_rounded),
  Quest(
      id: 'claim_3_quests_today',
      title: 'Revendică alte 3 quest-uri azi',
      target: 3,
      metricKey: 'quests_claimed_today',
      tier: QuestTier.hard,
      coinReward: 54,
      xpReward: 48,
      hintReward: 2,
      icon: Icons.flag_rounded),
  Quest(
      id: 'correct_20',
      title: 'Răspunde corect la 20 de întrebări',
      target: 20,
      metricKey: 'correct_count',
      tier: QuestTier.hard,
      coinReward: 53,
      xpReward: 45,
      hintReward: 2,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'answer_40',
      title: 'Răspunde la 40 de întrebări (corect sau greșit)',
      target: 40,
      metricKey: 'answer_count',
      tier: QuestTier.hard,
      coinReward: 51,
      xpReward: 42,
      hintReward: 2,
      icon: Icons.playlist_add_check_rounded),
  Quest(
      id: 'streak_10',
      title: 'Obține o serie de 10 răspunsuri corecte la rând',
      target: 1,
      metricKey: 'streak_hit_10',
      tier: QuestTier.hard,
      coinReward: 57,
      xpReward: 51,
      hintReward: 3,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'earn_500_coins',
      title: 'Strânge 500 de monede jucând',
      target: 500,
      metricKey: 'coins_earned',
      tier: QuestTier.hard,
      coinReward: 51,
      xpReward: 42,
      hintReward: 2,
      icon: Icons.savings_rounded),
  Quest(
      id: 'play_5_modes',
      title: 'Joacă în 5 gamemoduri diferite',
      target: 5,
      metricKey: 'modes_played',
      tier: QuestTier.hard,
      coinReward: 54,
      xpReward: 48,
      hintReward: 2,
      icon: Icons.grid_view_rounded),
  Quest(
      id: 'unlimited_correct_60',
      title: 'Răspunde corect la 60 de întrebări în Quiz Nelimitat',
      target: 60,
      metricKey: 'unlimited_quiz_correct',
      tier: QuestTier.hard,
      coinReward: 53,
      xpReward: 45,
      hintReward: 2,
      icon: Icons.all_inclusive_rounded),
  Quest(
      id: 'clippy_perfect_2',
      title: 'Termină un bonus de la Clippy perfect (3/3), de 2 ori azi',
      target: 2,
      metricKey: 'clippy_perfect',
      tier: QuestTier.hard,
      coinReward: 48,
      xpReward: 42,
      hintReward: 3,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'claim_5_quests_today',
      title: 'Revendică alte 5 quest-uri azi',
      target: 5,
      metricKey: 'quests_claimed_today',
      tier: QuestTier.hard,
      coinReward: 61,
      xpReward: 54,
      hintReward: 3,
      icon: Icons.flag_rounded),
];

/// Toate quest-urile din joc — sursă pentru [questById] și pentru afișarea
/// "din X quest-uri în total" pe ecranul de Quests. Vezi [todaysQuests]
/// pentru care dintre ele sunt active azi.
const List<Quest> allQuests = [
  ..._easyQuests,
  ..._mediumQuests,
  ..._hardQuests
];

Quest questById(String id) => allQuests.firstWhere((q) => q.id == id);

// ─── Rotația săptămânală de quest-uri ──────────────────────────────────────
// Cerința: nu toate cele 71 de quest-uri deodată, ci ~10 pe zi, DIFERITE de
// la o zi la alta și fără repetare în cadrul aceleiași săptămâni — iar când
// vine iar lunea, revine exact setul de luni.
//
// De-aia catalogul e împărțit O SINGURĂ DATĂ în [questRotationDays] grupe
// disjuncte, iar ziua săptămânii ([DateTime.weekday]) alege grupa. Partiția
// NU depinde de dată (sămânță fixă, vezi [_questRotationSeed]) — dacă ar
// depinde, "lunea viitoare" ar aduce alt set, nu același.
//
// Cele 71 nu se împart perfect la 7: grupele au 9-11 quest-uri (media 10,1),
// iar fiecare grupă primește din toate cele trei dificultăți, fiindcă
// împărțirea se face separat pe fiecare tier, cu decalaje diferite de
// pornire (0/3/5) ca resturile să nu cadă mereu în aceleași zile.

const int questRotationDays = 7;

/// Sămânță FIXĂ pentru amestecarea catalogului înainte de împărțire —
/// schimbarea ei rearanjează complet ce quest-uri pică în ce zi.
const int _questRotationSeed = 20260803;

List<List<Quest>>? _rotationCache;

/// Împarte un tier în grupele zilnice, dealuind familie cu familie (toate
/// variantele care împart același [Quest.metricKey], ex. answer_3/answer_5/
/// answer_10). Membrii unei familii pică pe zile CONSECUTIVE, deci — cât timp
/// o familie are cel mult [questRotationDays] variante într-un tier — nicio
/// zi nu primește două quest-uri care se completează din același contor.
void _dealTier(List<List<Quest>> days, List<Quest> pool, int startDay) {
  final families = <String, List<Quest>>{};
  for (final q in pool) {
    families.putIfAbsent(q.metricKey, () => <Quest>[]).add(q);
  }
  final keys = families.keys.toList()
    ..sort()
    ..shuffle(Random(_questRotationSeed + startDay));
  var slot = startDay;
  for (final key in keys) {
    for (final quest in families[key]!) {
      days[slot % questRotationDays].add(quest);
      slot++;
    }
  }
}

List<List<Quest>> _questRotation() {
  final cached = _rotationCache;
  if (cached != null) return cached;
  final days = List.generate(questRotationDays, (_) => <Quest>[]);
  _dealTier(days, _easyQuests, 0);
  _dealTier(days, _mediumQuests, 3);
  _dealTier(days, _hardQuests, 5);
  for (final day in days) {
    // ușoare întâi, grele la final — lista de pe ecran urcă în dificultate.
    day.sort((a, b) => a.tier.index.compareTo(b.tier.index));
  }
  return _rotationCache = days;
}

/// Quest-urile active AZI — grupa zilei curente din rotația săptămânală (vezi
/// mai sus). Progresul fiecăruia se resetează oricum zilnic (chei de storage
/// scoped pe dată).
List<Quest> todaysQuests([DateTime? now]) =>
    _questRotation()[((now ?? DateTime.now()).weekday - 1) % questRotationDays];

/// O realizare permanentă: spre deosebire de [Quest] (zilnic, se resetează),
/// progresul unei realizări e cumulativ pe viață — o dată revendicată,
/// rămâne revendicată pentru totdeauna. Monedele sunt DELIBERAT mari (×1,4
/// față de economia veche), iar XP-ul mult mai mic (÷3,4) — un punct de XP
/// valorează acum de ~15 ori mai mult decât înainte, vezi [xpForLevel].
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
    coinReward: 211,
    xpReward: 88,
    hintReward: 5,
    icon: Icons.check_circle_rounded,
  ),
  Achievement(
    id: 'correct_150',
    title: 'Expert',
    description: '150 de răspunsuri corecte, vreodată',
    target: 150,
    coinReward: 491,
    xpReward: 206,
    gemReward: 7,
    hintReward: 8,
    icon: Icons.verified_rounded,
  ),
  Achievement(
    id: 'correct_400',
    title: 'Maestru al cunoașterii',
    description: '400 de răspunsuri corecte, vreodată',
    target: 400,
    coinReward: 1123,
    xpReward: 471,
    gemReward: 27,
    heartReward: 3,
    hintReward: 15,
    icon: Icons.workspace_premium_rounded,
  ),
  Achievement(
    id: 'level_5',
    title: 'În ascensiune',
    description: 'Ajungi la nivelul 5',
    target: 5,
    coinReward: 281,
    gemReward: 4,
    hintReward: 3,
    icon: Icons.trending_up_rounded,
  ),
  Achievement(
    id: 'level_15',
    title: 'Veteran',
    description: 'Ajungi la nivelul 15',
    target: 15,
    coinReward: 703,
    gemReward: 13,
    heartReward: 2,
    hintReward: 8,
    icon: Icons.military_tech_rounded,
  ),
  Achievement(
    id: 'all_modes',
    title: 'Exploratorul',
    description: 'Joacă în toate gamemodurile deblocate',
    target: unlockedGameModeCount,
    coinReward: 491,
    xpReward: 176,
    gemReward: 11,
    hintReward: 5,
    icon: Icons.explore_rounded,
  ),
  Achievement(
    id: 'hints_50',
    title: 'Detectivul',
    description: 'Folosește 50 de hint-uri în total',
    target: 50,
    coinReward: 253,
    xpReward: 103,
    hintReward: 5,
    icon: Icons.tips_and_updates_rounded,
  ),
  Achievement(
    id: 'quests_25',
    title: 'Muncitor harnic',
    description: 'Revendică 25 de quest-uri zilnice',
    target: 25,
    coinReward: 563,
    xpReward: 206,
    gemReward: 17,
    heartReward: 2,
    hintReward: 5,
    icon: Icons.flag_rounded,
  ),
  Achievement(
    id: 'daily_10',
    title: 'Rutina de zi',
    description: 'Termină Daily Challenge de 10 ori',
    target: 10,
    coinReward: 421,
    xpReward: 162,
    gemReward: 7,
    hintReward: 5,
    icon: Icons.bolt_rounded,
  ),
  Achievement(
    id: 'starter_pack_bought',
    title: 'Susținător',
    description: 'Cumpără Pachetul de Start din Magazin',
    target: 1,
    coinReward: 703,
    xpReward: 294,
    gemReward: 67,
    heartReward: 13,
    hintReward: 27,
    icon: Icons.diamond_rounded,
  ),
];
