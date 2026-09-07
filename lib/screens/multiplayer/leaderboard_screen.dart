import 'package:flutter/material.dart';
import '../../core/cosmetics.dart';
import '../../core/elo.dart';
import '../../core/gamemodes.dart';
import '../../core/leagues.dart';
import '../../core/lang.dart';
import '../../core/theme.dart';
import '../../data/higher_lower_data.dart';
import '../../data/multiplayer_service.dart';
import '../../data/player_profile_service.dart';
import '../../data/storage_service.dart';
import '../../models/multiplayer_models.dart';
import '../../models/player_profile.dart';
import '../../widgets/avatar.dart';
import '../../widgets/cosmetic_title.dart';
import '../../widgets/entrance_item.dart';
import '../../widgets/league_badge.dart';
import '../../widgets/pressable.dart';
import '../../widgets/space_background.dart';

/// Clasament — 3 taburi:
/// - **Leaderboard** ([_GlobalLeaderboardTab]) — TOŢI jucătorii înregistraţi
///   (`fetchAllPlayers`), sortaţi după punctajul de sezon; cei inactivi cad
///   singuri la coadă (sezonul lor e vechi → [effectiveSeasonPoints] = 0).
///   Înainte erau două taburi separate („Toţi" + „Leaderboard") — redundant.
/// - **Prieteni** ([_FriendsLeaderboardTab]) — doar lista proprie + tu.
/// - **Al tău** ([_MyStatsTab]) — progresul PROPRIU: multiplayer (meciuri,
///   winrate, rating, streak, ligă) din profilul public + singleplayer
///   (întrebări, nivel, streak login, provocări, roată, planetă) din local +
///   punctaj pe mod în ciclul curent.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> with TickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);
  /// Intrarea în cascadă a antetului + tab bar-ului — aceeași senzație ca în
  /// Multiplayer, ca ecranul să nu apară dintr-o bucată.
  late final AnimationController _introCtrl;

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _introCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Poarta de ban: decizia proprietarului inchide Multiplayer SI Clasament
    // pentru cel banat. Acelasi tipar ca multiplayer_screen.dart — notifier
    // alimentat de abonament, deci ridicarea banului redeschide ecranul singur.
    return ValueListenableBuilder<bool>(
      valueListenable: PlayerProfileService.instance.amIBanned,
      builder: (context, banned, _) =>
          banned ? _buildBanned(context) : _buildLeaderboard(context),
    );
  }

  Widget _buildBanned(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.block_rounded, color: Colors.white54, size: 72),
                        const SizedBox(height: 20),
                        Text(
                          bannedFromOnlineMessage(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboard(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              EntranceItem(
                controller: _introCtrl,
                interval: const Interval(0.0, 0.45, curve: Curves.easeOut),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                  child: Row(
                    children: [
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70)),
                      const SizedBox(width: 4),
                      ShaderMask(
                        shaderCallback: (r) => const LinearGradient(colors: [Colors.white, AppColors.orange]).createShader(r),
                        child: const Text('CLASAMENT',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                      ),
                    ],
                  ),
                ),
              ),
              EntranceItem(
                controller: _introCtrl,
                interval: const Interval(0.15, 0.6, curve: Curves.easeOut),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withAlpha(30)),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFFFB020), AppColors.orange]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: AppColors.orange.withAlpha(120), blurRadius: 10)],
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                    unselectedLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    tabs: [
                      const Tab(text: 'Leaderboard'),
                      Tab(text: tr('Prieteni', 'Friends')),
                      Tab(text: tr('Al tău', 'Yours')),
                    ],
                  ),
                ),
              ),
              EntranceItem(
                controller: _introCtrl,
                interval: const Interval(0.25, 0.7, curve: Curves.easeOut),
                child: const _SeasonHeader(),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: const [_GlobalLeaderboardTab(), _FriendsLeaderboardTab(), _MyStatsTab()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "🏆 Sezon: August 2026 · se resetează în 7z 3h" — antetul de sezon din
/// planul de viitor (punctul 1): fără el, "toți suntem Bronze" nu se
/// explică nicăieri, iar sezoanele cu reset ar fi invizibile — un jucător
/// activ n-ar avea de unde să știe DE CE punctajul lui a scăzut brusc la
/// începutul lunii. Static la momentul montării (nu se reactualizează
/// singur în timp real) — suficient pentru un contor de zile, nu de secunde.
class _SeasonHeader extends StatelessWidget {
  const _SeasonHeader();

  @override
  Widget build(BuildContext context) {
    final remaining = seasonTimeRemaining();
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white.withAlpha(10), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.emoji_events_rounded, color: AppColors.orange, size: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tr('Sezon: ${seasonLabel()}', 'Season: ${seasonLabel()}'),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              tr('resetare în ${days}z ${hours}h', 'resets in ${days}d ${hours}h'),
              style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
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
  if (ts == null) return tr('niciodată online', 'never online');
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

void showPlayerProfileSheet(BuildContext context, PlayerProfile p) {
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
                AvatarWithLeagueBadge(
                  size: 44,
                  label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                  accentColor: pickAvatarColor(p.avatarSeed),
                  photoUrl: p.photoUrl,
                  style: avatarStyleFromId(p.avatarStyle),
                  frame: validatedFrame(p.equippedFrame, level: p.level, leaguePoints: p.leaguePoints),
                  tier: LeagueTier.values[(p.seasonKey == currentSeasonKey() ? p.seasonBestTierIndex : 0).clamp(0, LeagueTier.values.length - 1)],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      CosmeticTitle(titleId: p.equippedTitle),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(p.isRecentlyActive ? Icons.circle : Icons.access_time_rounded,
                    color: p.isRecentlyActive ? const Color(0xFF2ECC71) : Colors.white38,
                    size: p.isRecentlyActive ? 9 : 14),
                const SizedBox(width: 4),
                Text(
                  p.isRecentlyActive
                      ? tr('Activ acum', 'Active now')
                      : tr('Ultima dată online: ${_formatLastActive(p.lastActive)}',
                          'Last online: ${_formatLastActive(p.lastActive)}'),
                  style: TextStyle(
                      color: p.isRecentlyActive ? const Color(0xFF2ECC71) : Colors.white54,
                      fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Profilul public al altui jucător: statistici de bază, nu doar
            // punctajul pe moduri.
            Row(
              children: [
                _MiniStat(label: tr('Nivel', 'Level'), value: '${p.level}'),
                _MiniStat(label: tr('Meciuri', 'Matches'), value: '${p.matchesPlayed}'),
                _MiniStat(
                    label: tr('Rată câștig', 'Winrate'),
                    value: p.matchesPlayed == 0
                        ? '—'
                        : '${(p.winrate * 100).round()}%'),
                _MiniStat(
                    label: tr('Cel mai bun streak', 'Best streak'),
                    value: '${p.longestStreak}'),
              ],
            ),
            const SizedBox(height: 16),
            Text(tr('Unde și-a făcut punctajul', 'Where the points came from'), style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (p.modeBreakdown.isEmpty)
              Text(tr('Niciun meci încă.', 'No matches yet.'), style: const TextStyle(color: Colors.white38, fontSize: 13))
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

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }
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

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    // Sezon, nu punctaj pe viață — vezi core/leagues.dart#effectiveSeasonPoints.
    // Badge-ul cosmetic (peste avatar) folosește PEAK-ul sezonului
    // ([seasonBestTierIndex]), nu tier-ul de-acum, ca o înfrângere să nu
    // retrogradeze vizual pe cineva care chiar a atins tier-ul ăla luna asta.
    final seasonPts = effectiveSeasonPoints(seasonKey: profile.seasonKey, seasonPoints: profile.seasonPoints);
    final league = leagueForPoints(seasonPts);
    final peakTierIdx = profile.seasonKey == currentSeasonKey() ? profile.seasonBestTierIndex : 0;
    final peakTier = LeagueTier.values[peakTierIdx.clamp(0, LeagueTier.values.length - 1)];
    final medalColor = rank == 1 ? AppColors.coin : (rank == 2 ? const Color(0xFFC6D0DA) : const Color(0xFFCD8A4C));
    return Pressable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppColors.blue.withAlpha(40) : Colors.white.withAlpha(12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isMe ? AppColors.blue : (rank <= 3 ? medalColor.withAlpha(140) : Colors.white24)),
          boxShadow: rank <= 3 ? [BoxShadow(color: medalColor.withAlpha(45), blurRadius: 10, spreadRadius: -2)] : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: rank <= 3
                  ? Text(_medals[rank - 1], style: const TextStyle(fontSize: 18))
                  : Text('#$rank', maxLines: 1, softWrap: false, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
            ),
            AvatarWithLeagueBadge(
              size: 36,
              label: profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
              accentColor: pickAvatarColor(profile.avatarSeed),
              photoUrl: profile.photoUrl,
              style: avatarStyleFromId(profile.avatarStyle),
              frame: validatedFrame(profile.equippedFrame, level: profile.level, leaguePoints: profile.leaguePoints),
              tier: peakTier,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(profile.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                  CosmeticTitle(titleId: profile.equippedTitle, fontSize: 10),
                  if (profile.level > 0)
                    Text(tr('Nivel ${profile.level}', 'Level ${profile.level}'),
                        style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w600)),
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
            Text('$seasonPts pct', style: const TextStyle(color: AppColors.coin, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// Leaderboard-ul unic — TOŢI jucătorii înregistraţi (`fetchAllPlayers`),
/// sortaţi după punctajul de sezon. Cine e inactiv de mult are sezonul vechi,
/// deci [effectiveSeasonPoints] = 0 şi cade singur la coadă — nu mai e nevoie
/// de un tab separat „Toţi" care făcea aproape acelaşi lucru.
class _GlobalLeaderboardTab extends StatefulWidget {
  const _GlobalLeaderboardTab();

  @override
  State<_GlobalLeaderboardTab> createState() => _GlobalLeaderboardTabState();
}

class _GlobalLeaderboardTabState extends State<_GlobalLeaderboardTab> {
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
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Text(tr('Niciun jucător înregistrat momentan.', 'No registered players yet.'), style: const TextStyle(color: Colors.white38, fontSize: 13)),
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
                onTap: () => showPlayerProfileSheet(context, p),
              );
            },
          ),
        );
      },
    );
  }
}

/// Rivalitatea PERSONALĂ din planul de viitor (punctul 1): doar lista
/// proprie de prieteni + TU, sortați după punctajul de sezon — spre
/// deosebire de leaderboard-ul global, aici fiecare rând e cineva
/// recunoscut, nu un nume oarecare. Aceeași sursă de date ca notificarea
/// "te-a depășit cineva" (vezi PlayerProfileService._notifyOvertakes): dacă
/// cineva apare aici, poate declanșa/primi acea notificare.
class _FriendsLeaderboardTab extends StatefulWidget {
  const _FriendsLeaderboardTab();

  @override
  State<_FriendsLeaderboardTab> createState() => _FriendsLeaderboardTabState();
}

class _FriendsLeaderboardTabState extends State<_FriendsLeaderboardTab> {
  late Future<List<PlayerProfile>> _future = _load();

  static Future<List<PlayerProfile>> _load() async {
    final me = MultiplayerService.instance.currentPlayerId;
    final results = await Future.wait([
      PlayerProfileService.instance.fetchFriends(),
      PlayerProfileService.instance.getProfile(me),
    ]);
    final friends = results[0] as List<PlayerProfile>;
    final myProfile = results[1] as PlayerProfile?;
    final all = [...friends, if (myProfile != null) myProfile];
    // Sortare după punctajul de SEZON, nu cel pe viață — cine n-a jucat încă
    // în luna asta pică efectiv la 0 (vezi effectiveSeasonPoints), oricât de
    // sus ar fi rămas [leaguePoints] de anul trecut.
    all.sort((a, b) {
      final pa = effectiveSeasonPoints(seasonKey: a.seasonKey, seasonPoints: a.seasonPoints);
      final pb = effectiveSeasonPoints(seasonKey: b.seasonKey, seasonPoints: b.seasonPoints);
      return pb.compareTo(pa);
    });
    return all;
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
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
        // Fără prieteni, tot arăt propriul rând (dacă exista) — altfel un
        // jucător fără niciun prieten adăugat n-ar vedea nimic aici, deși
        // tehnic are un scor de sezon ca oricine altcineva.
        if (players.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.orange,
            child: ListView(
              children: [
                const SizedBox(height: 100),
                Center(
                  child: Text(
                    tr('Niciun prieten adăugat încă.', "You haven't added any friends yet."),
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    tr('Adaugă prieteni din ecranul de Prieteni ca să apară aici.',
                        'Add friends from the Friends screen to see them here.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white24, fontSize: 11.5),
                  ),
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
                onTap: () => showPlayerProfileSheet(context, p),
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

/// Progresul TĂU, într-un singur loc — ce vede un jucător când vrea să știe
/// „unde am ajuns": multiplayer (profil public) + singleplayer / progresie
/// zilnică (local) + punctajul pe mod în ciclul curent.
class _MyStatsTab extends StatefulWidget {
  const _MyStatsTab();

  @override
  State<_MyStatsTab> createState() => _MyStatsTabState();
}

class _MyStatsTabState extends State<_MyStatsTab> {
  late Future<_MyStatsData> _future = _load();

  static Future<_MyStatsData> _load() async {
    final results = await Future.wait([
      PlayerProfileService.instance.getMyProfile(),
      StorageService.getAllLeaderboardPoints(),
      StorageService.leaderboardPeriodRemaining(),
      StorageService.personalLocalStats(),
    ]);
    return _MyStatsData(
      profile: results[0] as PlayerProfile?,
      points: results[1] as Map<String, int>,
      periodRemaining: results[2] as Duration,
      local: results[3] as ({
        int intrebariIntalnite,
        int nivel,
        int streakLogin,
        int provocariZilei,
        int roataRotita,
        int planetePerfecte,
        int hinturiFolosite,
        int questeRevendicate,
      }),
    );
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
        final p = data.profile;
        final l = data.local;
        final seasonPts = p == null
            ? 0
            : effectiveSeasonPoints(seasonKey: p.seasonKey, seasonPoints: p.seasonPoints);
        final league = leagueForPoints(seasonPts);
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.orange,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
              // ── Multiplayer ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.blue, Color(0xFF3B5BDB)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sports_esports_rounded, color: Colors.white, size: 26),
                        const SizedBox(width: 10),
                        Text(tr('Multiplayer', 'Multiplayer'),
                            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('${p?.rating ?? eloStartRating}',
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                        const SizedBox(width: 4),
                        const Text('rating', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if ((p?.matchesPlayed ?? 0) == 0)
                      Text(tr('Încă n-ai jucat un meci multiplayer.',
                          'You have not played a multiplayer match yet.'),
                          style: const TextStyle(color: Colors.white60, fontSize: 12))
                    else
                      Row(
                        children: [
                          _MiniStat(label: tr('meciuri', 'matches'), value: '${p!.matchesPlayed}'),
                          _MiniStat(label: tr('victorii', 'wins'), value: '${p.wins}'),
                          _MiniStat(label: 'winrate', value: '${(p.winrate * 100).round()}%'),
                          _MiniStat(label: tr('cel mai lung streak', 'best streak'), value: '${p.longestStreak}'),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // ── Ligă + sezon ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: league.color.withAlpha(120)),
                ),
                child: Row(
                  children: [
                    Icon(league.icon, color: league.color, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(league.name, style: TextStyle(color: league.color, fontSize: 15, fontWeight: FontWeight.w800)),
                          Text(
                            tr('$seasonPts puncte de sezon · reset în ${_formatPeriod(data.periodRemaining)}',
                                '$seasonPts season points · resets in ${_formatPeriod(data.periodRemaining)}'),
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // ── Singleplayer / progresie ─────────────────────────────────
              Text(tr('Singleplayer & progresie', 'Singleplayer & progress'),
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _MiniStat(label: tr('întrebări văzute', 'questions seen'), value: '${l.intrebariIntalnite}'),
                        _MiniStat(label: tr('nivel', 'level'), value: '${l.nivel}'),
                        _MiniStat(label: tr('streak login', 'login streak'), value: '${l.streakLogin}'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _MiniStat(label: tr('provocări zilei', 'daily challenges'), value: '${l.provocariZilei}'),
                        _MiniStat(label: tr('roata', 'wheel spins'), value: '${l.roataRotita}'),
                        _MiniStat(label: tr('planete perfecte', 'perfect planets'), value: '${l.planetePerfecte}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // ── Punctaj pe mod (ciclul curent) ───────────────────────────
              Text(tr('Punctaj pe mod (ciclul curent)', 'Score per mode (current cycle)'),
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              // Higher or Lower nu face parte din gameModes (altă mecanică),
              // rândul lui e adăugat manual.
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
  final PlayerProfile? profile;
  final Map<String, int> points;
  final Duration periodRemaining;
  final ({
    int intrebariIntalnite,
    int nivel,
    int streakLogin,
    int provocariZilei,
    int roataRotita,
    int planetePerfecte,
    int hinturiFolosite,
    int questeRevendicate,
  }) local;

  _MyStatsData({
    required this.profile,
    required this.points,
    required this.periodRemaining,
    required this.local,
  });
}
