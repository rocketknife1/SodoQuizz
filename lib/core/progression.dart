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

double levelProgress(int xp) => xpIntoCurrentLevel(xp) / xpForLevel(levelForXp(xp));

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
  const LevelReward({this.coins = 0, this.hints = 0, this.hearts = 0, this.gems = 0});

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
  const GameModeMilestoneReward({required this.coins, required this.xp, required this.gems});
}

GameModeMilestoneReward gameModeMilestoneReward(int milestone) {
  return GameModeMilestoneReward(
    coins: 30 * milestone,
    xp: 80 * milestone,
    gems: milestone >= 3 ? (milestone - 2) * 3 : 0,
  );
}

/// Un quest zilnic: progresul se ține în [StorageService], definiția
/// (țintă, recompensă) e statică aici — o singură listă de editat.
class Quest {
  final String id;
  final String title;
  final int target;
  final int coinReward;
  final int xpReward;
  final IconData icon;

  const Quest({
    required this.id,
    required this.title,
    required this.target,
    required this.coinReward,
    required this.xpReward,
    required this.icon,
  });
}

const List<Quest> dailyQuests = [
  Quest(
    id: 'correct_5',
    title: 'Răspunde corect la 5 întrebări',
    target: 5,
    coinReward: 30,
    xpReward: 50,
    icon: Icons.check_circle_rounded,
  ),
  Quest(
    id: 'play_two_modes',
    title: 'Joacă în 2 gamemoduri diferite',
    target: 2,
    coinReward: 25,
    xpReward: 40,
    icon: Icons.grid_view_rounded,
  ),
  Quest(
    id: 'use_hints_3',
    title: 'Folosește 3 hint-uri',
    target: 3,
    coinReward: 15,
    xpReward: 20,
    icon: Icons.tips_and_updates_rounded,
  ),
  Quest(
    id: 'streak_3',
    title: 'Obține o serie de 3 răspunsuri corecte la rând',
    target: 1,
    coinReward: 35,
    xpReward: 60,
    icon: Icons.local_fire_department_rounded,
  ),
  Quest(
    id: 'answer_10',
    title: 'Răspunde la 10 întrebări (corect sau greșit)',
    target: 10,
    coinReward: 20,
    xpReward: 30,
    icon: Icons.playlist_add_check_rounded,
  ),
  Quest(
    id: 'no_hint_3',
    title: 'Ghicește corect 3 întrebări fără niciun hint',
    target: 3,
    coinReward: 30,
    xpReward: 45,
    icon: Icons.visibility_off_rounded,
  ),
  Quest(
    id: 'earn_60_coins',
    title: 'Strânge 60 de monede jucând',
    target: 60,
    coinReward: 25,
    xpReward: 35,
    icon: Icons.savings_rounded,
  ),
  Quest(
    id: 'daily_challenge_done',
    title: 'Termină Daily Challenge de azi',
    target: 1,
    coinReward: 40,
    xpReward: 70,
    icon: Icons.bolt_rounded,
  ),
];

Quest questById(String id) => dailyQuests.firstWhere((q) => q.id == id);

/// O realizare permanentă: spre deosebire de [Quest] (zilnic, se resetează),
/// progresul unei realizări e cumulativ pe viață — o dată revendicată,
/// rămâne revendicată pentru totdeauna.
class Achievement {
  final String id;
  final String title;
  final String description;
  final int target;
  final int coinReward;
  final int xpReward;
  final int gemReward;
  final IconData icon;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    required this.coinReward,
    required this.xpReward,
    this.gemReward = 0,
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
    coinReward: 40,
    xpReward: 80,
    icon: Icons.check_circle_rounded,
  ),
  Achievement(
    id: 'correct_150',
    title: 'Expert',
    description: '150 de răspunsuri corecte, vreodată',
    target: 150,
    coinReward: 90,
    xpReward: 180,
    icon: Icons.verified_rounded,
  ),
  Achievement(
    id: 'correct_400',
    title: 'Maestru al cunoașterii',
    description: '400 de răspunsuri corecte, vreodată',
    target: 400,
    coinReward: 200,
    xpReward: 400,
    gemReward: 20,
    icon: Icons.workspace_premium_rounded,
  ),
  Achievement(
    id: 'level_5',
    title: 'În ascensiune',
    description: 'Ajungi la nivelul 5',
    target: 5,
    coinReward: 50,
    xpReward: 0,
    icon: Icons.trending_up_rounded,
  ),
  Achievement(
    id: 'level_15',
    title: 'Veteran',
    description: 'Ajungi la nivelul 15',
    target: 15,
    coinReward: 150,
    xpReward: 0,
    icon: Icons.military_tech_rounded,
  ),
  Achievement(
    id: 'all_modes',
    title: 'Exploratorul',
    description: 'Joacă în toate gamemodurile deblocate',
    target: unlockedGameModeCount,
    coinReward: 70,
    xpReward: 120,
    icon: Icons.explore_rounded,
  ),
  Achievement(
    id: 'hints_50',
    title: 'Detectivul',
    description: 'Folosește 50 de hint-uri în total',
    target: 50,
    coinReward: 30,
    xpReward: 60,
    icon: Icons.tips_and_updates_rounded,
  ),
  Achievement(
    id: 'quests_25',
    title: 'Muncitor harnic',
    description: 'Revendică 25 de quest-uri zilnice',
    target: 25,
    coinReward: 80,
    xpReward: 140,
    gemReward: 10,
    icon: Icons.flag_rounded,
  ),
  Achievement(
    id: 'daily_10',
    title: 'Rutina de zi',
    description: 'Termină Daily Challenge de 10 ori',
    target: 10,
    coinReward: 60,
    xpReward: 100,
    icon: Icons.bolt_rounded,
  ),
];
