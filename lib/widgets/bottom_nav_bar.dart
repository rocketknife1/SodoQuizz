import 'package:flutter/material.dart';
import '../core/eco_mode.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';
import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/quests_screen.dart';
import '../screens/shop_screen.dart';

enum AppTab { home, quests, shop, profile }

/// Bară de navigare persistentă (Home / Quests / Shop / Profile), la fel
/// ca în orice joc mobil casual. Fiecare tab navighează prin
/// pushReplacement, ca să nu se adune ecrane una peste alta în istoric.
///
/// Pe Quests / Profile apare un punct roșu de notificare când există ceva
/// de revendicat (quest atins / realizare atinsă), verificat la construire.
class AppBottomNavBar extends StatefulWidget {
  final AppTab current;
  const AppBottomNavBar({super.key, required this.current});

  @override
  State<AppBottomNavBar> createState() => AppBottomNavBarState();
}

class AppBottomNavBarState extends State<AppBottomNavBar> {
  bool _questsDot = false;
  bool _profileDot = false;

  @override
  void initState() {
    super.initState();
    _loadDots();
  }

  /// Reîncarcă cele două puncte roșii pe loc — apelat de ecranele care
  /// revendică un quest/o realizare, ca bulina să dispară imediat, fără
  /// să fie nevoie să ieși și să reintri în tab (vezi [QuestsScreen],
  /// [ProfileScreen]). Necesită o [GlobalKey] către acest state.
  Future<void> refreshDots() => _loadDots();

  Future<void> _loadDots() async {
    final results = await Future.wait([
      StorageService.hasClaimableQuests(),
      StorageService.hasClaimableAchievements(),
    ]);
    if (!mounted) return;
    setState(() {
      _questsDot = results[0];
      _profileDot = results[1];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: const Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Etichetele erau deja in engleza si raman asa in ambele limbi —
            // sunt cuvinte intrate in vocabularul oricarui jucator de mobil,
            // iar "Pravalie" ar fi fost mai greu de recunoscut decat "Shop".
            _NavItem(icon: Icons.home_rounded, label: 'Home', active: widget.current == AppTab.home, onTap: () => _go(context, AppTab.home)),
            _NavItem(icon: Icons.flag_rounded, label: 'Quests', active: widget.current == AppTab.quests, showDot: _questsDot, useChest: true, onTap: () => _go(context, AppTab.quests)),
            _NavItem(icon: Icons.storefront_rounded, label: 'Shop', active: widget.current == AppTab.shop, onTap: () => _go(context, AppTab.shop)),
            _NavItem(icon: Icons.person_rounded, label: 'Profile', active: widget.current == AppTab.profile, showDot: _profileDot, onTap: () => _go(context, AppTab.profile)),
          ],
        ),
      ),
    );
  }

  void _go(BuildContext context, AppTab tab) {
    if (tab == widget.current) return;
    final builder = switch (tab) {
      AppTab.home => (BuildContext _) => const HomeScreen(),
      AppTab.quests => (BuildContext _) => const QuestsScreen(),
      AppTab.shop => (BuildContext _) => const ShopScreen(),
      AppTab.profile => (BuildContext _) => const ProfileScreen(),
    };
    Navigator.pushReplacement(context, MaterialPageRoute(builder: builder));
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool showDot;
  final bool useChest;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.showDot = false,
    this.useChest = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.play : Colors.white38;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: color, size: 22),
                  if (showDot)
                    Positioned(
                      right: -10,
                      top: -8,
                      child: useChest ? const ChestBadge() : const NotificationDot(),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cufăr mic care "pulsează" auriu — apare pe tab-ul Quests în locul
/// punctului roșu simplu de notificare, când ai cel puțin un quest gata de
/// revendicat. Bulina roșie clasică rămâne pe Profil/Realizări.
class ChestBadge extends StatefulWidget {
  const ChestBadge({super.key});

  @override
  State<ChestBadge> createState() => _ChestBadgeState();
}

class _ChestBadgeState extends State<ChestBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = EcoAnimationController(vsync: this, duration: const Duration(milliseconds: 1100), restValue: 0.5)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = 0.5 + _pulse.value * 0.5;
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFF3A2E0F),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.card, width: 2),
            boxShadow: [
              BoxShadow(color: AppColors.coin.withAlpha((120 * glow).round()), blurRadius: 8 + 4 * glow, spreadRadius: 1 * glow),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(Icons.card_giftcard_rounded, color: Color.lerp(AppColors.coin, Colors.white, _pulse.value * 0.4), size: 12),
        );
      },
    );
  }
}

/// Punct roșu mic de notificare, cu contur pe culoarea fundalului, ca să se
/// desprindă bine de orice iconiță peste care e suprapus.
class NotificationDot extends StatelessWidget {
  final double size;
  final Color borderColor;
  const NotificationDot({super.key, this.size = 10, this.borderColor = AppColors.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFE24B4A),
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
      ),
    );
  }
}
