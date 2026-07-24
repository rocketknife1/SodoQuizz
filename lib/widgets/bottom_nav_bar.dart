import 'package:flutter/material.dart';
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
  State<AppBottomNavBar> createState() => _AppBottomNavBarState();
}

class _AppBottomNavBarState extends State<AppBottomNavBar> {
  bool _questsDot = false;
  bool _profileDot = false;

  @override
  void initState() {
    super.initState();
    _loadDots();
  }

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
            _NavItem(icon: Icons.home_rounded, label: 'Home', active: widget.current == AppTab.home, onTap: () => _go(context, AppTab.home)),
            _NavItem(icon: Icons.flag_rounded, label: 'Quests', active: widget.current == AppTab.quests, showDot: _questsDot, onTap: () => _go(context, AppTab.quests)),
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
  final VoidCallback onTap;

  const _NavItem({required this.icon, required this.label, required this.active, required this.onTap, this.showDot = false});

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
                  if (showDot) const Positioned(right: -5, top: -3, child: NotificationDot()),
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
