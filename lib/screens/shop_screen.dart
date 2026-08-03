import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/quest_bump.dart';
import '../core/reward_collector.dart';
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
  int _hints = 0;
  bool _canClaimDaily = false;
  int _heartsBoughtToday = 0;
  int _hintPacksBoughtToday = 0;
  bool _noAdsOwned = false;
  bool _starterPackBought = false;
  bool _loading = true;
  bool _busy = false;
  int _loadSeq = 0;
  final _livesBadgeKey = GlobalKey();
  final _coinBadgeKey = GlobalKey();
  final _gemsBadgeKey = GlobalKey();
  final _hintsBadgeKey = GlobalKey();
  final GlobalKey<AppBottomNavBarState> _navBarKey = GlobalKey();

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
      StorageService.getHints(),
      StorageService.canClaimDailyReward(),
      StorageService.getHeartsBoughtToday(),
      StorageService.getHintPacksBoughtToday(),
      StorageService.getNoAdsForever(),
      StorageService.getStarterPackBought(),
    ]);
    if (!mounted) return;
    setState(() {
      _lives = results[0] as int;
      _coins = results[1] as int;
      _gems = results[2] as int;
      _hints = results[3] as int;
      _canClaimDaily = results[4] as bool;
      _heartsBoughtToday = results[5] as int;
      _hintPacksBoughtToday = results[6] as int;
      _noAdsOwned = results[7] as bool;
      _starterPackBought = results[8] as bool;
      _loading = false;
    });
  }

  /// Reîncarcă DOAR balanțele (nu întreg _loadState), folosit din
  /// onEachImpact — o achiziție cu mai multe etape (ex. bundle-ul "Fără
  /// reclame pe veci": monede+viață+hints+gems) declanșează câte o
  /// reîncărcare la fiecare impact. Fără gardă de secvență, un răspuns mai
  /// vechi care se rezolvă mai târziu (SharedPreferences are propriul
  /// program de microtask-uri) ar putea suprascrie unul mai nou, "înghețând"
  /// vizual balanța la o valoare veche — exact bug-ul semnalat.
  Future<void> _refreshBalances() async {
    final seq = ++_loadSeq;
    final results = await Future.wait([
      StorageService.getLives(),
      StorageService.getCoins(),
      StorageService.getGems(),
      StorageService.getHints(),
    ]);
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      _lives = results[0];
      _coins = results[1];
      _gems = results[2];
      _hints = results[3];
    });
  }

  Future<void> _claimDaily() async {
    final granted = await StorageService.claimDailyReward();
    if (!mounted) return;
    await bumpQuestMetric(context, 'daily_lives_claimed', 1);
    _navBarKey.currentState?.refreshDots();
    if (!mounted) return;
    Sfx.rewardPop();
    CoinRewardOverlay.show(
      context,
      amount: granted,
      targetKey: _livesBadgeKey,
      icon: Icons.favorite_rounded,
      color: AppColors.life,
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
      await bumpQuestMetric(context, 'heart_bought', 1);
      if (!mounted) return;
      await bumpQuestMetric(context, 'shop_spend', 1);
      if (!mounted) return;
      _navBarKey.currentState?.refreshDots();
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
      await bumpQuestMetric(context, 'shop_spend', 1);
      if (!mounted) return;
      _navBarKey.currentState?.refreshDots();
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
      await bumpQuestMetric(context, 'hint_pack_bought', 1);
      if (!mounted) return;
      await bumpQuestMetric(context, 'shop_spend', 1);
      if (!mounted) return;
      _navBarKey.currentState?.refreshDots();
      await _loadState();
    } else {
      _toast(_hintPacksBoughtToday >= hintPackDailyLimit
          ? 'Ai atins plafonul zilnic de pachete.'
          : 'Nu ai destule monede.');
    }
  }

  // ─── Bani reali (simulat — vezi shop.dart) ────────────────────────────────

  Future<bool> _confirmPurchase(String itemLabel, double priceRon) async {
    // Gate-ul de publicare: cât timp billing-ul real nu e integrat, nicio
    // achiziție simulată nu se poate întâmpla (vezi realMoneyStoreEnabled
    // din shop.dart — un build cu plăți simulate nu poate ajunge în Play).
    if (!realMoneyStoreEnabled) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('În curând', style: TextStyle(color: Colors.white)),
          content: Text(
            'Plățile reale nu sunt încă active în acest build.\n\n'
            '$itemLabel va costa ${formatRon(priceRon)} când magazinul se '
            'deschide. Până atunci, tot ce e în joc se poate obține jucând.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.play),
              child: const Text('Am înțeles', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return false;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Cumperi $itemLabel?', style: const TextStyle(color: Colors.white)),
        content: Text(
          'Preț: ${formatRon(priceRon)}\n\n'
          'Magazinul de plăți reale nu e conectat încă în acest build — nu se percepe nicio sumă, achiziția e doar simulată pentru testare.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Renunță')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cumpără', style: TextStyle(color: AppColors.play, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _buyGemPack(GemPack pack) async {
    if (_busy) return;
    if (!await _confirmPurchase('${pack.gems} gems', pack.priceRon)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    await collectRewards(
      context,
      coins: 0,
      xp: 0,
      lives: 0,
      gems: pack.gems,
      gemsBadgeKey: _gemsBadgeKey,
      coinBadgeKey: GlobalKey(),
      xpBadgeKey: GlobalKey(),
      livesBadgeKey: GlobalKey(),
      onEachImpact: () { _refreshBalances(); },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _loadState();
  }

  Future<void> _buyLivesPack(LivesPack pack) async {
    if (_busy) return;
    if (!await _confirmPurchase('${pack.lives} vieți', pack.priceRon)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    await collectRewards(
      context,
      coins: 0,
      xp: 0,
      lives: pack.lives,
      livesBadgeKey: _livesBadgeKey,
      coinBadgeKey: GlobalKey(),
      xpBadgeKey: GlobalKey(),
      onEachImpact: () { _refreshBalances(); },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _loadState();
  }

  Future<void> _buyUnlimitedLives24h() async {
    if (_busy) return;
    if (!await _confirmPurchase('Vieți nelimitate 24h', unlimitedLives24hPriceRon)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 900));
    await StorageService.activateUnlimitedLives(const Duration(hours: 24));
    if (!mounted) return;
    setState(() => _busy = false);
    Sfx.rewardPop();
    _toast('Vieți nelimitate activate pentru 24h!');
    await _loadState();
  }

  Future<void> _buyHintPackReal(HintPackReal pack) async {
    if (_busy) return;
    if (!await _confirmPurchase('${pack.hints} hints', pack.priceRon)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    await collectRewards(
      context,
      coins: 0,
      xp: 0,
      lives: 0,
      hints: pack.hints,
      hintsUncapped: true,
      hintsBadgeKey: _hintsBadgeKey,
      coinBadgeKey: GlobalKey(),
      xpBadgeKey: GlobalKey(),
      livesBadgeKey: GlobalKey(),
      onEachImpact: () { _refreshBalances(); },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _loadState();
  }

  Future<void> _buyBundle(Bundle b) async {
    if (_busy) return;
    if (b.oneTimeOnly && _starterPackBought) return;
    if (b.permanentNoAds && _noAdsOwned) return;
    if (!await _confirmPurchase(b.title, b.priceRon)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (b.permanentNoAds) await StorageService.setNoAdsForever();
    if (b.oneTimeOnly) await StorageService.setStarterPackBought();
    if (!mounted) return;
    await collectRewards(
      context,
      coins: b.coins,
      xp: 0,
      lives: b.hearts,
      hints: b.hints,
      hintsUncapped: true,
      hintsBadgeKey: _hintsBadgeKey,
      gems: b.gems,
      gemsBadgeKey: _gemsBadgeKey,
      coinBadgeKey: _coinBadgeKey,
      xpBadgeKey: GlobalKey(),
      livesBadgeKey: _livesBadgeKey,
      onEachImpact: () { _refreshBalances(); },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (b.oneTimeOnly) await checkAchievements(context);
    if (!mounted) return;
    await _loadState();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      bottomNavigationBar: AppBottomNavBar(key: _navBarKey, current: AppTab.shop),
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
                ],
              ),
            ),
            if (!_loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatPill(key: _livesBadgeKey, icon: Icons.favorite_rounded, iconColor: const Color(0xFFE24B4A), value: '$_lives'),
                    _StatPill(key: _coinBadgeKey, icon: Icons.monetization_on_rounded, iconColor: const Color(0xFFFFD700), value: '$_coins'),
                    _StatPill(key: _gemsBadgeKey, icon: Icons.diamond_rounded, iconColor: AppColors.gem, value: '$_gems'),
                    _StatPill(key: _hintsBadgeKey, icon: Icons.tips_and_updates_rounded, iconColor: AppColors.hint, value: '$_hints'),
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
                                priceIconColor: AppColors.gem,
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
                              // prețul crește cu fiecare pachet luat azi (la
                              // fel ca la vieți) — vezi hintPackPriceToday.
                              for (final pack in hintCoinPacks)
                                _ShopItem(
                                  title: '${pack.amount} hints',
                                  subtitle: _hintPacksBoughtToday >= hintPackDailyLimit
                                      ? 'Plafon zilnic atins ($_hintPacksBoughtToday/$hintPackDailyLimit pachete)'
                                      : 'Pachet ${_hintPacksBoughtToday + 1}/$hintPackDailyLimit de azi — prețul crește cu fiecare',
                                  priceLabel: _hintPacksBoughtToday >= hintPackDailyLimit
                                      ? '—'
                                      : '${hintPackPriceToday(pack, _hintPacksBoughtToday)}',
                                  priceIcon: Icons.monetization_on_rounded,
                                  priceIconColor: AppColors.coin,
                                  disabled: _busy ||
                                      _hintPacksBoughtToday >= hintPackDailyLimit ||
                                      _coins < hintPackPriceToday(pack, _hintPacksBoughtToday),
                                  onTap: () => _buyHintPack(pack),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Tot ce urmează se plătește cu bani reali și stă
                          // ascuns sub un strat "În curând" până la lansarea
                          // magazinului — vezi [premiumShopRevealed].
                          _PremiumVeil(
                            revealed: premiumShopRevealed,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _NoAdsHeroCard(
                                  bundle: noAdsBundle,
                                  owned: _noAdsOwned,
                                  busy: _busy,
                                  onTap: () => _buyBundle(noAdsBundle),
                                ),
                                const SizedBox(height: 14),
                                _ShopSectionCard(
                                  title: 'Pachete',
                                  subtitle: 'Mai multe resurse la un preț mai bun — bani reali',
                                  icon: Icons.card_giftcard_rounded,
                                  color: AppColors.teal,
                                  children: [
                                    for (final b in bundles)
                                      _BundleItem(
                                        bundle: b,
                                        disabled: _busy || (b.oneTimeOnly && _starterPackBought),
                                        owned: b.oneTimeOnly && _starterPackBought,
                                        onTap: () => _buyBundle(b),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                _ShopSectionCard(
                                  title: 'Gems',
                                  subtitle: 'Cumpără gems cu bani reali',
                                  icon: Icons.diamond_rounded,
                                  color: AppColors.gem,
                                  children: [
                                    for (final pack in gemPacks)
                                      _ShopItem(
                                        title: pack.bonusLabel.isEmpty ? '${pack.gems} gems' : '${pack.gems} gems  (${pack.bonusLabel})',
                                        subtitle: 'Achiziție cu bani reali',
                                        priceLabel: formatRon(pack.priceRon),
                                        disabled: _busy,
                                        onTap: () => _buyGemPack(pack),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                _ShopSectionCard(
                                  title: 'Vieți & Hints (bani reali)',
                                  subtitle: 'Cumpărare directă, fără gems',
                                  icon: Icons.shopping_bag_rounded,
                                  color: AppColors.life,
                                  children: [
                                    for (final pack in livesPacks)
                                      _ShopItem(
                                        title: '${pack.lives} vieți instant',
                                        subtitle: 'Achiziție cu bani reali',
                                        priceLabel: formatRon(pack.priceRon),
                                        disabled: _busy,
                                        onTap: () => _buyLivesPack(pack),
                                      ),
                                    _ShopItem(
                                      title: 'Vieți nelimitate 24h',
                                      subtitle: 'Joci fără să pierzi vieți timp de 24h',
                                      priceLabel: formatRon(unlimitedLives24hPriceRon),
                                      disabled: _busy,
                                      onTap: _buyUnlimitedLives24h,
                                    ),
                                    for (final pack in hintPacksReal)
                                      _ShopItem(
                                        title: '${pack.hints} hints',
                                        subtitle: 'Achiziție cu bani reali',
                                        priceLabel: formatRon(pack.priceRon),
                                        disabled: _busy,
                                        onTap: () => _buyHintPackReal(pack),
                                      ),
                                  ],
                                ),
                              ],
                            ),
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

/// Ascunde zona premium a shop-ului (bani reali) sub un blur + un strat "În
/// curând", fără să o scoată din layout — vezi [premiumShopRevealed] pentru
/// de ce. Când [revealed] e `true`, copilul se afișează absolut neatins, deci
/// reveal-ul nu cere nicio altă modificare de cod.
///
/// Blurăm CONȚINUTUL ([ImageFiltered]), nu fundalul din spate
/// ([BackdropFilter]) — altfel un scroll ar plimba blur-ul peste secțiunile
/// care trebuie să rămână citibile, iar textul de dedesubt ar rămâne lizibil
/// la margini.
class _PremiumVeil extends StatelessWidget {
  final bool revealed;
  final Widget child;

  /// Cât ocupă zona blurată pe ecran. Conținutul real e de ~4× mai înalt, dar
  /// nu are rost să fie parcurs la scroll cât timp e oricum ilizibil și
  /// inert — [OverflowBox] îl lasă să se așeze la înălțimea lui naturală, iar
  /// [ClipRRect] taie restul.
  static const double _veilHeight = 360;

  const _PremiumVeil({required this.revealed, required this.child});

  @override
  Widget build(BuildContext context) {
    if (revealed) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: _veilHeight,
        child: Stack(
          children: [
            Positioned.fill(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 0,
                maxHeight: double.infinity,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 11, sigmaY: 11, tileMode: TileMode.decal),
                  child: child,
                ),
              ),
            ),
            // IgnorePointer pe TOT (inclusiv peste conținut): niciun buton de
            // sub blur nu trebuie să mai poată fi apăsat "pe ghicite".
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: AppColors.bg.withAlpha(150),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.coin.withAlpha(38),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.coin.withAlpha(140)),
                        ),
                        child: const Icon(Icons.lock_rounded, color: AppColors.coin, size: 26),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'În curând',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Magazinul premium încă nu s-a deschis.\nTot ce e în joc se poate obține jucând.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
                      ),
                    ],
                  ),
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

/// Un pachet cu mai multe resurse deodată — rândul de chip-uri arată tot
/// conținutul dintr-o privire, spre deosebire de [_ShopItem] (o singură
/// resursă/preț).
class _BundleItem extends StatelessWidget {
  final Bundle bundle;
  final bool disabled;
  final bool owned;
  final VoidCallback? onTap;

  const _BundleItem({required this.bundle, this.disabled = false, this.owned = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(bundle.title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
                        if (bundle.oneTimeOnly) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.play.withAlpha(50), borderRadius: BorderRadius.circular(6)),
                            child: const Text('O SINGURĂ DATĂ', style: TextStyle(color: AppColors.play, fontSize: 8, fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(bundle.subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: disabled ? null : onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  disabledBackgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white38,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(owned ? 'DEȚINUT' : formatRon(bundle.priceRon), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (bundle.gems > 0) _chip(Icons.diamond_rounded, AppColors.gem, bundle.gems),
              if (bundle.coins > 0) _chip(Icons.monetization_on_rounded, AppColors.coin, bundle.coins),
              if (bundle.hearts > 0) _chip(Icons.favorite_rounded, AppColors.life, bundle.hearts),
              if (bundle.hints > 0) _chip(Icons.tips_and_updates_rounded, AppColors.hint, bundle.hints),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, Color color, int amount) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 13),
      const SizedBox(width: 3),
      Text('$amount', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    ]);
  }
}

/// Ofertă "hero" — vizual distinctă (accent auriu) de restul shop-ului,
/// fiindcă e oferta premium principală (achiziție unică, beneficiu
/// permanent).
class _NoAdsHeroCard extends StatelessWidget {
  final Bundle bundle;
  final bool owned;
  final bool busy;
  final VoidCallback? onTap;

  const _NoAdsHeroCard({required this.bundle, required this.owned, required this.busy, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.coin.withAlpha(60), AppColors.coin.withAlpha(15)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.coin.withAlpha(160), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, color: AppColors.coin, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Fără reclame pe veci',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Reclamele forțate rămân dezactivate definitiv, plus un bonus imediat',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _chip(Icons.diamond_rounded, AppColors.gem, bundle.gems),
              _chip(Icons.monetization_on_rounded, AppColors.coin, bundle.coins),
              _chip(Icons.favorite_rounded, AppColors.life, bundle.hearts),
              _chip(Icons.tips_and_updates_rounded, AppColors.hint, bundle.hints),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: owned || busy ? null : onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.coin,
                disabledBackgroundColor: Colors.white12,
                foregroundColor: Colors.black,
                disabledForegroundColor: Colors.white38,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                owned ? 'DEȚINUT' : 'Cumpără • ${formatRon(bundle.priceRon)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, Color color, int amount) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 13),
      const SizedBox(width: 3),
      Text('$amount', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    ]);
  }
}
