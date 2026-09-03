import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/lang.dart';
import '../core/quest_bump.dart';
import '../core/reward_collector.dart';
import '../core/theme.dart';
import '../data/auth_service.dart';
import '../data/player_profile_service.dart';
import '../data/storage_service.dart';
import '../widgets/beta_info_balloon.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/culture_quiz_panel.dart';
import '../widgets/edit_name_dialog.dart';
import '../widgets/level_header.dart';
import '../widgets/lives_countdown_card.dart';
import '../widgets/mascots/discord_mascot.dart';
import '../widgets/mascots/paperclip_mascot.dart';
import '../widgets/mascots/ring_mascot.dart';
import '../widgets/notification_bell.dart';
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
    StorageService.balanceRevision.addListener(_refresh);
    // Redenumirea din panoul de Admin ajunge live (vezi
    // PlayerProfileService.startLive) — reîmprospătăm ca numele nou să apară pe loc.
    PlayerProfileService.instance.profileChanged.addListener(_refresh);
  }

  @override
  void dispose() {
    StorageService.balanceRevision.removeListener(_refresh);
    PlayerProfileService.instance.profileChanged.removeListener(_refresh);
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
    final identity = await AuthService.instance.multiplayerIdentity();
    final forcedName = await StorageService.getForcedName();
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
      name: identity.name,
      nameSetByAdmin: forcedName.isNotEmpty,
    );
  }

  Future<void> _editName(_HomeData data) async {
    final result = await editDisplayName(context, currentName: data.name, nameSetByAdmin: data.nameSetByAdmin);
    if (result == null || !mounted) return;
    _refresh();
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
          content: Text(tr(
              '🔥 $best zile la rând! Bonus: +${best * 5} monede, +${best * 10} XP',
              '🔥 $best days in a row! Bonus: +${best * 5} coins, +${best * 10} XP'))),
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
                // Clippy e MICŞORAT şi coborât faţă de ceilalţi: cutia lui
                // (116px corp + etichetă = ~153px) urca peste colţul de jos al
                // panoului de Cultură Generală şi acoperea variantele de
                // răspuns — aceeaşi problemă pentru care balonul de BETA a fost
                // mutat deja în banda de jos. Scalarea se face AICI, nu în
                // widget: toate poziţiile dinăuntru (ochi, bulina, propuri)
                // sunt calculate faţă de cutia de 116, iar micşorarea ei le-ar
                // fi rupt una câte una.
                Positioned(
                  bottom: 6,
                  right: -6,
                  child: Transform.scale(
                    scale: 0.8,
                    alignment: Alignment.bottomRight,
                    child: PaperclipMascot(onRewardsChanged: _refresh),
                  ),
                ),
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
    // Pe 0 vieți apare cardul cu numărătoarea inversă (LivesCountdownCard) și
    // împinge tot ce e sub el în jos — inclusiv panoul de Cultură Generală,
    // care ajungea astfel exact peste Clippy și balonul de BETA (ambele
    // plutesc fix, în Stack-ul de deasupra). Soluția rămâne aceeași: ascundem
    // titlul (pur decorativ) cât timp cardul e pe ecran. Clopoțelul NU se
    // ascunde odată cu el — e un control, nu decor.
    final outOfLives = data != null && data.lives == 0;
    return SingleChildScrollView(
      // NU mări padding-ul de jos ca să „faci loc" mascotelor: meniul principal
      // NU are voie să deruleze, niciodată (regulă explicită a userului,
      // 2026-09-03). O încercare cu 130 aici a făcut exact asta. Tot ce se
      // adaugă pe Home trebuie să încapă pe ecran, nu să împingă în scroll.
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        children: [
          _buildTopBar(outOfLives),
          const SizedBox(height: 2),
          LevelHeader(
            xp: data?.xp ?? 0,
            coins: data?.coins ?? 0,
            lives: data?.lives ?? 5,
            hints: data?.hints ?? 3,
            gems: data?.gems ?? 0,
            pendingLevelRewards: data?.pendingLevelRewards ?? 0,
            livesUnlimited: data?.livesUnlimited ?? false,
            livesUnlimitedLabel: (data?.livesUnlimited ?? false) ? _formatCountdown(data!.livesUnlimitedRemaining) : null,
            // clopoțelul NU mai stă în rândul de resurse — s-a mutat în bara
            // de sus, lângă titlu (vezi [_buildTopBar]).
            coinBadgeKey: _coinBadgeKey,
            xpBadgeKey: _xpBadgeKey,
            livesBadgeKey: _livesBadgeKey,
            hintsBadgeKey: _hintsBadgeKey,
            gemsBadgeKey: _gemsBadgeKey,
            displayName: data?.name,
            onNameTap: data == null ? null : () => _editName(data),
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
                      label: tr('CLASAMENT', 'LEADERBOARD'),
                      subtitle: '',
                      angular: true,
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
                      subtitle: '',
                      angular: true,
                      color: AppColors.teal,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const MultiplayerScreen())),
                    ),
                    const SizedBox(height: 8),
                    SolidMenuButton(
                      icon: Icons.settings_rounded,
                      label: tr('SETĂRI', 'SETTINGS'),
                      subtitle: '',
                      angular: true,
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
                        child: SpinningPlanet(size: 76, onRewardsChanged: _refresh),
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
              tr('$streak ${streak == 1 ? "zi" : "zile"} la rând',
                  '$streak ${streak == 1 ? "day" : "days"} in a row'),
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

  /// Bara de sus: titlul centrat şi clopoţelul de notificări la dreapta, în
  /// spaţiul care era oricum gol de o parte şi de alta a titlului.
  ///
  /// Pe 0 vieţi titlul dispare (ca înainte, ca să facă loc cardului de
  /// reîncărcare), dar bara rămâne — clopoţelul e un control, nu decor, şi
  /// n-are voie să dispară exact când jucătorul stă şi aşteaptă.
  Widget _buildTopBar(bool outOfLives) {
    return SizedBox(
      height: outOfLives ? 38 : 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!outOfLives) _buildLogo(),
          Align(
            alignment: Alignment.centerRight,
            child: NotificationBell(onClosed: _refresh),
          ),
        ],
      ),
    );
  }

  /// Logo-ul jocului, cu efect de glow — o nebuloasă difuză în spate și
  /// text cu umbră colorată, ca un "badge" jucăuș, în stilul referinței.
  Widget _buildLogo() {
    return SizedBox(
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 210,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.purple.withAlpha(95),
                  AppColors.purple.withAlpha(0)
                ],
              ),
            ),
          ),
          // Fulgerul stă ACUM pe acelaşi rând cu titlul, nu pe un rând propriu
          // deasupra lui: aşezarea veche (icon + text în coloană, într-o cutie
          // de 88px) mânca ~46px de înălţime pur decorativă în capul unui ecran
          // deja aglomerat. Inline, blocul întreg intră în 42px.
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.bolt_rounded,
                color: AppColors.coin,
                size: 21,
                shadows: [
                  Shadow(color: AppColors.coin.withAlpha(200), blurRadius: 14)
                ],
              ),
              const SizedBox(width: 3),
              const Text(
                'SODO QUIZZ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                  shadows: [
                    Shadow(color: Color(0xAA9A5AFB), blurRadius: 18),
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
  final String name;

  /// `true` dacă numele curent a fost impus din Admin — dialogul îl ridică
  /// înainte de salvare ca primul heartbeat să nu-l pună la loc.
  final bool nameSetByAdmin;
  _HomeData({
    required this.xp,
    required this.coins,
    required this.lives,
    required this.streak,
    required this.hints,
    required this.pendingLevelRewards,
    required this.gems,
    required this.livesUnlimited,
    required this.name,
    required this.nameSetByAdmin,
    required this.livesUnlimitedRemaining,
  });
}
