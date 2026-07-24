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
    ]);
    return _HomeData(
      xp: results[0],
      coins: results[1],
      lives: results[2],
      streak: results[3],
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

  void _refresh() => setState(() {
        _dataFuture = _loadData();
      });

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
              // planetă centrală mare, în spațiul gol de sub butoane (nu se
              // suprapune cu ele), cu holograme ale categoriilor levitând
              // în jur — centrată pe toată lățimea ecranului.
              const Positioned(top: 460, right: 8, child: SpinningPlanet(size: 76)),
              Positioned(bottom: 16, right: 0, child: PaperclipMascot(onRewardsChanged: _refresh)),
              const Positioned(bottom: 24, left: 104, child: DiscordMascot()),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNavBar(current: AppTab.home),
    );
  }

  Widget _buildContent(BuildContext context, _HomeData? data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        children: [
          LevelHeader(
            xp: data?.xp ?? 0,
            coins: data?.coins ?? 0,
            lives: data?.lives ?? 5,
            coinBadgeKey: _coinBadgeKey,
            xpBadgeKey: _xpBadgeKey,
            livesBadgeKey: _livesBadgeKey,
            onCoinsTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ShopScreen()));
              _refresh();
            },
          ),
          if ((data?.streak ?? 0) > 0) ...[
            const SizedBox(height: 8),
            _buildStreakChip(data!.streak),
          ],
          const SizedBox(height: 18),
          _buildLogo(),
          const SizedBox(height: 22),
          // butoanele meniului (stânga, mai înguste) + panoul
          // interactiv de Cultură Generală (dreapta) — înălțimile
          // se egalizează automat prin IntrinsicHeight+stretch.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SolidMenuButton(
                        icon: Icons.play_arrow_rounded,
                        label: 'PLAY',
                        color: AppColors.play,
                        big: true,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const CategoriesScreen())),
                      ),
                      SolidMenuButton(
                        icon: Icons.emoji_events_rounded,
                        label: 'CLASAMENT',
                        color: AppColors.orange,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LeaderboardScreen())),
                      ),
                      SolidMenuButton(
                        icon: Icons.groups_rounded,
                        label: 'MULTIPLAYER',
                        color: AppColors.teal,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const MultiplayerScreen())),
                      ),
                      SolidMenuButton(
                        icon: Icons.settings_rounded,
                        label: 'SETĂRI',
                        color: AppColors.gray,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SettingsScreen())),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: CultureQuizPanel(
                    onRewardsChanged: _refresh,
                    coinBadgeKey: _coinBadgeKey,
                    xpBadgeKey: _xpBadgeKey,
                    livesBadgeKey: _livesBadgeKey,
                  ),
                ),
              ],
            ),
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
      height: 108,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 230,
            height: 100,
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
                size: 32,
                shadows: [
                  Shadow(color: AppColors.coin.withAlpha(200), blurRadius: 20)
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'GUESS IT!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  shadows: [
                    Shadow(color: Color(0xAA9A5AFB), blurRadius: 24),
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
  _HomeData({
    required this.xp,
    required this.coins,
    required this.lives,
    required this.streak,
  });
}
