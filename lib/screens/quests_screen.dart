import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/progression.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/coin_reward_overlay.dart';
import '../widgets/level_header.dart';

/// Quest-uri zilnice — se resetează automat la miezul nopții (progresul
/// e stocat sub o cheie care include data curentă, vezi StorageService).
class QuestsScreen extends StatefulWidget {
  const QuestsScreen({super.key});

  @override
  State<QuestsScreen> createState() => _QuestsScreenState();
}

class _QuestsScreenState extends State<QuestsScreen> {
  late Future<_QuestsData> _dataFuture;
  final GlobalKey _coinBadgeKey = GlobalKey();
  final GlobalKey<AppBottomNavBarState> _navBarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
  }

  Future<_QuestsData> _load() async {
    final xp = await StorageService.getXp();
    final coins = await StorageService.getCoins();
    final lives = await StorageService.getLives();
    final progress = <String, int>{};
    final claimed = <String, bool>{};
    for (final q in dailyQuests) {
      progress[q.id] = await StorageService.getQuestProgress(q.id);
      claimed[q.id] = await StorageService.isQuestClaimed(q.id);
    }
    return _QuestsData(xp: xp, coins: coins, lives: lives, progress: progress, claimed: claimed);
  }

  Future<void> _claim(Quest q) async {
    await StorageService.claimQuest(q);
    if (!mounted) return;
    // bulina roșie de pe tab-ul Quests trebuie să dispară pe loc dacă acesta
    // era ultimul quest revendicabil, nu doar la reintrarea în tab.
    _navBarKey.currentState?.refreshDots();
    // reîncărcăm imediat progresul/claimed (bifa apare pe loc), dar balanța
    // de monede afișată rămâne cea veche până lovește animația, ca numărul
    // să se actualizeze exact când "ajunge" moneda, nu instant la apăsare.
    final refreshed = await _load();
    if (!mounted) return;
    setState(() {
      _dataFuture = Future.value(_QuestsData(
        xp: refreshed.xp,
        coins: refreshed.coins - q.coinReward,
        lives: refreshed.lives,
        progress: refreshed.progress,
        claimed: refreshed.claimed,
      ));
    });
    Sfx.rewardPop();
    CoinRewardOverlay.show(
      context,
      amount: q.coinReward,
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
        child: FutureBuilder<_QuestsData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return Column(
              children: [
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
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text('Quest-uri zilnice', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text(
                    'Se resetează în fiecare zi la miezul nopții.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: data == null
                      ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: dailyQuests.length,
                          itemBuilder: (context, i) {
                            final q = dailyQuests[i];
                            final progress = (data.progress[q.id] ?? 0).clamp(0, q.target);
                            final done = progress >= q.target;
                            final claimed = data.claimed[q.id] ?? false;
                            return _QuestCard(quest: q, progress: progress, done: done, claimed: claimed, onClaim: () => _claim(q));
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(key: _navBarKey, current: AppTab.quests),
    );
  }
}

class _QuestsData {
  final int xp;
  final int coins;
  final int lives;
  final Map<String, int> progress;
  final Map<String, bool> claimed;
  _QuestsData({required this.xp, required this.coins, required this.lives, required this.progress, required this.claimed});
}

class _QuestCard extends StatelessWidget {
  final Quest quest;
  final int progress;
  final bool done;
  final bool claimed;
  final VoidCallback onClaim;

  const _QuestCard({required this.quest, required this.progress, required this.done, required this.claimed, required this.onClaim});

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
              color: (claimed ? AppColors.success : AppColors.purple).withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(quest.icon, color: claimed ? AppColors.success : AppColors.purple, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(quest.title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress / quest.target,
                    minHeight: 6,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(claimed ? AppColors.success : AppColors.purple),
                  ),
                ),
                const SizedBox(height: 4),
                Text('$progress / ${quest.target}  •  +${quest.coinReward} monede, +${quest.xpReward} XP',
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
