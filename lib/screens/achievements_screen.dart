import 'package:flutter/material.dart';
import '../core/achievements.dart';
import '../core/progression.dart';
import '../core/sfx.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';
import '../widgets/coin_reward_overlay.dart';
import '../widgets/level_header.dart';

/// Realizări permanente — spre deosebire de Quests (zilnic), progresul aici
/// e cumulativ pe viață și, o dată revendicată, o realizare rămâne bifată.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late Future<_AchievementsData> _dataFuture;
  final GlobalKey _coinBadgeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
  }

  Future<_AchievementsData> _load() async {
    final results = await Future.wait([
      StorageService.getXp(),
      StorageService.getCoins(),
      StorageService.getLives(),
      StorageService.getAnsweredIds(),
      StorageService.getModesEverPlayed(),
      StorageService.getHintsUsedTotal(),
      StorageService.getQuestsClaimedTotal(),
      StorageService.getDailyChallengesTotal(),
    ]);
    final xp = results[0] as int;
    final answeredCount = (results[3] as Set<String>).length;
    final modesPlayed = (results[4] as Set<String>).length;
    final hintsUsed = results[5] as int;
    final questsClaimed = results[6] as int;
    final dailyChallenges = results[7] as int;
    final level = levelForXp(xp);

    final progress = <String, int>{};
    final claimed = <String, bool>{};
    for (final a in achievements) {
      progress[a.id] = switch (a.id) {
        'correct_50' || 'correct_150' || 'correct_400' => answeredCount,
        'level_5' || 'level_15' => level,
        'all_modes' => modesPlayed,
        'hints_50' => hintsUsed,
        'quests_25' => questsClaimed,
        'daily_10' => dailyChallenges,
        _ => 0,
      };
      claimed[a.id] = await StorageService.isAchievementClaimed(a.id);
    }

    return _AchievementsData(
      xp: xp,
      coins: results[1] as int,
      lives: results[2] as int,
      progress: progress,
      claimed: claimed,
    );
  }

  Future<void> _claim(Achievement a) async {
    await StorageService.claimAchievement(a);
    if (!mounted) return;
    final refreshed = await _load();
    if (!mounted) return;
    setState(() {
      _dataFuture = Future.value(_AchievementsData(
        xp: refreshed.xp,
        coins: refreshed.coins - a.coinReward,
        lives: refreshed.lives,
        progress: refreshed.progress,
        claimed: refreshed.claimed,
      ));
    });
    Sfx.rewardPop();
    CoinRewardOverlay.show(
      context,
      amount: a.coinReward,
      targetKey: _coinBadgeKey,
      onImpact: () {
        Sfx.coinHit();
        if (!mounted) return;
        setState(() { _dataFuture = Future.value(refreshed); });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: FutureBuilder<_AchievementsData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                      ),
                      const SizedBox(width: 4),
                      const Text('Realizări', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: LevelHeader(
                    xp: data?.xp ?? 0,
                    coins: data?.coins ?? 0,
                    lives: data?.lives ?? 5,
                    coinBadgeKey: _coinBadgeKey,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Progres permanent — nu se resetează niciodată.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: data == null
                      ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: achievements.length,
                          itemBuilder: (context, i) {
                            final a = achievements[i];
                            final progress = (data.progress[a.id] ?? 0).clamp(0, a.target);
                            final done = progress >= a.target;
                            final claimed = data.claimed[a.id] ?? false;
                            return _AchievementCard(
                              achievement: a,
                              progress: progress,
                              done: done,
                              claimed: claimed,
                              onClaim: () => _claim(a),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AchievementsData {
  final int xp;
  final int coins;
  final int lives;
  final Map<String, int> progress;
  final Map<String, bool> claimed;
  _AchievementsData({required this.xp, required this.coins, required this.lives, required this.progress, required this.claimed});
}

class _AchievementCard extends StatelessWidget {
  final Achievement achievement;
  final int progress;
  final bool done;
  final bool claimed;
  final VoidCallback onClaim;

  const _AchievementCard({
    required this.achievement,
    required this.progress,
    required this.done,
    required this.claimed,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: claimed ? AppColors.success.withAlpha(120) : Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (claimed ? AppColors.success : AppColors.orange).withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(achievement.icon, color: claimed ? AppColors.success : AppColors.orange, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(achievement.title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(achievement.description, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress / achievement.target,
                    minHeight: 6,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(claimed ? AppColors.success : AppColors.orange),
                  ),
                ),
                const SizedBox(height: 4),
                Text('$progress / ${achievement.target}  •  +${achievement.coinReward} monede, +${achievement.xpReward} XP',
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (claimed)
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 26)
          else if (done)
            ElevatedButton(
              onPressed: onClaim,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.play,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Ridică', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            )
          else
            const Icon(Icons.lock_clock_rounded, color: Colors.white24, size: 22),
        ],
      ),
    );
  }
}
