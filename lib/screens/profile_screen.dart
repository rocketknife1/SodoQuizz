import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../core/leagues.dart';
import '../core/progression.dart';
import '../core/theme.dart';
import '../data/auth_service.dart';
import '../data/player_profile_service.dart';
import '../data/questions.dart';
import '../data/storage_service.dart';
import '../models/player_profile.dart';
import '../widgets/avatar.dart';
import '../widgets/bottom_nav_bar.dart';
import 'achievements_screen.dart';
import 'multiplayer/leaderboard_screen.dart';
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
      PlayerProfileService.instance.getMyProfile(),
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
      multiplayerProfile: results[6] as PlayerProfile?,
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
                const Center(child: MyAvatar(size: 88)),
                const SizedBox(height: 14),
                Center(child: Text('Level $level', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
                const SizedBox(height: 4),
                Center(
                  child: Text('${xpIntoCurrentLevel(data.xp)} / ${xpForLevel(level)} XP către nivelul ${level + 1}',
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
                _buildMultiplayerStats(data.multiplayerProfile),
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
                const SizedBox(height: 12),
                _buildAccountRow(),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(key: _navBarKey, current: AppTab.profile),
    );
  }

  /// Statistici multiplayer (winrate/meciuri/streak) + liga curentă — un
  /// jucător fără niciun meci încă (profil null sau cu matchesPlayed == 0)
  /// tot arată Bronze/0, nu un mesaj de eroare (vezi leagueForPoints, 0
  /// puncte pică natural pe Bronze). Tap pe rândul de ligă deschide
  /// leaderboard-ul global.
  Widget _buildMultiplayerStats(PlayerProfile? profile) {
    final p = profile ?? const PlayerProfile(uid: '', name: '', avatarSeed: '');
    final league = leagueForPoints(p.leaguePoints);
    final winratePct = (p.winrate * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Multiplayer', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _StatTile(icon: Icons.percent_rounded, color: AppColors.play, label: 'Winrate', value: '$winratePct%')),
            const SizedBox(width: 12),
            Expanded(child: _StatTile(icon: Icons.sports_esports_rounded, color: AppColors.blue, label: 'Meciuri', value: '${p.matchesPlayed}')),
          ],
        ),
        const SizedBox(height: 12),
        _StatTile(
          icon: Icons.local_fire_department_rounded,
          color: AppColors.orange,
          label: 'Cel mai lung streak de victorii',
          value: '${p.longestStreak}',
          wide: true,
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
            child: Row(
              children: [
                Icon(league.icon, color: league.color, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Liga ${league.name}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('${p.leaguePoints} puncte de ligă', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Rând reactiv (StreamBuilder) — arată "Guest" sau numele/emailul
  /// contului Google logat. La tap, deschide sheet-ul cu acțiunea
  /// disponibilă (login sau logout) — prea puțin conținut ca să merite un
  /// ecran separat, spre deosebire de Realizări/Setări.
  Widget _buildAccountRow() {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges(),
      initialData: AuthService.instance.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        return GestureDetector(
          onTap: () => _showAccountSheet(user),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
            child: Row(
              children: [
                Icon(Icons.account_circle_rounded, color: user != null ? AppColors.play : Colors.white70, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Cont', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(user?.displayName ?? user?.email ?? 'Guest', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAccountSheet(User? user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: user == null
                ? [
                    const Text('Guest', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      'Progresul e salvat doar pe acest telefon. Conectează-te cu Google ca să nu-l pierzi la reinstalare.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _signIn();
                        },
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Conectează-te cu Google'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                  ]
                : [
                    Text(user.displayName ?? 'Cont Google', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    if (user.email != null) ...[
                      const SizedBox(height: 4),
                      Text(user.email!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          AuthService.instance.signOut();
                        },
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Deconectare'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    try {
      await AuthService.instance.signInWithGoogle();
      // fara asta, numele public (leaderboard/profil) ar ramane pe cel
      // generat aleator - vezi AuthService.signInWithGoogle - pana la
      // urmatoarea pornire/revenire din fundal a aplicatiei (cand rulează
      // heartbeat-ul din main.dart). Il rulăm explicit acum, imediat, plus
      // reincarcam datele afisate ca schimbarea sa se vada pe loc.
      await PlayerProfileService.instance.ensureProfileHeartbeat();
      if (!mounted) return;
      setState(() => _dataFuture = _load());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is AccountUnavailableException ? e.message : 'Contul e indisponibil momentan.')),
      );
    }
  }
}

class _ProfileData {
  final int xp;
  final int coins;
  final int highScore;
  final int answeredCount;
  final int totalQuestions;
  final bool claimableAchievements;
  /// Null dacă profilul public încă nu există (ex. primul heartbeat de la
  /// pornirea aplicației nu s-a scris încă) — tratat ca "niciun meci încă"
  /// în UI, nu ca eroare.
  final PlayerProfile? multiplayerProfile;
  _ProfileData({
    required this.xp,
    required this.coins,
    required this.highScore,
    required this.answeredCount,
    required this.totalQuestions,
    required this.claimableAchievements,
    this.multiplayerProfile,
  });
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
