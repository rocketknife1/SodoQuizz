import 'package:flutter/material.dart';
import 'lang.dart';

/// Ligile multiplayer — vezi PlayerProfileService.recordMatchResult pentru
/// cum urcă/coboară punctele. Pragurile sunt de playtesting, nu literă de
/// lege — ușor de ajustat aici, într-un singur loc.
///
/// De la [currentSeasonKey] încoace (2026-08-23, PLAN_DE_VIITOR.md punctul
/// 1), există DOUĂ feluri de puncte pe fiecare profil:
///  - [PlayerProfile.leaguePoints] — cumulat pe viață, NU se resetează
///    niciodată. Rămâne sursa pentru "cel mai bun rezultat vreodată" și
///    pentru orice statistică istorică.
///  - [PlayerProfile.seasonPoints] — puncte în sezonul CURENT, calculat cu
///    [effectiveSeasonPoints] (se resetează lazy, fără job programat — vezi
///    nota de-acolo). Sezonul, tier-ul afișat în clasament și badge-ul de
///    cosmetică (vezi widgets/league_badge.dart) folosesc ACESTA, nu
///    punctajul pe viață — altfel un jucător activ acum trei luni ar rămâne
///    Diamond pentru totdeauna, fără nicio presiune să mai joace.
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

/// [LeagueTier.values.indexOf], expus ca funcție ca să nu trebuiască
/// reținută convenția de indexare de fiecare apelant — folosit la calculul
/// "cel mai bun tier atins sezonul ăsta" (vezi PlayerProfileService).
int leagueTierIndexForPoints(int points) => leagueForPoints(points).tier.index;

/// Cheia sezonului curent — o lună calendaristică, în ora LOCALĂ a
/// telefonului ("2026-08"). Client-trusted, ca tot restul multiplayer-ului
/// din acest proiect (fără Cloud Functions) — un ceas dat înapoi manual ar
/// putea păstra artificial sezonul vechi, dar nu deschide nicio portiță nouă
/// față de restul jocului (vezi core/obby.dart pentru același compromis).
String currentSeasonKey([DateTime? now]) {
  final n = now ?? DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}';
}

const _monthsRo = [
  'Ianuarie', 'Februarie', 'Martie', 'Aprilie', 'Mai', 'Iunie',
  'Iulie', 'August', 'Septembrie', 'Octombrie', 'Noiembrie', 'Decembrie',
];
const _monthsEn = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// "August 2026" / "August 2026" — eticheta sezonului curent, pentru
/// antetul clasamentului.
String seasonLabel([DateTime? now]) {
  final n = now ?? DateTime.now();
  return tr('${_monthsRo[n.month - 1]} ${n.year}', '${_monthsEn[n.month - 1]} ${n.year}');
}

/// Cât mai e până la resetarea sezonului — prima zi a lunii următoare,
/// miezul nopții local. Sezonul chiar se resetează SINGUR la prima
/// [recordMatchResult] din luna nouă (vezi acolo), deci numărătoarea de-aici
/// e informativă, nu declanșează nimic.
Duration seasonTimeRemaining([DateTime? now]) {
  final n = now ?? DateTime.now();
  final nextMonth = n.month == 12 ? DateTime(n.year + 1, 1, 1) : DateTime(n.year, n.month + 1, 1);
  final remaining = nextMonth.difference(n);
  return remaining.isNegative ? Duration.zero : remaining;
}

/// Punctele de sezon REALE ale unui profil, la momentul [now] — dacă
/// [seasonKey] al profilului nu mai e sezonul curent, sezonul lui s-a
/// terminat fără să fi jucat încă niciun meci în cel nou, deci efectiv are
/// 0 puncte, chiar dacă [seasonPoints] mai ține o valoare veche pe disc.
///
/// Reset LAZY, nu programat: [PlayerProfileService.recordMatchResult] scrie
/// [seasonPoints]/[seasonKey] din nou abia la URMĂTORUL meci al fiecărui
/// jucător — până atunci, orice altcineva care se uită la profilul lui
/// (clasament, verificarea de depășire) trebuie să știe să-l trateze ca 0,
/// nu ca valoarea veche. Aceeași idee ca „quest-urile de azi" din
/// core/progression.dart: nu există job care să reseteze totul la miezul
/// nopții, fiecare citire recalculează ce e valabil ACUM.
int effectiveSeasonPoints({required String seasonKey, required int seasonPoints, DateTime? now}) {
  return seasonKey == currentSeasonKey(now) ? seasonPoints : 0;
}
