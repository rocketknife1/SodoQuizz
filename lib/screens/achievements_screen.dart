import 'package:flutter/material.dart';
import '../core/ads_service.dart';
import '../core/progression.dart';
import '../core/reward_collector.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';
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
  final GlobalKey _xpBadgeKey = GlobalKey();
  final GlobalKey _livesBadgeKey = GlobalKey();
  final GlobalKey _hintsBadgeKey = GlobalKey();
  final GlobalKey _gemsBadgeKey = GlobalKey();

  /// True cât timp o colectare e în desfășurare — dezactivează toate
  /// butoanele "Ridică" între timp, ca să nu pornească două animații
  /// simultan (vezi quests_screen.dart pentru același tipar).
  bool _claiming = false;

  /// Vezi [_refreshBalances] — o reîncărcare mai veche care se rezolvă mai
  /// târziu e ignorată dacă între timp a mai pornit una nouă, altfel balanța
  /// putea rămâne "înghețată" (bug-ul semnalat de user).
  int _loadSeq = 0;

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
      StorageService.getHints(),
      StorageService.getGems(),
    ]);
    // Progresul vine din aceeași funcție folosită de notificările in-app și
    // de bulina roșie (vezi StorageService.achievementProgressResolver) —
    // ecranul avea înainte o copie proprie a switch-ului, care ar fi rămas în
    // urmă la fiecare realizare nouă.
    final progressFor = await StorageService.achievementProgressResolver();

    final progress = <String, int>{};
    final claimed = <String, bool>{};
    for (final a in achievements) {
      progress[a.id] = progressFor(a);
      claimed[a.id] = await StorageService.isAchievementClaimed(a.id);
    }

    return _AchievementsData(
      xp: results[0],
      coins: results[1],
      lives: results[2],
      hints: results[3],
      gems: results[4],
      progress: progress,
      claimed: claimed,
    );
  }

  /// [multiplier] e 2 când vine din "Revendică x2" (vezi [_claimX2]).
  Future<void> _claim(Achievement a, {int multiplier = 1}) async {
    if (_claiming) return;
    setState(() => _claiming = true);
    await StorageService.claimAchievement(a.id);
    if (!mounted) return;
    // vezi quests_screen.dart — Future.value cu date deja cunoscute, NICIODATĂ
    // un Future încă nerezolvat, ca pastilele de hints/gems să nu dispară
    // (LevelHeader le ascunde când valoarea e null) chiar când animația le
    // caută poziția.
    final current = await _dataFuture;
    if (!mounted) return;
    setState(() {
      _dataFuture = Future.value(_AchievementsData(
        xp: current.xp,
        coins: current.coins,
        lives: current.lives,
        hints: current.hints,
        gems: current.gems,
        progress: current.progress,
        claimed: Map<String, bool>.of(current.claimed)..[a.id] = true,
      ));
    });
    await collectRewards(
      context,
      coins: a.coinReward * multiplier,
      xp: a.xpReward * multiplier,
      lives: a.heartReward * multiplier,
      hints: a.hintReward * multiplier,
      hintsBadgeKey: _hintsBadgeKey,
      // Realizările se revendică o singură dată în viața contului și cele din
      // seria lungă acordă 37-89 de hint-uri — peste plafonul de stoc (26).
      // Fără asta, cardul ar promite 89 și ar livra 26, exact ca la vieți,
      // unde se folosește deja addLivesUncapped.
      hintsUncapped: true,
      gems: a.gemReward * multiplier,
      gemsBadgeKey: _gemsBadgeKey,
      coinBadgeKey: _coinBadgeKey,
      xpBadgeKey: _xpBadgeKey,
      livesBadgeKey: _livesBadgeKey,
      onEachImpact: _refreshBalances,
    );
    if (!mounted) return;
    setState(() => _claiming = false);
  }

  /// Vezi quests_screen.dart._claimX2 — reclamă recompensată (sau simulare)
  /// care dublează recompensa realizării.
  Future<void> _claimX2(Achievement a) async {
    if (_claiming) return;
    final earned = await AdsService.instance.watchOrSimulate();
    if (!mounted || !earned) return;
    await _claim(a, multiplier: 2);
  }

  /// Vezi quests_screen.dart._refreshBalances — aplică rezultatul DOAR dacă
  /// nicio altă reîncărcare n-a mai pornit între timp, altfel un răspuns
  /// vechi ajuns ultimul ar suprascrie unul mai nou și balanța ar părea
  /// "înghețată" până la următoarea colectare.
  void _refreshBalances() {
    final seq = ++_loadSeq;
    _load().then((refreshed) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _dataFuture = Future.value(refreshed);
      });
    });
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
                      Text(tr('Realizări', 'Achievements'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    tr('Progres permanent — nu se resetează niciodată.',
                        'Permanent progress — it never resets.'),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                              disabled: _claiming,
                              onClaim: () => _claim(a),
                              onClaimX2: () => _claimX2(a),
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
  final int hints;
  final int gems;
  final Map<String, int> progress;
  final Map<String, bool> claimed;
  _AchievementsData({
    required this.xp,
    required this.coins,
    required this.lives,
    required this.hints,
    required this.gems,
    required this.progress,
    required this.claimed,
  });
}

class _AchievementCard extends StatelessWidget {
  final Achievement achievement;
  final int progress;
  final bool done;
  final bool claimed;
  final bool disabled;
  final VoidCallback onClaim;
  final VoidCallback onClaimX2;

  const _AchievementCard({
    required this.achievement,
    required this.progress,
    required this.done,
    required this.claimed,
    this.disabled = false,
    required this.onClaim,
    required this.onClaimX2,
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
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('$progress / ${achievement.target}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    const SizedBox(width: 8),
                    Expanded(child: _RewardChips(achievement: achievement)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (claimed)
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 26)
          else if (done)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: disabled ? null : onClaim,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.play,
                    disabledBackgroundColor: Colors.white24,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(tr('Revendică', 'Claim'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: disabled ? null : onClaimX2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: disabled ? Colors.white10 : AppColors.coin.withAlpha(35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: disabled ? Colors.white24 : AppColors.coin),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.smart_display_rounded, size: 12, color: disabled ? Colors.white38 : AppColors.coin),
                        const SizedBox(width: 4),
                        Text(
                          tr('Revendică x2', 'Claim x2'),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: disabled ? Colors.white38 : AppColors.coin),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          else
            const Icon(Icons.lock_clock_rounded, color: Colors.white24, size: 22),
        ],
      ),
    );
  }
}

/// Rândul de recompense al unei realizări — vezi _RewardChips din
/// quests_screen.dart (același concept, duplicat aici fiindcă layout-ul
/// cardului diferă ușor și nu merită un widget comun pentru atât de puțin).
class _RewardChips extends StatelessWidget {
  final Achievement achievement;
  const _RewardChips({required this.achievement});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (achievement.xpReward > 0) _chip(Icons.star_rounded, AppColors.purple, achievement.xpReward),
      if (achievement.coinReward > 0) _chip(Icons.monetization_on_rounded, AppColors.coin, achievement.coinReward),
      if (achievement.gemReward > 0) _chip(Icons.diamond_rounded, AppColors.gem, achievement.gemReward),
      if (achievement.heartReward > 0) _chip(Icons.favorite_rounded, AppColors.life, achievement.heartReward),
      if (achievement.hintReward > 0) _chip(Icons.tips_and_updates_rounded, AppColors.hint, achievement.hintReward),
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
