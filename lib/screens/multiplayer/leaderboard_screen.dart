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

/// Clasament — 3 taburi: "Toți jucătorii" (roster complet, inclusiv cei
/// offline de mult, cu ultima oră online — vezi [_AllPlayersTab]) și
/// "Leaderboard" (doar userii activi recent — vezi [_GlobalLeaderboardTab]),
/// ambele alimentate de PlayerProfileService/player_profiles din Firestore;
/// "Al tău" (vezi [_MyStatsTab]) e strict local — punctajul propriu pe
/// ciclul curent de [StorageService.leaderboardPeriodHours]h, pe categorie.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

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
              tabs: const [Tab(text: 'Toți jucătorii'), Tab(text: 'Leaderboard'), Tab(text: 'Al tău')],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [_AllPlayersTab(), _GlobalLeaderboardTab(), _MyStatsTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formatează [Timestamp] "ultima activitate" cu dată+oră, scurt: "azi
/// HH:mm" / "ieri HH:mm" / "dd.MM HH:mm" (sau cu anul, dacă e diferit).
String _formatLastActive(dynamic ts) {
  if (ts == null) return 'niciodată online';
  final dt = (ts.toDate() as DateTime).toLocal();
  final now = DateTime.now();
  final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (sameDay(dt, now)) return 'azi $time';
  if (sameDay(dt, now.subtract(const Duration(days: 1)))) return 'ieri $time';
  final date = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}';
  return dt.year == now.year ? '$date $time' : '$date.${dt.year} $time';
}

String _modeTitle(String gameModeId) => gameModeId == 'higherLower' ? 'Higher or Lower' : 'Clasic';
IconData _modeIcon(String gameModeId) => gameModeId == 'higherLower' ? Icons.swap_vert_rounded : Icons.emoji_events_rounded;
Color _modeColor(String gameModeId) => gameModeId == 'higherLower' ? AppColors.purple : AppColors.orange;

void _showBreakdown(BuildContext context, PlayerProfile p) {
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
                Avatar(size: 44, label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?', accentColor: pickAvatarColor(p.avatarSeed), photoUrl: p.photoUrl, style: avatarStyleFromId(p.avatarStyle)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.access_time_rounded, color: Colors.white38, size: 14),
                const SizedBox(width: 4),
                Text('Ultima dată online: ${_formatLastActive(p.lastActive)}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
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

/// Un rând numerotat de jucător, folosit de ambele taburi — [showLastActive]
/// comută a doua linie între "ultima oră online" (tab "Toți jucătorii") și
/// numele ligii (tab "Leaderboard", unde toți sunt oricum activi recent).
class _PlayerRow extends StatelessWidget {
  final int rank;
  final PlayerProfile profile;
  final bool isMe;
  final bool showLastActive;
  final VoidCallback onTap;

  const _PlayerRow({required this.rank, required this.profile, required this.isMe, required this.showLastActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final league = leagueForPoints(profile.leaguePoints);
    return GestureDetector(
      onTap: onTap,
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
            SizedBox(width: 36, child: Text('#$rank', maxLines: 1, softWrap: false, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800))),
            Avatar(size: 36, label: profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?', accentColor: pickAvatarColor(profile.avatarSeed), photoUrl: profile.photoUrl, style: avatarStyleFromId(profile.avatarStyle)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(profile.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                  if (showLastActive)
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, color: Colors.white38, size: 12),
                        const SizedBox(width: 4),
                        Text(_formatLastActive(profile.lastActive), style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    )
                  else
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
            Text('${profile.leaguePoints} pct', style: const TextStyle(color: AppColors.coin, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// Roster COMPLET — toți userii (Google sau Guest) care au intrat vreodată
/// în joc, indiferent cât timp au stat departe, cu data+ora ultimei
/// prezențe online (vezi PlayerProfileService.fetchAllPlayers).
class _AllPlayersTab extends StatefulWidget {
  const _AllPlayersTab();

  @override
  State<_AllPlayersTab> createState() => _AllPlayersTabState();
}

class _AllPlayersTabState extends State<_AllPlayersTab> {
  late Future<List<PlayerProfile>> _future = PlayerProfileService.instance.fetchAllPlayers();

  Future<void> _refresh() async {
    setState(() => _future = PlayerProfileService.instance.fetchAllPlayers());
    await _future;
  }

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
                  child: Text('Niciun jucător înregistrat momentan.', style: TextStyle(color: Colors.white38, fontSize: 13)),
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
              return _PlayerRow(
                rank: i + 1,
                profile: p,
                isMe: p.uid == me,
                showLastActive: true,
                onTap: () => _showBreakdown(context, p),
              );
            },
          ),
        );
      },
    );
  }
}

/// Leaderboard-ul global filtrat — doar userii activi în ultimele
/// [PlayerProfileService.leaderboardFreshness] (progresul celor inactivi
/// rămâne salvat, revin automat aici dacă redevin activi — vezi
/// PlayerProfileService.fetchLeaderboard).
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
              return _PlayerRow(
                rank: i + 1,
                profile: p,
                isMe: p.uid == me,
                showLastActive: false,
                onTap: () => _showBreakdown(context, p),
              );
            },
          ),
        );
      },
    );
  }
}

String _formatPeriod(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return '${h}h ${m}m';
}

/// Punctajul tău propriu, strict local (nu vine din Firestore) — totalul pe
/// ciclul curent de [StorageService.leaderboardPeriodHours]h și defalcarea
/// pe fiecare categorie, exact cum arăta vechiul ecran "Clasamentul tău"
/// înainte de leaderboard-ul global (vezi git 3a2514d).
class _MyStatsTab extends StatefulWidget {
  const _MyStatsTab();

  @override
  State<_MyStatsTab> createState() => _MyStatsTabState();
}

class _MyStatsTabState extends State<_MyStatsTab> {
  late Future<_MyStatsData> _future = _load();

  static Future<_MyStatsData> _load() async {
    final points = await StorageService.getAllLeaderboardPoints();
    final periodRemaining = await StorageService.leaderboardPeriodRemaining();
    return _MyStatsData(points: points, periodRemaining: periodRemaining);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MyStatsData>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.orange,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
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
          ),
        );
      },
    );
  }
}

class _MyStatsData {
  final Map<String, int> points;
  final Duration periodRemaining;
  _MyStatsData({required this.points, required this.periodRemaining});

  int get total => points.values.fold(0, (sum, v) => sum + v);
}
