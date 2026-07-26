import 'package:flutter/material.dart';

/// Formula de nivel/XP: 1000 XP pe nivel, simplu și previzibil.
/// XP-ul câștigat la o întrebare corectă = punctele obținute la acea
/// întrebare (vezi calculateAwardedPoints din game_helpers.dart).
const int xpPerLevel = 1000;

int levelForXp(int xp) => (xp ~/ xpPerLevel) + 1;

int xpIntoCurrentLevel(int xp) => xp % xpPerLevel;

double levelProgress(int xp) => xpIntoCurrentLevel(xp) / xpPerLevel;

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
  final IconData icon;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    required this.coinReward,
    required this.xpReward,
    required this.icon,
  });
}

/// Numărul de gamemoduri deblocate (folosit de "all_modes" mai jos) — ține-l
/// sincronizat manual cu numărul de intrări `locked: false` din gamemodes.dart.
const int unlockedGameModeCount = 10;

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
