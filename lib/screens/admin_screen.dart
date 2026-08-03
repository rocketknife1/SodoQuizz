import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../core/progression.dart' show levelForXp;
import '../core/theme.dart';
import '../data/multiplayer_activity_service.dart';
import '../data/player_profile_service.dart';
import '../data/storage_service.dart';
import '../models/multiplayer_activity.dart';
import '../models/multiplayer_models.dart' show pickAvatarColor;
import '../models/player_profile.dart';
import '../widgets/avatar.dart';
import '../widgets/category_unlock_animation.dart';
import '../widgets/coin_reward_overlay.dart';
import 'test_images_screen.dart';

/// Panou vizibil DOAR pentru contul de admin (vezi profile_screen.dart,
/// randul care navigheaza aici, ascuns pentru oricine altcineva). Cinci
/// taburi: gestionare jucatori (interzicere + trimitere de resurse),
/// jucatorii inregistrati azi, camerele de multiplayer terminate recent,
/// uneltele de debug/test (mutate din SettingsScreen — acolo erau vizibile
/// oricui, fara nicio filtrare) si statistici agregate.
///
/// Un tap pe randul unui jucator deschide [_PlayerDetailScreen], unde apare
/// intai id-ul unic si apoi balanta/prietenii — vezi comentariul de acolo
/// pentru de ce id-ul, si nu numele, e cheia dupa care se opereaza.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 5, vsync: this);

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
              tabs: const [Tab(text: 'Jucători'), Tab(text: 'Noi azi'), Tab(text: 'Camere'), Tab(text: 'Debug'), Tab(text: 'Statistici')],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [_PlayersTab(), _NewTodayTab(), _RoomsTab(), _DebugTab(), _StatsTab()],
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

/// Ștergere totală a unui cont, din tab-ul Jucători. Spre deosebire de ban
/// (care doar scoate profilul din leaderboard și blochează recrearea lui),
/// asta șterge tot ce ține de cont — vezi [PlayerProfileService.purgePlayer]
/// pentru lista exactă. Dialogul spune explicit și ce NU se întâmplă imediat,
/// ca să nu pară că butonul a lăsat treaba pe jumătate.
Future<bool> _confirmAndPurge(BuildContext context, PlayerProfile p) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Ștergi complet acest cont?', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${p.name} dispare definitiv. Se șterg:',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          const Text(
            '• profilul public și locul din clasament\n'
            '• prietenii, în ambele sensuri\n'
            '• cererile de prietenie primite\n'
            '• salvarea din cloud (monede, XP, progres)\n'
            '• grant-urile de resurse în așteptare',
            style: TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 10),
          const Text(
            'Contul din Authentication se șterge la următoarea rulare a '
            'scriptului de întreținere — până atunci rămâne gol, fără nicio '
            'dată legată de el.',
            style: TextStyle(color: Colors.white38, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 10),
          const Text('Nu poate fi anulat.',
              style: TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Renunță')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Șterge tot', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  final ok = await PlayerProfileService.instance.purgePlayer(p.uid, name: p.name);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok
          ? '${p.name} a fost șters complet.'
          : 'Nu am putut șterge acest cont.')),
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
  final int pendingAuthDeletions;
  const _StatsData({
    required this.players,
    required this.completedMatches,
    required this.pendingAuthDeletions,
  });
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
      PlayerProfileService.instance.pendingAuthDeletionCount(),
    ]);
    return _StatsData(
      players: results[0] as List<PlayerProfile>,
      completedMatches: results[1] as int,
      pendingAuthDeletions: results[2] as int,
    );
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
              // Cate conturi sterse din joc mai asteapta stergerea din
              // Firebase Authentication — pasul care cere Admin SDK, deci
              // scriptul de intretinere (vezi tools/purge_accounts.py).
              // Aparea doar cand chiar e ceva de facut.
              if (snap.data!.pendingAuthDeletions > 0) ...[
                const SizedBox(height: 12),
                _StatCard(
                  icon: Icons.delete_sweep_rounded,
                  label: 'Conturi de șters din Auth — rulează tools/purge_accounts.py',
                  value: '${snap.data!.pendingAuthDeletions}',
                  color: AppColors.danger,
                ),
              ],
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

// ─────────────────────────────────────────────────────────────────────────
//  Detaliul unui jucător
// ─────────────────────────────────────────────────────────────────────────

/// Formatare scurtă de dată/oră, fără dependențe (proiectul nu folosește
/// `intl`). Ex: "3 aug, 15:42".
String _shortDate(DateTime d) {
  const luni = ['ian', 'feb', 'mar', 'apr', 'mai', 'iun', 'iul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${luni[d.month - 1]}, $h:$m';
}

/// "acum 3 min" / "acum 2 h" / "acum 5 zile" — pentru lastActive, unde
/// vechimea relativă spune mai mult decât ora exactă.
String _relative(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'chiar acum';
  if (diff.inMinutes < 60) return 'acum ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'acum ${diff.inHours} h';
  if (diff.inDays == 1) return 'ieri';
  return 'acum ${diff.inDays} zile';
}

/// Numere lizibile pentru sume mari: 18750 → "18.750".
String _grouped(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$buf';
}

/// Fișa completă a unui jucător, deschisă cu tap pe rândul din tab-urile
/// Jucători / Noi azi.
///
/// ORDINEA E INTENȚIONATĂ: primul lucru afișat, înaintea oricărei statistici,
/// e **id-ul unic**. Numele se poate schimba și se poate repeta între
/// jucători; uid-ul nu. Tot ce operează sistemul — grant-urile de resurse
/// (`admin_grants/{uid}`), banarea, ștergerea, legăturile de prietenie,
/// cloud-save-ul — se leagă de uid, niciodată de nickname. Butonul de copiere
/// e acolo tocmai ca id-ul să poată fi lipit într-o discuție de suport sau
/// într-un script, fără să fie transcris de mână.
///
/// Întoarce `true` prin Navigator.pop dacă a schimbat ceva (ban/ștergere), ca
/// lista din spate să se reîmprospăteze.
class _PlayerDetailScreen extends StatefulWidget {
  final PlayerProfile profile;
  const _PlayerDetailScreen({required this.profile});

  @override
  State<_PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<_PlayerDetailScreen> {
  late Future<_PlayerDetail> _future = _load();
  bool _changed = false;

  Future<_PlayerDetail> _load() async {
    final results = await Future.wait([
      PlayerProfileService.instance.fetchFriendsOf(widget.profile.uid),
      PlayerProfileService.instance.fetchCloudSaveAsAdmin(widget.profile.uid),
    ]);
    return _PlayerDetail(
      friends: results[0] as List<PlayerProfile>,
      cloudSave: results[1] as Map<String, dynamic>?,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _copyUid() {
    Clipboard.setData(ClipboardData(text: widget.profile.uid));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ID copiat.'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context, _changed),
                      icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        p.name,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<_PlayerDetail>(
                  future: _future,
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.orange));
                    }
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      color: AppColors.orange,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        children: _body(p, snap.data!),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(PlayerProfile p, _PlayerDetail d) {
    final save = d.cloudSave;
    final xp = (save?['xp'] as num?)?.toInt() ?? 0;
    return [
      // ── ID-ul unic, primul lucru pe ecran ──
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.teal.withAlpha(90)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(
                  size: 44,
                  label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                  accentColor: pickAvatarColor(p.avatarSeed),
                  photoUrl: p.photoUrl,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(p.name,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis),
                      Text(
                        p.hasGoogleAccount ? 'Cont Google' : 'Guest',
                        style: TextStyle(
                          color: p.hasGoogleAccount ? AppColors.play : Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('ID UNIC',
                style: TextStyle(color: AppColors.teal, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    p.uid,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace', height: 1.35),
                  ),
                ),
                IconButton(
                  onPressed: _copyUid,
                  icon: const Icon(Icons.copy_rounded, color: AppColors.teal, size: 20),
                  tooltip: 'Copiază ID-ul',
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Resursele, banarea și ștergerea se leagă de acest ID, nu de nume. '
              'Numele se poate schimba și se poate repeta; ID-ul nu.',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),

      // ── Balanța ──
      const _SectionTitle('Balanță'),
      if (save == null)
        _InfoCard(
          icon: Icons.lock_outline_rounded,
          text: p.hasGoogleAccount
              ? 'Nu există salvare în cloud pentru acest cont încă — se scrie la prima sincronizare după login.'
              : 'Cont Guest: progresul stă doar pe telefonul lui, nu ajunge niciodată în cloud. Nu are balanță de arătat aici.',
        )
      else ...[
        Row(
          children: [
            Expanded(
                child: _BalanceTile(
                    label: 'Monede',
                    value: (save['coins'] as num?)?.toInt() ?? 0,
                    color: AppColors.coin,
                    icon: Icons.monetization_on_rounded)),
            const SizedBox(width: 10),
            Expanded(
                child: _BalanceTile(
                    label: 'Gems',
                    value: (save['gems'] as num?)?.toInt() ?? 0,
                    color: AppColors.gem,
                    icon: Icons.diamond_rounded)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _BalanceTile(
                    label: 'Inimi',
                    value: (save['lives'] as num?)?.toInt() ?? 0,
                    color: AppColors.life,
                    icon: Icons.favorite_rounded)),
            const SizedBox(width: 10),
            Expanded(
                child: _BalanceTile(
                    label: 'Hints',
                    value: (save['hints_balance'] as num?)?.toInt() ?? 0,
                    color: AppColors.hint,
                    icon: Icons.lightbulb_rounded)),
          ],
        ),
        const SizedBox(height: 10),
        // XP-ul brut e o cifră lungă și fără înțeles la prima vedere; nivelul
        // e ce înseamnă ea de fapt (vezi core/progression.dart).
        _DetailRow(label: 'Nivel', value: '${levelForXp(xp)}', highlight: true),
        _DetailRow(label: 'XP total', value: _grouped(xp)),
      ],
      const SizedBox(height: 22),

      // ── Prietenii ──
      _SectionTitle('Prieteni (${d.friends.length})'),
      if (d.friends.isEmpty)
        const _InfoCard(icon: Icons.person_off_rounded, text: 'No friends — nu are nicio legătură de prietenie.')
      else
        ...d.friends.map((f) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Avatar(
                    size: 30,
                    label: f.name.isNotEmpty ? f.name[0].toUpperCase() : '?',
                    accentColor: pickAvatarColor(f.avatarSeed),
                    photoUrl: f.photoUrl,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(f.name,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('${f.leaguePoints} pct', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            )),
      const SizedBox(height: 22),

      // ── Restul datelor esențiale ──
      const _SectionTitle('Detalii'),
      _DetailRow(label: 'Cod de prieten', value: p.friendCode ?? 'încă negenerat', mono: p.friendCode != null),
      _DetailRow(label: 'Ultima activitate', value: p.lastActive == null ? '—' : _relative(p.lastActive!.toDate())),
      _DetailRow(label: 'Cont creat', value: p.createdAt == null ? '—' : _shortDate(p.createdAt!.toDate())),
      _DetailRow(label: 'Puncte de ligă', value: _grouped(p.leaguePoints)),
      _DetailRow(label: 'Meciuri', value: '${p.matchesPlayed}  (${p.wins}V / ${p.losses}Î)'),
      _DetailRow(
        label: 'Winrate',
        value: p.matchesPlayed == 0 ? '—' : '${(p.winrate * 100).toStringAsFixed(0)}%',
      ),
      _DetailRow(label: 'Serie curentă', value: '${p.currentStreak}  (record ${p.longestStreak})'),
      const SizedBox(height: 26),

      // ── Acțiuni ──
      const _SectionTitle('Acțiuni'),
      _ActionButton(
        label: p.hasGoogleAccount ? 'Trimite resurse' : 'Trimite resurse (doar conturi Google)',
        icon: Icons.card_giftcard_rounded,
        color: p.hasGoogleAccount ? AppColors.teal : AppColors.gray,
        onPressed: () => _openGrantSheet(context, p),
      ),
      const SizedBox(height: 10),
      _ActionButton(
        label: 'Interzice contul',
        icon: Icons.block_rounded,
        color: AppColors.danger,
        onPressed: () async {
          if (await _confirmBan(context, p)) {
            _changed = true;
            if (mounted) Navigator.pop(context, true);
          }
        },
      ),
      const SizedBox(height: 10),
      _ActionButton(
        label: 'Șterge complet',
        icon: Icons.delete_forever_rounded,
        color: AppColors.danger,
        onPressed: () async {
          if (await _confirmAndPurge(context, p)) {
            _changed = true;
            if (mounted) Navigator.pop(context, true);
          }
        },
      ),
    ];
  }
}

class _PlayerDetail {
  final List<PlayerProfile> friends;

  /// null = cont Guest, sau cont Google fără sincronizare încă.
  final Map<String, dynamic>? cloudSave;
  const _PlayerDetail({required this.friends, required this.cloudSave});
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2),
        ),
      );
}

class _BalanceTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  const _BalanceTile({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withAlpha(24),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(70)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  Text(_grouped(value),
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final bool highlight;
  const _DetailRow({required this.label, required this.value, this.mono = false, this.highlight = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ),
            Expanded(
              flex: 5,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: highlight ? AppColors.orange : Colors.white,
                  fontSize: highlight ? 16 : 13,
                  fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                  fontFamily: mono ? 'monospace' : null,
                ),
              ),
            ),
          ],
        ),
      );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white38, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4)),
            ),
          ],
        ),
      );
}

/// Buton de acțiune lat, în stilul pastilelor din meniul principal — nu chip
/// mic în colț, ca restul butoanelor reale din joc.
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          label: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────
//  Camere de multiplayer terminate
// ─────────────────────────────────────────────────────────────────────────

/// Numele lizibil al unui mod de joc, din `gameModeId`-ul salvat.
String _modeLabel(String id) {
  switch (id) {
    case 'classic':
      return 'Clasic';
    case 'higherLower':
      return 'Higher or Lower';
    default:
      return id;
  }
}

/// "se șterge în 7 min" — cât mai are camera până dispare singură.
String _expiryLabel(RoomActivity r) {
  final left = r.timeLeft;
  if (left == null) return 'se șterge acum';
  if (left.inMinutes < 1) return 'se șterge în ${left.inSeconds}s';
  return 'se șterge în ${left.inMinutes + 1} min';
}

/// Camerele terminate în ultimele [roomActivityRetention] — vezi
/// MultiplayerActivityService pentru de ce dispar singure și cum.
///
/// La fiecare încărcare se mătură întâi camerele expirate rămase de la
/// jucători care n-au mai deschis aplicația (clienții și le șterg singuri pe
/// ale lor, dar numai când mai pornesc jocul).
class _RoomsTab extends StatefulWidget {
  const _RoomsTab();

  @override
  State<_RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<_RoomsTab> {
  late Future<List<RoomActivity>> _future = _load();

  Future<List<RoomActivity>> _load() async {
    await MultiplayerActivityService.instance.sweepExpiredAsAdmin();
    return MultiplayerActivityService.instance.fetchRooms();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RoomActivity>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        final rooms = snap.data!;
        if (rooms.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.orange,
            child: ListView(
              children: const [
                SizedBox(height: 100),
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Nicio cameră activă.\n\nAici apar meciurile multiplayer terminate, '
                      'cu ce a pus și ce a luat fiecare jucător. Fiecare cameră se șterge '
                      'singură la 10 minute după terminarea meciului.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
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
            itemCount: rooms.length,
            itemBuilder: (context, i) => _RoomCard(
              room: rooms[i],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => _RoomDetailScreen(room: rooms[i])),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RoomCard extends StatelessWidget {
  final RoomActivity room;
  final VoidCallback onTap;
  const _RoomCard({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.purple.withAlpha(40),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.meeting_room_rounded, color: AppColors.purple, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Cameră de ${room.playerCount} jucători',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_modeLabel(room.gameModeId)} · pot ${_grouped(room.pool)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _expiryLabel(room),
                    style: const TextStyle(color: AppColors.orange, fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

/// Tabloul complet al unei camere: id-ul camerei sus, apoi fiecare jucător cu
/// id-ul lui unic și cu cât a intrat / cu cât a ieșit.
class _RoomDetailScreen extends StatelessWidget {
  final RoomActivity room;
  const _RoomDetailScreen({required this.room});

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
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Cameră de ${room.playerCount} jucători',
                    style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.purple.withAlpha(90)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ID CAMERĂ',
                            style: TextStyle(
                                color: AppColors.purple,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                room.roomId,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13, fontFamily: 'monospace', height: 1.35),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: room.roomId));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('ID cameră copiat.'), duration: Duration(seconds: 2)),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, color: AppColors.purple, size: 20),
                              tooltip: 'Copiază ID-ul camerei',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle('Meciul'),
                  _DetailRow(label: 'Mod de joc', value: _modeLabel(room.gameModeId)),
                  _DetailRow(
                      label: 'Terminat',
                      value: room.finishedAt == null ? '—' : _shortDate(room.finishedAt!.toDate())),
                  _DetailRow(label: 'Se șterge', value: _expiryLabel(room)),
                  _DetailRow(label: 'Pot total', value: _grouped(room.pool)),
                  _DetailRow(label: 'Plafonul mesei', value: _grouped(room.tableCap)),
                  const SizedBox(height: 22),
                  _SectionTitle('Jucători (${room.playerCount})'),
                  ...room.players.map((p) => _RoomPlayerCard(player: p)),
                  const SizedBox(height: 16),
                  const _InfoCard(
                    icon: Icons.info_outline_rounded,
                    text: 'Intrat = taxa fixă de intrare plus miza pusă. Ieșit = câștigul din pot '
                        'plus surplusul returnat de plafonul mesei. Diferența dintre ele e '
                        'câștigul sau pierderea reală.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomPlayerCard extends StatelessWidget {
  final RoomActivityPlayer player;
  const _RoomPlayerCard({required this.player});

  @override
  Widget build(BuildContext context) {
    final net = player.net;
    final netColor = net > 0 ? AppColors.play : (net < 0 ? AppColors.danger : Colors.white54);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: player.place == 1 ? AppColors.coin.withAlpha(50) : Colors.white12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${player.place}',
                  style: TextStyle(
                    color: player.place == 1 ? AppColors.coin : Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(player.name,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('${player.score} p', style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          // Id-ul jucătorului, la fel de vizibil ca numele — el e cheia prin
          // care se leagă rândul ăsta de restul bazei de date.
          SelectableText(
            player.uid,
            style: const TextStyle(color: Colors.white38, fontSize: 10.5, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Intrat cu', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
                    Text('−${_grouped(player.entry)}',
                        style: const TextStyle(color: AppColors.danger, fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ieșit cu', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
                    Text('+${_grouped(player.exit)}',
                        style: const TextStyle(color: AppColors.play, fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Net', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
                    Text('${net >= 0 ? '+' : ''}${_grouped(net)}',
                        style: TextStyle(color: netColor, fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
