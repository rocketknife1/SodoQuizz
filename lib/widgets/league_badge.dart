import 'package:flutter/material.dart';
import '../core/cosmetics.dart';
import '../core/leagues.dart';
import 'avatar.dart';

/// Cosmetica din planul de viitor (punctul 2): un status VIZIBIL, de arătat
/// altora, fără să atingă economia de bază (nu se cumpără, nu costă nimic) —
/// derivat pur din liga de sezon a jucătorului (vezi core/leagues.dart).
///
/// Doar cercul cu iconița tier-ului — pentru varianta gata montată peste un
/// avatar, vezi [AvatarWithLeagueBadge].
class LeagueBadge extends StatelessWidget {
  final LeagueTier tier;
  final double size;

  const LeagueBadge({super.key, required this.tier, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final league = _infoFor(tier);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: league.color,
        border: Border.all(color: const Color(0xFF1a1a2e), width: size * 0.12),
        boxShadow: [BoxShadow(color: league.color.withAlpha(140), blurRadius: size * 0.3)],
      ),
      child: Icon(league.icon, color: Colors.white, size: size * 0.62),
    );
  }

  static LeagueInfo _infoFor(LeagueTier tier) => leagueForPoints(_pointsForTier(tier));

  // leagueForPoints ia puncte, nu tier — un jucător poate avea un
  // [seasonBestTierIndex] fără să mai aibă chiar acum punctele care l-ar
  // recalcula la fel (a scăzut între timp), deci badge-ul se construiește
  // din TIER direct, nu recalculat din punctajul curent. Micuța conversie
  // de mai jos evită să dubleze paleta de culori/iconițe din leagueForPoints.
  static int _pointsForTier(LeagueTier tier) => switch (tier) {
        LeagueTier.bronze => 0,
        LeagueTier.silver => 100,
        LeagueTier.gold => 300,
        LeagueTier.platinum => 700,
        LeagueTier.diamond => 1500,
      };
}

/// [Avatar] + [LeagueBadge] în colțul din dreapta jos — folosit peste tot
/// unde un jucător apare cu identitate (clasament, profil, lobby-uri de
/// multiplayer), ca statusul de ligă să se vadă exact acolo unde ceilalți se
/// uită oricum, fără un ecran separat de "cosmetice".
///
/// [tier] e null pentru "nu arăta badge" (ex. un jucător fără niciun meci
/// jucat încă în sezon — Bronze de la 0 puncte nu spune nimic încă).
class AvatarWithLeagueBadge extends StatelessWidget {
  final double size;
  final String? label;
  final Color? accentColor;
  final String? photoUrl;
  final AvatarStyle style;
  final LeagueTier? tier;
  final Frame frame;

  const AvatarWithLeagueBadge({
    super.key,
    this.size = 44,
    this.label,
    this.accentColor,
    this.photoUrl,
    this.style = AvatarStyle.poza,
    required this.tier,
    this.frame = Frame.none,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = Avatar(size: size, label: label, accentColor: accentColor, photoUrl: photoUrl, style: style, frame: frame);
    if (tier == null) return avatar;
    final badgeSize = (size * 0.44).clamp(14.0, 26.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -badgeSize * 0.12,
            bottom: -badgeSize * 0.12,
            child: LeagueBadge(tier: tier!, size: badgeSize),
          ),
        ],
      ),
    );
  }
}
