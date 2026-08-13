import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../core/admin.dart';
import '../core/leagues.dart';
import '../core/progression.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/auth_service.dart';
import '../data/player_profile_service.dart';
import '../data/questions.dart';
import '../data/storage_service.dart';
import '../models/player_profile.dart';
import '../widgets/avatar.dart';
import '../widgets/bottom_nav_bar.dart';
import 'achievements_screen.dart';
import 'admin_screen.dart';
import 'friends_screen.dart';
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
      PlayerProfileService.instance.pendingFriendRequestCount(),
      AuthService.instance.multiplayerIdentity(),
      StorageService.getForcedName(),
    ]);
    final answered = results[3] as Set<String>;
    final total = (results[4] as List).length;
    final identity = results[8] as ({String name, String? photoUrl, String avatarStyle});
    final forcedName = results[9] as String;
    return _ProfileData(
      xp: results[0] as int,
      coins: results[1] as int,
      highScore: results[2] as int,
      answeredCount: answered.length,
      totalQuestions: total,
      claimableAchievements: results[5] as bool,
      multiplayerProfile: results[6] as PlayerProfile?,
      pendingFriendRequests: results[7] as int,
      name: identity.name,
      // Numele nu se poate schimba de aici în două cazuri: vine din contul
      // Google, sau a fost pus de administrator. Al doilea NU e o formalitate
      // — numele impus bate tot (vezi StorageService.getForcedName), deci
      // dacă butonul ar rămâne activ, jucătorul ar scrie altceva, ar apăsa
      // „Salvează" și n-ar vedea nicio schimbare, fără nicio explicație.
      nameLocked: identity.photoUrl != null || forcedName.isNotEmpty,
      nameSetByAdmin: forcedName.isNotEmpty,
    );
  }

  /// Schimbarea numelui, exact ca în ecranul de Multiplayer (de unde a fost
  /// mutată aici, la cererea userului): același dialog, aceeași salvare, ca
  /// jucătorul să n-aibă două locuri diferite în care se poate numi altfel.
  Future<void> _editName(_ProfileData data) async {
    if (data.nameLocked) return;
    final controller = TextEditingController(text: data.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Numele tău', 'Your name'),
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          maxLength: 16,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(counterStyle: TextStyle(color: Colors.white54)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('Anulează', 'Cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(tr('Salvează', 'Save')),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    await StorageService.setDisplayName(result);
    // fără asta, numele nou ar rămâne doar local — clasamentul și profilul
    // public ar arăta în continuare numele vechi până la următoarea pornire
    // a aplicației (vezi același pas în MultiplayerScreen._editName).
    await PlayerProfileService.instance.ensureProfileHeartbeat();
    if (mounted) setState(() => _dataFuture = _load());
  }

  /// Alegerea avatarului. Se salvează pe loc, la tap — fără buton de
  /// confirmare: e o alegere reversibilă dintr-o singură apăsare, iar
  /// avatarul din spatele dialogului se schimbă instant, deci se și vede ce
  /// ai ales. Alegerea urcă și în profilul public la următorul heartbeat, ca
  /// s-o vadă și ceilalți în clasament și în multiplayer.
  Future<void> _pickAvatar() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Alege-ți avatarul', 'Pick your avatar'),
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: double.maxFinite,
          child: ValueListenableBuilder<AvatarStyle>(
            valueListenable: myAvatarStyle,
            builder: (context, current, __) => Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final style in AvatarStyle.values)
                  GestureDetector(
                    onTap: () => setMyAvatarStyle(style),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: style == current ? AppColors.play : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: style == AvatarStyle.poza
                              ? const MyPhotoPreview(size: 62)
                              : AvatarArt(style: style, size: 62),
                        ),
                        const SizedBox(height: 4),
                        Text(style.label,
                            style: TextStyle(
                              color: style == current ? Colors.white : Colors.white54,
                              fontSize: 11,
                              fontWeight: style == current ? FontWeight.w800 : FontWeight.w500,
                            )),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('Gata', 'Done'), style: const TextStyle(color: AppColors.play, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    // urcă alegerea în profilul public, ca ceilalți s-o vadă fără să aștepte
    // repornirea aplicației
    await PlayerProfileService.instance.ensureProfileHeartbeat();
    if (mounted) setState(() {});
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
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: const Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        MyAvatar(size: 88),
                        // insignă mică de creion: fără ea, nimeni n-ar ghici
                        // că poza e apăsabilă
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: AppColors.purple,
                          child: Icon(Icons.edit_rounded, size: 14, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(tr('Apasă pe poză ca să-ți schimbi avatarul',
                          'Tap the picture to change your avatar'),
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ),
                const SizedBox(height: 14),
                // Numele, în locul în care stătea până acum „Level N". Nivelul
                // nu s-a pierdut: se citește pe rândul de sub el, care oricum
                // îl scria („... XP către nivelul N+1"). Numele are nevoie de
                // locul ăsta mai mult decât cifra nivelului — e singurul lucru
                // de pe ecran pe care îl văd ceilalți jucători.
                Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: data.nameLocked ? null : () => _editName(data),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            data.name.isEmpty ? '...' : data.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (!data.nameLocked) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.edit_rounded, color: Colors.white54, size: 18),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Center(
                  child: Text(
                    data.nameSetByAdmin
                        ? tr('Numele a fost stabilit de administrator', 'Your name was set by the administrator')
                        : data.nameLocked
                            ? tr('Numele vine din contul tău Google', 'Your name comes from your Google account')
                            : tr('Apasă pe nume ca să-l schimbi', 'Tap your name to change it'),
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                      tr('${xpIntoCurrentLevel(data.xp)} / ${xpForLevel(level)} XP către nivelul ${level + 1}',
                          '${xpIntoCurrentLevel(data.xp)} / ${xpForLevel(level)} XP to level ${level + 1}'),
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
                    Expanded(child: _StatTile(icon: Icons.monetization_on_rounded, color: AppColors.coin, label: tr('Monede', 'Coins'), value: '${data.coins}')),
                    const SizedBox(width: 12),
                    Expanded(child: _StatTile(icon: Icons.emoji_events_rounded, color: AppColors.orange, label: tr('Record', 'Best'), value: '${data.highScore}')),
                  ],
                ),
                const SizedBox(height: 12),
                _StatTile(
                  icon: Icons.fact_check_rounded,
                  color: AppColors.play,
                  label: tr('Întrebări răspunse', 'Questions answered'),
                  value: '${data.answeredCount} / ${data.totalQuestions}',
                  wide: true,
                ),
                const SizedBox(height: 24),
                _buildMultiplayerStats(data.multiplayerProfile),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendsScreen()));
                    // cererile acceptate/refuzate în Prieteni trebuie să
                    // schimbe pe loc bulina de mai jos, la fel ca la Realizări.
                    if (!mounted) return;
                    setState(() => _dataFuture = _load());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                    child: Row(
                      children: [
                        const Icon(Icons.group_rounded, color: AppColors.teal, size: 20),
                        const SizedBox(width: 12),
                        Text(tr('Prieteni', 'Friends'), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        if (data.pendingFriendRequests > 0) ...[
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
                        Text(tr('Realizări', 'Achievements'), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
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
                    child: Row(
                      children: [
                        const Icon(Icons.settings_rounded, color: Colors.white70, size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text(tr('Setări', 'Settings'), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildAccountRow(),
                _buildAdminRow(),
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
                      Text(tr('Liga ${league.name}', '${league.name} League'), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(tr('${p.leaguePoints} puncte de ligă', '${p.leaguePoints} league points'), style: const TextStyle(color: Colors.white54, fontSize: 11)),
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
                      // "Guest" DOAR când chiar nu e nimeni logat — un cont
                      // Play Games vine fără email si uneori fără nume, iar
                      // înainte cădea tocmai pe "Guest", deși era conectat.
                      Text(user == null ? 'Guest' : (user.displayName ?? user.email ?? 'Cont conectat'), style: const TextStyle(color: Colors.white54, fontSize: 11)),
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

  /// Vizibil DOAR pe contul de admin (vezi lib/core/admin.dart) — restul
  /// jucătorilor nu văd niciodată acest rând. Reutilizează exact aceeași
  /// pereche stream/initialData ca [_buildAccountRow], ca să nu adauge un
  /// al doilea listener redundant pe authStateChanges.
  Widget _buildAdminRow() {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges(),
      initialData: AuthService.instance.currentUser,
      builder: (context, snap) {
        if (snap.data?.email != kAdminEmail) return const SizedBox.shrink();
        return Column(
          children: [
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                child: const Row(
                  children: [
                    Icon(Icons.admin_panel_settings_rounded, color: AppColors.orange, size: 20),
                    SizedBox(width: 12),
                    Expanded(child: Text('Admin', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
                    Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 16),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAccountSheet(User? user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      // fara asta, randul nou (Sterge contul definitiv) pica taiat sub
      // ecran pe telefonul de test (verificat live) - modal bottom sheet
      // fara isScrollControlled nu lasa SingleChildScrollView sa creasca
      // peste inaltimea intrinseca initiala, fara nicio eroare in release.
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: user == null
                  ? [
                      const Text('Guest', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(
                        tr('Progresul e legat de această instalare. Conectează-te cu Google ca să nu-l pierzi la reinstalare sau la schimbarea telefonului.',
                            'Your progress is tied to this install. Sign in with Google so you do not lose it when reinstalling or changing phones.'),
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                          label: Text(tr('Conectează-te cu Google', 'Sign in with Google')),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      ),
                      if (AuthService.instance.isPlayGamesAvailable) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              _signIn(playGames: true);
                            },
                            icon: const Icon(Icons.sports_esports_rounded),
                            label: Text(tr('Conectează-te cu Play Games', 'Sign in with Play Games')),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.play, padding: const EdgeInsets.symmetric(vertical: 14)),
                          ),
                        ),
                      ],
                    ]
                  : [
                      Text(user.displayName ?? user.email ?? tr('Cont conectat', 'Signed in'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
                          label: Text(tr('Deconectare', 'Sign out')),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _confirmDeleteAccount();
                        },
                        child: Text(tr('Șterge contul definitiv', 'Delete account permanently'), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn({bool playGames = false}) async {
    _showSyncingDialog();
    try {
      if (playGames) {
        await AuthService.instance.signInWithPlayGames();
      } else {
        await AuthService.instance.signInWithGoogle();
      }
      // fara asta, numele public (leaderboard/profil) ar ramane pe cel
      // generat aleator - vezi AuthService.signInWithGoogle - pana la
      // urmatoarea pornire/revenire din fundal a aplicatiei (cand rulează
      // heartbeat-ul din main.dart). Il rulăm explicit acum, imediat, plus
      // reincarcam datele afisate ca schimbarea sa se vada pe loc.
      await PlayerProfileService.instance.ensureProfileHeartbeat();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // inchide dialogul de sincronizare
      setState(() => _dataFuture = _load());
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is AccountUnavailableException ? e.message : 'Contul e indisponibil momentan.')),
      );
    }
  }

  /// Acoperă tot fluxul de login (alegere cont Google + CloudSyncService.pullOrSeed,
  /// vezi AuthService.signInWithGoogle) — fără el, ecranul rămâne aparent
  /// înghețat câteva secunde între tap și rezultat, mai ales quand cloud-ul
  /// suprascrie progresul local (poate pierde progres de Guest, merită
  /// feedback vizibil cât se întâmplă). Blocant (fără dismiss/back), la fel
  /// ca celelalte dialoguri de tranziție obligatorie din joc (ex.
  /// GameScreen._showCategoryExitDialog).
  void _showSyncingDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1a1a2e),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.blue),
              const SizedBox(width: 20),
              Flexible(child: Text(tr('Se sincronizează progresul...', 'Syncing your progress...'), style: const TextStyle(color: Colors.white))),
            ],
          ),
        ),
      ),
    );
  }

  /// Dialog de confirmare explicit înainte de ștergerea definitivă de cont
  /// (vezi AuthService.deleteAccount) — enumeră clar ce se pierde, ca userul
  /// să nu apese din greșeală pe un TextButton mic din sheet-ul de cont.
  void _confirmDeleteAccount() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Ștergi contul definitiv?', 'Delete your account permanently?'), style: const TextStyle(color: Colors.white)),
        content: Text(
          tr(
            'Se șterg definitiv profilul public, prietenii, clasamentul și progresul salvat în cloud pentru acest cont Google. '
                'Progresul de pe acest telefon rămâne neatins. Acțiunea nu poate fi anulată.',
            'This permanently deletes the public profile, friends, leaderboard entry and cloud save for this Google account. '
                'The progress on this phone is left untouched. This cannot be undone.',
          ),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('Anulează', 'Cancel'))),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteAccount();
            },
            child: Text(tr('Șterge contul', 'Delete account'), style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    _showSyncingDialog();
    try {
      await AuthService.instance.deleteAccount();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // inchide dialogul de sincronizare
      setState(() => _dataFuture = _load());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Contul a fost șters.', 'The account has been deleted.'))),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Ștergerea a eșuat. Încearcă din nou.', 'Deletion failed. Please try again.'))),
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
  final int pendingFriendRequests;

  /// Numele cu care apari pentru ceilalți și dacă poate fi schimbat de aici
  /// (nu poate, dacă vine din contul Google sau e pus de administrator).
  final String name;
  final bool nameLocked;
  final bool nameSetByAdmin;

  _ProfileData({
    required this.xp,
    required this.coins,
    required this.highScore,
    required this.answeredCount,
    required this.totalQuestions,
    required this.claimableAchievements,
    this.multiplayerProfile,
    this.pendingFriendRequests = 0,
    this.name = '',
    this.nameLocked = false,
    this.nameSetByAdmin = false,
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
