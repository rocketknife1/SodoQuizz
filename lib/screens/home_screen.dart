import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/quest_bump.dart';
import '../core/reward_collector.dart';
import '../core/theme.dart';
import '../data/cloud_sync_service.dart';
import '../data/storage_service.dart';
import '../widgets/beta_info_balloon.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/culture_quiz_panel.dart';
import '../widgets/level_header.dart';
import '../widgets/lives_countdown_card.dart';
import '../widgets/mascots/discord_mascot.dart';
import '../widgets/mascots/paperclip_mascot.dart';
import '../widgets/mascots/ring_mascot.dart';
import '../widgets/solid_menu_button.dart';
import '../widgets/spinning_planet.dart';
import '../widgets/space_background.dart';
import 'categories_screen.dart';
import 'multiplayer/leaderboard_screen.dart';
import 'multiplayer/multiplayer_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _dataFuture;
  final GlobalKey _coinBadgeKey = GlobalKey();
  final GlobalKey _xpBadgeKey = GlobalKey();
  final GlobalKey _livesBadgeKey = GlobalKey();
  final GlobalKey _hintsBadgeKey = GlobalKey();
  final GlobalKey _gemsBadgeKey = GlobalKey();
  final GlobalKey<AppBottomNavBarState> _navBarKey = GlobalKey();

  /// Vezi quests_screen.dart._refreshBalances — aplică rezultatul DOAR dacă
  /// nicio altă reîncărcare n-a mai pornit între timp, altfel un răspuns
  /// vechi ajuns ultimul ar suprascrie unul mai nou și o balanță (de obicei
  /// hints, ultima etapă din collectRewards) ar părea "înghețată" — [_refresh]
  /// e chemat o dată per etapă (onEachImpact) la recompense compuse (nivel,
  /// Cultură Generală, bonusurile mascotelor), deci etapele se pot suprapune.
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
    _checkStreakMilestones();
    // Resursele trimise de admin (și resetul de cont) se aplică în fundal, la
    // pornire și la revenirea din fundal — momente în care ecranul ăsta poate
    // fi deja construit, cu cifrele de dinainte. Vezi CloudSyncService.
    CloudSyncService.instance.grantsApplied.addListener(_refresh);
    // Dezactivat temporar - popup-ul cerea prea multe apasari (o pagina pe
    // rand) la prima intrare. Codul (IntroTutorialDialog) ramane neatins,
    // doar apelul e oprit.
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   if (mounted) IntroTutorialDialog.maybeShow(context);
    // });
  }

  @override
  void dispose() {
    CloudSyncService.instance.grantsApplied.removeListener(_refresh);
    super.dispose();
  }

  Future<_HomeData> _loadData() async {
    final results = await Future.wait([
      StorageService.getXp(),
      StorageService.getCoins(),
      StorageService.getLives(),
      StorageService.getStreak(),
      StorageService.getHints(),
      StorageService.getPendingLevelRewardsCount(),
      StorageService.getGems(),
    ]);
    final livesUnlimited = await StorageService.hasUnlimitedLives();
    final livesUnlimitedRemaining = livesUnlimited ? await StorageService.unlimitedLivesRemaining() : Duration.zero;
    return _HomeData(
      xp: results[0],
      coins: results[1],
      lives: results[2],
      streak: results[3],
      hints: results[4],
      pendingLevelRewards: results[5],
      gems: results[6],
      livesUnlimited: livesUnlimited,
      livesUnlimitedRemaining: livesUnlimitedRemaining,
    );
  }

  /// "HH:MM:SS" — același format folosit de numărătoarea inversă a RingMascot.
  static String _formatCountdown(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Colectează, dintr-o singură mișcare, toate recompensele de nivel încă
  /// nerevendicate (poate fi mai multe deodată dacă jucătorul nu a mai
  /// intrat de o vreme — nimic nu se pierde niciodată, vezi StorageService)
  /// — fiecare resursă zboară spre pastila ei, exact ca la colectarea unui
  /// quest (vezi [collectRewards]).
  Future<void> _claimLevelRewards() async {
    final reward = await StorageService.claimAllPendingLevelRewards();
    if (!mounted || reward.isEmpty) {
      _refresh();
      return;
    }
    await collectRewards(
      context,
      coins: reward.coins,
      xp: 0,
      lives: reward.hearts,
      hints: reward.hints,
      gems: reward.gems,
      coinBadgeKey: _coinBadgeKey,
      xpBadgeKey: _xpBadgeKey,
      livesBadgeKey: _livesBadgeKey,
      hintsBadgeKey: _hintsBadgeKey,
      gemsBadgeKey: _gemsBadgeKey,
      onEachImpact: _refresh,
    );
    if (!mounted) return;
    await bumpQuestMetric(context, 'level_reward_claimed', 1);
    if (!mounted) return;
    _refresh();
  }

  /// Verifică dacă streak-ul a trecut de un prag nou (3/7/14... zile) —
  /// dacă da, bonusul e deja acordat de StorageService, arătăm doar mesajul.
  Future<void> _checkStreakMilestones() async {
    final newMilestones = await StorageService.claimNewStreakMilestones();
    if (newMilestones.isEmpty || !mounted) return;
    Sfx.rewardPop();
    final best = newMilestones.reduce((a, b) => a > b ? a : b);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              '🔥 $best zile la rând! Bonus: +${best * 5} monede, +${best * 10} XP')),
    );
    _refresh();
  }

  void _refresh() {
    final seq = ++_loadSeq;
    _loadData().then((refreshed) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _dataFuture = Future.value(refreshed);
      });
    });
    // bulina/cufărul de pe tab-ul Quests trebuie să reflecte pe loc orice
    // quest terminat în timpul unei sesiuni de joc, nu doar la reintrarea
    // manuală pe pagina Quests.
    _navBarKey.currentState?.refreshDots();
  }

  @override
  Widget build(BuildContext context) {
    // HomeScreen e mereu ruta de bază (root) a Navigator-ului — fără acest
    // PopScope, un back în plus (ex. 4 tap-uri de back în loc de 2, din
    // greșeală) ar ieși direct din aplicație. Cu canPop: false, back-ul e
    // pur și simplu absorbit aici: navigarea normală prin ecranele împinse
    // deasupra (Categorii, Setări, Joc etc.) rămâne neschimbată, dar odată
    // ajuns pe Home, niciun back suplimentar nu mai poate închide jocul.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SpaceBackground(
          child: SafeArea(
            child: Stack(
              children: [
                FutureBuilder<_HomeData>(
                  future: _dataFuture,
                  builder: (context, snapshot) {
                    final data = snapshot.data;

                    return _buildContent(context, data);
                  },
                ),
                // mascote plutind peste fundalul gol — nu ocupă spațiu din
                // layout; ambele au și o funcție reală (roata norocului /
                // bonusul cu întrebări), de-asta reîmprospătează header-ul.
                Positioned(bottom: 24, left: 12, child: RingMascot(onRewardsChanged: _refresh)),
                Positioned(bottom: 16, right: 0, child: PaperclipMascot(onRewardsChanged: _refresh)),
                const Positioned(bottom: 24, left: 104, child: DiscordMascot()),
                // Balonul de BETA stă în golul dintre marțianul de Discord
                // (cutia lui: left 104 + 92 lățime) și Clippy (right 0 + 116
                // lățime), la nivelul lor. NU mai sus: acolo plutea peste
                // panoul de Cultură Generală și acoperea variantele de
                // răspuns, făcând panoul imposibil de jucat.
                const Positioned(
                    bottom: 30, left: 200, right: 120, child: BetaInfoBalloon()),
              ],
            ),
          ),
        ),
        bottomNavigationBar: AppBottomNavBar(key: _navBarKey, current: AppTab.home),
      ),
    );
  }

  Widget _buildContent(BuildContext context, _HomeData? data) {
    // Pe 0 vieți apare cardul roșu cu numărătoarea inversă (LivesCountdownCard,
    // ~62px) și împinge tot ce e sub el în jos — inclusiv panoul de Cultură
    // Generală, care ajungea astfel exact peste Clippy și balonul de BETA
    // (ambele plutesc fix, în Stack-ul de deasupra). Soluția: ascundem logo-ul
    // (92px, pur decorativ) cât timp cardul e pe ecran. Net, conținutul urcă
    // ~30px față de normal, deci Cultura Generală stă imediat sub "fereastra"
    // de vieți și rămâne complet liberă de mascote.
    final outOfLives = data != null && data.lives == 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
      child: Column(
        children: [
          if (!outOfLives) ...[
            _buildLogo(),
            const SizedBox(height: 4),
          ],
          LevelHeader(
            xp: data?.xp ?? 0,
            coins: data?.coins ?? 0,
            lives: data?.lives ?? 5,
            hints: data?.hints ?? 3,
            gems: data?.gems ?? 0,
            pendingLevelRewards: data?.pendingLevelRewards ?? 0,
            livesUnlimited: data?.livesUnlimited ?? false,
            livesUnlimitedLabel: (data?.livesUnlimited ?? false) ? _formatCountdown(data!.livesUnlimitedRemaining) : null,
            coinBadgeKey: _coinBadgeKey,
            xpBadgeKey: _xpBadgeKey,
            livesBadgeKey: _livesBadgeKey,
            hintsBadgeKey: _hintsBadgeKey,
            gemsBadgeKey: _gemsBadgeKey,
            onCoinsTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ShopScreen()));
              _refresh();
            },
            onClaimLevelRewards: _claimLevelRewards,
          ),
          // vizibil DOAR pe 0 vieți — cât ai măcar una, nu se vede niciun
          // timer (vezi LivesCountdownCard).
          LivesCountdownCard(onLifeRecharged: _refresh),
          if ((data?.streak ?? 0) > 0) ...[
            const SizedBox(height: 6),
            _buildStreakChip(data!.streak),
          ],
          const SizedBox(height: 10),
          // butoanele meniului (stânga, mai înguste, banner-uri compacte) +
          // panoul interactiv de Cultură Generală (dreapta, mai lat) — fără
          // stretch forțat: panoul își ia înălțimea din propriul conținut,
          // nu e limitat la înălțimea (acum mai mică) a coloanei de butoane.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    SolidMenuButton(
                      icon: Icons.play_arrow_rounded,
                      label: 'PLAY',
                      subtitle: '',
                      color: AppColors.purple,
                      big: true,
                      angular: true,
                      onTap: () async {
                        // sesiunea de joc poate termina quest-uri — la
                        // revenire pe Home, reîmprospătăm inclusiv cufărul.
                        await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const CategoriesScreen()));
                        _refresh();
                      },
                    ),
                    const SizedBox(height: 8),
                    SolidMenuButton(
                      icon: Icons.emoji_events_rounded,
                      label: 'CLASAMENT',
                      color: AppColors.orange,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LeaderboardScreen())),
                    ),
                    const SizedBox(height: 8),
                    SolidMenuButton(
                      icon: Icons.groups_rounded,
                      label: 'MULTIPLAYER',
                      color: AppColors.teal,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MultiplayerScreen())),
                    ),
                    const SizedBox(height: 8),
                    SolidMenuButton(
                      icon: Icons.settings_rounded,
                      label: 'SETĂRI',
                      color: AppColors.gray,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SettingsScreen())),
                    ),
                    const SizedBox(height: 14),
                    // planeta stă direct sub Setări, în coloana de butoane —
                    // nu mai plutește izolată peste fundal, ca poziția ei să
                    // rămână corectă indiferent de scroll sau mărimea ecranului.
                    // Cutia ei animată (planetă + holograme) e mai lată decât
                    // coloana de butoane, de-aia o lăsăm să "depășească" în
                    // lateral printr-un OverflowBox, în loc să o comprimăm.
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: OverflowBox(
                        maxWidth: 260,
                        maxHeight: 260,
                        child: const SpinningPlanet(size: 76),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: CultureQuizPanel(
                  onRewardsChanged: _refresh,
                  coinBadgeKey: _coinBadgeKey,
                  xpBadgeKey: _xpBadgeKey,
                  livesBadgeKey: _livesBadgeKey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStreakChip(int streak) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.orange.withAlpha(30),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.orange.withAlpha(120)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔥', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              '$streak ${streak == 1 ? "zi" : "zile"} la rând',
              style: const TextStyle(
                  color: AppColors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  /// Logo-ul jocului, cu efect de glow — o nebuloasă difuză în spate și
  /// text cu umbră colorată, ca un "badge" jucăuș, în stilul referinței.
  Widget _buildLogo() {
    return SizedBox(
      height: 88,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 200,
            height: 82,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.purple.withAlpha(110),
                  AppColors.purple.withAlpha(0)
                ],
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bolt_rounded,
                color: AppColors.coin,
                size: 26,
                shadows: [
                  Shadow(color: AppColors.coin.withAlpha(200), blurRadius: 18)
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'GUESS IT!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  shadows: [
                    Shadow(color: Color(0xAA9A5AFB), blurRadius: 20),
                    Shadow(color: Colors.black87, blurRadius: 8),
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

class _HomeData {
  final int xp;
  final int coins;
  final int lives;
  final int streak;
  final int hints;
  final int pendingLevelRewards;
  final int gems;
  final bool livesUnlimited;
  final Duration livesUnlimitedRemaining;
  _HomeData({
    required this.xp,
    required this.coins,
    required this.lives,
    required this.streak,
    required this.hints,
    required this.pendingLevelRewards,
    required this.gems,
    required this.livesUnlimited,
    required this.livesUnlimitedRemaining,
  });
}
