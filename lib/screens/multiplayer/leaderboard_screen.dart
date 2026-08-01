import 'package:flutter/material.dart';
import '../../core/gamemodes.dart';
import '../../core/leagues.dart';
import '../../core/theme.dart';
import '../../data/higher_lower_data.dart';
import '../../data/multiplayer_service.dart';
import '../../data/player_profile_service.dart';
import '../../data/storage_service.dart';
import '../../models/multiplayer_models.dart';
import '../../models/player_profile.dart';
import '../../widgets/avatar.dart';
import '../../widgets/level_header.dart';

/// Clasament — 2 taburi: progresul local pe categorii (neschimbat, vezi
/// [_MyProgressTab]) și leaderboard-ul global real (vezi [_GlobalLeaderboardTab],
/// alimentat de PlayerProfileService/player_profiles din Firestore).
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70)),
                  const SizedBox(width: 4),
                  const Text('Clasament', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              indicatorColor: AppColors.orange,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [Tab(text: 'Al tău'), Tab(text: 'Leaderboard')],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [_MyProgressTab(), _GlobalLeaderboardTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Progresul personal, local — conținutul original al acestui ecran înainte
/// să capete tabul de leaderboard global: doar punctele proprii pe
/// categorii, resetate la fiecare [StorageService.leaderboardPeriodHours].
class _MyProgressTab extends StatefulWidget {
  const _MyProgressTab();

  @override
  State<_MyProgressTab> createState() => _MyProgressTabState();
}

class _MyProgressTabState extends State<_MyProgressTab> {
  late final Future<_LocalProgressData> _dataFuture = _load();

  Future<_LocalProgressData> _load() async {
    final xp = await StorageService.getXp();
    final coins = await StorageService.getCoins();
    final lives = await StorageService.getLives();
    final points = await StorageService.getAllLeaderboardPoints();
    final periodRemaining = await StorageService.leaderboardPeriodRemaining();
    return _LocalProgressData(xp: xp, coins: coins, lives: lives, points: points, periodRemaining: periodRemaining);
  }

  static String _formatPeriod(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LocalProgressData>(
      future: _dataFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            LevelHeader(xp: data.xp, coins: data.coins, lives: data.lives),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.orange, Color(0xFFFFB020)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 36),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Puncte în acest ciclu', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text('${data.total} puncte', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          'Se resetează în ${_formatPeriod(data.periodRemaining)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text('Puncte pe categorie (ciclul curent)', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            // Higher or Lower nu face parte din gameModes (altă mecanică,
            // fără poze/blur) — rândul lui e adăugat manual, nu prin bucla
            // de mai jos.
            _ModeScoreRow(
              color: AppColors.purple,
              icon: Icons.swap_vert_rounded,
              title: 'Higher or Lower',
              score: data.points[higherLowerModeId] ?? 0,
            ),
            for (final m in gameModes.where((m) => !m.locked))
              _ModeScoreRow(color: m.accentColor, icon: m.icon, title: m.title, score: data.points[m.id] ?? 0),
          ],
        );
      },
    );
  }
}

class _LocalProgressData {
  final int xp;
  final int coins;
  final int lives;
  final Map<String, int> points;
  final Duration periodRemaining;
  _LocalProgressData({required this.xp, required this.coins, required this.lives, required this.points, required this.periodRemaining});

  int get total => points.values.fold(0, (sum, v) => sum + v);
}

class _ModeScoreRow extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final int score;

  const _ModeScoreRow({required this.color, required this.icon, required this.title, required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
          Text('$score pct', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Leaderboard-ul global real — toți userii (Google sau Guest) care au
/// intrat vreodată în joc, cumulat pe viață, sortat după puncte de ligă.
/// Userii inactivi de peste [PlayerProfileService.leaderboardFreshness] nu
/// apar în listă (progresul lor rămâne salvat, revin automat dacă redevin
/// activi — vezi PlayerProfileService.fetchLeaderboard).
class _GlobalLeaderboardTab extends StatefulWidget {
  const _GlobalLeaderboardTab();

  @override
  State<_GlobalLeaderboardTab> createState() => _GlobalLeaderboardTabState();
}

class _GlobalLeaderboardTabState extends State<_GlobalLeaderboardTab> {
  late Future<List<PlayerProfile>> _future = PlayerProfileService.instance.fetchLeaderboard();

  Future<void> _refresh() async {
    setState(() => _future = PlayerProfileService.instance.fetchLeaderboard());
    await _future;
  }

  void _showBreakdown(PlayerProfile p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(size: 44, label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?', accentColor: pickAvatarColor(p.avatarSeed), photoUrl: p.photoUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Unde și-a făcut punctajul', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              if (p.modeBreakdown.isEmpty)
                const Text('Niciun meci încă.', style: TextStyle(color: Colors.white38, fontSize: 13))
              else
                for (final entry in p.modeBreakdown.entries)
                  _ModeScoreRow(
                    color: _modeColor(entry.key),
                    icon: _modeIcon(entry.key),
                    title: _modeTitle(entry.key),
                    score: entry.value,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  static String _modeTitle(String gameModeId) => gameModeId == 'higherLower' ? 'Higher or Lower' : 'Clasic';
  static IconData _modeIcon(String gameModeId) => gameModeId == 'higherLower' ? Icons.swap_vert_rounded : Icons.emoji_events_rounded;
  static Color _modeColor(String gameModeId) => gameModeId == 'higherLower' ? AppColors.purple : AppColors.orange;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlayerProfile>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        final players = snap.data!;
        final me = MultiplayerService.instance.currentPlayerId;
        if (players.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.orange,
            child: ListView(
              children: const [
                SizedBox(height: 120),
                Center(
                  child: Text('Niciun jucător activ momentan.', style: TextStyle(color: Colors.white38, fontSize: 13)),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.orange,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            itemCount: players.length,
            itemBuilder: (context, i) {
              final p = players[i];
              final isMe = p.uid == me;
              final league = leagueForPoints(p.leaguePoints);
              return GestureDetector(
                onTap: () => _showBreakdown(p),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.blue.withAlpha(40) : Colors.white.withAlpha(12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isMe ? AppColors.blue : Colors.white24),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 28, child: Text('#${i + 1}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800))),
                      Avatar(size: 36, label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?', accentColor: pickAvatarColor(p.avatarSeed), photoUrl: p.photoUrl),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                            Row(
                              children: [
                                Icon(league.icon, color: league.color, size: 12),
                                const SizedBox(width: 4),
                                Text(league.name, style: TextStyle(color: league.color, fontSize: 11, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Text('${p.leaguePoints} pct', style: const TextStyle(color: AppColors.coin, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
