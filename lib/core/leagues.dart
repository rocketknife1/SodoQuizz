import 'package:flutter/material.dart';

/// Ligile multiplayer — cumulate pe viață, fără sezoane/reset (v1, vezi
/// PlayerProfileService.recordMatchResult pentru cum urcă/coboară punctele).
/// Pragurile sunt de playtesting, nu literă de lege — ușor de ajustat aici,
/// într-un singur loc.
enum LeagueTier { bronze, silver, gold, platinum, diamond }

class LeagueInfo {
  final LeagueTier tier;
  final String name;
  final Color color;
  final IconData icon;
  const LeagueInfo({required this.tier, required this.name, required this.color, required this.icon});
}

const _leagues = [
  LeagueInfo(tier: LeagueTier.bronze, name: 'Bronze', color: Color(0xFFCD7F32), icon: Icons.shield_rounded),
  LeagueInfo(tier: LeagueTier.silver, name: 'Silver', color: Color(0xFFB0BEC5), icon: Icons.shield_rounded),
  LeagueInfo(tier: LeagueTier.gold, name: 'Gold', color: Color(0xFFFFD700), icon: Icons.military_tech_rounded),
  LeagueInfo(tier: LeagueTier.platinum, name: 'Platinum', color: Color(0xFF5EC8F2), icon: Icons.military_tech_rounded),
  LeagueInfo(tier: LeagueTier.diamond, name: 'Diamond', color: Color(0xFFB388FF), icon: Icons.workspace_premium_rounded),
];

/// Praguri de puncte de ligă (inclusiv) — 0 și fără meciuri jucate încă tot
/// pică pe Bronze, nu există un tier "Unranked" separat (un jucător nou e
/// pur și simplu Bronze cu 0 puncte).
LeagueInfo leagueForPoints(int points) {
  if (points >= 1500) return _leagues[4];
  if (points >= 700) return _leagues[3];
  if (points >= 300) return _leagues[2];
  if (points >= 100) return _leagues[1];
  return _leagues[0];
}
