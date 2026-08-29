import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/multiplayer_models.dart';
import 'avatar.dart';

/// Avatar + nume, cu un inel colorat opțional (evidențiază gazda, liderul
/// sau „tu") și o insignă mică sus (coroană, loc pe podium) — un singur
/// „portret de jucător" vizual, refolosit în lobby și în meciul live, ca
/// stilul din Multiplayer să fie identic peste tot, nu reinventat pe fiecare
/// ecran.
class PlayerBadge extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final String avatarSeed;
  final String? avatarStyle;
  final double size;
  final Color? ringColor;
  final Widget? topBadge;
  final Widget? scoreChip;
  final VoidCallback? onTap;

  const PlayerBadge({
    super.key,
    required this.name,
    this.photoUrl,
    this.avatarSeed = '',
    this.avatarStyle,
    this.size = 56,
    this.ringColor,
    this.topBadge,
    this.scoreChip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(ringColor != null ? 3 : 0),
                decoration: ringColor != null
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [ringColor!, ringColor!.withAlpha(110)]),
                        boxShadow: [BoxShadow(color: ringColor!.withAlpha(140), blurRadius: 12, spreadRadius: 1)],
                      )
                    : null,
                child: Avatar(
                  size: size,
                  label: name.isNotEmpty ? name[0].toUpperCase() : '?',
                  accentColor: pickAvatarColor(avatarSeed),
                  photoUrl: photoUrl,
                  style: avatarStyleFromId(avatarStyle),
                ),
              ),
              if (topBadge != null) Positioned(top: -10, child: topBadge!),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: size + 14,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          if (scoreChip != null) ...[const SizedBox(height: 2), scoreChip!],
        ],
      ),
    );
  }
}

/// Insigna rotundă mică pusă deasupra avatarului — coroană pentru gazdă,
/// sau numărul locului pentru clasamentul live din meci.
class PlayerTopBadge extends StatelessWidget {
  final String text;
  final Color color;

  const PlayerTopBadge({super.key, required this.text, required this.color});

  PlayerTopBadge.crown({super.key})
      : text = '👑',
        color = AppColors.coin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF0B1229), width: 2),
        boxShadow: [BoxShadow(color: color.withAlpha(150), blurRadius: 6)],
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
    );
  }
}
