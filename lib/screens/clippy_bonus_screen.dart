import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/game_helpers.dart';
import '../core/quest_bump.dart';
import '../core/reward_collector.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/questions.dart';
import '../data/storage_service.dart';
import '../models/question.dart';
import '../widgets/blur_image.dart';
import '../widgets/mascots/googly_eyes.dart';

const int clippyBonusQuestionCount = 3;

enum _ClippyPhase { intro, loading, playing, finished }

/// Câte vieți se acordă la un răspuns perfect (toate întrebările corecte).
const int clippyPerfectBonusLives = 1;

/// Bonusul lui Clippy: 3 întrebări alese complet aleatoriu din TOATE
/// categoriile deblocate (bazele de date reale, cu poze — nu pool-ul text
/// separat al Culturii Generale), plus o viață bonus dacă ieși perfect
/// (toate 3 corecte). Fără pierdere de vieți — un răspuns greșit doar nu
/// aduce recompensă, e un bonus fără risc. Ecran separat (nu panou pe Home)
/// — declanșat de [PaperclipMascot] când are o "notificare" activă.
///
/// Regula economică (vezi [clippyRewardMultiplier]): o întrebare de aici
/// plătește STRICT mai mult decât una din gameplay-ul normal — înainte
/// plătea 0,85×, adică mai puțin. Rămâne totuși mic în absolut (3 întrebări)
/// și limitat la [clippyDailyPlayLimit] runde pe zi calendaristică (cu 5
/// minute de cooldown între ele), ca să nu poată fi farmat la 12 runde pe oră.
class ClippyBonusScreen extends StatefulWidget {
  const ClippyBonusScreen({super.key});

  @override
  State<ClippyBonusScreen> createState() => _ClippyBonusScreenState();
}

class _ClippyBonusScreenState extends State<ClippyBonusScreen> {
  _ClippyPhase _phase = _ClippyPhase.intro;
  List<Question> _questions = const [];
  int qIndex = 0;
  int correctCount = 0;
  bool answered = false;
  String? selectedAnswer;
  int _coinsEarned = 0;
  int _xpEarned = 0;
  int _livesEarned = 0;
  bool _collecting = false;
  bool _collected = false;
  Timer? _autoCollectTimer;

  /// Câte runde mai are jucătorul azi DUPĂ cea tocmai terminată — afișat pe
  /// ecranul de final, ca plafonul zilnic să fie explicit exact în momentul
  /// în care se consumă (contorul de sub mascotă e departe, pe Home).
  int _playsLeftToday = clippyDailyPlayLimit;

  final _coinBadgeKey = GlobalKey();
  final _xpBadgeKey = GlobalKey();
  final _livesBadgeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (mounted && _phase == _ClippyPhase.intro) _loadQuestions();
    });
  }

  @override
  void dispose() {
    _autoCollectTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    setState(() => _phase = _ClippyPhase.loading);
    final all = await loadAllQuestions();
    final picked = (List.of(all)..shuffle(Random())).take(clippyBonusQuestionCount).toList();
    if (!mounted) return;
    setState(() {
      _questions = picked;
      qIndex = 0;
      correctCount = 0;
      _coinsEarned = 0;
      _xpEarned = 0;
      _livesEarned = 0;
      _phase = _ClippyPhase.playing;
    });
  }

  Question get _current => _questions[qIndex];

  Future<void> _select(String opt) async {
    if (answered) return;
    final correct = opt == _current.answer;
    setState(() {
      answered = true;
      selectedAnswer = opt;
    });

    if (correct) {
      correctCount++;
      final roundsToday = await StorageService.getDailyCounter('clippy_rounds');
      final rate = roundsToday < clippyFullRateDailyRounds
          ? clippyRewardMultiplier
          : clippyReducedMultiplier;
      if (!mounted) return;
      setState(() {
        _xpEarned += (xpForCorrectAnswer(_current.maxPoints) * rate).round();
        _coinsEarned +=
            (coinsForCorrectAnswer(_current.maxPoints) * rate).round();
      });
    }

    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    if (qIndex + 1 >= _questions.length) {
      final perfect = correctCount == _questions.length;
      // notificarea se "consumă" abia acum, la finalul efectiv al jocului —
      // dacă jucătorul iese mai devreme (fără să termine), rămâne valabilă.
      await StorageService.resetClippyCooldown();
      // bonusul de finalizare există doar cât timp ești sub plafonul zilnic
      // de runde la rată plină — contorul se incrementează abia acum, ca o
      // rundă abandonată la jumătate să nu consume un slot.
      final roundsToday = await StorageService.getDailyCounter('clippy_rounds');
      final withinDailyCap = roundsToday < clippyFullRateDailyRounds;
      await StorageService.incrementDailyCounter('clippy_rounds');
      final playsLeft = await StorageService.clippyPlaysLeftToday();
      if (!mounted) return;
      setState(() {
        _playsLeftToday = playsLeft;
        if (perfect) _livesEarned = clippyPerfectBonusLives;
        if (withinDailyCap && correctCount > 0) {
          _coinsEarned += clippyCompletionCoins;
        }
        _phase = _ClippyPhase.finished;
      });
      // plasă de siguranță: dacă userul iese din aplicație pe ecranul de
      // recompensă fără să apese COLECTEAZĂ, recompensa tot se aplică după
      // 10s — la fel ca la Cultură Generală (vezi _autoCollectFinalRound din
      // culture_quiz_panel.dart), ca să nu rămână niciodată nerevendicată.
      _autoCollectTimer?.cancel();
      _autoCollectTimer = Timer(const Duration(seconds: 10), () {
        if (mounted && !_collecting && !_collected) _collect();
      });
      if (mounted) await bumpQuestMetric(context, 'clippy_done', 1);
      if (perfect && mounted) await bumpQuestMetric(context, 'clippy_perfect', 1);
    } else {
      setState(() {
        qIndex++;
        answered = false;
        selectedAnswer = null;
      });
    }
  }

  Future<void> _collect() async {
    if (_collecting || _collected) return;
    _autoCollectTimer?.cancel();
    setState(() => _collecting = true);
    await collectRewards(
      context,
      coins: _coinsEarned,
      xp: _xpEarned,
      lives: _livesEarned,
      coinBadgeKey: _coinBadgeKey,
      xpBadgeKey: _xpBadgeKey,
      livesBadgeKey: _livesBadgeKey,
    );
    if (!mounted) return;
    setState(() {
      _collecting = false;
      _collected = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                  ),
                  const SizedBox(width: 4),
                  const Text('Bonusul lui Clippy', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              Expanded(
                child: switch (_phase) {
                  _ClippyPhase.intro => _buildIntro(),
                  _ClippyPhase.loading => Center(child: CircularProgressIndicator(color: AppColors.purple)),
                  _ClippyPhase.playing => _buildPlaying(),
                  _ClippyPhase.finished => _buildFinished(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.attach_file_rounded, size: 84, color: Color(0xFFD9D9F5), shadows: [Shadow(color: Colors.black45, blurRadius: 8)]),
              const Positioned(top: 22, child: GooglyEyes(size: 12)),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            margin: const EdgeInsets.symmetric(horizontal: 30),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(20),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              children: [
                Text(
                  tr('Am 3 întrebări speciale pentru tine!', 'I have 3 special questions for you!'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Fără risc — un răspuns greșit nu pierde nimic!', 'No risk — a wrong answer costs you nothing!'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.coin, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaying() {
    final q = _current;
    final opts = [...q.choices]..shuffle(Random(q.id.hashCode + qIndex));

    return Column(
      children: [
        const SizedBox(height: 8),
        Text(tr('Întrebarea ${qIndex + 1} din ${_questions.length}', 'Question ${qIndex + 1} of ${_questions.length}'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 12),
        Expanded(
          child: BlurImage(
            color: q.color,
            answer: q.answer,
            revealed: answered,
            hintsUsed: 2,
            imageAssetPath: q.imageAssetPath,
          ),
        ),
        const SizedBox(height: 12),
        const Text('Cine / ce este?', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ...List.generate(opts.length, (i) {
          final opt = opts[i];
          var bg = Colors.white.withAlpha(18);
          var border = Colors.white24;
          if (answered) {
            if (opt == q.answer) {
              bg = const Color(0xFF1D9E75).withAlpha(90);
              border = const Color(0xFF1D9E75);
            } else if (opt == selectedAnswer) {
              bg = const Color(0xFFE24B4A).withAlpha(90);
              border = const Color(0xFFE24B4A);
            }
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: answered ? null : () => _select(opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 1.5)),
                child: Text(opt, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          );
        }),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildFinished() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.celebration_rounded, color: AppColors.coin, size: 40),
          const SizedBox(height: 10),
          Text(tr('$correctCount/${_questions.length} corecte', '$correctCount/${_questions.length} correct'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            tr('+$_coinsEarned monede\n+$_xpEarned XP${_livesEarned > 0 ? '\n+$_livesEarned viață (răspuns perfect!)' : ''}',
                '+$_coinsEarned coins\n+$_xpEarned XP${_livesEarned > 0 ? '\n+$_livesEarned life (perfect round!)' : ''}'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: (_playsLeftToday > 0 ? AppColors.hint : Colors.white).withAlpha(24),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: (_playsLeftToday > 0 ? AppColors.hint : Colors.white).withAlpha(90)),
            ),
            child: Text(
              _playsLeftToday > 0
                  ? tr('Îți mai rămân $_playsLeftToday/$clippyDailyPlayLimit runde azi',
                      'You have $_playsLeftToday/$clippyDailyPlayLimit rounds left today')
                  : tr(
                      'Ai folosit toate cele $clippyDailyPlayLimit runde de azi — '
                          'revin în ${_untilTomorrow()}',
                      'You used all $clippyDailyPlayLimit rounds for today — '
                          'they come back in ${_untilTomorrow()}'),
              style: TextStyle(
                color: _playsLeftToday > 0 ? AppColors.hint : Colors.white54,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _miniBadge(_coinBadgeKey, Icons.monetization_on_rounded, AppColors.coin),
              const SizedBox(width: 14),
              _miniBadge(_xpBadgeKey, Icons.star_rounded, AppColors.purple),
              const SizedBox(width: 14),
              _miniBadge(_livesBadgeKey, Icons.favorite_rounded, AppColors.life),
            ],
          ),
          const SizedBox(height: 22),
          if (_collected)
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.play, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12)),
              child: Text(tr('Înapoi', 'Back'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          else
            ElevatedButton(
              onPressed: _collecting ? null : _collect,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.coin,
                disabledBackgroundColor: Colors.white24,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(_collecting ? '...' : tr('COLECTEAZĂ', 'COLLECT'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }

  /// "4h 12m" / "12m" — cât mai e până la 00:00, când se eliberează rundele.
  /// Mai util decât un simplu "mâine": la 23:50 diferența e reală.
  static String _untilTomorrow() {
    final left = StorageService.clippyNextDayRemaining();
    final hours = left.inHours;
    final minutes = left.inMinutes % 60;
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }

  Widget _miniBadge(GlobalKey key, IconData icon, Color color) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withAlpha(15), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white24)),
      child: Icon(icon, color: color, size: 20),
    );
  }
}
