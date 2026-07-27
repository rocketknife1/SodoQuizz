import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/theme.dart';
import '../data/shop.dart';
import '../data/storage_service.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/coin_reward_overlay.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  int _lives = 5;
  int _coins = 0;
  int _gems = 0;
  bool _canClaimDaily = false;
  int _heartsBoughtToday = 0;
  int _hintPacksBoughtToday = 0;
  bool _loading = true;
  bool _busy = false;
  final _livesBadgeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final results = await Future.wait([
      StorageService.getLives(),
      StorageService.getCoins(),
      StorageService.getGems(),
      StorageService.canClaimDailyReward(),
      StorageService.getHeartsBoughtToday(),
      StorageService.getHintPacksBoughtToday(),
    ]);
    if (!mounted) return;
    setState(() {
      _lives = results[0] as int;
      _coins = results[1] as int;
      _gems = results[2] as int;
      _canClaimDaily = results[3] as bool;
      _heartsBoughtToday = results[4] as int;
      _hintPacksBoughtToday = results[5] as int;
      _loading = false;
    });
  }

  Future<void> _claimDaily() async {
    final granted = await StorageService.claimDailyReward();
    if (!mounted) return;
    Sfx.rewardPop();
    CoinRewardOverlay.show(
      context,
      amount: granted,
      targetKey: _livesBadgeKey,
      icon: Icons.favorite_rounded,
      color: AppColors.life,
      flightDuration: const Duration(milliseconds: 1000),
      serpentine: true,
      onImpact: Sfx.heartHit,
      onFinished: _loadState,
    );
  }

  Future<void> _buyHeart() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await StorageService.buyHeartWithCoins();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Sfx.coinHit();
      await _loadState();
    } else {
      _toast(_heartsBoughtToday >= heartCoinPrices.length
          ? 'Ai atins plafonul zilnic de achiziții.'
          : 'Nu ai destule monede.');
    }
  }

  Future<void> _buyHeartWithGems() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await StorageService.buyHeartRefillWithGems();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Sfx.heartHit();
      await _loadState();
    } else {
      _toast(_lives >= 5 ? 'Ești deja plin.' : 'Nu ai destule gems.');
    }
  }

  Future<void> _buyHintPack(HintPack pack) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await StorageService.buyHintPackWithCoins(pack);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Sfx.coinHit();
      await _loadState();
    } else {
      _toast(_hintPacksBoughtToday >= hintPackDailyLimit
          ? 'Ai atins plafonul zilnic de pachete.'
          : 'Nu ai destule monede.');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
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
                    _StatPill(key: _livesBadgeKey, icon: Icons.favorite_rounded, iconColor: const Color(0xFFE24B4A), value: '$_lives'),
                    const SizedBox(width: 8),
                    _StatPill(icon: Icons.monetization_on_rounded, iconColor: const Color(0xFFFFD700), value: '$_coins'),
                    const SizedBox(width: 8),
                    _StatPill(icon: Icons.diamond_rounded, iconColor: const Color(0xFF5EC8F2), value: '$_gems'),
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
                            subtitle: 'Joacă fără să te oprești',
                            icon: Icons.favorite_rounded,
                            color: AppColors.purple,
                            children: [
                              _ShopItem(
                                title: 'Recompensă zilnică',
                                subtitle: '+$freeDailyLivesTarget vieți',
                                priceLabel: _canClaimDaily ? 'GRATUIT' : 'Revino mâine',
                                free: true,
                                disabled: !_canClaimDaily,
                                owned: !_canClaimDaily,
                                onTap: _canClaimDaily ? _claimDaily : null,
                              ),
                              _ShopItem(
                                title: '+1 viață',
                                subtitle: _heartsBoughtToday >= heartCoinPrices.length
                                    ? 'Plafon zilnic atins ($_heartsBoughtToday/${heartCoinPrices.length})'
                                    : 'Achiziția ${_heartsBoughtToday + 1}/${heartCoinPrices.length} de azi — prețul crește cu fiecare',
                                priceLabel: _heartsBoughtToday >= heartCoinPrices.length
                                    ? '—'
                                    : '${heartCoinPrices[_heartsBoughtToday]}',
                                priceIcon: Icons.monetization_on_rounded,
                                priceIconColor: AppColors.coin,
                                disabled: _busy ||
                                    _heartsBoughtToday >= heartCoinPrices.length ||
                                    _coins < heartCoinPrices[_heartsBoughtToday.clamp(0, heartCoinPrices.length - 1)],
                                onTap: _buyHeart,
                              ),
                              _ShopItem(
                                title: 'Completare instantă',
                                subtitle: 'Umple viețile la $freeDailyLivesTarget, indiferent de plafon',
                                priceLabel: '$heartRefillGemsPrice',
                                priceIcon: Icons.diamond_rounded,
                                priceIconColor: const Color(0xFF5EC8F2),
                                disabled: _busy || _lives >= 5 || _gems < heartRefillGemsPrice,
                                onTap: _buyHeartWithGems,
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
                              for (final pack in hintCoinPacks)
                                _ShopItem(
                                  title: '${pack.amount} hints',
                                  subtitle: _hintPacksBoughtToday >= hintPackDailyLimit
                                      ? 'Plafon zilnic atins ($_hintPacksBoughtToday/$hintPackDailyLimit pachete)'
                                      : 'Pachet ${_hintPacksBoughtToday + 1}/$hintPackDailyLimit de azi',
                                  priceLabel: _hintPacksBoughtToday >= hintPackDailyLimit
                                      ? '—'
                                      : '${pack.priceCoins}',
                                  priceIcon: Icons.monetization_on_rounded,
                                  priceIconColor: AppColors.coin,
                                  disabled: _busy ||
                                      _hintPacksBoughtToday >= hintPackDailyLimit ||
                                      _coins < pack.priceCoins,
                                  onTap: () => _buyHintPack(pack),
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

  const _StatPill({super.key, required this.icon, required this.iconColor, required this.value});

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
  // Aceeași iconiță (Icon widget) ca în pastilele din LevelHeader/Shop —
  // NU un emoji în text, ca să arate identic peste tot în aplicație.
  final IconData? priceIcon;
  final Color? priceIconColor;
  final bool free;
  final bool owned;
  final bool disabled;
  final VoidCallback? onTap;

  const _ShopItem({
    required this.title,
    required this.subtitle,
    required this.priceLabel,
    this.priceIcon,
    this.priceIconColor,
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
            child: priceIcon == null
                ? Text(priceLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(priceLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      Icon(priceIcon, color: priceIconColor, size: 14),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
