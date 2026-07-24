import 'dart:math';
import 'package:flutter/material.dart';
import '../core/game_helpers.dart';
import '../core/reward_collector.dart';
import '../core/theme.dart';
import '../data/questions.dart';
import '../data/storage_service.dart';
import '../models/question.dart';
import '../widgets/blur_image.dart';
import '../widgets/googly_eyes.dart';

const int clippyBonusQuestionCount = 3;
const double clippyRewardMultiplier = 1.25;

enum _ClippyPhase { intro, loading, playing, finished }

/// Câte vieți se acordă la un răspuns perfect (toate întrebările corecte).
const int clippyPerfectBonusLives = 1;

/// Bonusul lui Clippy: 3 întrebări alese complet aleatoriu din TOATE
/// categoriile deblocate (bazele de date reale, cu poze — nu pool-ul text
/// separat al Culturii Generale), cu recompensă ×1.25 la răspunsurile
/// corecte, plus o viață bonus dacă ieși perfect (toate 3 corecte). Fără
/// pierdere de vieți — un răspuns greșit doar nu aduce recompensă, e un
/// bonus fără risc. Ecran separat (nu panou pe Home) — declanșat de
/// [PaperclipMascot] când are o "notificare" activă.
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
      final sessionReward = calculateSessionQuestionReward(_current.maxPoints, Random());
      final basePts = calculateAwardedPoints(sessionReward, 0, _current.maxPoints);
      final baseCoins = basePts ~/ 10;
      setState(() {
        _xpEarned += (basePts * clippyRewardMultiplier).round();
        _coinsEarned += (baseCoins * clippyRewardMultiplier).round();
      });
    }

    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    if (qIndex + 1 >= _questions.length) {
      final perfect = correctCount == _questions.length;
      // notificarea se "consumă" abia acum, la finalul efectiv al jocului —
      // dacă jucătorul iese mai devreme (fără să termine), rămâne valabilă.
      await StorageService.resetClippyCooldown();
      setState(() {
        if (perfect) _livesEarned = clippyPerfectBonusLives;
        _phase = _ClippyPhase.finished;
      });
    } else {
      setState(() {
        qIndex++;
        answered = false;
        selectedAnswer = null;
      });
    }
  }

  Future<void> _collect() async {
    if (_collecting) return;
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
                  _ClippyPhase.loading => const Center(child: CircularProgressIndicator(color: AppColors.purple)),
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
                const Text(
                  'Am 3 întrebări speciale pentru tine!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Răspunsurile corecte aduc ×${clippyRewardMultiplier.toStringAsFixed(2)} recompensă!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.coin, fontSize: 13, fontWeight: FontWeight.w700),
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
        Text('Întrebarea ${qIndex + 1} din ${_questions.length}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
          const Icon(Icons.celebration_rounded, color: AppColors.coin, size: 40),
          const SizedBox(height: 10),
          Text('$correctCount/${_questions.length} corecte', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            '+$_coinsEarned monede\n+$_xpEarned XP${_livesEarned > 0 ? '\n+$_livesEarned viață (răspuns perfect!)' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _miniBadge(_coinBadgeKey, Icons.monetization_on_rounded, AppColors.coin),
              const SizedBox(width: 14),
              _miniBadge(_xpBadgeKey, Icons.bolt_rounded, AppColors.purple),
              const SizedBox(width: 14),
              _miniBadge(_livesBadgeKey, Icons.favorite_rounded, AppColors.life),
            ],
          ),
          const SizedBox(height: 22),
          if (_collected)
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.play, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12)),
              child: const Text('Înapoi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              child: Text(_collecting ? '...' : 'COLECTEAZĂ', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
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
