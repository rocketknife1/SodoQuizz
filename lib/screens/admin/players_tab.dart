// Listele de jucători: toți, cei intrați azi, cei banați.
//
// Parte din `admin_screen.dart` (vezi `part of` mai jos): panoul de Admin era
// un singur fișier de peste 3.000 de linii, imposibil de ținut în cap. E
// împărțit pe tab-uri, nu pe tipuri de clase, fiindcă asta e granița după
// care se lucrează la el în practică.
part of '../admin_screen.dart';

/// Roster complet, cu acțiuni de admin — copiat după `_AllPlayersTab` din
/// leaderboard_screen.dart (același `fetchAllPlayers`), plus grant/ban.
class _PlayersTab extends StatefulWidget {
  const _PlayersTab();

  @override
  State<_PlayersTab> createState() => _PlayersTabState();
}

class _PlayersTabState extends State<_PlayersTab> {
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
        if (players.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.orange,
            child: ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('Niciun jucător înregistrat momentan.', style: TextStyle(color: Colors.white38, fontSize: 13))),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.orange,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            // +1 pentru butonul de anunț global, primul din listă.
            itemCount: players.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _buildBroadcastButton(context, players.length);
              final p = players[index - 1];
              return _AdminPlayerRow(
                profile: p,
                onChanged: _refresh,
                onGrant: () => _openGrantSheet(context, p),
                onBan: () async {
                  if (await _confirmBan(context, p)) await _refresh();
                },
                onPurge: () async {
                  if (await _confirmAndPurge(context, p)) await _refresh();
                },
              );
            },
          ),
        );
      },
    );
  }

  /// Anunț către toți — stă în capul listei de jucători fiindcă e o acțiune
  /// asupra listei întregi, nu asupra unui rând anume.
  Widget _buildBroadcastButton(BuildContext context, int playerCount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.bg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          builder: (_) => const _MessageSheet(),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.orange.withAlpha(28),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.orange.withAlpha(110)),
          ),
          child: Row(
            children: [
              const Icon(Icons.campaign_rounded, color: AppColors.orange, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Anunț pentru toți',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('Ajunge la cei $playerCount jucători din listă',
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

/// Jucătorii al căror profil a fost creat azi — vezi
/// PlayerProfileService.fetchNewPlayersToday.
class _NewTodayTab extends StatefulWidget {
  const _NewTodayTab();

  @override
  State<_NewTodayTab> createState() => _NewTodayTabState();
}

class _NewTodayTabState extends State<_NewTodayTab> {
  /// Cine a DESCHIS jocul azi, nu doar cine si-a facut cont azi. Asta e
  /// intrebarea pe care si-o pune adminul cand deschide panoul ("a intrat
  /// cineva?"), iar conturile noi sunt oricum o submultime: un cont creat azi
  /// a si fost activ azi, deci apare aici, marcat cu NOU.
  late Future<List<PlayerProfile>> _future = PlayerProfileService.instance.fetchPlayersActiveToday();

  Future<void> _refresh() async {
    setState(() => _future = PlayerProfileService.instance.fetchPlayersActiveToday());
    await _future;
  }

  /// A fost creat azi? Doar ca sa punem eticheta NOU pe rand.
  static bool _isNewToday(PlayerProfile p) {
    final created = p.createdAt?.toDate();
    if (created == null) return false;
    final now = DateTime.now();
    return !created.isBefore(DateTime(now.year, now.month, now.day));
  }

  static String _when(Timestamp? ts) {
    if (ts == null) return '';
    final d = DateTime.now().difference(ts.toDate());
    if (d.inMinutes < 1) return 'acum';
    if (d.inMinutes < 60) return 'acum ${d.inMinutes}m';
    return 'acum ${d.inHours}h';
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
        if (players.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.orange,
            child: ListView(
              children: const [
                SizedBox(height: 120),
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Nimeni n-a intrat în joc azi.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
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
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Row(
                      children: [
                        Text(_when(p.lastActive),
                            style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        if (_isNewToday(p)) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.play.withAlpha(40),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.play.withAlpha(120)),
                            ),
                            child: const Text('NOU',
                                style: TextStyle(color: AppColors.play, fontSize: 9, fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _AdminPlayerRow(
                    profile: p,
                    onChanged: _refresh,
                    onGrant: () => _openGrantSheet(context, p),
                    onBan: () async {
                      if (await _confirmBan(context, p)) await _refresh();
                    },
                    onPurge: () async {
                      if (await _confirmAndPurge(context, p)) await _refresh();
                    },
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Rând de jucător pentru AdminScreen — variantă a `_PlayerRow` din
/// leaderboard_screen.dart, cu acțiuni de grant/ban în loc de scor.
class _AdminPlayerRow extends StatelessWidget {
  final PlayerProfile profile;
  final VoidCallback onGrant;
  final VoidCallback onBan;
  final VoidCallback onPurge;

  /// Reîmprospătarea listei după ce ecranul de detaliu a schimbat ceva
  /// (ban/ștergere pornite de acolo).
  final Future<void> Function() onChanged;

  const _AdminPlayerRow({
    required this.profile,
    required this.onGrant,
    required this.onBan,
    required this.onPurge,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => _PlayerDetailScreen(profile: profile)),
        );
        if (changed == true) await onChanged();
      },
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withAlpha(12), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24)),
      child: Row(
        children: [
          Avatar(size: 36, label: profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?', accentColor: pickAvatarColor(profile.avatarSeed), photoUrl: profile.photoUrl, style: avatarStyleFromId(profile.avatarStyle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                Text(
                  profile.hasGoogleAccount ? 'Cont Google · ${profile.leaguePoints} pct' : 'Guest · ${profile.leaguePoints} pct',
                  style: TextStyle(color: profile.hasGoogleAccount ? AppColors.play : Colors.white38, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onGrant,
            icon: const Icon(Icons.card_giftcard_rounded, color: AppColors.teal, size: 20),
            tooltip: 'Trimite resurse',
          ),
          IconButton(onPressed: onBan, icon: const Icon(Icons.block_rounded, color: AppColors.danger, size: 20), tooltip: 'Interzice'),
          IconButton(
            onPressed: onPurge,
            icon: const Icon(Icons.delete_forever_rounded, color: AppColors.danger, size: 21),
            tooltip: 'Șterge complet',
          ),
        ],
      ),
      ),
    );
  }
}

/// Conturile interzise (`banned_players`) — SINGURUL loc din aplicație de
/// unde o interdicție se poate ridica.
///
/// De ce un tab separat și nu un buton în fișa jucătorului: banul șterge
/// profilul public (vezi [PlayerProfileService.banPlayer]), deci contul banat
/// nu mai apare în tab-ul Jucători, în „Noi azi", în leaderboard sau în
/// căutare. Fără lista asta, un ban dat din greșeală n-avea nicio cale de
/// întoarcere din aplicație.
class _BannedTab extends StatefulWidget {
  const _BannedTab();

  @override
  State<_BannedTab> createState() => _BannedTabState();
}

class _BannedTabState extends State<_BannedTab> {
  late Future<List<BannedPlayer>> _future = PlayerProfileService.instance.fetchBannedPlayers();

  Future<void> _refresh() async {
    setState(() => _future = PlayerProfileService.instance.fetchBannedPlayers());
    await _future;
  }

  Future<void> _unban(BannedPlayer b) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Ridici interdicția?', style: TextStyle(color: Colors.white)),
        content: Text(
          '${b.name} va putea intra din nou în multiplayer și în clasament. '
          'Profilul public i se recreează singur la următoarea pornire a jocului '
          '(statisticile vechi nu se întorc — au fost șterse la ban).',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Renunță')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ridică interdicția', style: TextStyle(color: AppColors.orange)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await PlayerProfileService.instance.unbanPlayer(b.uid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Interdicția pentru ${b.name} a fost ridicată.' : 'Nu am putut ridica interdicția.')),
    );
    if (ok) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BannedPlayer>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        final banned = snap.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.orange,
          child: banned.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 100),
                    Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Niciun cont interzis.\n\nAici ajung conturile interzise din tab-ul Jucători '
                          'și tot de aici li se poate ridica interdicția.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  itemCount: banned.length,
                  itemBuilder: (context, i) {
                    final b = banned[i];
                    final at = b.bannedAt?.toDate();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b.name,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(
                                  at == null
                                      ? b.uid
                                      : 'Interzis la ${at.day}.${at.month}.${at.year}  ·  ${b.uid}',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _unban(b),
                            child: const Text('Ridică interdicția',
                                style: TextStyle(color: AppColors.orange, fontSize: 12)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
