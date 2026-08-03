import 'package:flutter/material.dart';
import '../core/ads_service.dart';
import '../core/audio.dart';
import '../core/progression.dart';
import '../core/reward_collector.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/coin_reward_overlay.dart';
import '../widgets/collect_all_overlay.dart';
import '../widgets/level_header.dart';

/// Quest-uri zilnice — ~10 pe zi, dintr-o rotație săptămânală peste tot
/// catalogul (vezi [todaysQuests]). Progresul se resetează automat la miezul
/// nopții (stocat sub o cheie care include data curentă).
class QuestsScreen extends StatefulWidget {
  const QuestsScreen({super.key});

  @override
  State<QuestsScreen> createState() => _QuestsScreenState();
}

class _QuestsScreenState extends State<QuestsScreen> {
  late Future<_QuestsData> _dataFuture;
  final GlobalKey _coinBadgeKey = GlobalKey();
  final GlobalKey _xpBadgeKey = GlobalKey();
  final GlobalKey _livesBadgeKey = GlobalKey();
  final GlobalKey _hintsBadgeKey = GlobalKey();
  final GlobalKey _gemsBadgeKey = GlobalKey();
  final GlobalKey<AppBottomNavBarState> _navBarKey = GlobalKey();

  /// True cât timp o colectare (individuală sau "Colectează tot") e în
  /// desfășurare — dezactivează TOATE butoanele "Ridică" între timp, ca să
  /// nu pornească două animații de colectare simultan (vezi bug-ul semnalat:
  /// suprapunerea lor confuza ordinea/afișarea).
  bool _claiming = false;

  /// Crește la fiecare reîncărcare declanșată din onEachImpact — un răspuns
  /// mai vechi care se rezolvă mai târziu (SharedPreferences își face
  /// propriile microtask-uri) e ignorat dacă între timp a mai pornit o
  /// reîncărcare mai nouă, altfel putea "îngheța" balanța afișată la o
  /// valoare veche până la următoarea colectare (bug-ul semnalat de user).
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
  }

  Future<_QuestsData> _load() async {
    final quests = todaysQuests();
    final xp = await StorageService.getXp();
    final coins = await StorageService.getCoins();
    final lives = await StorageService.getLives();
    final hints = await StorageService.getHints();
    final gems = await StorageService.getGems();
    final progress = <String, int>{};
    final claimed = <String, bool>{};
    for (final q in quests) {
      progress[q.id] = await StorageService.getQuestProgress(q.metricKey);
      claimed[q.id] = await StorageService.isQuestClaimed(q.id);
    }
    return _QuestsData(
      quests: quests,
      xp: xp,
      coins: coins,
      lives: lives,
      hints: hints,
      gems: gems,
      progress: progress,
      claimed: claimed,
    );
  }

  /// [multiplier] e 2 când vine din "Revendică x2" (vezi [_claimX2]) — restul
  /// fluxului (bifă, animație pe etape, refresh) rămâne identic.
  Future<void> _claim(Quest q, {int multiplier = 1}) async {
    if (_claiming) return;
    setState(() => _claiming = true);
    await StorageService.claimQuest(q.id);
    if (!mounted) return;
    _navBarKey.currentState?.refreshDots();
    // IMPORTANT: _dataFuture nu trebuie NICIODATĂ reasignat la un Future încă
    // nerezolvat în timpul animației — FutureBuilder resetează imediat
    // snapshot.data la null cât timp așteaptă noul Future, iar LevelHeader
    // ascunde complet pastilele de hints/gems când valorile lor sunt null
    // (vezi widget.hints/gems != null) — pastila dispărând exact când
    // CoinRewardOverlay îi caută poziția înseamnă că animația nu are unde
    // să zboare. De-asta folosim Future.value(...) cu date deja cunoscute
    // sincron, niciodată un Future "în zbor".
    final current = await _dataFuture;
    if (!mounted) return;
    // Gems-ul din quest-uri are un plafon zilnic ([dailyQuestGemCap]) —
    // rezervăm partea care chiar se poate acorda ÎNAINTE de animație, ca
    // numărul care zboară spre pastilă să fie exact cel primit, nu unul
    // promis și netăiat.
    final grantedGems = await StorageService.grantQuestGems(q.gemReward * multiplier);
    if (!mounted) return;
    setState(() {
      _dataFuture = Future.value(_QuestsData(
        quests: current.quests,
        xp: current.xp,
        coins: current.coins,
        lives: current.lives,
        hints: current.hints,
        gems: current.gems,
        progress: current.progress,
        claimed: Map<String, bool>.of(current.claimed)..[q.id] = true, // bifa apare pe loc
      ));
    });
    await collectRewards(
      context,
      coins: q.coinReward * multiplier,
      xp: q.xpReward * multiplier,
      lives: q.heartReward * multiplier,
      hints: q.hintReward * multiplier,
      hintsBadgeKey: _hintsBadgeKey,
      gems: grantedGems,
      gemsBadgeKey: _gemsBadgeKey,
      coinBadgeKey: _coinBadgeKey,
      xpBadgeKey: _xpBadgeKey,
      livesBadgeKey: _livesBadgeKey,
      onEachImpact: _refreshBalances,
    );
    if (!mounted) return;
    setState(() => _claiming = false);
  }

  /// "Revendică x2" — arată o reclamă recompensată (sau simulează dacă nu e
  /// încărcată, vezi [AdsService.watchOrSimulate], același tipar ca la Game
  /// Over din game_screen.dart) și, dacă a fost vizionată, revendică quest-ul
  /// cu recompensa dublată.
  Future<void> _claimX2(Quest q) async {
    if (_claiming) return;
    final earned = await AdsService.instance.watchOrSimulate();
    if (!mounted || !earned) return;
    await _claim(q, multiplier: 2);
  }

  /// Reîncarcă balanța+progresul, dar aplică rezultatul DOAR dacă nicio altă
  /// reîncărcare n-a mai pornit între timp (vezi [_loadSeq]) — altfel un
  /// răspuns vechi care ajunge ultimul ar suprascrie unul mai nou și
  /// balanța ar părea "înghețată" (bug-ul semnalat: se actualizează abia la
  /// al doilea claim).
  void _refreshBalances() {
    final seq = ++_loadSeq;
    _load().then((refreshed) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _dataFuture = Future.value(refreshed);
      });
    });
  }

  /// Colectează dintr-o dată TOATE quest-urile terminate și nerevendicate —
  /// spre deosebire de [_claim] (o singură recompensă, animată în etape
  /// separate cu [collectRewards]), aici sumăm toate resursele din quest-urile
  /// eligibile, le scriem O SINGURĂ DATĂ în storage, apoi arătăm UN SINGUR
  /// rezumat ([CollectAllOverlay]) — la cererea explicită a userului, ca să
  /// nu "bubuie telefonul" cu animații succesive la multe quest-uri deodată.
  Future<void> _collectAll() async {
    if (_claiming) return;
    final current = await _dataFuture;
    final claimable = current.quests.where((q) {
      final p = current.progress[q.id] ?? 0;
      return p >= q.target && !(current.claimed[q.id] ?? false);
    }).toList();
    if (claimable.isEmpty) return;
    if (!mounted) return;
    setState(() => _claiming = true);

    var coins = 0, xp = 0, gems = 0, hearts = 0, hints = 0;
    for (final q in claimable) {
      xp += q.xpReward;
      coins += q.coinReward;
      // plafonul zilnic de gems se aplică per quest, exact ca la [_claim] —
      // o colectare în bloc nu trebuie să-l poată ocoli.
      gems += await StorageService.grantQuestGems(q.gemReward);
      hearts += q.heartReward;
      hints += q.hintReward;
      await StorageService.claimQuest(q.id);
    }
    if (xp > 0) await StorageService.addXp(xp);
    if (coins > 0) await StorageService.addCoins(coins);
    if (gems > 0) await StorageService.addGems(gems);
    if (hearts > 0) await StorageService.addLivesUncapped(hearts);
    // hints NECAPAT aici ar afișa temporar un total peste plafonul de 20 din
    // StorageService — de-asta citim valoarea finală DIN storage (deja
    // plafonat corect) în loc să adunăm optimist current.hints + hints.
    if (hints > 0) await StorageService.addHints(hints);
    if (!mounted) return;
    _navBarKey.currentState?.refreshDots();

    // Citim valorile finale ACUM (corecte, plafonate), dar NU le aplicăm încă
    // în header — doar bifele de pe carduri apar pe loc (vezi mai jos). Fără
    // asta, bara de XP/pastilele ar sări la valoarea nouă cât timp dialogul
    // de rezumat e încă pe ecran, cu mult înainte ca stelutele să ajungă
    // vizual la ele (bug real semnalat de jucător). Fiecare valoare se
    // aplică abia la impactul propriei animații, în [_launchCollectAllFlights].
    final finalXp = xp > 0 ? await StorageService.getXp() : current.xp;
    final finalCoins = coins > 0 ? await StorageService.getCoins() : current.coins;
    final finalGems = gems > 0 ? await StorageService.getGems() : current.gems;
    final finalLives = hearts > 0 ? await StorageService.getLives() : current.lives;
    final finalHints = hints > 0 ? await StorageService.getHints() : current.hints;
    if (!mounted) return;

    final claimedUpdated = Map<String, bool>.of(current.claimed);
    for (final q in claimable) {
      claimedUpdated[q.id] = true; // bifele apar pe loc
    }
    setState(() {
      _dataFuture = Future.value(current.copyWith(claimed: claimedUpdated));
    });

    // ordinea intrărilor respectă mereu XP → monede → gems → viață → hints
    // (vezi reward_collector.dart și _RewardChips).
    final entries = <CollectAllEntry>[
      if (xp > 0)
        CollectAllEntry(
          icon: Icons.star_rounded,
          color: AppColors.purple,
          amount: xp,
          targetKey: _xpBadgeKey,
          onImpact: () {
            Sfx.xpHit();
            _applyHeaderField((d) => d.copyWith(xp: finalXp));
          },
        ),
      if (coins > 0)
        CollectAllEntry(
          icon: Icons.monetization_on_rounded,
          color: AppColors.coin,
          amount: coins,
          targetKey: _coinBadgeKey,
          onImpact: () {
            Sfx.coinHit();
            _applyHeaderField((d) => d.copyWith(coins: finalCoins));
          },
        ),
      if (gems > 0)
        CollectAllEntry(
          icon: Icons.diamond_rounded,
          color: AppColors.gem,
          amount: gems,
          targetKey: _gemsBadgeKey,
          onImpact: () {
            // nu exista un sunet dedicat de gems — refolosim coinHit (vezi Sfx).
            Sfx.coinHit();
            _applyHeaderField((d) => d.copyWith(gems: finalGems));
          },
        ),
      if (hearts > 0)
        CollectAllEntry(
          icon: Icons.favorite_rounded,
          color: AppColors.life,
          amount: hearts,
          targetKey: _livesBadgeKey,
          onImpact: () {
            Sfx.heartHit();
            _applyHeaderField((d) => d.copyWith(lives: finalLives));
          },
        ),
      if (hints > 0)
        CollectAllEntry(
          icon: Icons.tips_and_updates_rounded,
          color: AppColors.hint,
          amount: hints,
          targetKey: _hintsBadgeKey,
          onImpact: () {
            // nu exista un sunet dedicat de hint — refolosim xpHit (vezi Sfx).
            Sfx.xpHit();
            _applyHeaderField((d) => d.copyWith(hints: finalHints));
          },
        ),
    ];
    await CollectAllOverlay.show(context, entries: entries, questCount: claimable.length);

    if (!mounted) return;
    setState(() => _claiming = false);
    _launchCollectAllFlights(entries);
  }

  /// Aplică o singură schimbare punctuală (vezi apelurile din [_collectAll])
  /// pe TOP de orice e afișat ACUM, nu pe [current]-ul de mai devreme — dacă
  /// o altă resursă tocmai și-a aplicat propriul impact, nu vrem să o
  /// suprascriem. `_dataFuture` e mereu deja rezolvat în acest punct (vezi
  /// [_collectAll]), deci `.then` rulează practic imediat.
  void _applyHeaderField(_QuestsData Function(_QuestsData d) apply) {
    _dataFuture.then((d) {
      if (!mounted) return;
      setState(() {
        _dataFuture = Future.value(apply(d));
      });
    });
  }

  /// Odată ce jucătorul apasă "Grozav!" (dialogul [CollectAllOverlay] se
  /// închide și `await`-ul de mai sus se rezolvă), fiecare resursă își
  /// zboară propria animație spre pastila ei din header — TOATE pornesc
  /// aproape deodată, eșalonate cu doar 200ms între lansări (nu așteptate
  /// secvențial, ca la [collectRewards]), ca "explozia" să pară un singur
  /// moment, dar fără ca traseele suprapuse perfect să se încurce vizual.
  /// Valorile finale sunt deja cunoscute (vezi [_collectAll]) — [onImpact]
  /// doar le aplică în header, exact când propria animație ajunge acolo.
  void _launchCollectAllFlights(List<CollectAllEntry> entries) {
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      Future.delayed(Duration(milliseconds: 200 * i), () {
        if (!mounted) return;
        CoinRewardOverlay.show(
          context,
          amount: entry.amount,
          targetKey: entry.targetKey,
          icon: entry.icon,
          color: entry.color,
          onImpact: entry.onImpact,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: FutureBuilder<_QuestsData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: LevelHeader(
                    xp: data?.xp ?? 0,
                    coins: data?.coins ?? 0,
                    lives: data?.lives ?? 5,
                    hints: data?.hints,
                    gems: data?.gems,
                    coinBadgeKey: _coinBadgeKey,
                    xpBadgeKey: _xpBadgeKey,
                    livesBadgeKey: _livesBadgeKey,
                    hintsBadgeKey: _hintsBadgeKey,
                    gemsBadgeKey: _gemsBadgeKey,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Text('Quest-uri zilnice', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (data != null) _buildCollectAllButton(data),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Azi ai ${todaysQuests().length} quest-uri din cele ${allQuests.length}. '
                        'La miezul nopții primești un set complet nou — aceleași revin abia peste o săptămână.',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      // fiecare quest dă acum gems (1/2/4 după dificultate),
                      // dar cu un plafon zilnic — arătăm explicit cât a mai
                      // rămas, altfel un card cu 💎 care nu mai plătește ar
                      // părea stricat.
                      FutureBuilder<int>(
                        future: StorageService.questGemsLeftToday(),
                        builder: (context, snap) {
                          final left = snap.data;
                          if (left == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              left > 0
                                  ? 'Gems din quest-uri azi: încă $left din $dailyQuestGemCap.'
                                  : 'Ai atins plafonul de $dailyQuestGemCap 💎 din quest-uri pe ziua de azi — restul recompenselor vin normal.',
                              style: TextStyle(
                                  color: left > 0 ? AppColors.gem : Colors.white38,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: data == null
                      ? const Center(child: CircularProgressIndicator(color: AppColors.purple))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: data.quests.length,
                          itemBuilder: (context, i) {
                            final q = data.quests[i];
                            final progress = (data.progress[q.id] ?? 0).clamp(0, q.target);
                            final done = progress >= q.target;
                            final claimed = data.claimed[q.id] ?? false;
                            return _QuestCard(
                              quest: q,
                              progress: progress,
                              done: done,
                              claimed: claimed,
                              disabled: _claiming,
                              onClaim: () => _claim(q),
                              onClaimX2: () => _claimX2(q),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(key: _navBarKey, current: AppTab.quests),
    );
  }

  /// Numărul de quest-uri terminate și încă nerevendicate — butonul e vizibil
  /// doar când sunt cel puțin 2 (la unul singur, "Ridică" de pe cardul lui e
  /// deja suficient, n-are sens un buton separat pentru un singur element).
  Widget _buildCollectAllButton(_QuestsData data) {
    final claimableCount = data.quests.where((q) {
      final p = data.progress[q.id] ?? 0;
      return p >= q.target && !(data.claimed[q.id] ?? false);
    }).length;
    if (claimableCount < 2) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _claiming ? null : _collectAll,
      child: AnimatedOpacity(
        opacity: _claiming ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.coin,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: AppColors.coin.withAlpha(110), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Colors.black, size: 15),
              const SizedBox(width: 5),
              Text('Colectează tot ($claimableCount)', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestsData {
  final List<Quest> quests;
  final int xp;
  final int coins;
  final int lives;
  final int hints;
  final int gems;
  final Map<String, int> progress;
  final Map<String, bool> claimed;
  _QuestsData({
    required this.quests,
    required this.xp,
    required this.coins,
    required this.lives,
    required this.hints,
    required this.gems,
    required this.progress,
    required this.claimed,
  });

  /// Vezi [_QuestsScreenState._applyHeaderField] — schimbă DOAR câmpurile
  /// date, restul rămân cele curente (nu cele din momentul creării).
  _QuestsData copyWith({int? xp, int? coins, int? lives, int? hints, int? gems, Map<String, bool>? claimed}) {
    return _QuestsData(
      quests: quests,
      xp: xp ?? this.xp,
      coins: coins ?? this.coins,
      lives: lives ?? this.lives,
      hints: hints ?? this.hints,
      gems: gems ?? this.gems,
      progress: progress,
      claimed: claimed ?? this.claimed,
    );
  }
}

class _QuestCard extends StatelessWidget {
  final Quest quest;
  final int progress;
  final bool done;
  final bool claimed;
  final bool disabled;
  final VoidCallback onClaim;
  final VoidCallback onClaimX2;

  const _QuestCard({
    required this.quest,
    required this.progress,
    required this.done,
    required this.claimed,
    this.disabled = false,
    required this.onClaim,
    required this.onClaimX2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: claimed ? AppColors.success.withAlpha(120) : Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (claimed ? AppColors.success : AppColors.purple).withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(quest.icon, color: claimed ? AppColors.success : AppColors.purple, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(quest.title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress / quest.target,
                    minHeight: 6,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(claimed ? AppColors.success : AppColors.purple),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('$progress / ${quest.target}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    const SizedBox(width: 8),
                    Expanded(child: _RewardChips(quest: quest)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (claimed)
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 26)
          else if (done)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: disabled ? null : onClaim,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.play,
                    disabledBackgroundColor: Colors.white24,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Revendică', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: disabled ? null : onClaimX2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: disabled ? Colors.white10 : AppColors.coin.withAlpha(35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: disabled ? Colors.white24 : AppColors.coin),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.smart_display_rounded, size: 12, color: disabled ? Colors.white38 : AppColors.coin),
                        const SizedBox(width: 4),
                        Text(
                          'Revendică x2',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: disabled ? Colors.white38 : AppColors.coin),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          else
            const Icon(Icons.lock_clock_rounded, color: Colors.white24, size: 22),
        ],
      ),
    );
  }
}

/// Rândul de recompense al unui quest — un chip mic per resursă acordată
/// (până la 5: XP, monede, gems, viață, hint), în loc de o singură linie de
/// text ce nu mai încape odată ce un quest poate combina mai multe resurse.
class _RewardChips extends StatelessWidget {
  final Quest quest;
  const _RewardChips({required this.quest});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (quest.xpReward > 0) _chip(Icons.star_rounded, AppColors.purple, quest.xpReward),
      if (quest.coinReward > 0) _chip(Icons.monetization_on_rounded, AppColors.coin, quest.coinReward),
      if (quest.gemReward > 0) _chip(Icons.diamond_rounded, AppColors.gem, quest.gemReward),
      if (quest.heartReward > 0) _chip(Icons.favorite_rounded, AppColors.life, quest.heartReward),
      if (quest.hintReward > 0) _chip(Icons.tips_and_updates_rounded, AppColors.hint, quest.hintReward),
    ];
    return Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 3, children: chips);
  }

  Widget _chip(IconData icon, Color color, int amount) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 11),
        const SizedBox(width: 2),
        Text('$amount', style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
