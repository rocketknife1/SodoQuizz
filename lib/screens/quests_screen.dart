import 'package:flutter/material.dart';
import '../core/ads_service.dart';
import '../core/audio.dart';
import '../core/daily_challenge.dart';
import '../core/remote_flags.dart';
import '../core/progression.dart';
import '../core/reward_collector.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';
import 'daily_challenge_screen.dart';
import 'event_screen.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/coin_reward_overlay.dart';
import '../widgets/collect_all_overlay.dart';
import '../widgets/level_header.dart';
import '../core/breadcrumbs.dart';

/// Quest-uri zilnice — 12 pe zi în timpul săptămânii și 14 în weekend,
/// dintr-o rotație săptămânală peste tot catalogul (vezi [todaysQuests]).
/// Progresul se resetează automat la miezul nopții (stocat sub o cheie care
/// include data curentă).
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
    Breadcrumbs.drop('ecran: Questuri');
    _dataFuture = _load();
    // Resursele se pot schimba sub ecranul deschis: un grant de la admin, un
    // premiu încasat în fundal, sau salvarea coborâtă din cloud. Vezi
    // StorageService.balanceRevision.
    StorageService.balanceRevision.addListener(_refreshBalances);
  }

  @override
  void dispose() {
    StorageService.balanceRevision.removeListener(_refreshBalances);
    super.dispose();
  }

  Future<_QuestsData> _load() async {
    final quests = todaysQuests();
    // Nivelul cu care a început ziua — el fixează țintele și plățile de azi
    // (vezi StorageService.questScaleLevel). NU se recitește la fiecare
    // refresh de balanță, altfel un level-up câștigat chiar din colectarea
    // unui quest ar rescrie țintele celorlalte în mijlocul ecranului.
    final level = await StorageService.questScaleLevel();
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
      level: level,
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
        level: current.level,
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
      coins: q.coinRewardAt(current.level) * multiplier,
      xp: q.xpRewardAt(current.level) * multiplier,
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
    if (!mounted) return;
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
      return p >= q.targetAt(current.level) && !(current.claimed[q.id] ?? false);
    }).toList();
    if (claimable.isEmpty) return;
    if (!mounted) return;
    setState(() => _claiming = true);

    var coins = 0, xp = 0, gems = 0, hearts = 0, hints = 0;
    for (final q in claimable) {
      xp += q.xpRewardAt(current.level);
      coins += q.coinRewardAt(current.level);
      // plafonul zilnic de gems se aplică per quest, exact ca la [_claim] —
      // o colectare în bloc nu trebuie să-l poată ocoli.
      gems += await StorageService.grantQuestGems(q.gemReward);
      hearts += q.heartReward;
      hints += q.hintReward;
      await StorageService.claimQuest(q.id);
    }
    // Pauza pe notificarile de balanta: scrierile de mai jos se fac ACUM, dar
    // fiecare pastila din header se misca abia la impactul propriei animatii
    // (vezi onImpact-urile de mai jos si StorageService.holdBalanceNotifications).
    //
    // Eliberarea e IDEMPOTENTA si are trei declansatoare, oricare vine primul:
    // ultimul impact de animatie (calea fericita), o iesire timpurie prin
    // demontare, si un cronometru de siguranta. Fara toate trei, o navigatie
    // in timpul animatiei putea lasa pauza blocata la infinit -> toate
    // badge-urile din joc ingheata pana la restart (bug real prins in recenzie).
    StorageService.holdBalanceNotifications();
    var holdReleased = false;
    void releaseHold() {
      if (holdReleased) return;
      holdReleased = true;
      StorageService.releaseBalanceNotifications();
    }
    if (xp > 0) await StorageService.addXp(xp);
    if (coins > 0) await StorageService.addCoins(coins);
    if (gems > 0) await StorageService.addGems(gems);
    if (hearts > 0) await StorageService.addLivesUncapped(hearts);
    // hints NECAPAT aici ar afișa temporar un total peste plafonul de 20 din
    // StorageService — de-asta citim valoarea finală DIN storage (deja
    // plafonat corect) în loc să adunăm optimist current.hints + hints.
    if (hints > 0) await StorageService.addHints(hints);
    if (!mounted) {
      releaseHold();
      return;
    }
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
    if (!mounted) {
      releaseHold();
      return;
    }
    // Contor de impacturi: ultimul cheama releaseHold (idempotent).
    var pendingImpacts = [xp, coins, gems, hearts, hints].where((v) => v > 0).length;
    void releaseAfterImpact() {
      if (--pendingImpacts <= 0) releaseHold();
    }

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
            StorageService.notifyBalanceChanged();
            _applyHeaderField((d) => d.copyWith(xp: finalXp));
            releaseAfterImpact();
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
            StorageService.notifyBalanceChanged();
            _applyHeaderField((d) => d.copyWith(coins: finalCoins));
            releaseAfterImpact();
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
            StorageService.notifyBalanceChanged();
            _applyHeaderField((d) => d.copyWith(gems: finalGems));
            releaseAfterImpact();
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
            StorageService.notifyBalanceChanged();
            _applyHeaderField((d) => d.copyWith(lives: finalLives));
            releaseAfterImpact();
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
            StorageService.notifyBalanceChanged();
            _applyHeaderField((d) => d.copyWith(hints: finalHints));
            releaseAfterImpact();
          },
        ),
    ];
    await CollectAllOverlay.show(context, entries: entries, questCount: claimable.length);

    if (!mounted) {
      releaseHold();
      return;
    }
    setState(() => _claiming = false);
    _launchCollectAllFlights(entries);
    // Plasa de siguranta: daca vreun impact nu se mai declanseaza (navigatie
    // in timpul zborului, overlay distrus), pauza se elibereaza oricum.
    Future.delayed(const Duration(seconds: 6), releaseHold);
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

  /// Ce quest-uri intră mâine. Rotația e deterministă — [todaysQuests] ia
  /// grupa zilei din săptămână, deci ziua de mâine se poate arăta EXACT, nu
  /// ghicit. Lista e read-only: nu se poate progresa la ele azi.
  Future<void> _showTomorrowQuests() async {
    final level = await StorageService.questScaleLevel();
    if (!mounted) return;
    final quests = todaysQuests(DateTime.now().add(const Duration(days: 1)));
    Sfx.tileSelect();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141B36),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.event_rounded, color: AppColors.purple, size: 22),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(tr('Mâine intră astea', "Tomorrow's line-up"),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
                  Text('${quests.length}',
                      style: const TextStyle(color: Colors.white38, fontSize: 15, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                tr('Recompensele se văd la valorile nivelului tău de acum.',
                    'Rewards are shown at your current level.'),
                style: const TextStyle(color: Colors.white38, fontSize: 11.5),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: quests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final q = quests[i];
                    final color = switch (q.tier) {
                      QuestTier.easy => AppColors.teal,
                      QuestTier.medium => AppColors.orange,
                      QuestTier.hard => AppColors.danger,
                    };
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: color.withAlpha(70)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: color.withAlpha(38),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Icon(q.icon, color: color, size: 18),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(q.titleAt(level),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 8),
                          Text('💰${q.coinRewardAt(level)}',
                              style: const TextStyle(
                                  color: AppColors.coin, fontSize: 12, fontWeight: FontWeight.w800)),
                          if (q.gemReward > 0) ...[
                            const SizedBox(width: 7),
                            Text('💎${q.gemReward}',
                                style: const TextStyle(
                                    color: AppColors.gem, fontSize: 12, fontWeight: FontWeight.w800)),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: _EventCard(),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: _DailyChallengeCard(),
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
                      // Explicatia de dinainte era un paragraf de trei randuri
                      // pe care nimeni nu-l citeste a doua oara. Ce conteaza
                      // zilnic incape intr-o linie; restul e in pastilele de
                      // dedesubt, care sunt si actionabile.
                      Text(
                        tr('${todaysQuests().length} azi din ${allQuests.length}. La miezul nopții intră alt set.',
                            '${todaysQuests().length} today out of ${allQuests.length}. A new set arrives at midnight.'),
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          // Fiecare quest da gems (1/2/4 dupa dificultate), dar
                          // cu plafon zilnic — fara pastila asta un card cu 💎
                          // care nu mai plateste ar parea stricat.
                          FutureBuilder<int>(
                            future: StorageService.questGemsLeftToday(),
                            builder: (context, snap) {
                              final left = snap.data;
                              if (left == null) return const SizedBox.shrink();
                              final done = left <= 0;
                              return Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                                decoration: BoxDecoration(
                                  color: (done ? Colors.white24 : AppColors.gem).withAlpha(done ? 20 : 30),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: (done ? Colors.white24 : AppColors.gem).withAlpha(done ? 60 : 110)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.diamond_rounded,
                                        size: 14, color: done ? Colors.white38 : AppColors.gem),
                                    const SizedBox(width: 5),
                                    Text(
                                      done
                                          ? tr('plafon atins', 'cap reached')
                                          : tr('încă $left din $dailyQuestGemCap', '$left more of $dailyQuestGemCap'),
                                      style: TextStyle(
                                          color: done ? Colors.white38 : AppColors.gem,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          // Ce intra maine: jucatorii isi pot planifica seara
                          // ce joaca a doua zi. Rotatia e determinista (vezi
                          // todaysQuests), deci se poate arata exact, nu ghicit.
                          Material(
                            color: AppColors.purple.withAlpha(38),
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _showTomorrowQuests,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppColors.purple.withAlpha(120)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.event_rounded, size: 14, color: AppColors.purple),
                                    const SizedBox(width: 5),
                                    Text(tr('Ce intră mâine', "Tomorrow's quests"),
                                        style: const TextStyle(
                                            color: AppColors.purple, fontSize: 11.5, fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
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
                            final target = q.targetAt(data.level);
                            final progress = (data.progress[q.id] ?? 0).clamp(0, target);
                            final done = progress >= target;
                            final claimed = data.claimed[q.id] ?? false;
                            return _QuestCard(
                              quest: q,
                              level: data.level,
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

  /// Butonul plin, galben, apare doar de la 2 quest-uri colectabile în sus —
  /// la unul singur, "Ridică" de pe cardul lui e deja suficient.
  ///
  /// Sub acest prag NU dispare complet, ca înainte: rămâne o etichetă cyan
  /// discretă, ca jucătorul să știe că funcția există și de ce nu e activă
  /// încă. Un buton care apare din senin abia la al doilea quest terminat nu
  /// se poate descoperi.
  Widget _buildCollectAllButton(_QuestsData data) {
    final claimableCount = data.quests.where((q) {
      final p = data.progress[q.id] ?? 0;
      return p >= q.targetAt(data.level) && !(data.claimed[q.id] ?? false);
    }).length;
    if (claimableCount < 2) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded,
              color: AppColors.gem.withAlpha(110), size: 13),
          const SizedBox(width: 4),
          Text(
            tr('Colectează tot', 'Collect all'),
            style: TextStyle(
              color: AppColors.gem.withAlpha(130),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }
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
              Text(tr('Colectează tot ($claimableCount)', 'Collect all ($claimableCount)'), style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestsData {
  final List<Quest> quests;

  /// Nivelul cu care a început ziua — fixează țintele și plățile tuturor
  /// quest-urilor afișate (vezi StorageService.questScaleLevel). Ținut în
  /// date, nu recitit din storage la fiecare rebuild, ca un level-up câștigat
  /// chiar din colectare să nu rescrie ecranul sub ochii jucătorului.
  final int level;
  final int xp;
  final int coins;
  final int lives;
  final int hints;
  final int gems;
  final Map<String, int> progress;
  final Map<String, bool> claimed;
  _QuestsData({
    required this.quests,
    required this.level,
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
      level: level,
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

  /// Nivelul zilei — cardul îl are nevoie ca să afișeze ținta și plata
  /// EFECTIVE, nu valorile de catalog (vezi economyGrowth).
  final int level;
  final int progress;
  final bool done;
  final bool claimed;
  final bool disabled;
  final VoidCallback onClaim;
  final VoidCallback onClaimX2;

  const _QuestCard({
    required this.quest,
    required this.level,
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
                Text(quest.titleAt(level), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress / quest.targetAt(level),
                    minHeight: 6,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(claimed ? AppColors.success : AppColors.purple),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('$progress / ${quest.targetAt(level)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    const SizedBox(width: 8),
                    Expanded(child: _RewardChips(quest: quest, level: level)),
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
                  child: Text(tr('Revendică', 'Claim'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                          tr('Revendică x2', 'Claim x2'),
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
  final int level;
  const _RewardChips({required this.quest, required this.level});

  @override
  Widget build(BuildContext context) {
    final xp = quest.xpRewardAt(level);
    final coins = quest.coinRewardAt(level);
    final chips = <Widget>[
      if (xp > 0) _chip(Icons.star_rounded, AppColors.purple, xp),
      if (coins > 0) _chip(Icons.monetization_on_rounded, AppColors.coin, coins),
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

/// Cardul „Provocarea Zilei" din capul ecranului de Quest-uri — set fix de 5
/// întrebări pe zi, o rulare, recompensă mare + clasament de azi (vezi
/// [DailyChallengeScreen]). Se auto-încarcă: dacă azi s-a jucat deja, arată
/// scorul; altfel invită la joc.
class _DailyChallengeCard extends StatefulWidget {
  const _DailyChallengeCard();

  @override
  State<_DailyChallengeCard> createState() => _DailyChallengeCardState();
}

class _DailyChallengeCardState extends State<_DailyChallengeCard> {
  int? _todayCorrect;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = dailyChallengeDateKey(DateTime.now());
    final r = await StorageService.dailyChallengeResultFor(key);
    if (!mounted) return;
    setState(() {
      _todayCorrect = r;
      _loaded = true;
    });
  }

  Future<void> _open() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const DailyChallengeScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final done = _todayCorrect != null;
    return GestureDetector(
      onTap: _loaded ? _open : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.coin.withAlpha(60), AppColors.orange.withAlpha(30)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.coin.withAlpha(120)),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_fire_department_rounded, color: AppColors.coin, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('Provocarea Zilei', 'Daily Challenge'),
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    done
                        ? tr('Azi: $_todayCorrect/$dailyChallengeQuestionCount corecte · vezi clasamentul',
                            "Today: $_todayCorrect/$dailyChallengeQuestionCount correct · see the board")
                        : tr('$dailyChallengeQuestionCount întrebări · o dată pe zi · până la 350 monede',
                            '$dailyChallengeQuestionCount questions · once a day · up to 350 coins'),
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: done ? Colors.white.withAlpha(28) : AppColors.coin,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                done ? tr('CLASAMENT', 'BOARD') : tr('JOACĂ', 'PLAY'),
                style: TextStyle(
                    color: done ? Colors.white : Colors.black,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cardul unui eveniment limitat — apare DOAR când `RemoteFlags.activeEvent`
/// e non-null (un eveniment configurat şi în fereastra lui de timp). Tap →
/// [EventScreen]. Vezi core/game_event.dart.
class _EventCard extends StatelessWidget {
  const _EventCard();

  @override
  Widget build(BuildContext context) {
    final e = RemoteFlags.instance.activeEvent;
    if (e == null) return const SizedBox.shrink();
    final daysLeft = e.daysLeftAt(DateTime.now());
    return GestureDetector(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => EventScreen(event: e))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            AppColors.purple.withAlpha(70),
            AppColors.orange.withAlpha(40),
          ]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.purple.withAlpha(130)),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_rounded, color: AppColors.coin, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr(e.titleRo, e.titleEn),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    daysLeft > 0
                        ? tr('Eveniment · încă $daysLeft ${daysLeft == 1 ? 'zi' : 'zile'} · clasament propriu',
                            'Event · $daysLeft ${daysLeft == 1 ? 'day' : 'days'} left · own leaderboard')
                        : tr('Eveniment · ultima zi · clasament propriu',
                            'Event · last day · own leaderboard'),
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: AppColors.coin, borderRadius: BorderRadius.circular(14)),
              child: Text(tr('VEZI', 'OPEN'),
                  style: const TextStyle(color: Colors.black, fontSize: 11.5, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }
}
