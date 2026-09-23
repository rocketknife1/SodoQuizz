import 'dart:math';

import '../models/question.dart';
import 'daily_challenge.dart' show dailyChallengeDateKey;
import 'game_event.dart';
import 'gamemodes.dart';
import 'progression.dart';
import 'stable_hash.dart';

/// **Săptămâna tematică** — un eveniment mereu activ, cu altă categorie în
/// fiecare săptămână (luni → luni), clasament propriu și premii după loc.
///
/// Cum se câștigă puncte: DOAR din „cursa zilei" — o rulare pe zi, 7 întrebări
/// fixe, aceleași pentru toți în ziua respectivă. Jocul liber pe categorie NU
/// contează la clasament: altfel locul 1 l-ar lua cine are cel mai mult timp
/// liber, nu cine știe. Totalul săptămânii e suma celor 7 zile, deci
/// constanța contează cât priceperea.
///
/// Echilibrul premiilor: tot ce e monede se exprimă în „zile de venit din
/// quest-uri" la nivelul jucătorului ([dailyQuestIncome]), ca premiul să
/// cântărească la fel la nivelul 1 și la nivelul 40. Topul ia în primul rând
/// STATUT (titlu), nu avere. Păzit de test/weekly_event_test.dart.
///
/// Totul e determinist (aceleași rezultate pe web și pe telefon): săptămâna și
/// întrebările zilei vin din [stableHash], nu din `Random(seed)`.

/// Câte întrebări are cursa zilei.
const int weeklyRunQuestionCount = 7;

/// Plafonul pe răspuns — egal cu plafonul din regulile Firestore
/// (`eventPointsOk`: +50 pe scriere). Punctele se scriu răspuns cu răspuns.
const int weeklyRunMaxPointsPerAnswer = 50;

/// Categoriile din rotație, în ordinea în care vin. Doar categorii cu poze
/// (Matematica arată formule, n-are loc într-o cursă pe poze).
const List<String> weeklyThemeRotation = [
  'sport', 'mecanica', 'medical', 'masini', 'steaguri', 'jocuri', 'animale',
  'logouri', 'celebritati', 'monumente', 'cartoon', 'aplicatii', 'romania',
  'instrumente',
];

/// Lunea (ora locală, miezul nopții) a săptămânii care conține [day].
///
/// Aritmetică pe calendar, nu pe `Duration`: la trecerea la ora de iarnă o zi
/// are 23 de ore, iar „minus N×24 h" ar cădea în ziua de dinainte.
DateTime weekStart(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

/// Id-ul evenimentului săptămânii — și documentul lui din Firestore
/// (`events/{id}/scores`).
String weeklyEventId(DateTime day) => 'saptamana-${dailyChallengeDateKey(weekStart(day))}';

/// Categoria săptămânii care conține [day].
String weeklyThemeFor(DateTime day) {
  // numărul săptămânii de la o luni fixă — nu depinde de fusul orar al
  // serverului, doar de calendarul local, ca restul „zilnicelor" din joc
  final epoch = DateTime(2026, 1, 5); // luni
  // .round(): o săptămână cu schimbare de oră are 167 sau 169 de ore
  final weeks = (weekStart(day).difference(epoch).inHours / (24 * 7)).round();
  final i = weeks % weeklyThemeRotation.length;
  return weeklyThemeRotation[i < 0 ? i + weeklyThemeRotation.length : i];
}

GameMode? weeklyThemeMode(DateTime day) {
  final id = weeklyThemeFor(day);
  for (final g in gameModes) {
    if (g.id == id) return g;
  }
  return null;
}

/// Evenimentul săptămânii, în aceeași formă ca evenimentele din Remote Config
/// — ca ecranele existente (card în Quest-uri, EventScreen) să-l arate fără
/// cod nou. Fără bonus la jocul liber (vezi [GameEvent.dailyRunOnly]).
GameEvent weeklyEventFor(DateTime day) {
  final start = weekStart(day);
  final mode = weeklyThemeMode(day);
  // `title` e deja în limba curentă; evenimentul se reconstruiește la fiecare
  // citire, deci o schimbare de limbă se vede imediat
  final name = mode?.title ?? weeklyThemeFor(day);
  return GameEvent(
    id: weeklyEventId(day),
    titleRo: 'Săptămâna $name',
    titleEn: '$name Week',
    descRo: 'O cursă pe zi, 7 întrebări, aceleași pentru toți. Duminică seara se '
        'închide clasamentul și se împart premiile.',
    descEn: 'One race a day, 7 questions, the same for everyone. On Sunday night '
        'the leaderboard closes and prizes go out.',
    categoryId: weeklyThemeFor(day),
    start: start,
    end: DateTime(start.year, start.month, start.day + 7),
    coinBonus: 1.0,
    dailyRunOnly: true,
  );
}

/// Cele [weeklyRunQuestionCount] întrebări ale cursei din [day], din
/// categoria săptămânii. Aceleași pentru toți; nu modifică [pool].
List<Question> weeklyRunQuestions(List<Question> pool, DateTime day) {
  final theme = weeklyThemeFor(day);
  final eligible = pool
      .where((q) => q.categoryId == theme && q.imageAssetPath != null && q.formula == null)
      .toList();
  stableShuffle(eligible, stableHash('cursa-zilei-${dailyChallengeDateKey(day)}'));
  return eligible.take(weeklyRunQuestionCount).toList();
}

// ─── Punctele cursei ─────────────────────────────────────────────────────

/// Punctele unui răspuns: corectitudinea e baza, viteza și seria din cursă
/// despart jucătorii buni de cei foarte buni. Greșit = 0, fără penalizare.
///
///  • 20 pentru răspunsul corect;
///  • până la 20 pentru viteză — plin sub 3 s, scade liniar până la 15 s;
///  • +2 pentru fiecare corect la rând din cursa de azi, maxim +10.
int weeklyAnswerPoints({required bool correct, required int answerMs, required int streakBefore}) {
  if (!correct) return 0;
  final secs = answerMs / 1000;
  final speed = secs <= 3 ? 20.0 : (secs >= 15 ? 0.0 : 20 * (15 - secs) / 12);
  final streak = min(streakBefore * 2, 10);
  return min(20 + speed.round() + streak, weeklyRunMaxPointsPerAnswer);
}

// ─── Premiul zilnic ──────────────────────────────────────────────────────

/// Monedele cursei de azi: 18 pe corect, +40 la perfect, plus un bonus pentru
/// zilele la rând jucate în săptămâna asta (+5 pe zi, maxim +30) — motivul
/// să revii și mâine. Rămâne sub Provocarea Zilei, ca să nu devină salariu.
int weeklyDailyCoins({required int correct, required int consecutiveDays}) {
  final c = correct.clamp(0, weeklyRunQuestionCount);
  final perfect = c >= weeklyRunQuestionCount ? 40 : 0;
  final days = min(max(consecutiveDays - 1, 0) * 5, 30);
  return c * 18 + perfect + days;
}

// ─── Premiul de la final ─────────────────────────────────────────────────

/// Venitul mediu dintr-o zi de quest-uri la [level] — unitatea în care se
/// măsoară toate premiile finale. Media pe cele 7 zile ale rotației.
double dailyQuestIncome(int level) {
  var weekly = 0;
  for (var d = 0; d < 7; d++) {
    for (final q in todaysQuests(DateTime(2026, 8, 3 + d))) {
      weekly += q.coinRewardAt(level);
    }
  }
  return weekly / 7;
}

/// Câte zile trebuie jucate ca să intri la premiile pe loc. Fără prag, într-o
/// săptămână liniștită o singură cursă bună ar lua locul 1 — adică premiul
/// cel mare fără „munca de a farma".
const int weeklyMinDaysForRank = 3;

enum WeeklyTier { champion, second, third, top10, top25, participant, tried }

class WeeklyReward {
  final WeeklyTier tier;
  final int coins;
  final int gems;

  /// Realizarea-marcaj care deblochează un titlu (vezi core/cosmetics.dart),
  /// sau null.
  final String? honor;
  const WeeklyReward({required this.tier, required this.coins, required this.gems, this.honor});
}

/// Multiplicatorul (în zile de quest-uri) pentru fiecare treaptă.
double weeklyTierDays(WeeklyTier t) => switch (t) {
      WeeklyTier.champion => 2.5,
      WeeklyTier.second => 1.8,
      WeeklyTier.third => 1.4,
      WeeklyTier.top10 => 1.0,
      WeeklyTier.top25 => 0.6,
      WeeklyTier.participant => 0.3,
      WeeklyTier.tried => 0.12,
    };

WeeklyTier weeklyTierFor({required int rank, required int participants, required int daysPlayed}) {
  if (daysPlayed >= weeklyMinDaysForRank) {
    if (rank == 1) return WeeklyTier.champion;
    if (rank == 2) return WeeklyTier.second;
    if (rank == 3) return WeeklyTier.third;
    if (rank <= 10) return WeeklyTier.top10;
    if (rank <= max(1, (participants * 0.25).ceil())) return WeeklyTier.top25;
    return WeeklyTier.participant;
  }
  return WeeklyTier.tried;
}

/// Premiul final pentru [rank] din [participants], la [level]. `daysPlayed` =
/// zilele în care a terminat cursa.
WeeklyReward weeklyRewardFor({
  required int rank,
  required int participants,
  required int daysPlayed,
  required int level,
}) {
  final tier = weeklyTierFor(rank: rank, participants: participants, daysPlayed: daysPlayed);
  final coins = (dailyQuestIncome(level) * weeklyTierDays(tier)).round();
  final gems = switch (tier) {
    WeeklyTier.champion => 5,
    WeeklyTier.second => 3,
    WeeklyTier.third => 2,
    WeeklyTier.top10 => 1,
    _ => 0,
  };
  final honor = switch (tier) {
    WeeklyTier.champion => weeklyChampionHonor,
    WeeklyTier.second || WeeklyTier.third => weeklyPodiumHonor,
    _ => null,
  };
  return WeeklyReward(tier: tier, coins: coins, gems: gems, honor: honor);
}

/// Marcajele care deblochează titlurile săptămânii (vezi `ownsTitle`).
const String weeklyChampionHonor = 'weekly_champion';
const String weeklyPodiumHonor = 'weekly_podium';
