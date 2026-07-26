import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/game_helpers.dart';
import '../core/gamemodes.dart';
import '../core/progression.dart';
import '../core/reward_collector.dart';
import '../core/theme.dart';
import '../data/questions.dart';
import '../data/storage_service.dart';
import '../models/question.dart';
import '../widgets/blur_image.dart';
import '../widgets/in_app_notification.dart';
import '../widgets/next_button.dart';
import 'achievements_screen.dart';
import 'home_screen.dart';
import 'loading_screen.dart';
import 'quests_screen.dart';

/// Un singur ecran de joc pentru toate gamemodurile: fiecare întrebare
/// arată o imagine care se limpezește cu fiecare hint și 4 variante de
/// răspuns — aceeași mecanică peste tot (pixelat, logo-uri, gamers cave,
/// medical), doar conținutul (întrebări/poze/culori) diferă.
class GameScreen extends StatefulWidget {
  final String gameModeId;
  const GameScreen({super.key, required this.gameModeId});

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
  int currentQuestionReward = 0;
  final Map<String, int> _questionRewards = {};
  bool answered = false;
  String? selectedAnswer;
  bool _noBlur = false;
  late final AnimationController _shakeController;

  GameMode get mode => gameModeById(widget.gameModeId);
  Question get currentQ =>
      questions.isNotEmpty ? questions[qIndex] : throw StateError('No questions');

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _loadQuestions();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    final results = await Future.wait([loadAllQuestions(), StorageService.getLives(), StorageService.getNoBlurMode(), StorageService.getHints()]);
    final loaded = results[0] as List<Question>;
    final savedLives = results[1] as int;
    final noBlur = results[2] as bool;
    final savedHints = results[3] as int;

    if (await StorageService.recordModePlayedToday(widget.gameModeId)) {
      final newModesToday = await StorageService.getQuestProgress('play_two_modes');
      if (newModesToday < 2) {
        await _bumpQuest('play_two_modes', 1);
      }
    }
    StorageService.recordDailyStreak();
    await StorageService.recordModeEverPlayed(widget.gameModeId);
    await _checkAchievements();

    setState(() {
      lives = savedLives;
      hintsBalance = savedHints;
      _noBlur = noBlur;
      questions = loaded.where((q) => q.categoryId == widget.gameModeId).toList()..shuffle(Random());
      qIndex = 0;
      _questionRewards.clear();
      for (final q in questions) {
        _questionRewards[q.id] = calculateSessionQuestionReward(q.maxPoints, Random());
      }
      _loadingQuestions = false;
      if (questions.isNotEmpty) _initQuestion();
    });
  }

  void _initQuestion() {
    hintsUsed = 0;
    answered = false;
    selectedAnswer = null;
    currentQuestionReward =
        _questionRewards[currentQ.id] ?? calculateSessionQuestionReward(currentQ.maxPoints, Random());
  }

  int get _hintCost => calculateHintPenalty(currentQuestionReward, currentQ.maxPoints);

  /// Un hint costă atât puncte din scorul acumulat CÂT ȘI un hint din
  /// balanța persistată (aceeași resursă afișată pe Home, lângă vieți și
  /// monede) — trebuie să ai și destule puncte, și cel puțin 1 hint deținut.
  bool get _canAffordHint {
    if (answered || hintsUsed >= maxHintsPerQuestion) return false;
    return score >= _hintCost && hintsBalance > 0;
  }

  void _addHint() {
    if (answered || hintsUsed >= maxHintsPerQuestion) return;
    final cost = _hintCost;
    if (hintsBalance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nu mai ai hint-uri — cumpără din Magazin.'), duration: Duration(milliseconds: 1400)),
      );
      return;
    }
    if (score < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ai nevoie de $cost puncte pentru un hint (ai $score).'), duration: const Duration(milliseconds: 1400)),
      );
      return;
    }
    StorageService.spendHint().then((spent) {
      if (!mounted || !spent) return;
      setState(() {
        hintsUsed++;
        score -= cost; // hint-ul se scade din scorul acumulat
        hintsBalance--;
      });
      _bumpQuest('use_hints_3', 1);
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
    // Recompensa completă la răspuns corect — hint-urile NU o mai reduc,
    // fiindcă se plătesc separat, din scorul acumulat, chiar la folosire
    // (vezi [_addHint]).
    final pts = correct ? currentQuestionReward : 0;
    final coinsEarned = correct ? pts ~/ 10 : 0;

    setState(() {
      answered = true;
      if (correct) {
        score += pts;
        streak++;
      } else {
        // doar plafon inferior — dacă viețile sunt peste 5 (bonus din
        // Cultură Generală), scăderea nu trebuie să le retează înapoi la 5.
        lives = lives > 0 ? lives - 1 : 0;
        streak = 0;
        _shakeController.forward(from: 0);
      }
    });

    if (lives <= 0) {
      Future.delayed(const Duration(seconds: 1), _showGameOver);
    }

    // scrierile de mai jos sunt awaited (nu fire-and-forget) — ca punctele,
    // monedele și viețile să fie deja salvate pe disc înainte ca metoda
    // să se termine, chiar dacă utilizatorul iese brusc din joc imediat
    // după acest tap (buton Acasă / back).
    await _bumpQuest('answer_10', 1);
    if (correct) {
      await StorageService.addCoins(coinsEarned);
      await StorageService.addXp(pts);
      await StorageService.addAnsweredId(currentQ.id);
      await _bumpQuest('correct_5', 1);
      await _bumpQuest('earn_60_coins', coinsEarned);
      if (hintsUsed == 0) await _bumpQuest('no_hint_3', 1);
      if (streak == 3) await _bumpQuest('streak_3', 1);
      // salvăm recordul pe loc, nu doar la finalul sesiunii — altfel un
      // jucător care iese din joc la jumătate (buton Acasă) pierde scorul.
      await StorageService.updateHighScore(score);
      await StorageService.updateModeHighScore(widget.gameModeId, score);
      await _checkAchievements();
    } else {
      await StorageService.setLives(lives);
    }
  }

  /// Adaugă progres la un quest zilnic; dacă tocmai a atins ținta (și nu
  /// e deja revendicat), arată o notificare in-app spre ecranul de Quests.
  Future<void> _bumpQuest(String questId, int amount) async {
    final updated = await StorageService.addQuestProgress(questId, amount);
    if (!mounted) return;
    final quest = questById(questId);
    final justCompleted = updated >= quest.target && (updated - amount) < quest.target;
    if (!justCompleted) return;
    final alreadyClaimed = await StorageService.isQuestClaimed(questId);
    if (alreadyClaimed || !mounted) return;
    Sfx.tileSelect();
    InAppNotification.show(
      context,
      title: 'Quest completat! 🎯',
      message: quest.title,
      icon: quest.icon,
      color: const Color(0xFF534AB7),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuestsScreen())),
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
        title: 'Realizare deblocată! 🏆',
        message: a.title,
        icon: a.icon,
        color: const Color(0xFFFF7A1A),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AchievementsScreen())),
      );
      if (i < newlyDone.length - 1) await Future.delayed(const Duration(milliseconds: 400));
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

  void _goHome() => Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LoadingScreen(nextBuilder: (_) => const HomeScreen(), duration: const Duration(milliseconds: 900)),
        ),
      );

  // Fără opțiune de "Reîncepe" — nu are sens ca la Game Over (0 vieți) să
  // poți reporni instant cu viețile refăcute; singura ieșire e Acasă.
  void _showEndDialog({required String title, required String message}) {
    StorageService.updateHighScore(score);
    StorageService.updateModeHighScore(widget.gameModeId, score);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF534AB7)),
            onPressed: _goHome,
            child: const Text('Acasă', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showFinishedDialog() {
    _showEndDialog(
      title: 'Ai terminat toate întrebările! 🎉',
      message: 'Ai răspuns la ${questions.length} întrebări în modul ${mode.title}.\nScor final: $score',
    );
  }

  /// Game Over (0 vieți) e singurul caz cu opțiune de continuare: un buton
  /// auriu "Reclamă" (simulată — fără SDK real) acordă +2 vieți/+5 hint-uri
  /// prin [collectRewards] (fără plafon de folosiri în acest MVP — decizie
  /// simplă, ajustabilă ulterior) și reia jocul chiar de unde a rămas
  /// (întrebarea era deja dezvăluită, cu butonul "Următoarea" gata de tap).
  /// Dacă nu vrea reclama, "Acasă" se comportă ca înainte.
  void _showGameOver() {
    StorageService.updateHighScore(score);
    StorageService.updateModeHighScore(widget.gameModeId, score);
    var watchingAd = false;
    var adWatched = false;
    final adLivesKey = GlobalKey();
    final adHintsKey = GlobalKey();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a2e),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Game Over! 💀', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Scor final: $score puncte\nSeria: $streak', style: const TextStyle(color: Colors.white70)),
              if (adWatched) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _adMiniBadge(adLivesKey, Icons.favorite_rounded, AppColors.life),
                    const SizedBox(width: 14),
                    _adMiniBadge(adHintsKey, Icons.tips_and_updates_rounded, AppColors.hint),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            if (!adWatched)
              ElevatedButton(
                onPressed: watchingAd
                    ? null
                    : () async {
                        setDialogState(() => watchingAd = true);
                        // simuleaza vizionarea unei reclame - fara SDK real.
                        await Future.delayed(const Duration(milliseconds: 900));
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          watchingAd = false;
                          adWatched = true;
                        });
                        await collectRewards(
                          dialogContext,
                          coins: 0,
                          xp: 0,
                          lives: 2,
                          hints: 5,
                          coinBadgeKey: GlobalKey(),
                          xpBadgeKey: GlobalKey(),
                          livesBadgeKey: adLivesKey,
                          hintsBadgeKey: adHintsKey,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        if (!mounted) return;
                        _continueAfterAd();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.coin,
                  disabledBackgroundColor: Colors.white24,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  watchingAd ? 'Se încarcă reclama...' : 'Reclamă  •  +2 ❤ +5 💡',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
                ),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF534AB7)),
              onPressed: watchingAd ? null : _goHome,
              child: const Text('Acasă', style: TextStyle(color: Colors.white)),
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
      decoration: BoxDecoration(color: Colors.white.withAlpha(15), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white24)),
      child: Icon(icon, color: color, size: 20),
    );
  }

  void _continueAfterAd() {
    setState(() {
      lives = 2;
      hintsBalance += 5;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingQuestions) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF9A5AFB))));
    }

    if (questions.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.white24),
              const SizedBox(height: 16),
              const Text('Nicio întrebare disponibilă pentru acest mod.',
                  style: TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _goHome, child: const Text('Înapoi la meniu')),
            ],
          ),
        ),
      );
    }

    final q = currentQ;
    final opts = [...q.choices]..shuffle(Random(q.id.hashCode + qIndex));

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: buildQuestionGradient(q.id, q.color)),
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
                              final shake = sin(_shakeController.value * pi * 6) * 8;
                              return Transform.translate(offset: Offset(shake, 0), child: child);
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
                          Positioned(top: -9, left: 14, child: _buildQuestionBadge(q)),
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
                icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                onPressed: _goHome,
              ),
              const SizedBox(width: 8),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < lives ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: i < lives ? const Color(0xFFE24B4A) : Colors.white24,
                    size: 20,
                  ),
                ),
              ),
              const Spacer(),
              if (streak > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF9F27).withAlpha(51),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFEF9F27).withAlpha(128)),
                  ),
                  child: Text('🔥 $streak', style: const TextStyle(color: Color(0xFFEF9F27), fontSize: 13)),
                ),
              const SizedBox(width: 8),
              Text('$score pct', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('Întrebarea ${qIndex + 1} din ${questions.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
      child: Text(q.category, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
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
              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500),
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
              const SizedBox(width: 8),
              TextButton(
                onPressed: _nextQuestion,
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
                child: const Text('Skip'),
              ),
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
              'Hint (-${calculateHintPenalty(currentQuestionReward, currentQ.maxPoints)} pts) • $hintsBalance',
              style: TextStyle(color: fg, fontSize: 12),
            ),
          ],
        ),
      ),
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
      child: Text(hintText, style: TextStyle(color: q.color, fontSize: 13), textAlign: TextAlign.center),
    );
  }

  /// Cele 4 variante ca listă verticală de rânduri cu literă (A/B/C/D) —
  /// același stil, indiferent de gamemod (pixelat, logo-uri, gamers cave,
  /// medical etc.), doar conținutul (opts) diferă.
  Widget _buildOptionsGrid(Question q, List<String> opts) {
    const letters = ['A', 'B', 'C', 'D'];
    return Column(
      children: List.generate(opts.length, (i) {
        final opt = opts[i];
        var btnColor = Colors.white.withAlpha(18);
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
                color: btnColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: letterBg, shape: BoxShape.circle),
                    child: Text(letters[i], style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      opt,
                      style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
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
