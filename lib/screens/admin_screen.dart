import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/player_profile_service.dart';
import '../data/storage_service.dart';
import '../models/multiplayer_models.dart' show pickAvatarColor;
import '../models/player_profile.dart';
import '../widgets/avatar.dart';
import '../widgets/category_unlock_animation.dart';
import '../widgets/coin_reward_overlay.dart';
import 'test_images_screen.dart';

/// Panou vizibil DOAR pentru contul de admin (vezi profile_screen.dart,
/// randul care navigheaza aici, ascuns pentru oricine altcineva). Patru
/// taburi: gestionare jucatori (interzicere + trimitere de resurse),
/// jucatorii inregistrati azi, uneltele de debug/test (mutate din
/// SettingsScreen — acolo erau vizibile oricui, fara nicio filtrare) si
/// statistici agregate.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 4, vsync: this);

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
                  const Text('Admin', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AppColors.orange,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [Tab(text: 'Jucători'), Tab(text: 'Noi azi'), Tab(text: 'Debug'), Tab(text: 'Statistici')],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [_PlayersTab(), _NewTodayTab(), _DebugTab(), _StatsTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmă și execută interzicerea unui cont — comun taburilor Jucători/Noi
/// azi. Întoarce true doar dacă chiar s-a șters (apelantul decide dacă
/// reîmprospătează lista).
Future<bool> _confirmBan(BuildContext context, PlayerProfile p) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Interzici acest cont?', style: TextStyle(color: Colors.white)),
      content: Text(
        '${p.name} dispare din leaderboard și din listele de prieteni ale altora și nu-și mai poate recrea profilul. Nu poate fi anulat.',
        style: const TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Renunță')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Interzice', style: TextStyle(color: AppColors.danger))),
      ],
    ),
  );
  if (confirmed != true) return false;
  final ok = await PlayerProfileService.instance.banPlayer(p.uid, name: p.name);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '${p.name} a fost interzis.' : 'Nu am putut interzice acest cont.')),
    );
  }
  return ok;
}

/// Deschide sheet-ul de trimitere resurse — refuză direct conturile Guest,
/// care nu au niciun canal către telefonul lor (vezi CloudSyncService).
void _openGrantSheet(BuildContext context, PlayerProfile p) {
  if (!p.hasGoogleAccount) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Doar conturile Google pot primi resurse.')));
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1a1a2e),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _GrantSheet(profile: p),
  );
}

/// Rând de jucător pentru AdminScreen — variantă a `_PlayerRow` din
/// leaderboard_screen.dart, cu acțiuni de grant/ban în loc de scor.
class _AdminPlayerRow extends StatelessWidget {
  final PlayerProfile profile;
  final VoidCallback onGrant;
  final VoidCallback onBan;
  const _AdminPlayerRow({required this.profile, required this.onGrant, required this.onBan});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withAlpha(12), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24)),
      child: Row(
        children: [
          Avatar(size: 36, label: profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?', accentColor: pickAvatarColor(profile.avatarSeed), photoUrl: profile.photoUrl),
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
            icon: Icon(Icons.card_giftcard_rounded, color: profile.hasGoogleAccount ? AppColors.teal : Colors.white24, size: 20),
            tooltip: profile.hasGoogleAccount ? 'Trimite resurse' : 'Doar conturi Google',
          ),
          IconButton(onPressed: onBan, icon: const Icon(Icons.block_rounded, color: AppColors.danger, size: 20), tooltip: 'Interzice'),
        ],
      ),
    );
  }
}

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
            itemCount: players.length,
            itemBuilder: (context, i) {
              final p = players[i];
              return _AdminPlayerRow(
                profile: p,
                onGrant: () => _openGrantSheet(context, p),
                onBan: () async {
                  if (await _confirmBan(context, p)) await _refresh();
                },
              );
            },
          ),
        );
      },
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
  late Future<List<PlayerProfile>> _future = PlayerProfileService.instance.fetchNewPlayersToday();

  Future<void> _refresh() async {
    setState(() => _future = PlayerProfileService.instance.fetchNewPlayersToday());
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
                Center(child: Text('Niciun jucător nou azi.', style: TextStyle(color: Colors.white38, fontSize: 13))),
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
              return _AdminPlayerRow(
                profile: p,
                onGrant: () => _openGrantSheet(context, p),
                onBan: () async {
                  if (await _confirmBan(context, p)) await _refresh();
                },
              );
            },
          ),
        );
      },
    );
  }
}

/// Sheet cu 5 câmpuri numerice (delta cu semn) — scrie în `admin_grants/{uid}`
/// cu `increment()`, ca grant-uri succesive netransmise încă să se adune,
/// nu să se suprascrie. Ridicat de telefonul jucătorului la următoarea
/// pornire, vezi CloudSyncService.consumePendingGrant.
class _GrantSheet extends StatefulWidget {
  final PlayerProfile profile;
  const _GrantSheet({required this.profile});

  @override
  State<_GrantSheet> createState() => _GrantSheetState();
}

class _GrantSheetState extends State<_GrantSheet> {
  final _hearts = TextEditingController();
  final _hints = TextEditingController();
  final _coins = TextEditingController();
  final _gems = TextEditingController();
  final _xp = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _hearts.dispose();
    _hints.dispose();
    _coins.dispose();
    _gems.dispose();
    _xp.dispose();
    super.dispose();
  }

  int _parse(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Future<void> _send() async {
    final hearts = _parse(_hearts);
    final hints = _parse(_hints);
    final coins = _parse(_coins);
    final gems = _parse(_gems);
    final xp = _parse(_xp);
    if (hearts == 0 && hints == 0 && coins == 0 && gems == 0 && xp == 0) {
      Navigator.pop(context);
      return;
    }
    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance.collection('admin_grants').doc(widget.profile.uid).set({
        if (hearts != 0) 'hearts': FieldValue.increment(hearts),
        if (hints != 0) 'hints': FieldValue.increment(hints),
        if (coins != 0) 'coins': FieldValue.increment(coins),
        if (gems != 0) 'gems': FieldValue.increment(gems),
        if (xp != 0) 'xp': FieldValue.increment(xp),
      }, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Trimis către ${widget.profile.name} — se aplică la următoarea deschidere a jocului lui.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nu am putut trimite resursele.')));
    }
  }

  Widget _field(TextEditingController c, String label, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: color, size: 20),
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          hintText: 'ex: 50 sau -20',
          hintStyle: const TextStyle(color: Colors.white24),
          filled: true,
          fillColor: AppColors.card,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resurse pentru ${widget.profile.name}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Numere negative = luare. Se aplică data viitoare când deschide jocul.', style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 16),
          _field(_hearts, 'Inimi', Icons.favorite_rounded, AppColors.life),
          _field(_hints, 'Hint-uri', Icons.tips_and_updates_rounded, AppColors.hint),
          _field(_coins, 'Monede', Icons.monetization_on_rounded, AppColors.coin),
          _field(_gems, 'Gems', Icons.diamond_rounded, const Color(0xFF5EC8F2)),
          _field(_xp, 'XP', Icons.star_rounded, AppColors.purple),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Trimite'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Unelte de debug/test — mutate 1:1 din SettingsScreen (acolo erau vizibile
/// oricui, fără nicio filtrare de cont). TEST verifică doar pozele
/// înlocuite manual (TestImagesScreen.testQuestionIds), fără să afecteze
/// scorul real; UNLIMITED umple resursele la maxim, pentru testare rapidă.
class _DebugTab extends StatefulWidget {
  const _DebugTab();

  @override
  State<_DebugTab> createState() => _DebugTabState();
}

class _DebugTabState extends State<_DebugTab> {
  final _coinPreviewKey = GlobalKey();
  final _xpPreviewKey = GlobalKey();
  final _livesPreviewKey = GlobalKey();
  final _hintsPreviewKey = GlobalKey();
  final _gemsPreviewKey = GlobalKey();

  /// Rulează, pe rând, aceeași animație de zbor (CoinRewardOverlay) folosită
  /// la colectarea reală de monede/XP/vieți/hints/gems — dar fără să scrie
  /// nimic în storage, doar ca previzualizare vizuală rapidă.
  Future<void> _previewRewardAnimations(BuildContext context) async {
    Future<void> stage({
      required int amount,
      required IconData icon,
      required Color color,
      required GlobalKey targetKey,
    }) async {
      final impactCompleter = Completer<void>();
      CoinRewardOverlay.show(
        context,
        amount: amount,
        targetKey: targetKey,
        icon: icon,
        color: color,
        onImpact: () {
          if (!impactCompleter.isCompleted) impactCompleter.complete();
        },
      );
      await impactCompleter.future;
      await Future.delayed(const Duration(milliseconds: 280));
    }

    await stage(amount: 25, icon: Icons.monetization_on_rounded, color: AppColors.coin, targetKey: _coinPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 40, icon: Icons.star_rounded, color: AppColors.purple, targetKey: _xpPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 4, icon: Icons.favorite_rounded, color: AppColors.life, targetKey: _livesPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 3, icon: Icons.tips_and_updates_rounded, color: AppColors.hint, targetKey: _hintsPreviewKey);
    if (!context.mounted) return;
    await stage(amount: 3, icon: Icons.diamond_rounded, color: const Color(0xFF5EC8F2), targetKey: _gemsPreviewKey);
  }

  Widget _buildPreviewBadge(GlobalKey key, IconData icon, Color color) {
    return Container(
      key: key,
      width: 34,
      height: 34,
      decoration: BoxDecoration(color: color.withAlpha(50), shape: BoxShape.circle, border: Border.all(color: color)),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 17),
    );
  }

  Future<void> _grantUnlimited(BuildContext context) async {
    await StorageService.setLives(999);
    final currentHints = await StorageService.getHints();
    if (currentHints < 999) await StorageService.addHintsUncapped(999 - currentHints);
    await StorageService.addCoins(99999);
    await StorageService.addGems(9999);
    await StorageService.debugUnlockAllQuestsAndAchievements();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('999 vieți, 999 hint-uri, +99999 monede, +9999 gems, toate quest-urile + realizările gata de revendicat (test)'),
          duration: Duration(milliseconds: 2200)),
    );
  }

  /// Butoane de test — la fel de vizibile ca butoanele de meniu (culoare
  /// solidă + iconiță), nu chip-uri mici de colț.
  Widget _buildDevToolButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, color.withAlpha(210)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: color.withAlpha(100), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDevToolButton(
                  icon: Icons.image_search_rounded,
                  label: 'TEST',
                  color: AppColors.blue,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TestImagesScreen())),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDevToolButton(
                  icon: Icons.all_inclusive_rounded,
                  label: 'UNLIMITED',
                  color: AppColors.orange,
                  onTap: () => _grantUnlimited(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDevToolButton(
            icon: Icons.lock_open_rounded,
            label: 'PREVIEW ANIMAȚIE DEBLOCARE',
            color: AppColors.purple,
            onTap: () => CategoryUnlockAnimation.show(context, categoryTitle: 'Categorie de test', unlockedCount: 15),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPreviewBadge(_coinPreviewKey, Icons.monetization_on_rounded, AppColors.coin),
              _buildPreviewBadge(_xpPreviewKey, Icons.star_rounded, AppColors.purple),
              _buildPreviewBadge(_livesPreviewKey, Icons.favorite_rounded, AppColors.life),
              _buildPreviewBadge(_hintsPreviewKey, Icons.tips_and_updates_rounded, AppColors.hint),
              _buildPreviewBadge(_gemsPreviewKey, Icons.diamond_rounded, const Color(0xFF5EC8F2)),
            ],
          ),
          const SizedBox(height: 8),
          _buildDevToolButton(
            icon: Icons.auto_awesome_rounded,
            label: 'PREVIEW RECOMPENSE',
            color: AppColors.teal,
            onTap: () => _previewRewardAnimations(context),
          ),
        ],
      ),
    );
  }
}

/// Datele agregate ale tabului Statistici — jucătorii (primii 300, pentru
/// total/Google-vs-Guest) și numărul REAL de meciuri încheiate (agregare
/// server-side, fără plafon — vezi PlayerProfileService.fetchCompletedMatchesCount).
class _StatsData {
  final List<PlayerProfile> players;
  final int completedMatches;
  const _StatsData({required this.players, required this.completedMatches});
}

class _StatsTab extends StatefulWidget {
  const _StatsTab();

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  late Future<_StatsData> _future = _load();

  Future<_StatsData> _load() async {
    final results = await Future.wait([
      PlayerProfileService.instance.fetchAllPlayers(),
      PlayerProfileService.instance.fetchCompletedMatchesCount(),
    ]);
    return _StatsData(players: results[0] as List<PlayerProfile>, completedMatches: results[1] as int);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StatsData>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        final players = snap.data!.players;
        final total = players.length;
        final google = players.where((p) => p.hasGoogleAccount).length;
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.orange,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              _StatCard(icon: Icons.groups_rounded, label: 'Total jucători', value: '$total', color: AppColors.orange),
              const SizedBox(height: 12),
              _StatCard(icon: Icons.verified_user_rounded, label: 'Google / Guest', value: '$google / ${total - google}', color: AppColors.play),
              const SizedBox(height: 12),
              _StatCard(
                icon: Icons.sports_esports_rounded,
                label: 'Meciuri multiplayer jucate',
                value: '${snap.data!.completedMatches}',
                color: AppColors.blue,
              ),
              const SizedBox(height: 16),
              const Text(
                'Meciuri: total real, încheiate normal, cu minim 2 jucători. Total jucători/Google-Guest: calculate din primii 300, ordonați după puncte de ligă.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
