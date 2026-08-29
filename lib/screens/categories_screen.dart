import 'dart:math';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/gamemodes.dart';
import '../core/lang.dart';
import '../core/progression.dart';
import '../core/quest_bump.dart';
import '../core/theme.dart';
import '../data/higher_lower_data.dart';
import '../data/questions.dart';
import '../data/shop.dart';
import '../data/storage_service.dart';
import '../widgets/category_card.dart';
import '../widgets/category_unlock_animation.dart';
import '../widgets/entrance_item.dart';
import '../widgets/pressable.dart';
import '../widgets/space_background.dart';
import 'higher_lower_screen.dart';
import 'loading_screen.dart';

class _ModeStats {
  final int total;
  final int answered;
  final int unlocked;
  final int tier;
  const _ModeStats(
      {required this.total,
      required this.answered,
      required this.unlocked,
      required this.tier});
  double get pct => total > 0 ? answered / total : 0.0;
}

/// Starea butonului din [_CategoriesScreenState._buildFeaturedCategoryBanner]
/// — a jucat-o azi categoria evidențiată? A revendicat deja bonusul?
class _FeaturedClaimState {
  final bool played;
  final bool claimed;
  const _FeaturedClaimState({required this.played, required this.claimed});
}

/// Ecranul care apare când apeși PLAY: alegi unul dintre cele 4
/// gamemoduri. Cardurile sunt generate din [gameModes] — nu e nimic
/// hardcodat aici, un gamemod nou apare automat.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> with TickerProviderStateMixin {
  late Future<Map<String, _ModeStats>> _statsFuture;

  /// Categoria evidențiată azi (conținut rotativ, PLAN_DE_VIITOR.md punctul
  /// 5) — calculată o singură dată la montare, nu la fiecare build: nu se
  /// schimbă cât timp stai pe ecran, iar `DateTime.now()` direct în build ar
  /// fi doar zgomot.
  final GameMode _featured = featuredGameModeToday();
  late Future<_FeaturedClaimState> _featuredFuture;

  /// Intrarea în cascadă a listei de categorii — aceeași senzație ca în
  /// Multiplayer (vezi widgets/entrance_item.dart), ca ecranul să nu apară
  /// dintr-o bucată, static.
  late final AnimationController _introCtrl;

  /// Bucla continuă a planetelor — inelul lui Saturn se rotește încet, iar
  /// glow-ul din jurul globului respiră. O singură buclă, împărțită de
  /// TOATE cardurile (nu un controller per card), ca ecranul să nu pară o
  /// listă statică odată ce intrarea în cascadă s-a terminat.
  late final AnimationController _liveCtrl;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
    _featuredFuture = _loadFeaturedClaimState();
    _introCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
    _liveCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  }

  @override
  void dispose() {
    _introCtrl.dispose();
    _liveCtrl.dispose();
    super.dispose();
  }

  /// Fereastra de timp în care intră cardul de pe poziția [i] — fiecare
  /// pornește puțin după cel de deasupra, dar toate se termină în prima
  /// secundă, ca lista să nu pară că se încarcă greu.
  Interval _stagger(int i) {
    final start = (0.06 * i).clamp(0.0, 0.55);
    return Interval(start, (start + 0.45).clamp(0.0, 1.0), curve: Curves.easeOutCubic);
  }

  Future<Map<String, _ModeStats>> _loadStats() async {
    final results = await Future.wait(
        [loadAllQuestions(), StorageService.getAnsweredIds()]);
    final all = results[0] as List;
    final answeredIds = results[1] as Set<String>;
    final entries =
        await Future.wait(gameModes.where((m) => !m.locked).map((m) async {
      final total = all.where((q) => q.categoryId == m.id).length;
      final answered = all
          .where((q) => q.categoryId == m.id && answeredIds.contains(q.id))
          .length;
      final tier = await StorageService.getUnlockedTier(m.id);
      final unlocked =
          await StorageService.getUnlockedQuestionCount(m.id, total);
      return MapEntry(
          m.id,
          _ModeStats(
              total: total,
              answered: answered,
              unlocked: unlocked,
              tier: tier));
    }));
    return Map.fromEntries(entries);
  }

  /// Cumpără următoarea treaptă de upgrade pentru [mode] — deblochează chiar
  /// categoria dacă era la tier 0. La succes arată animația de deblocare și
  /// reîncarcă statisticile, ca noul tier să se reflecte imediat în card.
  Future<void> _upgrade(GameMode mode, _ModeStats stats) async {
    final ok = await StorageService.unlockNextQuestionBatch(mode.id);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr('Nu ai destule gems.', 'Not enough gems.')),
            duration: const Duration(milliseconds: 1400)),
      );
      return;
    }
    await bumpQuestMetric(context, 'question_batch_unlocked', 1);
    if (!mounted) return;
    await bumpQuestMetric(context, 'shop_spend', 1);
    if (!mounted) return;
    final newUnlocked =
        await StorageService.getUnlockedQuestionCount(mode.id, stats.total);
    if (!mounted) return;
    await CategoryUnlockAnimation.show(
      context,
      categoryTitle: mode.title,
      unlockedCount: newUnlocked - stats.unlocked,
      // planeta care se trezește trebuie să fie CHIAR planeta categoriei —
      // aceeași culoare, aceeași iconiță, același seed ca pe card.
      color: mode.accentColor,
      icon: mode.icon,
      seed: gameModes.indexOf(mode) + 1,
    );
    if (!mounted) return;
    setState(() => _statsFuture = _loadStats());
  }

  /// Taxă de intrare + confirmare — vezi progression.dart pentru formula
  /// recompensei la ieșire. Dacă nu ai destule monede, butonul de confirmare
  /// e dezactivat direct în dialog (nu doar un mesaj după ce apeși).
  Future<void> _enterCategory(GameMode mode) async {
    final coins = await StorageService.getCoins();
    if (!mounted) return;
    // Taxa nu mai e fixă: e un procent din averea curentă, cu plafoane (vezi
    // categoryEntryFee) — principalul sink care crește odată cu venitul.
    final fee = categoryEntryFee(coins);
    final canAfford = coins >= fee;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF141B36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: Colors.white.withAlpha(30)),
        ),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [mode.accentColor, mode.accentColor.withAlpha(120)],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withAlpha(70)),
              ),
              alignment: Alignment.center,
              child: Icon(mode.icon, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tr('Intri în ${mode.title}?', 'Enter ${mode.title}?'),
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        content: Text(
          tr(
            'Taxă de intrare: $fee monede '
                '(${(categoryEntryFeeRatio * 100).toStringAsFixed(1).replaceAll('.', ',')}% '
                'din câte ai, între $categoryEntryFeeMin și $categoryEntryFeeMax).\n\n'
                'Recompensa la ieșire depinde STRICT de câte răspunzi corect:\n'
                '• sub 4 corecte — nimic înapoi\n'
                '• 4-7 corecte — 60% din taxă\n'
                '• 8-14 corecte — taxa întreagă\n'
                '• 15+ corecte — taxa +30%'
                '${canAfford ? '' : '\n\nNu ai destule monede (ai $coins).'}',
            'Entry fee: $fee coins '
                '(${(categoryEntryFeeRatio * 100).toStringAsFixed(1)}% '
                'of what you have, between $categoryEntryFeeMin and $categoryEntryFeeMax).\n\n'
                'Your payout depends STRICTLY on how many you answer correctly:\n'
                '• under 4 correct — nothing back\n'
                '• 4-7 correct — 60% of the fee\n'
                '• 8-14 correct — the whole fee\n'
                '• 15+ correct — the fee +30%'
                '${canAfford ? '' : '\n\nNot enough coins (you have $coins).'}',
          ),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr('Renunță', 'Cancel'))),
          ElevatedButton(
            onPressed:
                canAfford ? () => Navigator.pop(dialogContext, true) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.play,
              disabledBackgroundColor: Colors.white24,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('${tr('Intră', 'Enter')}  •  💰$fee',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final spent = await StorageService.spendCoins(fee);
    if (!mounted || !spent) return;
    Sfx.tileSelect();
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              LoadingScreen(gameModeId: mode.id, entryFeePaid: fee)),
    );
  }

  /// Card special pentru "Higher or Lower" — vizual diferit de
  /// [CategoryCard] (fără planetă/inel de progres, care n-au sens pentru un
  /// mod arcade de streak), dar cu aceleași proporții/rotunjimi, ca lista
  /// să rămână coerentă. Recordul se citește direct din storage (aceeași
  /// infrastructură de high-score per mod ca la celelalte gamemoduri).
  Widget _buildHigherLowerCard() {
    return FutureBuilder<int>(
      future: StorageService.getModeHighScore(higherLowerModeId),
      builder: (context, snapshot) {
        final best = snapshot.data ?? 0;
        return Pressable(
          onTap: () {
            Sfx.tileSelect();
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HigherLowerScreen()));
          },
          child: AnimatedBuilder(
            animation: _liveCtrl,
            builder: (context, child) {
              final breathe = (sin(_liveCtrl.value * 2 * pi) + 1) / 2;
              return Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.purple.withAlpha(150), width: 1.4),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.purple.withAlpha((50 + breathe * 45).round()),
                        blurRadius: 14 + breathe * 8,
                        spreadRadius: -3)
                  ],
                ),
                child: child,
              );
            },
            child: Row(
              children: [
                SizedBox(
                  width: 58,
                  height: 58,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                            color: Colors.black.withAlpha(70),
                            shape: BoxShape.circle),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_upward_rounded,
                              color: AppColors.play, size: 20),
                          Icon(Icons.arrow_downward_rounded,
                              color: AppColors.danger, size: 20),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                                color: AppColors.purple,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(tr('NOU', 'NEW'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5)),
                          ),
                          const SizedBox(width: 7),
                          const Expanded(
                            child: Text(
                              'Higher or Lower',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        tr('Ce se caută mai mult? Ai 10 secunde să ghicești.',
                            'Which one is searched more? You have 10 seconds to guess.'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.emoji_events_rounded,
                        color: AppColors.coin, size: 20),
                    const SizedBox(height: 2),
                    Text('$best',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Îndrumar pentru jucătorul nou: la instalare primește [starterGemGrant]
  /// gems "din partea casei", exact cât să-și deblocheze SINGUR o categorie
  /// pe care și-o dorește (cele 3 de start sunt alese random). Dispare de
  /// îndată ce gems-ul scade sub prețul primei trepte — deci imediat după ce
  /// și-a ales categoria.
  Widget _buildStarterGemsBanner() {
    return FutureBuilder<int>(
      future: StorageService.getGems(),
      builder: (context, snapshot) {
        final gems = snapshot.data ?? 0;
        final firstTierPrice = questionUnlockGemsPrice(1);
        if (gems < firstTierPrice || gems > starterGemGrant) {
          return const SizedBox.shrink();
        }
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF5EC8F2).withAlpha(28),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF5EC8F2).withAlpha(120)),
          ),
          child: Row(
            children: [
              const Icon(Icons.diamond_rounded,
                  color: Color(0xFF5EC8F2), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(
                    'Ai $gems 💎 din partea casei — deblochează categoria pe care '
                        'o vrei tu (prima treaptă costă $firstTierPrice).',
                    'Here are $gems 💎 on the house — unlock whichever category '
                        'you want (the first tier costs $firstTierPrice).',
                  ),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.3),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<_FeaturedClaimState> _loadFeaturedClaimState() async {
    final results = await Future.wait([
      StorageService.wasModePlayedToday(_featured.id),
      StorageService.isFeaturedCategoryClaimed(),
    ]);
    return _FeaturedClaimState(played: results[0], claimed: results[1]);
  }

  /// Aplică efectiv bonusul (StorageService, nu doar marcajul de
  /// revendicare) — aceeași convenție ca [claimQuest]/[_upgrade]: metoda de
  /// storage doar ȚINE MINTE că s-a revendicat, apelantul scrie banii.
  Future<void> _claimFeatured() async {
    await StorageService.addCoins(featuredCategoryCoinReward);
    await StorageService.addXp(featuredCategoryXpReward);
    await StorageService.claimFeaturedCategory();
    Sfx.rewardPop();
    if (!mounted) return;
    setState(() => _featuredFuture = _loadFeaturedClaimState());
  }

  /// Conținut rotativ (PLAN_DE_VIITOR.md punctul 5) — categoria evidențiată
  /// azi, aceeași pentru toți jucătorii (vezi [_featured] și
  /// core/gamemodes.dart#featuredGameModeToday). Trei stări: încă nejucată
  /// azi (doar anunț), jucată dar nerevendicată (buton activ), deja
  /// revendicată (banner-ul dispare — motivul de a deschide jocul azi s-a
  /// consumat, nu mai are ce să mai arate).
  Widget _buildFeaturedCategoryBanner() {
    return FutureBuilder<_FeaturedClaimState>(
      future: _featuredFuture,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null || state.claimed) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_featured.accentColor.withAlpha(50), _featured.accentColor.withAlpha(18)]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _featured.accentColor.withAlpha(150)),
          ),
          child: Row(
            children: [
              Icon(Icons.star_rounded, color: _featured.accentColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr('Categoria zilei: ${_featured.title}', 'Category of the day: ${_featured.title}'),
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      state.played
                          ? tr('Ai jucat-o azi — revendică bonusul!', "You've played it today — claim the bonus!")
                          : tr('Joacă un joc din ea azi și iei bonus.', 'Play a round from it today for a bonus.'),
                      style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if (state.played)
                ElevatedButton(
                  onPressed: _claimFeatured,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _featured.accentColor,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('💰+$featuredCategoryCoinReward', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SpaceBackground(
        child: SafeArea(
          child: FutureBuilder<Map<String, _ModeStats>>(
            future: _statsFuture,
            builder: (context, snapshot) {
              final stats = snapshot.data;
              final totalAnswered =
                  stats?.values.fold<int>(0, (sum, s) => sum + s.answered) ?? 0;
              final totalQuestions =
                  stats?.values.fold<int>(0, (sum, s) => sum + s.total) ?? 0;

              return Column(
                children: [
                  EntranceItem(
                    controller: _introCtrl,
                    interval: const Interval(0.0, 0.45, curve: Curves.easeOut),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 20, 6),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_ios_rounded,
                                color: Colors.white70),
                          ),
                          const SizedBox(width: 4),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShaderMask(
                                shaderCallback: (r) => const LinearGradient(
                                        colors: [Colors.white, Color(0xFFC9B8FF)])
                                    .createShader(r),
                                child: Text(
                                  tr('Alege o categorie', 'Pick a category'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w900),
                                ),
                              ),
                              if (totalQuestions > 0)
                                Text(
                                  tr('$totalAnswered/$totalQuestions întrebări cucerite',
                                      '$totalAnswered/$totalQuestions questions conquered'),
                                  style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildStarterGemsBanner(),
                  _buildFeaturedCategoryBanner(),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                      itemCount: gameModes.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        // primul rând e cardul special "Higher or Lower" —
                        // mecanică total diferită (fără poze/blur), nu face
                        // parte din gameModes, deci nu e afectat de gating cu
                        // Gems / progres pe întrebări ca restul categoriilor.
                        if (i == 0) {
                          return EntranceItem(
                            controller: _introCtrl,
                            interval: _stagger(0),
                            child: _buildHigherLowerCard(),
                          );
                        }
                        final mode = gameModes[i - 1];
                        final s = stats?[mode.id];
                        final tier = s?.tier ?? 0;
                        final total = s?.total ?? 0;
                        final unlocked = s?.unlocked ?? 0;
                        // conținut inexistent încă (mode.locked) vs. blocată
                        // cu Gems (tier 0) — două motive diferite, ambele
                        // arătate ca "locked" vizual, dar cu text diferit.
                        final accessLocked =
                            !mode.locked && s != null && tier == 0;
                        final visualLocked = mode.locked || accessLocked;
                        final canUpgrade = !mode.locked &&
                            s != null &&
                            tier < maxUnlockTier &&
                            total > initialUnlockedQuestions;
                        final upgradePrice = canUpgrade
                            ? questionUnlockGemsPrice(tier + 1)
                            : null;

                        final String subtitle;
                        if (mode.locked) {
                          subtitle = tr('Va urma într-un update viitor',
                              'Coming in a future update');
                        } else if (accessLocked) {
                          subtitle = tr('Blocată — deblocheaz-o cu Gems mai jos',
                              'Locked — unlock it with Gems below');
                        } else if (unlocked < total) {
                          subtitle = tr(
                              '${s?.answered ?? 0}/$unlocked jucate (din $total)',
                              '${s?.answered ?? 0}/$unlocked played (of $total)');
                        } else {
                          subtitle = tr('${s?.answered ?? 0}/$total întrebări',
                              '${s?.answered ?? 0}/$total questions');
                        }

                        // Evidențiere "categoria zilei" — doar textul (⭐ în
                        // titlu), fără să atingem randarea proprie a
                        // CategoryCard: cel mai mic risc pentru un widget
                        // folosit de toate cele 14 carduri din listă.
                        //
                        // Arată steaua INDIFERENT de stare (blocată/tier 0
                        // inclus): banner-ul de mai sus anunță deja numele
                        // categoriei — cine dă scroll să o găsească trebuie
                        // s-o recunoască pe card, nu doar pe cele deja
                        // deblocate.
                        final isFeaturedToday = mode.id == _featured.id;
                        return EntranceItem(
                          controller: _introCtrl,
                          interval: _stagger(i),
                          child: CategoryCard(
                          index: i,
                          pulse: _liveCtrl,
                          icon: mode.icon,
                          title: isFeaturedToday ? '⭐ ${mode.title}' : mode.title,
                          color: mode.accentColor,
                          locked: visualLocked,
                          totalQuestions: total,
                          answered: s?.answered ?? 0,
                          subtitle: subtitle,
                          upgradePrice: upgradePrice,
                          onUpgrade:
                              canUpgrade ? () => _upgrade(mode, s) : null,
                          onTap: mode.locked
                              ? () =>
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(tr(
                                            'Va urma în următorul update! 🚀',
                                            'Coming in the next update! 🚀'))),
                                  )
                              : accessLocked
                                  ? () => ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(tr(
                                                'Deblocheaz-o cu Gems — vezi butonul de pe card.',
                                                'Unlock it with Gems — see the button on the card.'))),
                                      )
                                  : () => _enterCategory(mode),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
