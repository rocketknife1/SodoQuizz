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

// ─── Planeta hologramelor ─────────────────────────────────────────────────
// Înlocuiește vechiul Quiz Nelimitat (nelimitat, plătea puțin, se putea farma
// la nesfârșit) cu o rulare SCURTĂ, RARĂ și cu miză: 17 întrebări, 10 inimi
// proprii ale planetei, două-trei rulări la 12 ore.
//
// Inimile planetei sunt separate de cele din balanță — o greșeală aici nu te
// costă niciodată o viață reală. Sunt totuși o condiție de eșec adevărată:
// 10 inimi la 17 întrebări înseamnă că a 11-a greșeală încheie rularea
// înainte de final.
//
// Întrebările sunt un amestec de poze (loadAllQuestions) și Cultură Generală,
// în proporție care se schimbă de la o rulare la alta — vezi
// PlanetHologramScreen. Fără hint și fără blur: pozele se văd clar.

const int planetQuestionCount = 17;
const int planetHearts = 10;

/// Pragurile de scor peste care rularea poate plăti recompensa MARE. Cerința
/// a fost exprimată pe 10 întrebări ("7/10 șansă mică, 8/10 mai mare, 9/10 și
/// mai mare, 10/10 sigur"); aici sunt aceleași proporții mutate pe 17:
/// 70%, 82%, 88% și 100%.
const int planetGoodRunCorrect = 12; // ~70%
const int planetStrongRunCorrect = 14; // ~82%
const int planetGreatRunCorrect = 15; // ~88%

/// Probabilitatea ca recompensa mare să pice, pe praguri. Doar rularea
/// perfectă e garantată; restul sunt EXPLICIT nesigure și rare, cum s-a
/// cerut — un 15/17 e o veste bună, nu un salariu.
double planetJackpotChance(int correct) {
  if (correct >= planetQuestionCount) return 1.0;
  if (correct >= planetGreatRunCorrect) return 0.61;
  if (correct >= planetStrongRunCorrect) return 0.34;
  if (correct >= planetGoodRunCorrect) return 0.17;
  return 0.0;
}

/// Recompensa pe care o poate da o rulare, indiferent de formă.
class PlanetReward {
  final int coins;
  final int xp;
  final int gems;
  final int hearts;
  final int hints;
  const PlanetReward({
    this.coins = 0,
    this.xp = 0,
    this.gems = 0,
    this.hearts = 0,
    this.hints = 0,
  });

  bool get isEmpty =>
      coins == 0 && xp == 0 && gems == 0 && hearts == 0 && hints == 0;
}

/// "Reward din toate" — se acordă întreg, din toate cele cinci resurse.
/// Deliberat mare: planeta se poate juca de cel mult 3 ori la 12 ore, deci
/// valoarea unei rulări reușite trebuie să se simtă, nu să fie încă o sursă
/// măruntă. La mijlocul curbei e comparabilă cu o rotire de roată (~489
/// echivalent-monede, vezi secțiunea 4.1), fiindcă și cooldown-ul e comparabil.
///
/// Monedele și XP-ul urmează [economyGrowth] ca tot restul economiei: 373 la
/// nivelul 1, ~522 la nivelul 10, 772 la plafon. Un premiu fix ar fi fost
/// enorm pentru un începător (aproape o zi întreagă de venit) și derizoriu
/// pentru un veteran. Gems, vieți și hint-uri rămân fixe — sunt resursele cu
/// plafon.
PlanetReward planetJackpotReward(int level) {
  final g = economyGrowth(level);
  return PlanetReward(
    coins: (373 * g).round(),
    xp: (167 * g).round(),
    gems: 23,
    hearts: 4,
    hints: 7,
  );
}

/// Ce primești când zarul nu a căzut bine — sau când n-ai atins nici pragul
/// minim. Proporțională cu câte ai nimerit, ca o rulare bună fără noroc să
/// nu iasă pe zero. Fără gems: aceia rămân exclusiv la recompensa mare.
PlanetReward planetConsolationReward(int correct, int level) {
  if (correct <= 0) return const PlanetReward();
  final g = economyGrowth(level);
  return PlanetReward(
    coins: (8 * correct * g).round(),
    xp: (4 * correct * g).round(),
    hearts: correct >= planetGreatRunCorrect ? 1 : 0,
    hints: correct >= planetGoodRunCorrect ? 2 : 0,
  );
}

/// Câte rulări ai la dispoziție într-un ciclu, fără și cu reclamă vizionată.
/// După ce le consumi pe toate ȘI ridici recompensa ultimei, pornește
/// cooldown-ul — vezi StorageService.planetRunsLeft / startPlanetCooldown.
const int planetRunsPerCycle = 2;
const int planetRunsPerCycleWithAd = 3;
const int planetCooldownHours = 12;

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
  final String _titleTemplate;
  final int _baseTarget;
  final String metricKey;
  final QuestTier tier;
  final int _baseCoinReward;
  final int _baseXpReward;
  final int _baseHeartReward;
  final int _baseHintReward;
  final IconData icon;

  const Quest({
    required this.id,
    required String title,
    required int target,
    required this.tier,
    String? metricKey,
    int coinReward = 0,
    int xpReward = 0,
    int heartReward = 0,
    int hintReward = 0,
    required this.icon,
  })  : metricKey = metricKey ?? id,
        _titleTemplate = title,
        _baseTarget = target,
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

  /// Monedele și XP-ul cresc cu nivelul jucătorului (vezi [economyGrowth]) —
  /// de-aia sunt METODE, nu getteri: nu există o valoare corectă a lor în
  /// afara unui jucător anume.
  int coinRewardAt(int level) =>
      (_baseCoinReward * questCoinRewardMultiplier * economyGrowth(level))
          .round();

  int xpRewardAt(int level) =>
      (_baseXpReward * questXpRewardMultiplier * economyGrowth(level)).round();

  /// Vieți, hint-uri și gems NU cresc cu nivelul — toate trei au plafoane pe
  /// care scalarea le-ar face fără sens (vezi comentariul de la
  /// [economyGrowth]).
  int get heartReward => (_baseHeartReward * questHeartRewardMultiplier).round();
  int get hintReward => (_baseHintReward * questHintRewardMultiplier).round();

  /// Ținta EFECTIVĂ la nivelul dat. Crește pe ACEEAȘI curbă ca plata, ca
  /// moneda pe minut să rămână constantă: un jucător de nivel 20 are cifre mai
  /// mari pe ecran, dar nu și o zi mai profitabilă la aceeași cantitate de joc.
  ///
  /// Scalarea se aplică DOAR metricilor fără plafon zilnic natural. Un quest
  /// pe `wheel_spin` (o rotire la 24h) sau pe `planet_run` (2-3 rulări la 12h)
  /// ar deveni imposibil de terminat dacă i-am înmulți ținta — de-aia
  /// [scalableQuestMetrics] e o listă albă explicită, nu o excludere.
  int targetAt(int level) => scalableQuestMetrics.contains(metricKey)
      ? (_baseTarget * questTargetScale * economyGrowth(level)).round()
      : _baseTarget;

  /// Titlul afișat, la nivelul dat. Quest-urile a căror țintă se scalează își
  /// scriu numărul în catalog ca `{n}`, nu ca cifră: altfel "Răspunde corect
  /// la 5 întrebări" ar rămâne pe ecran lângă o bară care cere 12.
  ///
  /// `{n}` aduce cu el și "de"-ul, fiindcă în română depinde de număr: "5
  /// întrebări", dar "35 DE întrebări". Cum ținta depinde de nivel, "de" nu
  /// poate sta scris în catalog.
  String titleAt(int level) {
    final n = targetAt(level);
    final lastTwo = n % 100;
    final needsDe = lastTwo == 0 || lastTwo >= 20;
    return _titleTemplate.replaceAll('{n}', needsDe ? '$n de' : '$n');
  }

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

// ─── Creșterea organică a economiei ───────────────────────────────────────
// Problema pe care o rezolvă: orice număr FIX e greșit pentru cineva. O
// recompensă calibrată pentru un jucător de nivel 20 îneacă un începător; una
// calibrată pentru începător face ca la nivelul 20 să nu mai conteze nimic.
// Iar o creștere pusă dintr-o dată (multiplicatorul sărit de la 3,0 la 5,4)
// se simte ca un salt artificial, nu ca progres.
//
// De-aia și EFORTUL și PLATA cresc împreună cu nivelul, pe aceeași curbă:
//
//   nivel 1  → 1,00×      nivel 15 → 1,63×
//   nivel 5  → 1,18×      nivel 20 → 1,86×
//   nivel 10 → 1,40×      nivel 24+ → 2,07× (plafon)
//
// Consecințele intenționate:
//  • moneda pe minut rămâne aproape constantă la orice nivel — nimeni nu
//    "descoperă" brusc că ziua lui valorează dublu;
//  • cifrele de pe ecran cresc totuși vizibil, deci progresul se vede;
//  • taxele (intrare în categorie, hint, pariu multiplayer) scalează deja cu
//    AVEREA, nu cu nivelul, deci ele urcă doar dacă chiar aduni bani — asta
//    e frâna care împiedică acumularea exponențială;
//  • plafonul la 2,07× la nivelul 24 oprește curba înainte să devină absurdă.
//
// Se aplică DOAR monedelor și XP-ului. Gems, vieți și hint-uri rămân fixe:
// toate trei sunt resurse cu plafon (stoc de hint-uri 26, gems calibrate pe
// "o categorie pe săptămână", viețile controlează cât poți juca), iar
// scalarea lor ar strica exact plafoanele alea.

/// Plafonul curbei și nivelul la care se atinge — un singur loc de reglat.
const double economyGrowthMax = 2.07;

/// Ales ca plafonul să cadă EXACT pe nivelul 24 (1 + 0,0465 × 23 = 2,0695),
/// nu undeva la 24,8 — ca "de la nivelul 24 în sus nu mai crește" să fie o
/// afirmație adevărată, nu aproximativă.
const double economyGrowthPerLevel = 0.0465;

double economyGrowth(int level) =>
    (1.0 + economyGrowthPerLevel * (level - 1)).clamp(1.0, economyGrowthMax);

/// Multiplicatorii de bază, aplicați peste valorile din catalog ÎNAINTE de
/// [economyGrowth]. 2,9 la nivelul 1 e practic cât era vechiul multiplicator
/// fix (3,0), deci un jucător nou primește exact ce primea înainte — creșterea
/// vine din curbă, nu dintr-un salt.
const double questCoinRewardMultiplier = 2.9;
const double questXpRewardMultiplier = 2.9;

/// Hint-urile NU urmează saltul monedelor, ci rămân la valoarea din catalog.
/// Stocul de hint-uri e plafonat la 26 (vezi StorageService.addHints), iar la
/// un multiplicator de 2,2 o zi de quest-uri acorda 35-54 de hint-uri: cea mai
/// mare parte se evapora la plafon, deci cifra de pe card promitea ceva ce
/// jucătorul nu primea. La ×1 ies ~14-22 pe zi, adică sub plafon.
const double questHintRewardMultiplier = 1.0;

/// Viețile sunt SINGURA recompensă de quest care nu se mai multiplică: acum
/// numărul scris în catalog e exact cel primit. Cerința a fost o distribuție
/// citibilă — "la unele nimic, la altele 1-2, la câteva 5" — iar un
/// multiplicator ar fi transformat un 1 din catalog în 3 pe ecran și n-ar mai
/// fi existat nicio treaptă de 1 sau 2.
///
/// Distribuția din catalog: 44 de quest-uri fără vieți, 36 cu una, 5 cu două
/// și 3 cu cinci (cele mai grele din tot jocul: serie de 10 la rând, 9
/// quest-uri revendicate într-o zi, rulare perfectă pe planetă). Pe o zi
/// întreagă revendicată ies ~8-9 vieți.
const double questHeartRewardMultiplier = 1.0;

/// Cât se înmulțesc țintele din catalog — cerința a fost ca un quest să se
/// termine "în decursul unei zile, nu în câteva minute / o oră". Se aplică
/// DOAR metricilor din [scalableQuestMetrics].
const double questTargetScale = 2.3;

/// Metricile care pot crește oricât într-o zi, deci cărora li se poate mări
/// ținta fără să devină imposibile.
///
/// Restul catalogului rămâne NESCALAT, și fiecare exclus are un motiv fizic:
/// `wheel_spin` are o rotire la 24h; `planet_run`/`planet_correct` și
/// familiile lor sunt limitate la 2-3 rulări la 12 ore; `clippy_done`/
/// `clippy_perfect` la 5 runde pe zi; `heart_bought` la 5 și
/// `hint_pack_bought` la 3; `modes_played` la câte gamemoduri există (14);
/// `daily_challenge_done`/`daily_lives_claimed` sunt o dată pe zi;
/// `quests_claimed_today` nu poate depăși numărul de quest-uri ale zilei;
/// `streak_hit_*` numără cât de des atingi o serie, nu volum.
const Set<String> scalableQuestMetrics = {
  'correct_count',
  'coins_earned',
  'no_hint_correct',
  'hints_used',
  'culture_quiz_correct',
};

/// Câte gems pot veni în total din quest-uri într-o zi calendaristică. Peste
/// plafon, quest-ul se revendică normal (monede/XP/hints/vieți), doar partea
/// de gems e 0. A urcat de la 13 la 19 odată cu trecerea la 12-14 quest-uri
/// pe zi: cea mai bogată zi din rotație dă acum 15-16 gems revendicată
/// integral, deci plafonul tot nu retează un jucător cinstit — există strict
/// ca "Revendică x2" (care dublează și gems-ul) să nu poată transforma o
/// săptămână de gems într-una singură.
const int dailyQuestGemCap = 19;

// ─── Catalogul de quest-uri (71 în total) ──────────────────────────────────
// Împărțit pe 3 nivele de dificultate ([QuestTier], care determină și gems-ul
// acordat). NU toate sunt active în aceeași zi: [todaysQuests] le împarte
// într-o rotație săptămânală de ~10 pe zi. Progresul fiecăruia se resetează
// oricum zilnic.

const List<Quest> _easyQuests = [
  Quest(
      id: 'planet_survive_1',
      title: 'Ieși de pe planetă cu inimi rămase',
      target: 1,
      metricKey: 'planet_survived',
      tier: QuestTier.easy,
      coinReward: 14,
      xpReward: 11,
      hintReward: 1,
      heartReward: 1,
      icon: Icons.favorite_border_rounded),
  Quest(
      id: 'correct_5',
      title: 'Răspunde corect la {n} întrebări',
      target: 5,
      metricKey: 'correct_count',
      tier: QuestTier.easy,
      coinReward: 15,
      xpReward: 10,
      hintReward: 1,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'culture_correct_8',
      title: 'Răspunde corect la {n} întrebări de Cultură Generală',
      target: 8,
      metricKey: 'culture_quiz_correct',
      tier: QuestTier.easy,
      coinReward: 15,
      xpReward: 11,
      hintReward: 1,
      icon: Icons.public_rounded),
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
      title: 'Folosește {n} hint-uri',
      target: 3,
      metricKey: 'hints_used',
      tier: QuestTier.easy,
      coinReward: 11,
      xpReward: 8,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'no_hint_3',
      title: 'Ghicește corect {n} întrebări fără niciun hint',
      target: 3,
      metricKey: 'no_hint_correct',
      tier: QuestTier.easy,
      coinReward: 17,
      xpReward: 12,
      hintReward: 1,
      heartReward: 1,
      icon: Icons.visibility_off_rounded),
  Quest(
      id: 'earn_60_coins',
      title: 'Strânge {n} monede jucând',
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
      title: 'Răspunde corect la {n} întrebări de Cultură Generală',
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
      heartReward: 1,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'planet_correct_12',
      title: 'Ghicește 12 holograme pe Planeta hologramelor',
      target: 12,
      metricKey: 'planet_correct',
      tier: QuestTier.easy,
      coinReward: 13,
      xpReward: 10,
      hintReward: 1,
      icon: Icons.blur_on_rounded),
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
      heartReward: 1,
      icon: Icons.storefront_rounded),
  Quest(
      id: 'clippy_done_4',
      title: 'Termină 4 bonusuri de la Clippy',
      target: 4,
      metricKey: 'clippy_done',
      tier: QuestTier.easy,
      coinReward: 15,
      xpReward: 11,
      hintReward: 1,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'culture_batches_4',
      title: 'Termină 4 loturi de Cultură Generală',
      target: 4,
      metricKey: 'culture_quiz_batches',
      tier: QuestTier.easy,
      coinReward: 16,
      xpReward: 12,
      hintReward: 1,
      icon: Icons.public_rounded),
  Quest(
      id: 'streak_5_thrice',
      title: 'Obține o serie de 5 răspunsuri corecte, de 3 ori azi',
      target: 3,
      metricKey: 'streak_hit_5',
      tier: QuestTier.easy,
      coinReward: 17,
      xpReward: 13,
      hintReward: 1,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'earn_30_coins',
      title: 'Strânge {n} monede jucând',
      target: 30,
      metricKey: 'coins_earned',
      tier: QuestTier.easy,
      coinReward: 9,
      xpReward: 8,
      hintReward: 1,
      icon: Icons.savings_rounded),
  Quest(
      id: 'earn_45_coins',
      title: 'Strânge {n} monede jucând',
      target: 45,
      metricKey: 'coins_earned',
      tier: QuestTier.easy,
      coinReward: 11,
      xpReward: 9,
      hintReward: 1,
      heartReward: 1,
      icon: Icons.savings_rounded),
  Quest(
      id: 'use_hints_1',
      title: 'Folosește {n} hint',
      target: 1,
      metricKey: 'hints_used',
      tier: QuestTier.easy,
      coinReward: 9,
      xpReward: 7,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'use_hints_2',
      title: 'Folosește {n} hint-uri',
      target: 2,
      metricKey: 'hints_used',
      tier: QuestTier.easy,
      coinReward: 9,
      xpReward: 8,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'no_hint_1',
      title: 'Ghicește corect {n} întrebări fără niciun hint',
      target: 1,
      metricKey: 'no_hint_correct',
      tier: QuestTier.easy,
      coinReward: 11,
      xpReward: 8,
      hintReward: 1,
      icon: Icons.visibility_off_rounded),
  Quest(
      id: 'culture_correct_3',
      title: 'Răspunde corect la {n} întrebări de Cultură Generală',
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
      heartReward: 1,
      icon: Icons.public_rounded),
  Quest(
      id: 'planet_correct_7',
      title: 'Ghicește 7 holograme pe Planeta hologramelor',
      target: 7,
      metricKey: 'planet_correct',
      tier: QuestTier.easy,
      coinReward: 11,
      xpReward: 8,
      hintReward: 1,
      icon: Icons.blur_on_rounded),
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
  Quest(
      id: 'planet_visit_1',
      title: 'Aterizează o dată pe Planeta hologramelor',
      target: 1,
      metricKey: 'planet_run',
      tier: QuestTier.easy,
      coinReward: 14,
      xpReward: 11,
      hintReward: 1,
      icon: Icons.travel_explore_rounded),
  Quest(
      id: 'clippy_done_5',
      title: 'Termină 5 bonusuri de la Clippy',
      target: 5,
      metricKey: 'clippy_done',
      tier: QuestTier.easy,
      coinReward: 16,
      xpReward: 12,
      hintReward: 1,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'correct_7',
      title: 'Răspunde corect la {n} întrebări',
      target: 7,
      metricKey: 'correct_count',
      tier: QuestTier.easy,
      coinReward: 16,
      xpReward: 11,
      hintReward: 1,
      heartReward: 1,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'use_hints_4',
      title: 'Folosește {n} hint-uri',
      target: 4,
      metricKey: 'hints_used',
      tier: QuestTier.easy,
      coinReward: 12,
      xpReward: 9,
      icon: Icons.tips_and_updates_rounded),
];

const List<Quest> _mediumQuests = [
  Quest(
      id: 'correct_10',
      title: 'Răspunde corect la {n} întrebări',
      target: 10,
      metricKey: 'correct_count',
      tier: QuestTier.medium,
      coinReward: 29,
      xpReward: 24,
      hintReward: 2,
      heartReward: 2,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'clippy_perfect_3',
      title: 'Termină 3 bonusuri de la Clippy perfect (3/3)',
      target: 3,
      metricKey: 'clippy_perfect',
      tier: QuestTier.medium,
      coinReward: 31,
      xpReward: 25,
      hintReward: 2,
      icon: Icons.auto_awesome_rounded),
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
      title: 'Folosește {n} hint-uri',
      target: 6,
      metricKey: 'hints_used',
      tier: QuestTier.medium,
      coinReward: 27,
      xpReward: 20,
      heartReward: 1,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'no_hint_6',
      title: 'Ghicește corect {n} întrebări fără niciun hint',
      target: 6,
      metricKey: 'no_hint_correct',
      tier: QuestTier.medium,
      coinReward: 34,
      xpReward: 27,
      hintReward: 2,
      icon: Icons.visibility_off_rounded),
  Quest(
      id: 'earn_150_coins',
      title: 'Strânge {n} monede jucând',
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
      heartReward: 2,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'culture_correct_10',
      title: 'Răspunde corect la {n} întrebări de Cultură Generală',
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
      hintReward: 2,
      heartReward: 1,
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
      id: 'planet_correct_17',
      title: 'Ghicește 17 holograme pe Planeta hologramelor',
      target: 17,
      metricKey: 'planet_correct',
      tier: QuestTier.medium,
      coinReward: 29,
      xpReward: 24,
      hintReward: 2,
      icon: Icons.blur_on_rounded),
  Quest(
      id: 'level_up_1',
      title: 'Revendică o recompensă de nivel',
      target: 1,
      metricKey: 'level_reward_claimed',
      tier: QuestTier.medium,
      coinReward: 24,
      xpReward: 19,
      hintReward: 1,
      heartReward: 1,
      icon: Icons.military_tech_rounded),
  Quest(
      id: 'spend_any_1',
      title: 'Cheltuie monede sau gems în Magazin',
      target: 1,
      metricKey: 'shop_spend',
      tier: QuestTier.medium,
      xpReward: 16,
      hintReward: 1,
      icon: Icons.shopping_cart_rounded),
  Quest(
      id: 'planet_visit_3',
      title: 'Intră de 3 ori pe Planeta hologramelor',
      target: 3,
      metricKey: 'planet_run',
      tier: QuestTier.medium,
      coinReward: 23,
      xpReward: 20,
      hintReward: 2,
      heartReward: 2,
      icon: Icons.travel_explore_rounded),
  Quest(
      id: 'no_hint_13',
      title: 'Ghicește corect {n} întrebări fără niciun hint',
      target: 13,
      metricKey: 'no_hint_correct',
      tier: QuestTier.medium,
      coinReward: 31,
      xpReward: 27,
      hintReward: 2,
      heartReward: 1,
      icon: Icons.visibility_off_rounded),
  Quest(
      id: 'hints_used_10',
      title: 'Folosește {n} hint-uri',
      target: 10,
      metricKey: 'hints_used',
      tier: QuestTier.medium,
      coinReward: 25,
      xpReward: 22,
      hintReward: 1,
      icon: Icons.tips_and_updates_rounded),
  Quest(
      id: 'no_hint_10',
      title: 'Ghicește corect {n} întrebări fără niciun hint',
      target: 10,
      metricKey: 'no_hint_correct',
      tier: QuestTier.medium,
      coinReward: 29,
      xpReward: 24,
      hintReward: 2,
      icon: Icons.visibility_off_rounded),
  Quest(
      id: 'earn_250_coins',
      title: 'Strânge {n} monede jucând',
      target: 250,
      metricKey: 'coins_earned',
      tier: QuestTier.medium,
      coinReward: 27,
      xpReward: 22,
      hintReward: 1,
      heartReward: 1,
      icon: Icons.savings_rounded),
  Quest(
      id: 'culture_correct_15',
      title: 'Răspunde corect la {n} întrebări de Cultură Generală',
      target: 15,
      metricKey: 'culture_quiz_correct',
      tier: QuestTier.medium,
      coinReward: 27,
      xpReward: 23,
      hintReward: 2,
      icon: Icons.public_rounded),
  Quest(
      id: 'planet_correct_23',
      title: 'Ghicește 23 de holograme pe Planeta hologramelor',
      target: 23,
      metricKey: 'planet_correct',
      tier: QuestTier.medium,
      coinReward: 27,
      xpReward: 23,
      hintReward: 2,
      icon: Icons.blur_on_rounded),
  Quest(
      id: 'clippy_done_3',
      title: 'Termină 3 bonusuri de la Clippy',
      target: 3,
      metricKey: 'clippy_done',
      tier: QuestTier.medium,
      coinReward: 24,
      xpReward: 22,
      hintReward: 2,
      heartReward: 2,
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
      heartReward: 1,
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
  Quest(
      id: 'planet_visit_2',
      title: 'Intră de 2 ori pe Planeta hologramelor',
      target: 2,
      metricKey: 'planet_run',
      tier: QuestTier.medium,
      coinReward: 28,
      xpReward: 24,
      hintReward: 2,
      heartReward: 1,
      icon: Icons.travel_explore_rounded),
  Quest(
      id: 'planet_good_run_1',
      title: 'Ieși de pe planetă cu cel puțin $planetGoodRunCorrect din $planetQuestionCount',
      target: 1,
      metricKey: 'planet_good_run',
      tier: QuestTier.medium,
      coinReward: 32,
      xpReward: 26,
      heartReward: 2,
      icon: Icons.auto_graph_rounded),
  Quest(
      id: 'mp_win_1',
      title: 'Câștigă un meci multiplayer',
      target: 1,
      metricKey: 'mp_win',
      tier: QuestTier.medium,
      coinReward: 33,
      xpReward: 28,
      hintReward: 1,
      icon: Icons.emoji_events_rounded),
  Quest(
      id: 'correct_13',
      title: 'Răspunde corect la {n} întrebări',
      target: 13,
      metricKey: 'correct_count',
      tier: QuestTier.medium,
      coinReward: 32,
      xpReward: 26,
      hintReward: 2,
      heartReward: 1,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'culture_correct_21',
      title: 'Răspunde corect la {n} întrebări de Cultură Generală',
      target: 21,
      metricKey: 'culture_quiz_correct',
      tier: QuestTier.medium,
      coinReward: 31,
      xpReward: 25,
      hintReward: 2,
      icon: Icons.public_rounded),
  Quest(
      id: 'no_hint_8',
      title: 'Ghicește corect {n} întrebări fără niciun hint',
      target: 8,
      metricKey: 'no_hint_correct',
      tier: QuestTier.medium,
      coinReward: 33,
      xpReward: 27,
      hintReward: 2,
      icon: Icons.visibility_off_rounded),
];

const List<Quest> _hardQuests = [
  Quest(
      id: 'correct_15',
      title: 'Răspunde corect la {n} întrebări',
      target: 15,
      metricKey: 'correct_count',
      tier: QuestTier.hard,
      coinReward: 51,
      xpReward: 42,
      hintReward: 2,
      heartReward: 1,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'streak_8',
      title: 'Obține o serie de 8 răspunsuri corecte la rând',
      target: 1,
      metricKey: 'streak_hit_8',
      tier: QuestTier.hard,
      coinReward: 54,
      xpReward: 54,
      hintReward: 2,
      heartReward: 1,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'earn_300_coins',
      title: 'Strânge {n} monede jucând',
      target: 300,
      metricKey: 'coins_earned',
      tier: QuestTier.hard,
      coinReward: 48,
      xpReward: 39,
      hintReward: 3,
      heartReward: 1,
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
      heartReward: 1,
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
      heartReward: 1,
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
      heartReward: 1,
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
      heartReward: 1,
      icon: Icons.public_rounded),
  Quest(
      id: 'claim_3_quests_today',
      title: 'Revendică alte 6 quest-uri azi',
      target: 6,
      metricKey: 'quests_claimed_today',
      tier: QuestTier.hard,
      coinReward: 54,
      xpReward: 48,
      hintReward: 2,
      heartReward: 1,
      icon: Icons.flag_rounded),
  Quest(
      id: 'correct_20',
      title: 'Răspunde corect la {n} întrebări',
      target: 20,
      metricKey: 'correct_count',
      tier: QuestTier.hard,
      coinReward: 53,
      xpReward: 45,
      hintReward: 2,
      heartReward: 1,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'mp_win_3',
      title: 'Câștigă {n} meciuri multiplayer',
      target: 3,
      metricKey: 'mp_win',
      tier: QuestTier.hard,
      coinReward: 51,
      xpReward: 42,
      hintReward: 2,
      heartReward: 1,
      icon: Icons.emoji_events_rounded),
  Quest(
      id: 'streak_10',
      title: 'Obține o serie de 10 răspunsuri corecte la rând',
      target: 1,
      metricKey: 'streak_hit_10',
      tier: QuestTier.hard,
      coinReward: 57,
      xpReward: 51,
      hintReward: 3,
      heartReward: 5,
      icon: Icons.local_fire_department_rounded),
  Quest(
      id: 'earn_500_coins',
      title: 'Strânge {n} monede jucând',
      target: 500,
      metricKey: 'coins_earned',
      tier: QuestTier.hard,
      coinReward: 51,
      xpReward: 42,
      hintReward: 2,
      heartReward: 1,
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
      heartReward: 1,
      icon: Icons.grid_view_rounded),
  Quest(
      id: 'planet_correct_29',
      title: 'Ghicește 29 de holograme pe Planeta hologramelor',
      target: 29,
      metricKey: 'planet_correct',
      tier: QuestTier.hard,
      coinReward: 53,
      xpReward: 45,
      hintReward: 2,
      heartReward: 1,
      icon: Icons.blur_on_rounded),
  Quest(
      id: 'clippy_perfect_2',
      title: 'Termină un bonus de la Clippy perfect (3/3), de 2 ori azi',
      target: 2,
      metricKey: 'clippy_perfect',
      tier: QuestTier.hard,
      coinReward: 48,
      xpReward: 42,
      hintReward: 3,
      heartReward: 1,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'claim_5_quests_today',
      title: 'Revendică alte 9 quest-uri azi',
      target: 9,
      metricKey: 'quests_claimed_today',
      tier: QuestTier.hard,
      coinReward: 61,
      xpReward: 54,
      hintReward: 3,
      heartReward: 5,
      icon: Icons.flag_rounded),
  Quest(
      id: 'planet_great_run_1',
      title: 'Ieși de pe planetă cu cel puțin $planetGreatRunCorrect din $planetQuestionCount',
      target: 1,
      metricKey: 'planet_great_run',
      tier: QuestTier.hard,
      coinReward: 59,
      xpReward: 49,
      hintReward: 2,
      heartReward: 1,
      icon: Icons.auto_graph_rounded),
  Quest(
      id: 'planet_perfect_1',
      title: 'Rulare perfectă pe planetă: $planetQuestionCount din $planetQuestionCount',
      target: 1,
      metricKey: 'planet_perfect',
      tier: QuestTier.hard,
      coinReward: 71,
      xpReward: 63,
      hintReward: 3,
      heartReward: 5,
      icon: Icons.workspace_premium_rounded),
  Quest(
      id: 'mp_win_2',
      title: 'Câștigă 2 meciuri multiplayer',
      target: 2,
      metricKey: 'mp_win',
      tier: QuestTier.hard,
      coinReward: 64,
      xpReward: 56,
      hintReward: 2,
      heartReward: 1,
      icon: Icons.emoji_events_rounded),
  Quest(
      id: 'correct_27',
      title: 'Răspunde corect la {n} întrebări',
      target: 27,
      metricKey: 'correct_count',
      tier: QuestTier.hard,
      coinReward: 58,
      xpReward: 51,
      hintReward: 2,
      heartReward: 1,
      icon: Icons.check_circle_rounded),
  Quest(
      id: 'clippy_perfect_4',
      title: 'Termină un bonus de la Clippy perfect (3/3), de {n} ori azi',
      target: 4,
      metricKey: 'clippy_perfect',
      tier: QuestTier.hard,
      coinReward: 62,
      xpReward: 53,
      hintReward: 3,
      heartReward: 1,
      icon: Icons.auto_awesome_rounded),
  Quest(
      id: 'culture_correct_27',
      title: 'Răspunde corect la {n} întrebări de Cultură Generală',
      target: 27,
      metricKey: 'culture_quiz_correct',
      tier: QuestTier.hard,
      coinReward: 56,
      xpReward: 47,
      hintReward: 2,
      heartReward: 1,
      icon: Icons.public_rounded),
  Quest(
      id: 'no_hint_23',
      title: 'Ghicește corect {n} întrebări fără niciun hint',
      target: 23,
      metricKey: 'no_hint_correct',
      tier: QuestTier.hard,
      coinReward: 66,
      xpReward: 57,
      hintReward: 2,
      heartReward: 1,
      icon: Icons.visibility_off_rounded),
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
// Cerința: nu tot catalogul deodată, ci 12 pe zi în timpul săptămânii și mai
// multe în weekend, DIFERITE de la o zi la alta și fără repetare în cadrul
// aceleiași săptămâni — iar când vine iar lunea, revine exact setul de luni.
//
// De-aia catalogul e împărțit O SINGURĂ DATĂ în [questRotationDays] grupe
// disjuncte, iar ziua săptămânii ([DateTime.weekday]) alege grupa. Partiția
// NU depinde de dată (sămânță fixă, vezi [_questRotationSeed]) — dacă ar
// depinde, "lunea viitoare" ar aduce alt set, nu același.
//
// Numărul de quest-uri din catalog nu e ales la întâmplare: 5×12 + 2×14 = 88,
// exact cât are [allQuests]. Sâmbăta și duminica primesc câte două în plus
// fiindcă atunci se joacă mai mult — cerut explicit. Dacă adaugi sau scoți
// quest-uri din catalog, [questsPerWeekday] trebuie să însumeze noul total,
// altfel partiția nu mai iese exact (există un test care prinde asta).

const int questRotationDays = 7;

/// Câte quest-uri primește fiecare zi, indexat de la luni (0) la duminică (6).
const List<int> questsPerWeekday = [12, 12, 12, 12, 12, 14, 14];

/// Sămânță FIXĂ pentru amestecarea catalogului înainte de împărțire —
/// schimbarea ei rearanjează complet ce quest-uri pică în ce zi.
const int _questRotationSeed = 20260803;

List<List<Quest>>? _rotationCache;

/// Împarte TOT catalogul în cele 7 grupe zilnice.
///
/// Regula tare: **într-o zi, fiecare quest e unic** — nu există două
/// quest-uri care se completează din același contor de progres
/// ([Quest.metricKey]). Fără ea, "Răspunde la 23 de întrebări" și "Răspunde
/// la 35" ar apărea în aceeași zi, iar prima s-ar bifa singură pe drumul spre
/// a doua: două rânduri pe ecran pentru o singură acțiune.
///
/// Consecința asupra catalogului, de ținut minte la orice adăugare: **o
/// familie nu poate avea mai mult de [questRotationDays] variante**, altfel
/// nu încap pe zile distincte. `correct_count` are exact 7; `answer_count`
/// (răspunsuri "corecte SAU greșite", care se putea termina spamând
/// întrebări la nimereală) a fost eliminat complet pe 2026-08-05 — surplusul
/// lui de atunci a fost mutat pe alte metrici, care cer rezultat, nu volum.
/// Există un test care prinde orice familie viitoare peste limită.
///
/// Familiile mari se așază primele, cât timp tabla e goală. Fiecare quest
/// ajunge în ziua care are (în ordine) cele mai puține quest-uri din
/// dificultatea lui și cele mai puține în total; zilele pline (vezi
/// [questsPerWeekday]) sau care au deja familia respectivă sunt excluse din
/// start. Decalajul per familie ține împărțirea variată fără hazard.
List<List<Quest>> _questRotation() {
  final cached = _rotationCache;
  if (cached != null) return cached;

  final days = List.generate(questRotationDays, (_) => <Quest>[]);
  final metricsPerDay = List.generate(questRotationDays, (_) => <String>{});

  final families = <String, List<Quest>>{};
  for (final q in allQuests) {
    families.putIfAbsent(q.metricKey, () => <Quest>[]).add(q);
  }
  for (final members in families.values) {
    members.sort((a, b) => a.tier.index.compareTo(b.tier.index));
  }

  final keys = families.keys.toList()
    ..sort()
    ..shuffle(Random(_questRotationSeed));
  // familiile mari întâi — ele sunt cele constrânse, restul umple golurile.
  keys.sort((a, b) => families[b]!.length.compareTo(families[a]!.length));

  for (var f = 0; f < keys.length; f++) {
    final key = keys[f];
    assert(families[key]!.length <= questRotationDays,
        'familia "$key" are ${families[key]!.length} variante, peste cele $questRotationDays zile');
    for (final quest in families[key]!) {
      var best = -1;
      List<int>? bestScore;
      for (var i = 0; i < questRotationDays; i++) {
        // decalajul per familie: fără el, toate familiile ar începe să caute
        // din ziua 0 și primele zile s-ar umple sistematic mai repede.
        final d = (i + f) % questRotationDays;
        if (days[d].length >= questsPerWeekday[d]) continue;
        if (metricsPerDay[d].contains(key)) continue; // regula tare
        final score = [
          days[d].where((q) => q.tier == quest.tier).length,
          days[d].length,
        ];
        if (bestScore == null || _lessThan(score, bestScore)) {
          bestScore = score;
          best = d;
        }
      }
      // Suma din questsPerWeekday e egală cu allQuests.length și nicio
      // familie nu depășește 7 (ambele prinse de teste), deci există mereu o
      // zi liberă. Assert-ul e plasa pentru viitor.
      assert(best >= 0,
          'nu mai e loc pentru "${quest.id}": verifica questsPerWeekday si marimea familiilor');
      if (best < 0) continue;
      days[best].add(quest);
      metricsPerDay[best].add(key);
    }
  }

  for (final day in days) {
    // ușoare întâi, grele la final — lista de pe ecran urcă în dificultate.
    day.sort((a, b) => a.tier.index.compareTo(b.tier.index));
  }
  return _rotationCache = days;
}

/// Comparație lexicografică pe scorurile din [_questRotation].
bool _lessThan(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return false;
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

  // ─── Seria lungă (adăugată 2026-08-05) ──────────────────────────────────
  // Zece realizări gândite pe o LUNĂ de joc, nu pe o seară: fiecare are ca
  // țintă un lucru care nu se poate grăbi (o serie de zile, un cooldown de
  // 24h, un plafon zilnic) sau un volum care cere săptămâni.
  //
  // Regula de compoziție: NICIO recompensă nu seamănă cu alta. Fiecare
  // combină alt SUBSET din cele cinci resurse (monede / XP / gems / vieți /
  // hints), ca deblocarea să se simtă de fiecare dată altfel — singurul
  // lucru comun e că toate sunt generoase.
  //
  // Progresul lor vine din contoarele pe viață (vezi
  // StorageService.getLifetimeMetric), hrănite automat de bumpQuestMetric.

  Achievement(
    id: 'streak_30',
    title: 'Lună fără pauză',
    description: 'Intră în joc 30 de zile la rând',
    target: 30,
    coinReward: 2417,
    heartReward: 37,
    hintReward: 43,
    icon: Icons.local_fire_department_rounded,
  ),
  Achievement(
    id: 'wheel_28',
    title: 'Curtezanul norocului',
    description: 'Învârte Roata norocului de 28 de ori (una la 24h)',
    target: 28,
    gemReward: 347,
    icon: Icons.casino_rounded,
  ),
  Achievement(
    id: 'mp_wins_23',
    title: 'Spaima mesei',
    description: 'Câștigă 23 de meciuri multiplayer',
    target: 23,
    coinReward: 3271,
    xpReward: 583,
    icon: Icons.sports_mma_rounded,
  ),
  Achievement(
    id: 'no_hint_250',
    title: 'Ochi liber',
    description: '250 de răspunsuri corecte fără niciun hint',
    target: 250,
    xpReward: 719,
    hintReward: 89,
    icon: Icons.visibility_off_rounded,
  ),
  Achievement(
    id: 'culture_600',
    title: 'Enciclopedia ambulantă',
    description: '600 de răspunsuri corecte la Cultură Generală',
    target: 600,
    coinReward: 1879,
    gemReward: 113,
    heartReward: 19,
    icon: Icons.menu_book_rounded,
  ),
  Achievement(
    id: 'clippy_perfect_47',
    title: 'Cel mai bun prieten al agrafei',
    description: '47 de bonusuri de la Clippy terminate perfect (3/3)',
    target: 47,
    xpReward: 461,
    heartReward: 23,
    hintReward: 61,
    icon: Icons.auto_awesome_rounded,
  ),
  Achievement(
    id: 'unlock_batches_3',
    title: 'Colecționarul',
    description: 'Deblochează 3 loturi noi de întrebări cu gems',
    target: 3,
    coinReward: 4637,
    icon: Icons.lock_open_rounded,
  ),
  Achievement(
    id: 'planet_perfect_5',
    title: 'Stăpânul hologramelor',
    description: '5 rulări perfecte pe Planeta hologramelor',
    target: 5,
    gemReward: 167,
    heartReward: 29,
    hintReward: 37,
    icon: Icons.blur_on_rounded,
  ),
  Achievement(
    id: 'coins_earned_37k',
    title: 'Bancherul',
    description: 'Strânge 37.000 de monede jucând',
    target: 37000,
    xpReward: 907,
    gemReward: 89,
    hintReward: 53,
    icon: Icons.account_balance_rounded,
  ),
  Achievement(
    id: 'quests_180',
    title: 'Neobositul',
    description: 'Revendică 180 de quest-uri zilnice',
    target: 180,
    coinReward: 3889,
    xpReward: 1117,
    gemReward: 211,
    heartReward: 41,
    icon: Icons.workspace_premium_rounded,
  ),
];
