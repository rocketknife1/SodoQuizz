import 'package:flutter/material.dart';
import '../core/sfx.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/culture_quiz_panel.dart';
import '../widgets/discord_mascot.dart';
import '../widgets/level_header.dart';
import '../widgets/paperclip_mascot.dart';
import '../widgets/ring_mascot.dart';
import '../widgets/solid_menu_button.dart';
import '../widgets/spinning_planet.dart';
import '../widgets/space_background.dart';
import 'categories_screen.dart';
import 'leaderboard_screen.dart';
import 'multiplayer_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';
import 'test_images_screen.dart';

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
  final GlobalKey<AppBottomNavBarState> _navBarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
    _checkStreakMilestones();
  }

  Future<_HomeData> _loadData() async {
    final results = await Future.wait([
      StorageService.getXp(),
      StorageService.getCoins(),
      StorageService.getLives(),
      StorageService.getStreak(),
      StorageService.getHints(),
    ]);
    return _HomeData(
      xp: results[0],
      coins: results[1],
      lives: results[2],
      streak: results[3],
      hints: results[4],
    );
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
    setState(() {
      _dataFuture = _loadData();
    });
    // bulina/cufărul de pe tab-ul Quests trebuie să reflecte pe loc orice
    // quest terminat în timpul unei sesiuni de joc, nu doar la reintrarea
    // manuală pe pagina Quests.
    _navBarKey.currentState?.refreshDots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            ],
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(key: _navBarKey, current: AppTab.home),
    );
  }

  Widget _buildContent(BuildContext context, _HomeData? data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
      child: Column(
        children: [
          LevelHeader(
            xp: data?.xp ?? 0,
            coins: data?.coins ?? 0,
            lives: data?.lives ?? 5,
            hints: data?.hints ?? 3,
            coinBadgeKey: _coinBadgeKey,
            xpBadgeKey: _xpBadgeKey,
            livesBadgeKey: _livesBadgeKey,
            hintsBadgeKey: _hintsBadgeKey,
            onCoinsTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ShopScreen()));
              _refresh();
            },
          ),
          if ((data?.streak ?? 0) > 0) ...[
            const SizedBox(height: 6),
            _buildStreakChip(data!.streak),
          ],
          const SizedBox(height: 8),
          _buildLogo(),
          const SizedBox(height: 10),
          _buildDevToolsRow(context),
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

  Future<void> _grantUnlimited(BuildContext context) async {
    await StorageService.setLives(999);
    final currentHints = await StorageService.getHints();
    if (currentHints < 999) await StorageService.addHints(999 - currentHints);
    if (!context.mounted) return;
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('999 vieți + 999 hint-uri (test)'), duration: Duration(milliseconds: 1200)),
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

  /// Rând dedicat, temporar, cu 2 butoane de test — la fel de vizibile ca
  /// butoanele de meniu (culoare solidă + iconiță), nu mai sunt înghesuite
  /// langa logo unde abia se vedeau.
  /// TEST: verifica doar pozele inlocuite manual (vezi
  /// TestImagesScreen.testQuestionIds), fara sa afecteze scorul real.
  /// UNLIMITED: umple vieti + hint-uri la 999, pentru testare rapida.
  Widget _buildDevToolsRow(BuildContext context) {
    return Row(
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
    );
  }

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
}

class _HomeData {
  final int xp;
  final int coins;
  final int lives;
  final int streak;
  final int hints;
  _HomeData({
    required this.xp,
    required this.coins,
    required this.lives,
    required this.streak,
    required this.hints,
  });
}
