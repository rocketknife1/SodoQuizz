import 'package:flutter/material.dart';

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
