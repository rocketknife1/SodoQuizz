import 'dart:math';
import 'package:flutter/material.dart';
import '../core/game_helpers.dart';
import '../core/quest_bump.dart';
import '../core/theme.dart';
import '../data/questions.dart';
import '../data/storage_service.dart';
import '../models/question.dart';
import '../widgets/blur_image.dart';

/// Quiz nelimitat: întrebări alese aleatoriu din TOATE categoriile
/// deblocate (aceeași bază de date reală, cu poze, ca la Clippy), dar fără
/// limită de 3 — continuă la nesfârșit (reamestecă și o ia de la capăt
/// când epuizează pool-ul) până ieși din ecran. Recompensă standard
/// (aceeași formulă ca la un gamemod normal), acordată imediat la fiecare
/// răspuns corect — fără vieți în joc, un răspuns greșit doar nu aduce
/// puncte. Declanșat de planeta centrală de pe Home.
class UnlimitedQuizScreen extends StatefulWidget {
  const UnlimitedQuizScreen({super.key});

  @override
  State<UnlimitedQuizScreen> createState() => _UnlimitedQuizScreenState();
}

class _UnlimitedQuizScreenState extends State<UnlimitedQuizScreen> with SingleTickerProviderStateMixin {
  List<Question> _questions = const [];
  bool _loading = true;
  int qIndex = 0;
  int questionNumber = 1;
  int score = 0;
  bool answered = false;
  String? selectedAnswer;
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _load();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await loadAllQuestions();
    if (!mounted) return;
    setState(() {
      _questions = List.of(all)..shuffle(Random());
      qIndex = 0;
      _loading = false;
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
      final reward = calculateSessionQuestionReward(_current.maxPoints, Random());
      final basePts = calculateAwardedPoints(reward, 0, _current.maxPoints);
      // fără risc de inimă aici — plătește sub baseline-ul lui GameScreen,
      // cu o rată și mai mică peste plafonul zilnic (vezi game_helpers.dart).
      final correctToday = await StorageService.getDailyCounter('unlimited_correct');
      final rate = correctToday < unlimitedQuizFullRateDailyCap ? unlimitedQuizFullRate : unlimitedQuizReducedRate;
      final pts = (basePts * rate).round();
      final coinsEarned = pts ~/ 10;
      setState(() => score += pts);
      await StorageService.addCoins(coinsEarned);
      await StorageService.addXp(pts);
      await StorageService.addAnsweredId(_current.id);
      await StorageService.incrementDailyCounter('unlimited_correct');
      if (mounted) await bumpQuestMetric(context, 'unlimited_quiz_correct', 1);
    } else {
      _shakeController.forward(from: 0);
    }

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      answered = false;
      selectedAnswer = null;
      questionNumber++;
      if (qIndex + 1 >= _questions.length) {
        // pool epuizat — reamestecă și o ia de la capăt (nelimitat cu adevărat)
        _questions = List.of(_questions)..shuffle(Random());
        qIndex = 0;
      } else {
        qIndex++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: AppColors.bg, body: Center(child: CircularProgressIndicator(color: AppColors.purple)));
    }

    final q = _current;
    final opts = [...q.choices]..shuffle(Random(q.id.hashCode + qIndex));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: BoxDecoration(gradient: buildQuestionGradient(q.id, q.color)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    const Text('Quiz nelimitat', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('$score pct', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text('Întrebarea $questionNumber', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
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
                                hintsUsed: 2,
                                imageAssetPath: q.imageAssetPath,
                              ),
                            ),
                            Positioned(top: -9, left: 14, child: _buildBadge(q)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text('Cine / ce este?', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...List.generate(opts.length, (i) {
                          final opt = opts[i];
                          const letters = ['A', 'B', 'C', 'D'];
                          var bg = Colors.white.withAlpha(18);
                          var border = Colors.white24;
                          var letterBg = Colors.white.withAlpha(30);
                          if (answered) {
                            if (opt == q.answer) {
                              bg = const Color(0xFF1D9E75).withAlpha(70);
                              border = const Color(0xFF1D9E75);
                              letterBg = const Color(0xFF1D9E75);
                            } else if (opt == selectedAnswer) {
                              bg = const Color(0xFFE24B4A).withAlpha(70);
                              border = const Color(0xFFE24B4A);
                              letterBg = const Color(0xFFE24B4A);
                            }
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: GestureDetector(
                              onTap: answered ? null : () => _select(opt),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 1.5)),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 22,
                                      height: 22,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(color: letterBg, shape: BoxShape.circle),
                                      child: Text(letters[i], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(opt, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
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

  Widget _buildBadge(Question q) {
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
}
