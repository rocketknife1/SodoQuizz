import 'dart:math';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/lang.dart';
import '../core/progression.dart';
import '../core/quest_bump.dart';
import '../core/reward_collector.dart';
import '../core/theme.dart';
import '../data/culture_questions.dart';
import '../data/questions.dart';
import '../data/storage_service.dart';
import '../models/question.dart';
import '../widgets/blur_image.dart';
import '../widgets/level_header.dart';

/// Planeta hologramelor — modul care a înlocuit Quiz Nelimitat.
///
/// O rulare are [planetQuestionCount] întrebări și [planetHearts] inimi ALE
/// PLANETEI: greșelile se scad din ele, niciodată din viețile din balanță.
/// Sunt totuși o condiție reală de eșec — 10 inimi la 17 întrebări înseamnă
/// că a 11-a greșeală încheie rularea mai devreme.
///
/// Întrebările sunt un amestec de poze (aceleași ca la modul Clasic, dar
/// CLARE — fără blur și fără hint) și Cultură Generală. Proporția se trage la
/// zar la fiecare rulare, deci nu e niciodată un număr fix dintr-o categorie
/// sau alta; garantăm doar că apar minimum [_minPerKind] din fiecare fel, ca
/// să fie mereu "de toate acolo".
///
/// La final, scorul decide dacă se acordă [planetJackpotReward] — garantat
/// doar la scor perfect, altfel o șansă care crește cu scorul (vezi
/// [planetJackpotChance]) și care NU e niciodată sigură. Când zarul nu cade
/// bine, rularea plătește oricum [planetConsolationReward].
class PlanetHologramScreen extends StatefulWidget {
  const PlanetHologramScreen({super.key});

  @override
  State<PlanetHologramScreen> createState() => _PlanetHologramScreenState();
}

/// Câte întrebări minim din fiecare fel intră în rulare — restul se împart
/// după o pondere trasă la zar.
const int _minPerKind = 3;

/// O întrebare din rulare, indiferent dacă vine din pozele jocului sau din
/// Cultură Generală — ecranul nu are nevoie să știe care e care, în afară de
/// prezența imaginii.
class _PlanetQuestion {
  final String prompt;
  final String? imageAssetPath;
  final List<String> choices;
  final String answer;
  final Color color;
  final String badge;

  const _PlanetQuestion({
    required this.prompt,
    required this.imageAssetPath,
    required this.choices,
    required this.answer,
    required this.color,
    required this.badge,
  });

  factory _PlanetQuestion.fromPhoto(Question q) => _PlanetQuestion(
        prompt: q.hint1,
        imageAssetPath: q.imageAssetPath,
        choices: q.choices,
        answer: q.answer,
        color: q.color,
        badge: q.category,
      );

  factory _PlanetQuestion.fromCulture(CultureQuestion q, Color color) =>
      _PlanetQuestion(
        prompt: q.question,
        imageAssetPath: null,
        choices: q.choices,
        answer: q.answer,
        color: color,
        badge: tr('Cultură Generală', 'General Knowledge'),
      );
}

class _PlanetHologramScreenState extends State<PlanetHologramScreen> {
  final _rnd = Random();
  final GlobalKey _coinBadgeKey = GlobalKey();
  final GlobalKey _xpBadgeKey = GlobalKey();
  final GlobalKey _livesBadgeKey = GlobalKey();
  final GlobalKey _hintsBadgeKey = GlobalKey();
  final GlobalKey _gemsBadgeKey = GlobalKey();

  List<_PlanetQuestion> _pool = const [];
  bool _loading = true;

  int _index = 0;
  int _correct = 0;
  int _heartsLeft = planetHearts;
  bool _answered = false;
  String? _picked;

  /// Balanțele afișate în header — se împrospătează la fiecare impact de
  /// animație, la fel ca pe restul ecranelor cu recompense.
  int _xp = 0, _coins = 0, _lives = 0, _hints = 0, _gems = 0;

  bool _finished = false;
  bool _collecting = false;
  bool _collected = false;
  PlanetReward _reward = const PlanetReward();
  bool _jackpot = false;

  bool get _outOfHearts => _heartsLeft <= 0;
  _PlanetQuestion get _current => _pool[_index];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final photos = await loadAllQuestions();
    if (!mounted) return;
    await _refreshBalances();
    if (!mounted) return;
    setState(() {
      _pool = _buildRun(photos);
      _loading = false;
    });
    if (mounted) await bumpQuestMetric(context, 'planet_run', 1);
  }

  /// Compune cele 17 întrebări. Ponderea pozelor se trage la zar între 35% și
  /// 75% la FIECARE rulare — de-aia nu iese niciodată același număr dintr-o
  /// categorie sau alta — dar ambele feluri au un minim garantat.
  List<_PlanetQuestion> _buildRun(List<Question> photos) {
    final photoPool = List.of(photos)..shuffle(_rnd);
    final culturePool = List.of(cultureQuestions)..shuffle(_rnd);

    final photoWeight = 0.35 + _rnd.nextDouble() * 0.40;
    var photoCount = 0;
    for (var i = 0; i < planetQuestionCount; i++) {
      if (_rnd.nextDouble() < photoWeight) photoCount++;
    }
    // minimele se aplică în ambele capete, fără să depășim vreodată ce avem
    // efectiv în pool-uri (categoriile blocate pot lăsa puține poze).
    photoCount = photoCount.clamp(
      _minPerKind,
      planetQuestionCount - _minPerKind,
    );
    if (photoCount > photoPool.length) photoCount = photoPool.length;
    var cultureCount = planetQuestionCount - photoCount;
    if (cultureCount > culturePool.length) {
      cultureCount = culturePool.length;
      photoCount = planetQuestionCount - cultureCount;
    }

    // culorile hologramelor de Cultură Generală, ca să nu fie toate la fel
    const cultureColors = [
      AppColors.teal,
      AppColors.blue,
      AppColors.purple,
      AppColors.orange,
    ];

    final run = <_PlanetQuestion>[
      for (var i = 0; i < photoCount && i < photoPool.length; i++)
        _PlanetQuestion.fromPhoto(photoPool[i]),
      for (var i = 0; i < cultureCount && i < culturePool.length; i++)
        _PlanetQuestion.fromCulture(
            culturePool[i], cultureColors[i % cultureColors.length]),
    ]..shuffle(_rnd);
    return run;
  }

  Future<void> _refreshBalances() async {
    final results = await Future.wait([
      StorageService.getXp(),
      StorageService.getCoins(),
      StorageService.getLives(),
      StorageService.getHints(),
      StorageService.getGems(),
    ]);
    if (!mounted) return;
    setState(() {
      _xp = results[0];
      _coins = results[1];
      _lives = results[2];
      _hints = results[3];
      _gems = results[4];
    });
  }

  Future<void> _pick(String option) async {
    if (_answered || _finished) return;
    final correct = option == _current.answer;
    setState(() {
      _answered = true;
      _picked = option;
      if (correct) {
        _correct++;
      } else {
        _heartsLeft--;
      }
    });
    correct ? Sfx.coinHit() : Sfx.tileSelect();
    if (correct && mounted) {
      await bumpQuestMetric(context, 'planet_correct', 1);
    }

    await Future.delayed(const Duration(milliseconds: 850));
    if (!mounted) return;
    // rularea se încheie fie la epuizarea inimilor planetei, fie la ultima
    // întrebare — oricare vine prima.
    if (_outOfHearts || _index + 1 >= _pool.length) {
      await _finishRun();
      return;
    }
    setState(() {
      _index++;
      _answered = false;
      _picked = null;
    });
  }

  /// Închide rularea: trage zarul pentru recompensă și raportează metricile.
  /// NU pornește cooldown-ul — acela începe abia după colectare (vezi
  /// [_collect]), ca o ieșire forțată să nu coste o rulare neplătită.
  Future<void> _finishRun() async {
    final chance = planetJackpotChance(_correct);
    final won = chance >= 1.0 || _rnd.nextDouble() < chance;
    // Aceeași curbă ca la quest-uri: recompensa crește cu nivelul, ca un
    // premiu fix să nu fie enorm pentru un începător și derizoriu pentru un
    // veteran (vezi economyGrowth).
    final level = levelForXp(_xp);
    setState(() {
      _finished = true;
      _jackpot = won;
      _reward = won
          ? planetJackpotReward(level)
          : planetConsolationReward(_correct, level);
    });
    Sfx.rewardPop();

    if (!mounted) return;
    if (_heartsLeft > 0) await bumpQuestMetric(context, 'planet_survived', 1);
    if (!mounted) return;
    if (_correct >= planetGoodRunCorrect) {
      await bumpQuestMetric(context, 'planet_good_run', 1);
    }
    if (!mounted) return;
    if (_correct >= planetGreatRunCorrect) {
      await bumpQuestMetric(context, 'planet_great_run', 1);
    }
    if (!mounted) return;
    if (_correct >= planetQuestionCount) {
      await bumpQuestMetric(context, 'planet_perfect', 1);
    }
    if (!mounted) return;
    await checkAchievements(context);
  }

  /// Ridică recompensa și consumă rularea. Ordinea contează: rularea se
  /// înregistrează DUPĂ ce recompensa a intrat în cont, ca o închidere bruscă
  /// a aplicației la mijloc să nu ardă intrarea degeaba.
  Future<void> _collect() async {
    if (_collecting || _collected) return;
    setState(() => _collecting = true);
    if (!_reward.isEmpty) {
      await collectRewards(
        context,
        coins: _reward.coins,
        xp: _reward.xp,
        lives: _reward.hearts,
        hints: _reward.hints,
        gems: _reward.gems,
        coinBadgeKey: _coinBadgeKey,
        xpBadgeKey: _xpBadgeKey,
        livesBadgeKey: _livesBadgeKey,
        hintsBadgeKey: _hintsBadgeKey,
        gemsBadgeKey: _gemsBadgeKey,
        onEachImpact: _refreshBalances,
      );
    }
    if (!mounted) return;
    await StorageService.recordPlanetRunFinished();
    if (!mounted) return;
    setState(() {
      _collecting = false;
      _collected = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator(color: AppColors.gem)),
      );
    }
    if (_pool.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Nicio întrebare disponibilă.', 'No questions available.'),
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('Înapoi', 'Back'))),
            ],
          ),
        ),
      );
    }

    return PopScope(
      // cât timp recompensa nu e ridicată, back-ul nu trebuie să scoată
      // jucătorul din "fereastra de colectare" fără să fi primit nimic.
      canPop: !_finished || _collected,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.spaceGradient),
          child: SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: LevelHeader(
                    xp: _xp,
                    coins: _coins,
                    lives: _lives,
                    hints: _hints,
                    gems: _gems,
                    coinBadgeKey: _coinBadgeKey,
                    xpBadgeKey: _xpBadgeKey,
                    livesBadgeKey: _livesBadgeKey,
                    hintsBadgeKey: _hintsBadgeKey,
                    gemsBadgeKey: _gemsBadgeKey,
                  ),
                ),
                _buildHearts(),
                Expanded(
                  child: _finished ? _buildResults() : _buildQuestion(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 2),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
            // în fereastra de colectare butonul e inert: recompensa se ridică
            // întâi, altfel rularea ar fi consumată fără plată.
            onPressed:
                _finished && !_collected ? null : () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          const Text('Planeta hologramelor',
              style: TextStyle(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (!_finished)
            Text('${_index + 1} / ${_pool.length}',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  /// Cele 10 inimi ale planetei — se sparg una câte una, separat de balanța
  /// jucătorului (care se vede deasupra, neatinsă).
  Widget _buildHearts() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < planetHearts; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Icon(
                i < _heartsLeft
                    ? Icons.favorite_rounded
                    : Icons.heart_broken_rounded,
                size: 17,
                color: i < _heartsLeft
                    ? AppColors.gem
                    : Colors.white.withAlpha(45),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestion() {
    final q = _current;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Column(
        children: [
          if (q.imageAssetPath != null)
            Stack(
              clipBehavior: Clip.none,
              children: [
                // noBlur: poza se vede CLARĂ de la început — planeta nu are
                // hint-uri, deci nu există nimic de limpezit treptat.
                BlurImage(
                  color: q.color,
                  answer: q.answer,
                  revealed: _answered,
                  hintsUsed: 0,
                  noBlur: true,
                  imageAssetPath: q.imageAssetPath,
                ),
                Positioned(top: -9, left: 14, child: _buildBadge(q)),
              ],
            )
          else
            _buildCultureCard(q),
          const SizedBox(height: 10),
          if (q.imageAssetPath != null) ...[
            _buildPrompt(q),
            const SizedBox(height: 8),
          ],
          ..._buildOptions(q),
        ],
      ),
    );
  }

  /// Întrebările de Cultură Generală n-au poză — în locul ei stă un panou cu
  /// textul întrebării, la aceeași înălțime vizuală ca o hologramă cu imagine.
  Widget _buildCultureCard(_PlanetQuestion q) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 150),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: q.color.withAlpha(120), width: 1.5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [q.color.withAlpha(60), Colors.white.withAlpha(10)],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: q.color.withAlpha(70),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(q.badge,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 12),
          Text(
            q.prompt,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildPrompt(_PlanetQuestion q) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: q.color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(q.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildOptions(_PlanetQuestion q) {
    // ordinea variantelor e stabilă cât timp stai pe întrebare (seed din
    // indexul rulării), ca să nu sară butoanele sub deget la un rebuild.
    final opts = [...q.choices]..shuffle(Random(q.answer.hashCode + _index));
    const letters = ['A', 'B', 'C', 'D'];
    return List.generate(opts.length, (i) {
      final opt = opts[i];
      var bg = Colors.white.withAlpha(18);
      var border = Colors.white24;
      var letterBg = Colors.white.withAlpha(30);
      if (_answered) {
        if (opt == q.answer) {
          bg = AppColors.success.withAlpha(70);
          border = AppColors.success;
          letterBg = AppColors.success;
        } else if (opt == _picked) {
          bg = AppColors.danger.withAlpha(70);
          border = AppColors.danger;
          letterBg = AppColors.danger;
        }
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GestureDetector(
          onTap: _answered ? null : () => _pick(opt),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration:
                      BoxDecoration(color: letterBg, shape: BoxShape.circle),
                  child: Text(letters[i],
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(opt,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildBadge(_PlanetQuestion q) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF141B36),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: q.color, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
      ),
      child: Text(q.badge,
          style: const TextStyle(
              color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildResults() {
    final chance = planetJackpotChance(_correct);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: Column(
        children: [
          Text(
            _outOfHearts
                ? tr('Planeta a rămas fără inimi', 'The planet ran out of hearts')
                : (_jackpot
                    ? tr('Transmisie completă!', 'Transmission complete!')
                    : tr('Rulare încheiată', 'Run finished')),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(tr('$_correct din $planetQuestionCount', '$_correct of $planetQuestionCount'),
              style: const TextStyle(
                  color: AppColors.gem,
                  fontSize: 30,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          _buildChanceExplainer(chance),
          const SizedBox(height: 16),
          _buildRewardPanel(),
          const SizedBox(height: 18),
          if (!_collected)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _collecting ? null : _collect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.play,
                  disabledBackgroundColor: Colors.white24,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(_reward.isEmpty
                        ? tr('Închide', 'Close')
                        : tr('Ridică recompensa', 'Claim the reward'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w900)),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gem,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(tr('Înapoi la bază', 'Back to base'),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Colors.black)),
              ),
            ),
        ],
      ),
    );
  }

  /// Explicație onestă a zarului: jucătorul trebuie să vadă că un scor bun
  /// i-a dat o ȘANSĂ, nu o promisiune — altfel un 15/17 fără jackpot pare bug.
  Widget _buildChanceExplainer(double chance) {
    if (_correct >= planetQuestionCount) {
      return Text(
        tr('Scor perfect — recompensa mare vine garantat.',
            'Perfect score — the big reward is guaranteed.'),
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: AppColors.play, fontSize: 12.5, fontWeight: FontWeight.w700),
      );
    }
    if (chance <= 0) {
      return Text(
        tr('De la $planetGoodRunCorrect corecte în sus începi să ai șansă la recompensa mare.',
            'From $planetGoodRunCorrect correct upwards you start having a shot at the big reward.'),
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 12.5),
      );
    }
    final percent = (chance * 100).round();
    return Text(
      _jackpot
          ? tr('Aveai $percent% șansă la recompensa mare — și a picat.',
              'You had a $percent% shot at the big reward — and it landed.')
          : tr('Aveai $percent% șansă la recompensa mare. N-a picat de data asta.',
              'You had a $percent% shot at the big reward. It did not land this time.'),
      textAlign: TextAlign.center,
      style: TextStyle(
          color: _jackpot ? AppColors.play : Colors.white.withAlpha(150),
          fontSize: 12.5,
          fontWeight: FontWeight.w600),
    );
  }

  Widget _buildRewardPanel() {
    if (_reward.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          tr('Fără recompensă de data asta. Planeta te așteaptă la următoarea rulare.',
              'No reward this time. The planet will be waiting on your next run.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),
      );
    }
    final chips = <Widget>[
      if (_reward.xp > 0)
        _rewardChip(Icons.star_rounded, AppColors.purple, _reward.xp),
      if (_reward.coins > 0)
        _rewardChip(
            Icons.monetization_on_rounded, AppColors.coin, _reward.coins),
      if (_reward.gems > 0)
        _rewardChip(Icons.diamond_rounded, AppColors.gem, _reward.gems),
      if (_reward.hearts > 0)
        _rewardChip(Icons.favorite_rounded, AppColors.life, _reward.hearts),
      if (_reward.hints > 0)
        _rewardChip(
            Icons.tips_and_updates_rounded, AppColors.hint, _reward.hints),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: _jackpot ? AppColors.coin : Colors.white24,
            width: _jackpot ? 2 : 1),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _jackpot
              ? [AppColors.coin.withAlpha(55), AppColors.gem.withAlpha(35)]
              : [Colors.white.withAlpha(16), Colors.white.withAlpha(8)],
        ),
      ),
      child: Column(
        children: [
          Text(
            _jackpot
                ? tr('★ RECOMPENSA MARE ★', '★ THE BIG REWARD ★')
                : tr('Recompensă de consolare', 'Consolation reward'),
            style: TextStyle(
                color: _jackpot ? AppColors.coin : Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 10,
            children: chips,
          ),
        ],
      ),
    );
  }

  Widget _rewardChip(IconData icon, Color color, int amount) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 4),
        Text('$amount',
            style: TextStyle(
                color: color, fontSize: 16, fontWeight: FontWeight.w900)),
      ],
    );
  }
}
