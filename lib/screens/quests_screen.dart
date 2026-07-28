import 'package:flutter/material.dart';
import '../core/progression.dart';
import '../core/reward_collector.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/level_header.dart';

/// Quest-uri zilnice — toate cele 70, mereu active (vezi [todaysQuests]).
/// Progresul se resetează automat la miezul nopții (stocat sub o cheie care
/// include data curentă).
class QuestsScreen extends StatefulWidget {
  const QuestsScreen({super.key});

  @override
  State<QuestsScreen> createState() => _QuestsScreenState();
}

class _QuestsScreenState extends State<QuestsScreen> {
  late Future<_QuestsData> _dataFuture;
  final GlobalKey _coinBadgeKey = GlobalKey();
  final GlobalKey _xpBadgeKey = GlobalKey();
  final GlobalKey _livesBadgeKey = GlobalKey();
  final GlobalKey _hintsBadgeKey = GlobalKey();
  final GlobalKey _gemsBadgeKey = GlobalKey();
  final GlobalKey<AppBottomNavBarState> _navBarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
  }

  Future<_QuestsData> _load() async {
    final quests = todaysQuests();
    final xp = await StorageService.getXp();
    final coins = await StorageService.getCoins();
    final lives = await StorageService.getLives();
    final hints = await StorageService.getHints();
    final gems = await StorageService.getGems();
    final progress = <String, int>{};
    final claimed = <String, bool>{};
    for (final q in quests) {
      progress[q.id] = await StorageService.getQuestProgress(q.metricKey);
      claimed[q.id] = await StorageService.isQuestClaimed(q.id);
    }
    return _QuestsData(
      quests: quests,
      xp: xp,
      coins: coins,
      lives: lives,
      hints: hints,
      gems: gems,
      progress: progress,
      claimed: claimed,
    );
  }

  Future<void> _claim(Quest q) async {
    await StorageService.claimQuest(q.id);
    if (!mounted) return;
    _navBarKey.currentState?.refreshDots();
    // IMPORTANT: _dataFuture nu trebuie NICIODATĂ reasignat la un Future încă
    // nerezolvat în timpul animației — FutureBuilder resetează imediat
    // snapshot.data la null cât timp așteaptă noul Future, iar LevelHeader
    // ascunde complet pastilele de hints/gems când valorile lor sunt null
    // (vezi widget.hints/gems != null) — pastila dispărând exact când
    // CoinRewardOverlay îi caută poziția înseamnă că animația nu are unde
    // să zboare. De-asta folosim Future.value(...) cu date deja cunoscute
    // sincron, niciodată un Future "în zbor".
    final current = await _dataFuture;
    if (!mounted) return;
    setState(() {
      _dataFuture = Future.value(_QuestsData(
        quests: current.quests,
        xp: current.xp,
        coins: current.coins,
        lives: current.lives,
        hints: current.hints,
        gems: current.gems,
        progress: current.progress,
        claimed: Map<String, bool>.of(current.claimed)..[q.id] = true, // bifa apare pe loc
      ));
    });
    await collectRewards(
      context,
      coins: q.coinReward,
      xp: q.xpReward,
      lives: q.heartReward,
      hints: q.hintReward,
      hintsBadgeKey: _hintsBadgeKey,
      gems: q.gemReward,
      gemsBadgeKey: _gemsBadgeKey,
      coinBadgeKey: _coinBadgeKey,
      xpBadgeKey: _xpBadgeKey,
      livesBadgeKey: _livesBadgeKey,
      onEachImpact: () {
        // balanțele reale se actualizează treptat, o dată cu impactul
        // fiecărei etape — dar reîncărcarea (_load) e async, deci aplicăm
        // rezultatul abia când e gata (nu reasignăm direct Future-ul pendinte).
        _load().then((refreshed) {
          if (!mounted) return;
          setState(() => _dataFuture = Future.value(refreshed));
        });
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
                    hints: data?.hints,
                    gems: data?.gems,
                    coinBadgeKey: _coinBadgeKey,
                    xpBadgeKey: _xpBadgeKey,
                    livesBadgeKey: _livesBadgeKey,
                    hintsBadgeKey: _hintsBadgeKey,
                    gemsBadgeKey: _gemsBadgeKey,
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
                    'Se resetează în fiecare zi la miezul nopții — toate cele 70 de quest-uri sunt active.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                Expanded(
                  child: data == null
                      ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: data.quests.length,
                          itemBuilder: (context, i) {
                            final q = data.quests[i];
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
  final List<Quest> quests;
  final int xp;
  final int coins;
  final int lives;
  final int hints;
  final int gems;
  final Map<String, int> progress;
  final Map<String, bool> claimed;
  _QuestsData({
    required this.quests,
    required this.xp,
    required this.coins,
    required this.lives,
    required this.hints,
    required this.gems,
    required this.progress,
    required this.claimed,
  });
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
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('$progress / ${quest.target}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    const SizedBox(width: 8),
                    Expanded(child: _RewardChips(quest: quest)),
                  ],
                ),
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

/// Rândul de recompense al unui quest — un chip mic per resursă acordată
/// (până la 5: XP, monede, gems, viață, hint), în loc de o singură linie de
/// text ce nu mai încape odată ce un quest poate combina mai multe resurse.
class _RewardChips extends StatelessWidget {
  final Quest quest;
  const _RewardChips({required this.quest});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (quest.xpReward > 0) _chip(Icons.star_rounded, AppColors.purple, quest.xpReward),
      if (quest.coinReward > 0) _chip(Icons.monetization_on_rounded, AppColors.coin, quest.coinReward),
      if (quest.gemReward > 0) _chip(Icons.diamond_rounded, AppColors.gem, quest.gemReward),
      if (quest.heartReward > 0) _chip(Icons.favorite_rounded, AppColors.life, quest.heartReward),
      if (quest.hintReward > 0) _chip(Icons.tips_and_updates_rounded, AppColors.hint, quest.hintReward),
    ];
    return Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 3, children: chips);
  }

  Widget _chip(IconData icon, Color color, int amount) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 11),
        const SizedBox(width: 2),
        Text('$amount', style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
