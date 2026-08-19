import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/ads_service.dart';
import '../core/audio.dart';
import '../core/game_helpers.dart';
import '../core/gamemodes.dart';
import '../core/lang.dart';
import '../core/progression.dart';
import '../core/quest_bump.dart';
import '../core/reward_collector.dart';
import '../core/theme.dart';
import '../data/questions.dart';
import '../data/shop.dart';
import '../data/storage_service.dart';
import '../models/question.dart';
import '../widgets/blur_image.dart';
import '../widgets/category_unlock_animation.dart';
import '../widgets/in_app_notification.dart';
import '../widgets/next_button.dart';
import '../widgets/report_question_button.dart';
import 'achievements_screen.dart';
import 'home_screen.dart';
import 'loading_screen.dart';

/// Un singur ecran de joc pentru toate gamemodurile: fiecare întrebare
/// arată o imagine care se limpezește cu fiecare hint și 4 variante de
/// răspuns — aceeași mecanică peste tot (cartoon, logo-uri, gamers cave,
/// medical), doar conținutul (întrebări/poze/culori) diferă.
class GameScreen extends StatefulWidget {
  final String gameModeId;

  /// Taxa plătită la intrare (vezi categories_screen.dart._enterCategory) —
  /// 0 înseamnă sesiune fără taxă, deci fără recompensă/notificare la
  /// ieșire (vezi _settleExitReward).
  final int entryFeePaid;
  const GameScreen(
      {super.key, required this.gameModeId, this.entryFeePaid = 0});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  List<Question> questions = [];
  bool _loadingQuestions = true;
  int qIndex = 0;
  int score = 0;
  int lives = 5;
  int streak = 0;
  int hintsUsed = 0;
  int hintsBalance = 0;

  /// Averea curentă, ținută local ca să putem afișa și încasa taxa de hint
  /// (scalată cu averea) fără o citire din storage la fiecare frame — se
  /// resincronizează la fiecare răspuns corect și la fiecare hint.
  int coinsBalance = 0;
  /// Setat când al 2-lea hint e cumpărat: 2 din cele 3 variante greșite
  /// dispar, rămânând doar cea corectă + una greșită ("50/50"). Calculat o
  /// singură dată (nu la fiecare build) ca alegerea variantei greșite rămase
  /// să nu se schimbe la fiecare re-render.
  List<String>? _fiftyFiftyOptions;
  /// Setat când al 3-lea hint e cumpărat: highlight pe una din cele 2
  /// variante rămase (post 50/50), însoțit de un procent de "șansă" afișat.
  /// NU garantează răspunsul corect — procentul e generat aleator, iar
  /// varianta evidențiată e corectă exact cu acea probabilitate (calibrat:
  /// la 70% arătat, e corectă în ~70% din cazuri, nu mereu). Calculat o
  /// singură dată, ca la [_fiftyFiftyOptions].
  String? _hintGuessOption;
  int? _hintGuessPercent;
  int currentQuestionReward = 0;
  final Map<String, int> _questionRewards = {};
  bool answered = false;
  String? selectedAnswer;
  bool _noBlur = false;
  bool _unlimitedLives = false;
  int _sessionAnswered = 0;
  int _sessionCorrect = 0;
  int _totalInCategory = 0;
  bool _exitRewardSettled = false;
  late final AnimationController _shakeController;

  GameMode get mode => gameModeById(widget.gameModeId);
  Question get currentQ => questions.isNotEmpty
      ? questions[qIndex]
      : throw StateError('No questions');

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _loadQuestions();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    final results = await Future.wait([
      loadAllQuestions(),
      StorageService.getLives(),
      StorageService.getNoBlurMode(),
      StorageService.getHints(),
      StorageService.hasUnlimitedLives(),
      StorageService.getCoins(),
    ]);
    final loaded = results[0] as List<Question>;
    final savedLives = results[1] as int;
    final noBlur = results[2] as bool;
    final savedHints = results[3] as int;
    final unlimitedLives = results[4] as bool;
    final savedCoins = results[5] as int;

    // sortare deterministă (nu shuffle) ca "primele N" să fie mereu ACELEAȘI
    // întrebări între sesiuni — altfel deblocarea treptată n-ar avea sens
    // (ai vedea alt set de N întrebări de fiecare dată).
    final forMode = loaded
        .where((q) => q.categoryId == widget.gameModeId)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final unlockedCount = await StorageService.getUnlockedQuestionCount(
        widget.gameModeId, forMode.length);

    if (await StorageService.recordModePlayedToday(widget.gameModeId) &&
        mounted) {
      await bumpQuestMetric(context, 'modes_played', 1);
    }
    StorageService.recordDailyStreak();
    await StorageService.recordModeEverPlayed(widget.gameModeId);
    await _checkAchievements();

    setState(() {
      lives = savedLives;
      hintsBalance = savedHints;
      coinsBalance = savedCoins;
      _noBlur = noBlur;
      _unlimitedLives = unlimitedLives;
      _sessionAnswered = 0;
      // NU resetăm _sessionCorrect aici — spre deosebire de _sessionAnswered
      // (contorul de milestone-uri, care repornește la fiecare reîncărcare,
      // inclusiv după un upgrade de lot), _sessionCorrect trebuie să
      // supraviețuiască unui upgrade-continuare în mijlocul aceleiași
      // sesiuni PLĂTITE — altfel un upgrade la jumătatea sesiunii ar
      // "șterge" progresul real deja făcut, retrogradând treapta de
      // recompensă la ieșire (vezi _settleExitReward).
      _totalInCategory = forMode.length;
      questions = forMode.take(unlockedCount).toList()..shuffle(Random());
      qIndex = 0;
      _questionRewards.clear();
      for (final q in questions) {
        _questionRewards[q.id] =
            calculateSessionQuestionReward(q.maxPoints, Random());
      }
      _loadingQuestions = false;
      if (questions.isNotEmpty) _initQuestion();
    });
  }

  void _initQuestion() {
    hintsUsed = 0;
    answered = false;
    selectedAnswer = null;
    _fiftyFiftyOptions = null;
    _hintGuessOption = null;
    _hintGuessPercent = null;
    currentQuestionReward = _questionRewards[currentQ.id] ??
        calculateSessionQuestionReward(currentQ.maxPoints, Random());
  }

  /// Aceeași ordine amestecată, determinist, indiferent câte ori se apelează
  /// pentru aceeași întrebare (folosită și în build, și la calculul 50/50).
  List<String> _shuffledOptions(Question q) =>
      [...q.choices]..shuffle(Random(q.id.hashCode + qIndex));

  /// Taxa în monede a următorului hint — scalată cu averea curentă (vezi
  /// [hintCoinCost]). Recalculată la fiecare folosire, fiindcă averea se
  /// schimbă în timpul sesiunii.
  int get _hintCost => hintCoinCost(coinsBalance);

  /// Un hint costă un hint din stoc PLUS o taxă în monede — spre deosebire de
  /// varianta veche, unde costa puncte din scorul de sesiune (o resursă pe
  /// care nu o "ții", deci un cost invizibil). Scorul nu mai e afectat deloc.
  bool get _canAffordHint {
    if (answered || hintsUsed >= maxHintsPerQuestion) return false;
    return hintsBalance > 0;
  }

  void _addHint() {
    if (answered || hintsUsed >= maxHintsPerQuestion) return;
    final cost = _hintCost;
    if (hintsBalance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr('Nu mai ai hint-uri — cumpără din Magazin.',
                'You are out of hints — buy some from the Shop.')),
            duration: const Duration(milliseconds: 1400)),
      );
      return;
    }
    StorageService.spendHint().then((spent) async {
      if (!mounted || !spent) return;
      // taxa nu poate depăși niciodată averea (vezi hintCoinCost), deci
      // spendCoins nu are cum să eșueze aici — dar dacă totuși ar eșua,
      // hint-ul rămâne acordat, nu blocăm jucătorul pentru o monedă.
      if (cost > 0) await StorageService.spendCoins(cost);
      if (!mounted) return;
      setState(() {
        hintsUsed++;
        coinsBalance -= cost;
        hintsBalance--;
        // La al 2-lea hint: elimină 2 din cele 3 variante greșite, rămân
        // doar cea corectă + una greșită ("50/50").
        if (hintsUsed == 2 && _fiftyFiftyOptions == null) {
          final shuffled = _shuffledOptions(currentQ);
          final wrongKept =
              shuffled.firstWhere((o) => o != currentQ.answer);
          _fiftyFiftyOptions = [currentQ.answer, wrongKept]
            ..shuffle(Random(currentQ.id.hashCode + qIndex));
        }
        // La al 3-lea hint: evidențiază una din cele 2 variante rămase, cu
        // un procent de șansă afișat — NU e un răspuns garantat. Procentul
        // e generat aleator (20-80%), apoi decidem, cu exact acea
        // probabilitate, dacă varianta evidențiată e cea corectă sau cea
        // greșită rămasă — altfel jucătorul ar putea deduce mereu corect
        // urmărind highlight-ul, ceea ce ar face 50/50-ul de la hint 2
        // redundant.
        if (hintsUsed == 3 && _hintGuessOption == null) {
          final remaining = _fiftyFiftyOptions ?? _shuffledOptions(currentQ);
          final wrongRemaining =
              remaining.firstWhere((o) => o != currentQ.answer);
          final rng = Random();
          final pct = 20 + rng.nextInt(61); // 20..80
          final guessIsRight = rng.nextDouble() * 100 < pct;
          _hintGuessPercent = pct;
          _hintGuessOption = guessIsRight ? currentQ.answer : wrongRemaining;
        }
      });
      if (hintsUsed == 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(tr('50/50! 2 variante greșite au fost eliminate.',
                  '50/50! 2 wrong options have been removed.')),
              duration: const Duration(milliseconds: 1600)),
        );
      }
      bumpQuestMetric(context, 'hints_used', 1);
      StorageService.incrementHintsUsedTotal().then((_) {
        if (mounted) _checkAchievements();
      });
    });
  }

  void _selectAnswer(String opt) {
    if (answered) return;
    setState(() => selectedAnswer = opt);
    _resolveAnswer(opt == currentQ.answer);
  }

  Future<void> _resolveAnswer(bool correct) async {
    if (answered) return;
    // Punctele (scor de sesiune / record / clasament) rămân neschimbate;
    // monedele și XP-ul au acum formule proprii, decuplate de puncte (vezi
    // game_helpers.dart — XP-ul egal cu punctele era motivul pentru care se
    // ajungea la nivelul 5 în 16 răspunsuri corecte). Multiplicatorul se
    // aplică pe seria de DUPĂ acest răspuns, deci al 3-lea corect la rând e
    // deja plătit cu bonus.
    final pts = correct ? currentQuestionReward : 0;
    final multiplier = correct ? streakMultiplier(streak + 1) : 1.0;
    final coinsEarned = correct
        ? (coinsForCorrectAnswer(currentQ.maxPoints) * multiplier).round()
        : 0;
    final xpEarned = correct
        ? (xpForCorrectAnswer(currentQ.maxPoints) * multiplier).round()
        : 0;
    // verificat live (nu cache-uit la intrarea în ecran) — dacă bonusul de
    // 24h expiră la mijlocul sesiunii, următorul răspuns greșit trebuie deja
    // să scadă viața din nou.
    final unlimited =
        correct ? _unlimitedLives : await StorageService.hasUnlimitedLives();

    setState(() {
      answered = true;
      _unlimitedLives = unlimited;
      if (correct) {
        score += pts;
        streak++;
      } else {
        // doar plafon inferior — dacă viețile sunt peste 5 (bonus din
        // Cultură Generală / milestone-uri de sesiune), scăderea nu trebuie
        // să le reteze înapoi la 5. Cât timp vieți nelimitate e activ, nu
        // scade deloc.
        if (!unlimited) lives = lives > 0 ? lives - 1 : 0;
        streak = 0;
        _shakeController.forward(from: 0);
      }
    });

    if (lives <= 0 && !unlimited) {
      Future.delayed(const Duration(seconds: 1), _showGameOver);
    }

    // scrierile de mai jos sunt awaited (nu fire-and-forget) — ca punctele,
    // monedele și viețile să fie deja salvate pe disc înainte ca metoda
    // să se termine, chiar dacă utilizatorul iese brusc din joc imediat
    // după acest tap (buton Acasă / back).
    if (mounted) await bumpQuestMetric(context, 'answer_count', 1);
    _sessionAnswered++;
    if (correct) _sessionCorrect++;
    if (correct) {
      await StorageService.addCoins(coinsEarned);
      await StorageService.addXp(xpEarned);
      if (mounted) setState(() => coinsBalance += coinsEarned);
      await StorageService.addAnsweredId(currentQ.id);
      await StorageService.addLeaderboardPoints(widget.gameModeId, pts);
      if (mounted) await bumpQuestMetric(context, 'correct_count', 1);
      if (mounted) await bumpQuestMetric(context, 'coins_earned', coinsEarned);
      if (hintsUsed == 0 && mounted) {
        await bumpQuestMetric(context, 'no_hint_correct', 1);
      }
      if (streak == 3 && mounted) {
        await bumpQuestMetric(context, 'streak_hit_3', 1);
      }
      if (streak == 5 && mounted) {
        await bumpQuestMetric(context, 'streak_hit_5', 1);
      }
      if (streak == 8 && mounted) {
        await bumpQuestMetric(context, 'streak_hit_8', 1);
      }
      if (streak == 10 && mounted) {
        await bumpQuestMetric(context, 'streak_hit_10', 1);
      }
      // salvăm recordul pe loc, nu doar la finalul sesiunii — altfel un
      // jucător care iese din joc la jumătate (buton Acasă) pierde scorul.
      await StorageService.updateHighScore(score);
      await StorageService.updateModeHighScore(widget.gameModeId, score);
      await _checkAchievements();
    } else {
      await StorageService.setLives(lives);
    }
    await _checkSessionMilestone();
  }

  /// La fiecare 10 întrebări răspunse în sesiunea curentă (corect sau
  /// greșit — la fel ca quest-ul "answer_10" de mai sus), acordă un bonus
  /// progresiv (vezi [gameModeMilestoneReward]): monede + XP care cresc cu
  /// fiecare prag, +1 viață mereu, și gems abia de la al treilea prag (30 de
  /// întrebări — semn că ai "ajuns departe"). Arătat printr-un banner, la fel
  /// ca la quest/achievement — GameScreen n-are pastile-țintă spre care să
  /// zboare o animație de recompensă ca pe Home.
  Future<void> _checkSessionMilestone() async {
    if (_sessionAnswered % 10 != 0) return;
    final milestone = _sessionAnswered ~/ 10;
    final reward = gameModeMilestoneReward(milestone);
    final grantsLife = milestoneGrantsLife(milestone);
    await StorageService.addCoins(reward.coins);
    await StorageService.addXp(reward.xp);
    if (reward.gems > 0) await StorageService.addGems(reward.gems);
    if (grantsLife) await StorageService.addLivesUncapped(1);
    if (!mounted) return;
    setState(() {
      coinsBalance += reward.coins;
      if (grantsLife) lives += 1;
    });
    Sfx.rewardPop();
    InAppNotification.show(
      context,
      title: tr('Bonus la $_sessionAnswered întrebări! 🎁',
          'Bonus at $_sessionAnswered questions! 🎁'),
      message: '+${reward.coins} ${tr('monede', 'coins')}, +${reward.xp} XP'
          '${grantsLife ? ', +1 ❤️' : ''}'
          '${reward.gems > 0 ? ', +${reward.gems} 💎' : ''}',
      icon: Icons.military_tech_rounded,
      color: AppColors.coin,
      onTap: () {},
    );
  }

  /// Verifică toate realizările permanente și anunță, pe rând, orice a
  /// fost tocmai deblocată.
  Future<void> _checkAchievements() async {
    final newlyDone = await StorageService.checkNewlyCompletedAchievements();
    if (!mounted || newlyDone.isEmpty) return;
    for (var i = 0; i < newlyDone.length; i++) {
      if (!mounted) return;
      final a = newlyDone[i];
      Sfx.tileSelect();
      InAppNotification.show(
        context,
        title: tr('Realizare deblocată! 🏆', 'Achievement unlocked! 🏆'),
        message: a.title,
        icon: a.icon,
        color: const Color(0xFFFF7A1A),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AchievementsScreen())),
      );
      if (i < newlyDone.length - 1) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
  }

  void _nextQuestion() {
    // dacă viețile au ajuns la 0, dialogul de Game Over e deja programat
    // să apară — nu mai trecem la întrebarea următoare între timp.
    if (lives <= 0) return;
    if (qIndex + 1 >= questions.length) {
      _showFinishedDialog();
      return;
    }
    setState(() {
      qIndex += 1;
      _initQuestion();
    });
  }

  /// Punctul UNIC de ieșire din GameScreen (săgeata din bara de sus, back-ul
  /// telefonului — vezi PopScope din build — și butoanele "Acasă" din
  /// dialoguri) — de-asta recompensa de ieșire se decontează AICI, o
  /// singură dată, indiferent pe ce ușă ai plecat.
  Future<void> _goHome() async {
    await _settleExitReward();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LoadingScreen(
            nextBuilder: (_) => const HomeScreen(),
            duration: const Duration(milliseconds: 900)),
      ),
    );
  }

  /// Dacă sesiunea asta a fost plătită (vezi widget.entryFeePaid), acordă
  /// recompensa în trepte din [categoryExitReward] și arată o notificare
  /// NESKIPUIBILĂ (fără tap-outside, fără back — trebuie apăsat butonul) cu
  /// exact ce s-a primit, înainte să se poată pleca mai departe spre Acasă.
  /// Idempotent — [_exitRewardSettled] garantează o singură decontare chiar
  /// dacă [_goHome] ar fi apelat de mai multe ori.
  Future<void> _settleExitReward() async {
    if (_exitRewardSettled || widget.entryFeePaid <= 0) return;
    _exitRewardSettled = true;
    final reward = categoryExitReward(_sessionCorrect, widget.entryFeePaid);
    await StorageService.addCoins(reward);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1a1a2e),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(tr('Recompensă la ieșire', 'Payout on exit'),
              style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  '$_sessionCorrect ${_sessionCorrect == 1 ? 'răspuns corect' : 'răspunsuri corecte'} în sesiunea asta (taxă plătită: ${widget.entryFeePaid} monede).',
                  '$_sessionCorrect correct ${_sessionCorrect == 1 ? 'answer' : 'answers'} this session (fee paid: ${widget.entryFeePaid} coins).',
                ),
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  'Praguri: 4 corecte → 60% din taxă · 8 → taxa întreagă · 15 → +30%.',
                  'Thresholds: 4 correct → 60% of the fee · 8 → the whole fee · 15 → +30%.',
                ),
                style: const TextStyle(color: Colors.white38, fontSize: 11.5),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.monetization_on_rounded,
                      color: AppColors.coin, size: 28),
                  const SizedBox(width: 8),
                  Text('+$reward ${tr('monede', 'coins')}',
                      style: const TextStyle(
                          color: AppColors.coin,
                          fontSize: 22,
                          fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.play),
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('Am înțeles', 'Got it'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // Fără opțiune de "Reîncepe" — nu are sens ca la Game Over (0 vieți) să
  // poți reporni instant cu viețile refăcute; singura ieșire e Acasă.
  void _showEndDialog(
      {required String title,
      required String message,
      List<Widget> extraActions = const []}) {
    StorageService.updateHighScore(score);
    StorageService.updateModeHighScore(widget.gameModeId, score);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          ...extraActions,
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF534AB7)),
            onPressed: () {
              // închide ÎNTÂI acest dialog — altfel notificarea de recompensă
              // din _goHome (vezi _settleExitReward) s-ar deschide peste el.
              Navigator.pop(dialogContext);
              _goHome();
            },
            child: Text(tr('Acasă', 'Home'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Dacă mai sunt întrebări dincolo de lotul curent deblocat, arată și un
  /// buton de deblocare (Gems) — vezi StorageService.unlockNextQuestionBatch.
  /// La succes, dialogul se închide și ecranul se reîncarcă direct cu noul
  /// lot, ca jucătorul să poată continua pe loc, fără să mai treacă prin
  /// Acasă și să reintre în categorie.
  Future<void> _showFinishedDialog() async {
    final locked = _totalInCategory - questions.length;
    List<Widget> extraActions = const [];
    if (locked > 0) {
      final tier = await StorageService.getUnlockedTier(widget.gameModeId);
      if (!mounted) return;
      if (tier < maxUnlockTier) {
        final price = questionUnlockGemsPrice(tier + 1);
        final batch = min(questionUnlockBatch, locked);
        extraActions = [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.coin),
            onPressed: () async {
              final ok = await StorageService.unlockNextQuestionBatch(
                  widget.gameModeId);
              if (!mounted) return;
              if (ok) {
                await bumpQuestMetric(context, 'question_batch_unlocked', 1);
                if (!mounted) return;
                await bumpQuestMetric(context, 'shop_spend', 1);
                if (!mounted) return;
                Navigator.pop(context);
                await CategoryUnlockAnimation.show(
                  context,
                  categoryTitle: mode.title,
                  unlockedCount: batch,
                );
                if (!mounted) return;
                _loadQuestions();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Nu ai destule gems.'),
                      duration: Duration(milliseconds: 1400)),
                );
              }
            },
            child: Text('Upgrade +$batch  •  💎 $price',
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.w800)),
          ),
        ];
      }
    }
    final lockedNote = extraActions.isNotEmpty
        ? tr('\n\n$locked întrebări mai sunt de deblocat în această categorie.',
            '\n\n$locked more questions can still be unlocked in this category.')
        : (locked > 0
            ? tr('\n\nAi atins nivelul maxim de upgrade pentru această categorie.',
                '\n\nYou have reached the maximum upgrade level for this category.')
            : '');
    _showEndDialog(
      title: tr('Ai terminat toate întrebările! 🎉', 'You finished every question! 🎉'),
      message: tr(
          'Ai răspuns la ${questions.length} întrebări în modul ${mode.title}.\nScor final: $score$lockedNote',
          'You answered ${questions.length} questions in ${mode.title}.\nFinal score: $score$lockedNote'),
      extraActions: extraActions,
    );
  }

  /// Game Over (0 vieți) e singurul caz cu opțiune de continuare: un buton
  /// auriu "Reclamă" (reclamă recompensată reală prin [AdsService]) acordă
  /// vieți+hint-uri prin [collectRewards] și reia jocul chiar de unde a rămas
  /// (întrebarea era
  /// deja dezvăluită, cu butonul "Următoarea" gata de tap). Plafonat la
  /// câteva vizionări/zi (vezi StorageService.canClaimRewardedAdReward) —
  /// reclama e un supliment, nu principala sursă de resurse. Dacă plafonul
  /// e atins sau nu vrea reclama, "Acasă" se comportă ca înainte.
  void _showGameOver() async {
    StorageService.updateHighScore(score);
    StorageService.updateModeHighScore(widget.gameModeId, score);
    final canWatchAd = await StorageService.canClaimRewardedAdReward();
    if (!mounted) return;
    var watchingAd = false;
    var adWatched = false;
    final adLivesKey = GlobalKey();
    final adHintsKey = GlobalKey();
    final adCoinsKey = GlobalKey();
    const adReward = StorageService.rewardedAdReward;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a2e),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Game Over! 💀',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Scor final: $score puncte\nSeria: $streak', 'Final score: $score points\nStreak: $streak'),
                  style: const TextStyle(color: Colors.white70)),
              if (adWatched) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _adMiniBadge(
                        adLivesKey, Icons.favorite_rounded, AppColors.life),
                    const SizedBox(width: 14),
                    _adMiniBadge(adHintsKey, Icons.tips_and_updates_rounded,
                        AppColors.hint),
                    const SizedBox(width: 14),
                    _adMiniBadge(adCoinsKey, Icons.monetization_on_rounded,
                        AppColors.coin),
                  ],
                ),
              ] else if (!canWatchAd) ...[
                const SizedBox(height: 12),
                const Text('Ai atins plafonul zilnic de reclame.',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            if (canWatchAd && !adWatched)
              ElevatedButton(
                onPressed: watchingAd
                    ? null
                    : () async {
                        setDialogState(() => watchingAd = true);
                        var earnedReward = false;
                        final adShown = await AdsService.instance.showRewarded(
                          onReward: () => earnedReward = true,
                        );
                        if (!adShown) {
                          // reclama nu era incarcata - simuleaza asteptarea in loc sa blocheze recompensa.
                          await Future.delayed(
                              const Duration(milliseconds: 900));
                          earnedReward = true;
                        }
                        if (!dialogContext.mounted) return;
                        if (!earnedReward) {
                          setDialogState(() => watchingAd = false);
                          return;
                        }
                        final reward =
                            await StorageService.claimRewardedAdReward();
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          watchingAd = false;
                          adWatched = true;
                        });
                        // asteapta un frame ca badge-urile (ascunse pana acum, sub
                        // "adWatched") sa fie randate - altfel prima animatie (vieti)
                        // nu gaseste GlobalKey-ul montat si cade pe fallback dreapta-sus.
                        await WidgetsBinding.instance.endOfFrame;
                        if (!dialogContext.mounted) return;
                        await collectRewards(
                          dialogContext,
                          coins: reward.coins,
                          xp: 0,
                          lives: reward.hearts,
                          hints: reward.hints,
                          coinBadgeKey: adCoinsKey,
                          xpBadgeKey: GlobalKey(),
                          livesBadgeKey: adLivesKey,
                          hintsBadgeKey: adHintsKey,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        if (!mounted) return;
                        _continueAfterAd(reward);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.coin,
                  disabledBackgroundColor: Colors.white24,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  watchingAd
                      ? tr('Se încarcă reclama...', 'Loading the ad...')
                      : '${tr('Reclamă', 'Watch ad')}  •  +${adReward.hearts} ❤ +${adReward.hints} 💡 +${adReward.coins} 💰',
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.w800),
                ),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF534AB7)),
              onPressed: watchingAd
                  ? null
                  : () {
                      // vezi _showEndDialog — închide dialogul curent ÎNTÂI,
                      // ca notificarea de recompensă din _goHome să nu se
                      // deschidă peste el.
                      Navigator.pop(dialogContext);
                      _goHome();
                    },
              child: Text(tr('Acasă', 'Home'), style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adMiniBadge(GlobalKey key, IconData icon, Color color) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white.withAlpha(15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24)),
      child: Icon(icon, color: color, size: 20),
    );
  }

  void _continueAfterAd(AdRewardResult reward) {
    setState(() {
      lives = reward.hearts;
      hintsBalance += reward.hints;
      coinsBalance += reward.coins;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingQuestions) {
      return const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: Color(0xFF9A5AFB))));
    }

    if (questions.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.white24),
              const SizedBox(height: 16),
              Text(tr('Nicio întrebare disponibilă pentru acest mod.',
                      'No questions available for this mode.'),
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _goHome, child: Text(tr('Înapoi la meniu', 'Back to the menu'))),
            ],
          ),
        ),
      );
    }

    final q = currentQ;
    final opts = _fiftyFiftyOptions ?? _shuffledOptions(q);

    // back-ul telefonului (gest sau buton fizic) trebuie să treacă prin
    // aceeași ieșire ca săgeata din bara de sus — altfel un jucător care
    // taxa sesiunii ar putea ieși fără să decontăm recompensa (vezi
    // _goHome/_settleExitReward).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goHome();
      },
      child: Scaffold(
        body: Container(
          decoration:
              BoxDecoration(gradient: buildQuestionGradient(q.id, q.color)),
          child: SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: Column(
                      children: [
                        // Imaginea (dimensiune fixă 4:3, constantă înainte și
                        // după răspuns) cu eticheta categoriei prinsă pe
                        // marginea de sus, ca un tab pe ramă — economisește
                        // rândul separat de badge de dinainte.
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedBuilder(
                              animation: _shakeController,
                              builder: (_, child) {
                                final shake =
                                    sin(_shakeController.value * pi * 6) * 8;
                                return Transform.translate(
                                    offset: Offset(shake, 0), child: child);
                              },
                              child: BlurImage(
                                color: q.color,
                                answer: q.answer,
                                revealed: answered,
                                hintsUsed: hintsUsed,
                                imageAssetPath: q.imageAssetPath,
                                noBlur: _noBlur,
                              ),
                            ),
                            Positioned(
                                top: -9,
                                left: 14,
                                child: _buildQuestionBadge(q)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _buildRevealRow(q),
                        // După răspuns, butonul de continuare apare CHIAR aici,
                        // sub rândul "Claritate" — nu la baza ecranului — ca să
                        // fie vizibil fără scroll. Nu mai afișăm un banner de
                        // "Corect/Greșit": varianta corectă e deja evidențiată
                        // pe grila de opțiuni, deci ar fi redundant.
                        if (answered) ...[
                          const SizedBox(height: 6),
                          NextButton(onTap: _nextQuestion),
                        ],
                        if (hintsUsed > 0 && !answered) ...[
                          const SizedBox(height: 6),
                          _buildHintCard(q),
                        ],
                        const SizedBox(height: 8),
                        // În loc de întrebarea generică "Cine / ce este?", un
                        // indiciu mic (primul hint) despre ce e în poză — gratuit.
                        _buildClue(q),
                        const SizedBox(height: 6),
                        if (!answered && _hintGuessPercent != null) ...[
                          _buildConfidenceHint(),
                          const SizedBox(height: 6),
                        ],
                        _buildOptionsGrid(q, opts),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Rândul fix de 5 inimioare nu poate arăta vieți peste 5 (bonus de la
  /// milestone-uri de sesiune sau Cultură Generală) — peste acel prag,
  /// devine o singură inimă + cifră; cât timp vieți nelimitate e activ,
  /// devine simbolul de infinit, ca bonusul să fie efectiv vizibil.
  Widget _buildHeartsDisplay() {
    if (_unlimitedLives) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.all_inclusive_rounded, color: Color(0xFFE24B4A), size: 20),
        ],
      );
    }
    if (lives > 5) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite_rounded,
              color: Color(0xFFE24B4A), size: 20),
          const SizedBox(width: 4),
          Text('×$lives',
              style: const TextStyle(
                  color: Color(0xFFE24B4A),
                  fontWeight: FontWeight.w800,
                  fontSize: 14)),
        ],
      );
    }
    return Row(
      children: List.generate(
        5,
        (i) => Icon(
          i < lives ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: i < lives ? const Color(0xFFE24B4A) : Colors.white24,
          size: 20,
        ),
      ),
    );
  }

  /// Afișat lângă vieți, ca jucătorul să poată urmări din prima privire câte
  /// hint-uri mai are, nu doar viețile.
  Widget _buildHintsDisplay() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.tips_and_updates_rounded,
            color: AppColors.hint, size: 20),
        const SizedBox(width: 4),
        Text('×$hintsBalance',
            style: const TextStyle(
                color: AppColors.hint,
                fontWeight: FontWeight.w800,
                fontSize: 14)),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.arrow_back_ios_rounded,
                    color: Colors.white70),
                onPressed: _goHome,
              ),
              const SizedBox(width: 8),
              _buildHeartsDisplay(),
              const SizedBox(width: 10),
              _buildHintsDisplay(),
              const Spacer(),
              if (streak > 1)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF9F27).withAlpha(51),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFFEF9F27).withAlpha(128)),
                  ),
                  child: Text('🔥 $streak',
                      style: const TextStyle(
                          color: Color(0xFFEF9F27), fontSize: 13)),
                ),
              const SizedBox(width: 8),
              Text('$score pct',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                  tr('Întrebarea ${qIndex + 1} din ${questions.length}',
                      'Question ${qIndex + 1} of ${questions.length}'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const Spacer(),
              ReportQuestionButton(
                questionId: currentQ.id,
                questionText: currentQ.answer,
                category: currentQ.category,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionBadge(Question q) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF141B36),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: q.color, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
      ),
      child: Text(q.category,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700)),
    );
  }

  /// Indiciu mic, gratuit, afișat mereu în locul vechii etichete
  /// "Cine / ce este?" — primul hint al întrebării, ca un punct de plecare
  /// despre ce ar putea fi în poză (hint-urile plătite dezvăluie restul).
  Widget _buildClue(Question q) {
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
            child: Text(
              q.hint1,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevealRow(Question q) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Claritate: ${(resolveHintExposure(hintsUsed) * 100).round()}%',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        // Când s-a răspuns, rândul rămâne doar cu "Claritate" — Hint și Skip
        // dispar (butonul Următoarea întrebare apare imediat sub acest rând).
        if (!answered)
          Row(
            children: [
              _buildHintButton(),
              // Skip e disponibil doar cu modul "poze clare" (fără blur)
              // activat — altfel ar permite sărirea pozelor fără nicio taxă.
              if (_noBlur) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _nextQuestion,
                  style: TextButton.styleFrom(foregroundColor: Colors.white54),
                  child: const Text('Skip'),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildHintButton() {
    final enabled = _canAffordHint;
    final fg = enabled ? Colors.white54 : Colors.white24;
    return GestureDetector(
      onTap: _addHint,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: enabled ? Colors.white10 : Colors.white.withAlpha(5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: enabled ? Colors.white24 : Colors.white10),
        ),
        child: Row(
          children: [
            Icon(Icons.tips_and_updates_rounded, color: fg, size: 16),
            const SizedBox(width: 4),
            Text(
              'Hint (-$_hintCost 💰) • $hintsBalance',
              style: TextStyle(color: fg, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// Textul de "șansă" al hint-ului 3 — vezi [_hintGuessOption]: procentul
  /// e informativ, nu o garanție, deci fraza clarifică asta explicit ca
  /// jucătorul să nu tragă concluzia greșită că highlight-ul = răspunsul.
  Widget _buildConfidenceHint() {
    return Text(
      tr('Șansă răspuns corect: $_hintGuessPercent% (nu e o garanție)',
          'Chance of being right: $_hintGuessPercent% (not a guarantee)'),
      style: const TextStyle(
        color: Color(0xFFFFC107),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildHintCard(Question q) {
    // hint_1 e deja arătat gratuit ca indiciu (vezi [_buildClue]) — hint-urile
    // plătite dezvăluie hint_2, apoi hint_3.
    final hintText = switch (hintsUsed) { 1 => q.hint2, _ => q.hint3 };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: q.color.withAlpha((0.1 * 255).round()),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: q.color.withAlpha((0.3 * 255).round())),
      ),
      child: Text(hintText,
          style: TextStyle(color: q.color, fontSize: 13),
          textAlign: TextAlign.center),
    );
  }

  /// Cele 4 variante ca listă verticală de rânduri cu literă (A/B/C/D) —
  /// același stil, indiferent de gamemod (cartoon, logo-uri, gamers cave,
  /// medical etc.), doar conținutul (opts) diferă.
  Widget _buildOptionsGrid(Question q, List<String> opts) {
    const letters = ['A', 'B', 'C', 'D'];
    return Column(
      children: List.generate(opts.length, (i) {
        final opt = opts[i];
        var btnColor = Colors.white.withAlpha(18);
        Gradient? btnGradient;
        var borderColor = Colors.white24;
        var textColor = Colors.white;
        var letterBg = Colors.white.withAlpha(30);

        if (answered) {
          if (opt == q.answer) {
            btnColor = const Color(0xFF1D9E75).withAlpha(70);
            borderColor = const Color(0xFF1D9E75);
            letterBg = const Color(0xFF1D9E75);
          } else if (opt == selectedAnswer) {
            btnColor = const Color(0xFFE24B4A).withAlpha(70);
            borderColor = const Color(0xFFE24B4A);
            letterBg = const Color(0xFFE24B4A);
          }
        } else if (opt == _hintGuessOption) {
          // Highlight "de șansă" (hint 3) — gradient distinct de
          // verde/roșu (rezervate răspunsului efectiv), ca să nu pară o
          // confirmare certă. Vezi procentul afișat în _buildConfidenceHint.
          btnGradient = const LinearGradient(
            colors: [Color(0xFFFFB300), Color(0xFF9A5AFB)],
          );
          borderColor = const Color(0xFFFFC107);
          letterBg = const Color(0xFF9A5AFB);
        }

        return Padding(
          padding: EdgeInsets.only(bottom: i == opts.length - 1 ? 0 : 6),
          child: GestureDetector(
            onTap: answered ? null : () => _selectAnswer(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: btnGradient == null ? btnColor : null,
                gradient: btnGradient,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 1.5),
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
                        style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 12)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      opt,
                      style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
