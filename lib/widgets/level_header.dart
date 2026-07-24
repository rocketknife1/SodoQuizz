import 'package:flutter/material.dart';
import '../core/progression.dart';
import '../core/theme.dart';
import 'avatar.dart';

/// Header cu avatar + nivel + bară de progres XP (stânga) și pastilă de
/// monede (dreapta) — folosit în capul fiecărui ecran principal.
class LevelHeader extends StatelessWidget {
  final int xp;
  final int coins;
  final int? lives;
  final VoidCallback? onCoinsTap;
  final Key? coinBadgeKey;
  final Key? xpBadgeKey;
  final Key? livesBadgeKey;

  const LevelHeader({
    super.key,
    required this.xp,
    required this.coins,
    this.lives,
    this.onCoinsTap,
    this.coinBadgeKey,
    this.xpBadgeKey,
    this.livesBadgeKey,
  });

  @override
  Widget build(BuildContext context) {
    final level = levelForXp(xp);
    final progress = levelProgress(xp);

    return Row(
      children: [
        const Avatar(size: 44),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            key: xpBadgeKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nivel $level', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(AppColors.purple),
                ),
              ),
            ],
          ),
        ),
        if (lives != null) ...[
          Container(
            key: livesBadgeKey,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.favorite_rounded, color: AppColors.life, size: 16),
                const SizedBox(width: 6),
                Text('$lives', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 10),
        ],
        GestureDetector(
          key: coinBadgeKey,
          onTap: onCoinsTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monetization_on_rounded, color: AppColors.coin, size: 16),
                const SizedBox(width: 6),
                Text('$coins', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                if (onCoinsTap != null) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.add_circle_rounded, color: AppColors.play, size: 16),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
