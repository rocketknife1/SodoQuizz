import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/gamemodes.dart';
import '../core/quest_bump.dart';
import '../core/theme.dart';
import '../data/higher_lower_data.dart';
import '../data/questions.dart';
import '../data/shop.dart';
import '../data/storage_service.dart';
import '../widgets/category_card.dart';
import '../widgets/category_unlock_animation.dart';
import '../widgets/space_background.dart';
import 'higher_lower_screen.dart';
import 'loading_screen.dart';

class _ModeStats {
  final int total;
  final int answered;
  final int unlocked;
  final int tier;
  const _ModeStats({required this.total, required this.answered, required this.unlocked, required this.tier});
  double get pct => total > 0 ? answered / total : 0.0;
}

/// Ecranul care apare când apeși PLAY: alegi unul dintre cele 4
/// gamemoduri. Cardurile sunt generate din [gameModes] — nu e nimic
/// hardcodat aici, un gamemod nou apare automat.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late Future<Map<String, _ModeStats>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  Future<Map<String, _ModeStats>> _loadStats() async {
    final results = await Future.wait([loadAllQuestions(), StorageService.getAnsweredIds()]);
    final all = results[0] as List;
    final answeredIds = results[1] as Set<String>;
    final entries = await Future.wait(gameModes.where((m) => !m.locked).map((m) async {
      final total = all.where((q) => q.categoryId == m.id).length;
      final answered = all.where((q) => q.categoryId == m.id && answeredIds.contains(q.id)).length;
      final tier = await StorageService.getUnlockedTier(m.id);
      final unlocked = await StorageService.getUnlockedQuestionCount(m.id, total);
      return MapEntry(m.id, _ModeStats(total: total, answered: answered, unlocked: unlocked, tier: tier));
    }));
    return Map.fromEntries(entries);
  }

  /// Cumpără următoarea treaptă de upgrade pentru [mode] — deblochează chiar
  /// categoria dacă era la tier 0. La succes arată animația de deblocare și
  /// reîncarcă statisticile, ca noul tier să se reflecte imediat în card.
  Future<void> _upgrade(GameMode mode, _ModeStats stats) async {
    final ok = await StorageService.unlockNextQuestionBatch(mode.id);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nu ai destule gems.'), duration: Duration(milliseconds: 1400)),
      );
      return;
    }
    await bumpQuestMetric(context, 'question_batch_unlocked', 1);
    if (!mounted) return;
    await bumpQuestMetric(context, 'shop_spend', 1);
    if (!mounted) return;
    final newUnlocked = await StorageService.getUnlockedQuestionCount(mode.id, stats.total);
    if (!mounted) return;
    await CategoryUnlockAnimation.show(
      context,
      categoryTitle: mode.title,
      unlockedCount: newUnlocked - stats.unlocked,
    );
    if (!mounted) return;
    setState(() => _statsFuture = _loadStats());
  }

  /// Card special pentru "Higher or Lower" — vizual diferit de
  /// [CategoryCard] (fără planetă/inel de progres, care n-au sens pentru un
  /// mod arcade de streak), dar cu aceleași proporții/rotunjimi, ca lista
  /// să rămână coerentă. Recordul se citește direct din storage (aceeași
  /// infrastructură de high-score per mod ca la celelalte gamemoduri).
  Widget _buildHigherLowerCard() {
    return FutureBuilder<int>(
      future: StorageService.getModeHighScore(higherLowerModeId),
      builder: (context, snapshot) {
        final best = snapshot.data ?? 0;
        return GestureDetector(
          onTap: () {
            Sfx.tileSelect();
            Navigator.push(context, MaterialPageRoute(builder: (_) => const HigherLowerScreen()));
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.purple.withAlpha(150), width: 1.4),
              boxShadow: [BoxShadow(color: AppColors.purple.withAlpha(65), blurRadius: 16, spreadRadius: -3)],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 58,
                  height: 58,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(color: Colors.black.withAlpha(70), shape: BoxShape.circle),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.arrow_upward_rounded, color: AppColors.play, size: 20),
                          Icon(Icons.arrow_downward_rounded, color: AppColors.danger, size: 20),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.purple, borderRadius: BorderRadius.circular(8)),
                            child: const Text('NOU', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                          ),
                          const SizedBox(width: 7),
                          const Expanded(
                            child: Text(
                              'Higher or Lower',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Ce se caută mai mult? Ai 10 secunde să ghicești.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.emoji_events_rounded, color: AppColors.coin, size: 20),
                    const SizedBox(height: 2),
                    Text('$best', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SpaceBackground(
        child: SafeArea(
          child: FutureBuilder<Map<String, _ModeStats>>(
            future: _statsFuture,
            builder: (context, snapshot) {
              final stats = snapshot.data;
              final totalAnswered = stats?.values.fold<int>(0, (sum, s) => sum + s.answered) ?? 0;
              final totalQuestions = stats?.values.fold<int>(0, (sum, s) => sum + s.total) ?? 0;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 20, 6),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                        ),
                        const SizedBox(width: 4),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShaderMask(
                              shaderCallback: (r) => const LinearGradient(colors: [Colors.white, Color(0xFFC9B8FF)])
                                  .createShader(r),
                              child: const Text(
                                'Alege o categorie',
                                style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
                              ),
                            ),
                            if (totalQuestions > 0)
                              Text(
                                '$totalAnswered/$totalQuestions întrebări cucerite',
                                style: const TextStyle(color: Colors.white54, fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                      itemCount: gameModes.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        // primul rând e cardul special "Higher or Lower" —
                        // mecanică total diferită (fără poze/blur), nu face
                        // parte din gameModes, deci nu e afectat de gating cu
                        // Gems / progres pe întrebări ca restul categoriilor.
                        if (i == 0) return _buildHigherLowerCard();
                        final mode = gameModes[i - 1];
                        final s = stats?[mode.id];
                        final tier = s?.tier ?? 0;
                        final total = s?.total ?? 0;
                        final unlocked = s?.unlocked ?? 0;
                        // conținut inexistent încă (mode.locked) vs. blocată
                        // cu Gems (tier 0) — două motive diferite, ambele
                        // arătate ca "locked" vizual, dar cu text diferit.
                        final accessLocked = !mode.locked && s != null && tier == 0;
                        final visualLocked = mode.locked || accessLocked;
                        final canUpgrade = !mode.locked && s != null && tier < maxUnlockTier && total > initialUnlockedQuestions;
                        final upgradePrice = canUpgrade ? questionUnlockGemsPrice(tier + 1) : null;

                        final String subtitle;
                        if (mode.locked) {
                          subtitle = 'Va urma într-un update viitor';
                        } else if (accessLocked) {
                          subtitle = 'Blocată — deblocheaz-o cu Gems mai jos';
                        } else if (unlocked < total) {
                          subtitle = '${s?.answered ?? 0}/$unlocked jucate (din $total)';
                        } else {
                          subtitle = '${s?.answered ?? 0}/$total întrebări';
                        }

                        return CategoryCard(
                          index: i,
                          icon: mode.icon,
                          title: mode.title,
                          color: mode.accentColor,
                          locked: visualLocked,
                          totalQuestions: total,
                          answered: s?.answered ?? 0,
                          subtitle: subtitle,
                          upgradePrice: upgradePrice,
                          onUpgrade: canUpgrade ? () => _upgrade(mode, s) : null,
                          onTap: mode.locked
                              ? () => ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Va urma în următorul update! 🚀')),
                                  )
                              : accessLocked
                                  ? () => ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Deblocheaz-o cu Gems — vezi butonul de pe card.')),
                                      )
                                  : () {
                                      Sfx.tileSelect();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => LoadingScreen(gameModeId: mode.id)),
                                      );
                                    },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
