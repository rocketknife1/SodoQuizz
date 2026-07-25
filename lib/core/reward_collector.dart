import 'dart:async';
import 'package:flutter/material.dart';
import '../data/storage_service.dart';
import '../widgets/coin_reward_overlay.dart';
import 'sfx.dart';
import 'theme.dart';

/// Aplică o recompensă compusă (monede + XP + vieți) în 3 etape separate și
/// secvențiale, fiecare cu animație proprie (praf magic + traiectorie
/// șerpuită) spre pastila ei din header, sunet propriu, scriere în storage
/// chiar înainte să pornească — și trece la etapa următoare imediat după
/// IMPACT (nu așteaptă coada de "+"-uri plutitoare), ca să nu fie timpi
/// morți între etape. O singură sursă de adevăr pentru "senzația" de
/// colectare — folosită de orice ecran care acordă recompense compuse
/// dintr-o singură acțiune (Cultură Generală, bonusul lui Clippy).
Future<void> collectRewards(
  BuildContext context, {
  required int coins,
  required int xp,
  required int lives,
  required GlobalKey coinBadgeKey,
  required GlobalKey xpBadgeKey,
  required GlobalKey livesBadgeKey,
  VoidCallback? onEachImpact,
}) async {
  Future<void> stage({
    required int amount,
    required IconData icon,
    required Color color,
    required GlobalKey targetKey,
    required Future<void> Function() applyReward,
    required VoidCallback impactSound,
  }) async {
    if (amount <= 0) return;
    await applyReward();
    if (!context.mounted) return;

    final impactCompleter = Completer<void>();
    Sfx.rewardPop();
    CoinRewardOverlay.show(
      context,
      amount: amount,
      targetKey: targetKey,
      icon: icon,
      color: color,
      flightDuration: const Duration(milliseconds: 1000),
      serpentine: true,
      onImpact: () {
        impactSound();
        onEachImpact?.call();
        if (!impactCompleter.isCompleted) impactCompleter.complete();
      },
    );
    await impactCompleter.future;
    await Future.delayed(const Duration(milliseconds: 120));
  }

  await stage(
    amount: coins,
    icon: Icons.monetization_on_rounded,
    color: AppColors.coin,
    targetKey: coinBadgeKey,
    applyReward: () => StorageService.addCoins(coins),
    impactSound: Sfx.coinHit,
  );
  await stage(
    amount: xp,
    icon: Icons.star_rounded,
    color: AppColors.purple,
    targetKey: xpBadgeKey,
    applyReward: () => StorageService.addXp(xp),
    impactSound: Sfx.xpHit,
  );
  await stage(
    amount: lives,
    icon: Icons.favorite_rounded,
    color: AppColors.life,
    targetKey: livesBadgeKey,
    // fără plafon — inimile câștigate aici pot depăși maximul standard de 5.
    applyReward: () => StorageService.addLivesUncapped(lives),
    impactSound: Sfx.heartHit,
  );
}
