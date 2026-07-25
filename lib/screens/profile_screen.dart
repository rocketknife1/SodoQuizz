import 'package:flutter/material.dart';
import '../core/progression.dart';
import '../core/theme.dart';
import '../data/questions.dart';
import '../data/storage_service.dart';
import '../widgets/avatar.dart';
import '../widgets/bottom_nav_bar.dart';
import 'achievements_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<_ProfileData> _dataFuture = _load();
  final GlobalKey<AppBottomNavBarState> _navBarKey = GlobalKey();

  Future<_ProfileData> _load() async {
    final results = await Future.wait([
      StorageService.getXp(),
      StorageService.getCoins(),
      StorageService.getHighScore(),
      StorageService.getAnsweredIds(),
      loadAllQuestions(),
      StorageService.hasClaimableAchievements(),
    ]);
    final answered = results[3] as Set<String>;
    final total = (results[4] as List).length;
    return _ProfileData(
      xp: results[0] as int,
      coins: results[1] as int,
      highScore: results[2] as int,
      answeredCount: answered.length,
      totalQuestions: total,
      claimableAchievements: results[5] as bool,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: FutureBuilder<_ProfileData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator(color: AppColors.purple));
            }
            final level = levelForXp(data.xp);
            final progress = levelProgress(data.xp);

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              children: [
                const Center(child: Avatar(size: 88)),
                const SizedBox(height: 14),
                Center(child: Text('Nivel $level', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
                const SizedBox(height: 4),
                Center(
                  child: Text('${xpIntoCurrentLevel(data.xp)} / $xpPerLevel XP către nivelul ${level + 1}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(AppColors.purple),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: _StatTile(icon: Icons.monetization_on_rounded, color: AppColors.coin, label: 'Monede', value: '${data.coins}')),
                    const SizedBox(width: 12),
                    Expanded(child: _StatTile(icon: Icons.emoji_events_rounded, color: AppColors.orange, label: 'Record', value: '${data.highScore}')),
                  ],
                ),
                const SizedBox(height: 12),
                _StatTile(
                  icon: Icons.fact_check_rounded,
                  color: AppColors.play,
                  label: 'Întrebări răspunse',
                  value: '${data.answeredCount} / ${data.totalQuestions}',
                  wide: true,
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AchievementsScreen()));
                    // la revenire din Realizări, revendicările făcute acolo
                    // trebuie să dispară pe loc de pe rândul de mai jos și de
                    // pe bulina din bottom nav, fără să fie nevoie de un tab
                    // switch pentru a le reîncărca.
                    if (!mounted) return;
                    setState(() => _dataFuture = _load());
                    _navBarKey.currentState?.refreshDots();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                    child: Row(
                      children: [
                        const Icon(Icons.emoji_events_rounded, color: AppColors.orange, size: 20),
                        const SizedBox(width: 12),
                        const Text('Realizări', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        if (data.claimableAchievements) ...[
                          const SizedBox(width: 8),
                          const NotificationDot(borderColor: AppColors.card),
                        ],
                        const Spacer(),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                    child: const Row(
                      children: [
                        Icon(Icons.settings_rounded, color: Colors.white70, size: 20),
                        SizedBox(width: 12),
                        Expanded(child: Text('Setări', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
                        Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(key: _navBarKey, current: AppTab.profile),
    );
  }
}

class _ProfileData {
  final int xp;
  final int coins;
  final int highScore;
  final int answeredCount;
  final int totalQuestions;
  final bool claimableAchievements;
  _ProfileData({required this.xp, required this.coins, required this.highScore, required this.answeredCount, required this.totalQuestions, required this.claimableAchievements});
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool wide;

  const _StatTile({required this.icon, required this.color, required this.label, required this.value, this.wide = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
