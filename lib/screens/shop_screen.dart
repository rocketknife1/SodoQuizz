import 'package:flutter/material.dart';
import '../core/sfx.dart';
import '../core/theme.dart';
import '../data/shop.dart';
import '../data/storage_service.dart';
import '../widgets/bottom_nav_bar.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  int _lives = 5;
  int _coins = 0;
  bool _canClaimDaily = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final results = await Future.wait([
      StorageService.getLives(),
      StorageService.getCoins(),
      StorageService.canClaimDailyReward(),
    ]);
    if (!mounted) return;
    setState(() {
      _lives = results[0] as int;
      _coins = results[1] as int;
      _canClaimDaily = results[2] as bool;
      _loading = false;
    });
  }

  Future<void> _claimDaily() async {
    Sfx.rewardPop();
    await StorageService.claimDailyReward();
    // aceeași pereche de sunete ca la revendicarea unui quest — pop la
    // colectare, apoi ding-ul de impact puțin mai târziu.
    Future.delayed(const Duration(milliseconds: 950), Sfx.coinHit);
    await _loadState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ai primit 5 vieți!')),
    );
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Plățile în magazin vor fi disponibile într-o versiune viitoare.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vieti = shopData['vieti'] as Map<String, dynamic>;
    final vietiPachete = vieti['pachete'] as List<dynamic>;
    final hints = shopData['hints_cumparate'] as Map<String, dynamic>;

    return Scaffold(
      backgroundColor: AppColors.bg,
      bottomNavigationBar: const AppBottomNavBar(current: AppTab.shop),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                  ),
                  const SizedBox(width: 4),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MAGAZIN', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                      SizedBox(height: 2),
                      Text('Shop', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Spacer(),
                  if (!_loading) ...[
                    _StatPill(icon: Icons.favorite_rounded, iconColor: const Color(0xFFE24B4A), value: '$_lives'),
                    const SizedBox(width: 8),
                    _StatPill(icon: Icons.monetization_on_rounded, iconColor: const Color(0xFFFFD700), value: '$_coins'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF9A5AFB)))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ShopSectionCard(
                            title: 'Vieți',
                            subtitle: 'Joacă fără limite',
                            icon: Icons.favorite_rounded,
                            color: AppColors.purple,
                            children: [
                              _ShopItem(
                                title: 'Recompensă zilnică',
                                subtitle: '+${vieti['gratuit_zilnic']} vieți',
                                priceLabel: _canClaimDaily ? 'GRATUIT' : 'Revino mâine',
                                free: true,
                                disabled: !_canClaimDaily,
                                owned: !_canClaimDaily,
                                onTap: _canClaimDaily ? _claimDaily : null,
                              ),
                              for (final p in vietiPachete)
                                _ShopItem(
                                  title: p['nume'] as String,
                                  subtitle: 'Joacă non-stop, fără să pierzi vieți',
                                  priceLabel: '${p['pret_ron']} RON',
                                  onTap: _comingSoon,
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _ShopSectionCard(
                            title: 'Hints',
                            subtitle: 'Primește ajutor când ai nevoie',
                            icon: Icons.lightbulb_rounded,
                            color: const Color(0xFFFFD54F),
                            children: [
                              for (final entry in hints.entries)
                                _ShopItem(
                                  title: entry.value['nume'] as String,
                                  subtitle: '${entry.value['cantitate']} hints',
                                  priceLabel: '${entry.value['pret_ron']} RON',
                                  onTap: _comingSoon,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;

  const _StatPill({required this.icon, required this.iconColor, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ShopSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  const _ShopSectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0f3460),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withAlpha(38),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _ShopItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final String priceLabel;
  final bool free;
  final bool owned;
  final bool disabled;
  final VoidCallback? onTap;

  const _ShopItem({
    required this.title,
    required this.subtitle,
    required this.priceLabel,
    this.free = false,
    this.owned = false,
    this.disabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final buttonColor = owned
        ? Colors.white24
        : free
            ? AppColors.success
            : AppColors.teal;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: disabled ? null : onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonColor,
              disabledBackgroundColor: Colors.white12,
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(
              priceLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
