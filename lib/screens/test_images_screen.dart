import 'dart:math';
import 'package:flutter/material.dart';
import '../core/game_helpers.dart';
import '../data/questions.dart';
import '../models/question.dart';
import '../widgets/blur_image.dart';
import '../widgets/next_button.dart';

/// Id-urile intrebarilor la care poza automata a fost inlocuita cu una
/// adusa manual — actualizeaza lista pe masura ce se testeaza poze noi.
const List<String> testQuestionIds = [
  'lgf_001', 'lgf_002', 'lgf_003', 'lgf_004', 'lgf_005', 'lgf_006', 'lgf_007',
  'lgf_008', 'lgf_009', 'lgf_010', 'lgf_011', 'lgf_012', 'lgf_013', 'lgf_014',
  'lgf_015', 'lgf_016', 'lgf_017',
  'med_001', 'med_002', 'med_003', 'med_004', 'med_006', 'med_007', 'med_008',
  'med_009', 'med_010', 'med_011', 'med_012',
  'gam_001', 'gam_003', 'gam_004', 'gam_005', 'gam_006', 'gam_007', 'gam_009',
  'gam_010', 'gam_011',
  'mec_001', 'mec_002', 'mec_003', 'mec_004', 'mec_005', 'mec_006', 'mec_007',
  'mec_008', 'mec_009', 'mec_010', 'mec_011', 'mec_012', 'mec_013', 'mec_014',
  'mec_015', 'mec_016', 'mec_017', 'mec_018', 'mec_019', 'mec_020',
  'apl_001',
];

/// Ecran de test intern: acelasi stil vizual ca in joc (blur, hint-uri,
/// grid de variante) dar restrans doar la [testQuestionIds] si fara sa
/// atinga scorul/quest-urile/achievements reale — pur pentru verificarea
/// vizuala a pozelor aduse manual.
class TestImagesScreen extends StatefulWidget {
  const TestImagesScreen({super.key});

  @override
  State<TestImagesScreen> createState() => _TestImagesScreenState();
}

class _TestImagesScreenState extends State<TestImagesScreen> {
  List<Question> questions = [];
  bool _loading = true;
  int qIndex = 0;
  int hintsUsed = 0;
  bool answered = false;
  String? selectedAnswer;

  Question get currentQ => questions[qIndex];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await loadAllQuestions();
    if (!mounted) return;
    setState(() {
      questions = all.where((q) => testQuestionIds.contains(q.id)).toList();
      _loading = false;
    });
  }

  void _selectAnswer(String opt) {
    if (answered) return;
    setState(() {
      selectedAnswer = opt;
      answered = true;
    });
  }

  void _addHint() {
    if (answered || hintsUsed >= maxHintsPerQuestion) return;
    setState(() => hintsUsed++);
  }

  void _next() {
    if (qIndex + 1 >= questions.length) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      qIndex += 1;
      hintsUsed = 0;
      answered = false;
      selectedAnswer = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF9A5AFB))));
    }

    if (questions.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image_not_supported_rounded, size: 64, color: Colors.white24),
              const SizedBox(height: 16),
              const Text('Nicio intrebare de test momentan.',
                  style: TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Inapoi')),
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
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          BlurImage(
                            color: q.color,
                            answer: q.answer,
                            revealed: answered,
                            hintsUsed: hintsUsed,
                            imageAssetPath: q.imageAssetPath,
                          ),
                          Positioned(top: -9, left: 14, child: _buildQuestionBadge(q)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _buildRevealRow(q),
                      if (answered) ...[
                        const SizedBox(height: 6),
                        NextButton(onTap: _next),
                      ],
                      const SizedBox(height: 8),
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
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Text('TEST POZE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const Spacer(),
          Text('${qIndex + 1} / ${questions.length}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
        if (!answered)
          Row(
            children: [
              _buildHintButton(),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _next,
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
                child: const Text('Skip'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildHintButton() {
    final enabled = !answered && hintsUsed < maxHintsPerQuestion;
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
            Text('Hint (liber, doar test)', style: TextStyle(color: fg, fontSize: 12)),
          ],
        ),
      ),
    );
  }

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
