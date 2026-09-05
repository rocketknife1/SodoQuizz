import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/admin.dart';
import '../core/cosmetics.dart';
import '../core/leagues.dart';
import '../core/progression.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/auth_service.dart';
import '../data/google_web_signin_button.dart';
import '../data/player_profile_service.dart';
import '../data/questions.dart';
import '../data/storage_service.dart';
import '../models/player_profile.dart';
import '../widgets/appearance_sheet.dart';
import '../widgets/avatar.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/cosmetic_title.dart';
import '../widgets/league_badge.dart';
import '../widgets/edit_name_dialog.dart';
import 'achievements_screen.dart';
import 'admin_screen.dart';
import 'friends_screen.dart';
import 'multiplayer/leaderboard_screen.dart';
import 'settings_screen.dart';
import '../core/breadcrumbs.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<_ProfileData> _dataFuture = _load();
  final GlobalKey<AppBottomNavBarState> _navBarKey = GlobalKey();

  // Pe web nu putem porni login-ul Google din cod (vezi AuthService pentru
  // de ce) - userul apasă butonul randat chiar de Google, iar noi doar
  // ascultăm rezultatul pe acest stream. Abonare o singură dată la nivel de
  // ecran (nu la fiecare deschidere a sheet-ului) ca să nu pierdem
  // evenimentul dacă vine chiar în clipa în care sheet-ul se închide.
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleWebSub;

  @override
  void initState() {
    super.initState();
    Breadcrumbs.drop('ecran: Profil');
    // Resursele se pot schimba sub ecranul deschis: un grant de la admin, un
    // premiu încasat în fundal, sau salvarea coborâtă din cloud. Vezi
    // StorageService.balanceRevision.
    StorageService.balanceRevision.addListener(_refreshBalances);
    // Redenumirea făcută din panoul de Admin ajunge live pe telefon (vezi
    // PlayerProfileService.startLive) — reîncărcăm ca numele nou să apară pe loc.
    PlayerProfileService.instance.profileChanged.addListener(_refreshBalances);
    if (kIsWeb) {
      AuthService.instance.ensureGoogleInitialized();
      _googleWebSub = AuthService.instance.googleAuthenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          _completeWebGoogleSignIn(event.user);
        }
      });
    }
  }

  @override
  void dispose() {
    StorageService.balanceRevision.removeListener(_refreshBalances);
    PlayerProfileService.instance.profileChanged.removeListener(_refreshBalances);
    _googleWebSub?.cancel();
    super.dispose();
  }

  void _refreshBalances() {
    if (!mounted) return;
    setState(() => _dataFuture = _load());
  }

  Future<void> _completeWebGoogleSignIn(GoogleSignInAccount account) async {
    if (!mounted) return;
    final sheetContext = _accountSheetContext;
    if (sheetContext != null && Navigator.canPop(sheetContext)) {
      Navigator.pop(sheetContext); // inchide sheet-ul "Conectează-te" — userul a apasat butonul Google, nu al nostru
    }
    _showSyncingDialog();
    try {
      await AuthService.instance.completeWebGoogleSignIn(account);
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
    final identity = results[8] as ({String name, String? photoUrl, String avatarStyle,
        String equippedFrame, String equippedTitle, int level});
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
      nameSetByAdmin: forcedName.isNotEmpty,
    );
  }

  /// Schimbarea numelui — același dialog folosit peste tot în aplicație
  /// (vezi widgets/edit_name_dialog.dart), ca jucătorul să n-aibă două
  /// locuri diferite în care se poate numi altfel.
  Future<void> _editName(_ProfileData data) async {
    final result = await editDisplayName(context, currentName: data.name, nameSetByAdmin: data.nameSetByAdmin);
    if (result == null || !mounted) return;
    setState(() => _dataFuture = _load());
  }

  /// Alegerea avatarului. Se salvează pe loc, la tap — fără buton de
  /// confirmare: e o alegere reversibilă dintr-o singură apăsare, iar
  /// avatarul din spatele dialogului se schimbă instant, deci se și vede ce
  /// ai ales. Alegerea urcă și în profilul public la următorul heartbeat, ca
  /// s-o vadă și ceilalți în clasament și în multiplayer.
  Future<void> _pickAppearance() async {
    final data = await _dataFuture;
    final achievements = await StorageService.completedAchievementIds();
    if (!mounted) return;
    await showAppearanceSheet(
      context,
      level: levelForXp(data.xp),
      leaguePoints: data.multiplayerProfile?.leaguePoints ?? 0,
      achievements: achievements,
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
                    onTap: _pickAppearance,
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
                  child: Text(tr('Apasă pe avatar ca să-ți schimbi aspectul',
                          'Tap the avatar to change your look'),
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
                    onTap: () => _editName(data),
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
                        const SizedBox(width: 8),
                        const Icon(Icons.edit_rounded, color: Colors.white54, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Center(
                  child: ValueListenableBuilder<PlayerTitle>(
                    valueListenable: myTitle,
                    builder: (_, title, __) => CosmeticTitle(
                      titleId: title.name,
                      fontSize: 12,
                      align: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Center(
                  child: Text(
                    tr('Apasă pe nume ca să-l schimbi', 'Tap your name to change it'),
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
    // Sezon, nu punctaj pe viață — la fel ca în clasament, vezi
    // core/leagues.dart#effectiveSeasonPoints. [leaguePoints] rămâne
    // afișat, dar ca linie secundară "cel mai bun rezultat pe viață".
    final seasonPts = effectiveSeasonPoints(seasonKey: p.seasonKey, seasonPoints: p.seasonPoints);
    final league = leagueForPoints(seasonPts);
    final peakTierIdx = p.seasonKey == currentSeasonKey() ? p.seasonBestTierIndex : 0;
    final peakTier = LeagueTier.values[peakTierIdx.clamp(0, LeagueTier.values.length - 1)];
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
                LeagueBadge(tier: peakTier, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr('Liga ${league.name} · ${seasonLabel()}', '${league.name} League · ${seasonLabel()}'),
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(
                        tr('$seasonPts puncte sezonul ăsta · ${p.leaguePoints} pe viață',
                            '$seasonPts points this season · ${p.leaguePoints} lifetime'),
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
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
      builder: (sheetContext) {
        _accountSheetContext = sheetContext;
        return SafeArea(
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
                      // Pe web, Google interzice pornirea flow-ului din cod
                      // (authenticate() aruncă UnimplementedError acolo) -
                      // userul trebuie să apese butonul lor randat direct în
                      // DOM. Vezi AuthService.googleAuthenticationEvents și
                      // _completeWebGoogleSignIn pentru restul fluxului.
                      if (kIsWeb)
                        Center(child: buildGoogleWebSignInButton())
                      else
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
        );
      },
    ).whenComplete(() => _accountSheetContext = null);
  }

  BuildContext? _accountSheetContext;

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

  /// Numele cu care apari pentru ceilalți jucători.
  final String name;

  /// `true` dacă numele curent a fost impus din Admin — dialogul îl ridică
  /// înainte de salvare ca primul heartbeat să nu-l pună la loc.
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
