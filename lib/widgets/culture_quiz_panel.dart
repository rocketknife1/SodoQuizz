import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/reward_collector.dart';
import '../core/theme.dart';
import '../data/culture_questions.dart';
import '../data/storage_service.dart';
import 'countdown_ring.dart';

enum _Phase { teaser, playing, justFinished }

/// Panou compact, integrat direct în Home (nu navighează spre alt ecran):
/// un mini-quiz de cultură generală (BETA), fără imagine, cronometrat
/// (35s/întrebare). Nelimitat — după ce colectezi recompensa unui lot de
/// [cultureQuizQuestionCount] întrebări, pornește automat următorul, fără
/// să mai fie nevoie de un tap manual pe START; se oprește doar dacă
/// părăsești Home. markDailyChallengeDone se apelează la finalul fiecărui
/// lot, pentru contorul de quiz-uri terminate și quest-uri.
///
/// Recompensele NU se acordă după fiecare răspuns — se acumulează doar local
/// pe durata sesiunii și se aplică toate deodată la apăsarea butonului
/// COLECTEAZĂ de pe ecranul final, cu aceeași animație/sunet ca la
/// revendicarea unui quest (vezi [CoinRewardOverlay] + [Sfx]).
class CultureQuizPanel extends StatefulWidget {
  /// Apelat după fiecare etapă de colectare (nu în timpul jocului) — Home îl
  /// folosește ca să-și reîmprospăteze header-ul (LevelHeader) exact la
  /// impactul fiecărei animații, sincron cu actualizarea afișajului.
  final VoidCallback? onRewardsChanged;

  /// Cheile pastilelor din LevelHeader-ul Home — fiecare etapă a colectării
  /// (monede/XP/vieți) "zboară" spre pastila ei proprie, cu sunetul ei.
  final GlobalKey coinBadgeKey;
  final GlobalKey xpBadgeKey;
  final GlobalKey livesBadgeKey;

  const CultureQuizPanel({
    super.key,
    this.onRewardsChanged,
    required this.coinBadgeKey,
    required this.xpBadgeKey,
    required this.livesBadgeKey,
  });

  @override
  State<CultureQuizPanel> createState() => _CultureQuizPanelState();
}

class _CultureQuizPanelState extends State<CultureQuizPanel> {
  _Phase _phase = _Phase.teaser;
  List<CultureQuestion> _questions = const [];
  int qIndex = 0;
  int correctCount = 0;
  int secondsLeft = cultureSecondsPerQuestion;
  bool answered = false;
  String? selectedAnswer;
  int _coinsEarned = 0;
  int _xpEarned = 0;
  int _livesEarned = 0;
  bool _collecting = false;
  Timer? _questionTimer;

  @override
  void dispose() {
    _questionTimer?.cancel();
    super.dispose();
  }

  void _start() {
    // sesiune nouă = alt set aleatoriu de întrebări din pool
    _questions = (List.of(cultureQuestions)..shuffle(Random()))
        .take(cultureQuizQuestionCount)
        .toList();
    setState(() {
      _phase = _Phase.playing;
      qIndex = 0;
      correctCount = 0;
      _coinsEarned = 0;
      _xpEarned = 0;
      _livesEarned = 0;
      _collecting = false;
    });
    _initQuestion();
  }

  void _initQuestion() {
    answered = false;
    selectedAnswer = null;
    secondsLeft = cultureSecondsPerQuestion;
    _questionTimer?.cancel();
    _questionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || answered) {
        timer.cancel();
        return;
      }
      final next = secondsLeft - 1;
      if (next <= 0) {
        timer.cancel();
        setState(() => secondsLeft = 0);
        _select(null);
      } else {
        setState(() => secondsLeft = next);
      }
    });
    setState(() {});
  }

  CultureQuestion get _current => _questions[qIndex];

  /// opt == null înseamnă că a expirat timpul fără răspuns ales.
  Future<void> _select(String? opt) async {
    if (answered) return;
    _questionTimer?.cancel();
    final correct = opt != null && opt == _current.answer;
    setState(() {
      answered = true;
      selectedAnswer = opt;
    });

    if (correct) {
      correctCount++;
      const coinsPerCorrect = 20;
      const xpPerCorrect = 40;
      _coinsEarned += coinsPerCorrect;
      _xpEarned += xpPerCorrect;
      // bonus de viață la fiecare 3 răspunsuri corecte — doar acumulat aici,
      // fără plafon (se acordă efectiv, peste maximul de 5, la colectare).
      if (correctCount % 3 == 0) _livesEarned++;
    }

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    if (qIndex + 1 >= _questions.length) {
      await _finish();
    } else {
      setState(() => qIndex++);
      _initQuestion();
    }
  }

  Future<void> _finish() async {
    const completionCoins = 30;
    const completionXp = 60;
    // contorul de quiz-uri terminate + progresul de quest se înregistrează
    // la final indiferent de colectare — doar monede/XP/vieți așteaptă tap-ul
    // pe COLECTEAZĂ.
    await StorageService.markDailyChallengeDone();
    await StorageService.addQuestProgress('daily_challenge_done', 1);
    if (!mounted) return;
    setState(() {
      _phase = _Phase.justFinished;
      _coinsEarned += completionCoins;
      _xpEarned += completionXp;
    });
  }

  /// Aplică toată recompensa acumulată, în 3 etape separate și în ordine
  /// fixă (monede → XP → vieți) — vezi [collectRewards].
  Future<void> _collect() async {
    if (_collecting) return;
    setState(() => _collecting = true);
    await collectRewards(
      context,
      coins: _coinsEarned,
      xp: _xpEarned,
      lives: _livesEarned,
      coinBadgeKey: widget.coinBadgeKey,
      xpBadgeKey: widget.xpBadgeKey,
      livesBadgeKey: widget.livesBadgeKey,
      onEachImpact: widget.onRewardsChanged,
    );

    if (!mounted) return;
    // continuă automat cu un set nou de întrebări — nelimitat, până
    // părăsești Home, nu doar câte un lot de 10 urmat de "START" manual.
    _start();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: switch (_phase) {
        _Phase.teaser => _buildTeaser(),
        _Phase.playing => _buildPlaying(),
        _Phase.justFinished => _buildFinished(),
      },
    );
  }

  Widget _buildTeaser() {
    return GestureDetector(
      onTap: _start,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.public_rounded, color: AppColors.coin, size: 34),
          const SizedBox(height: 8),
          const Text(
            'Cultură Generală',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.purple.withAlpha(60),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.purple),
            ),
            child: const Text('BETA', style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ),
          const SizedBox(height: 4),
          Text(
            'Nelimitat • ${cultureSecondsPerQuestion}s/întrebare',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
          Text(
            'Recompensă la fiecare $cultureQuizQuestionCount întrebări',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 8.5),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppColors.coin, borderRadius: BorderRadius.circular(20)),
            child: const Text('START', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaying() {
    final q = _current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${qIndex + 1}/${_questions.length}', style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w700)),
            CountdownRing(secondsLeft: secondsLeft, totalSeconds: cultureSecondsPerQuestion, size: 34),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          q.question,
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.25),
        ),
        const SizedBox(height: 10),
        ...List.generate(q.choices.length, (i) {
          final opt = q.choices[i];
          var bg = Colors.white.withAlpha(18);
          var border = Colors.white24;
          if (answered) {
            if (opt == q.answer) {
              bg = const Color(0xFF1D9E75).withAlpha(110);
              border = const Color(0xFF1D9E75);
            } else if (opt == selectedAnswer) {
              bg = const Color(0xFFE24B4A).withAlpha(110);
              border = const Color(0xFFE24B4A);
            }
          }
          return Padding(
            padding: EdgeInsets.only(bottom: i == q.choices.length - 1 ? 0 : 6),
            child: GestureDetector(
              onTap: answered ? null : () => _select(opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
                child: Text(
                  opt,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFinished() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.celebration_rounded, color: AppColors.coin, size: 26),
        const SizedBox(height: 8),
        Text(
          '$correctCount/${_questions.length} corecte',
          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          '+$_coinsEarned monede\n+$_xpEarned XP${_livesEarned > 0 ? '\n+$_livesEarned viață/vieți' : ''}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _collecting ? null : _collect,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: _collecting ? Colors.white24 : AppColors.coin,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _collecting ? '...' : 'COLECTEAZĂ',
              style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

}
