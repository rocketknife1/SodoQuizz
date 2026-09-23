import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/admin_reveal.dart';
import '../core/audio.dart';
import '../core/daily_challenge.dart' show dailyChallengeDateKey;
import '../core/game_event.dart';
import '../core/lang.dart';
import '../core/reward_collector.dart';
import '../core/theme.dart';
import '../core/weekly_event.dart';
import '../data/event_service.dart';
import '../data/questions.dart';
import '../data/storage_service.dart';
import '../models/question.dart';
import '../widgets/blur_image.dart';
import '../widgets/space_background.dart';

/// **Cursa zilei** din săptămâna tematică: 7 întrebări fixe pe zi, aceleași
/// pentru toți, o singură rulare. Regulile și cifrele: core/weekly_event.dart.
///
/// Ce o face să se simtă ca o cursă, nu ca un test: bara de viteză care se
/// golește sub fiecare întrebare (punctele pe viteză se văd scăzând), „+34"
/// care sare la fiecare răspuns bun, flacăra seriei și totalul care urcă.
///
/// Încercarea se consumă la PRIMUL răspuns și progresul se scrie după fiecare
/// (tiparul de la Provocarea Zilei): ieșirea din aplicație nu dă o a doua
/// șansă la aceleași întrebări.
class WeeklyRunScreen extends StatefulWidget {
  final GameEvent event;
  const WeeklyRunScreen({super.key, required this.event});

  @override
  State<WeeklyRunScreen> createState() => _WeeklyRunScreenState();
}

enum _Phase { loading, intro, playing, finished }

class _WeeklyRunScreenState extends State<WeeklyRunScreen> with SingleTickerProviderStateMixin {
  _Phase _phase = _Phase.loading;
  late final String _dayKey = dailyChallengeDateKey(DateTime.now());

  List<Question> _questions = const [];
  int _qIndex = 0;
  int _correct = 0;
  int _points = 0;
  int _streak = 0;
  bool _answered = false;
  String? _selected;
  int _lastGain = 0;
  DateTime _shownAt = DateTime.now();

  /// Ceasul barei de viteză — se golește în 15 s (după care viteza nu mai
  /// aduce nimic, vezi [weeklyAnswerPoints]).
  late final AnimationController _speed =
      AnimationController(vsync: this, duration: const Duration(seconds: 15));

  int _coins = 0;
  int _consecutive = 1;
  bool _collected = false;
  bool _collecting = false;
  ({int rank, int participants, int points, int days})? _standing;

  final _coinBadgeKey = GlobalKey();
  final _xpBadgeKey = GlobalKey();
  final _livesBadgeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _speed.dispose();
    // Ieșire înainte de colectare: cursa e deja înregistrată (nu se mai
    // poate rejuca), deci monedele se scriu direct, fără animație.
    if (_phase == _Phase.finished && !_collected && !_collecting && _coins > 0) {
      StorageService.addCoins(_coins);
    }
    super.dispose();
  }

  Future<void> _boot() async {
    final prev = await StorageService.weeklyRunFor(_dayKey);
    if (prev != null && prev.done) {
      _correct = prev.correct;
      _points = prev.points;
      _collected = true;
      _coins = 0;
      _loadStanding();
      if (mounted) setState(() => _phase = _Phase.finished);
      return;
    }
    final all = await loadAllQuestions();
    final questions = weeklyRunQuestions(all, DateTime.now());
    if (!mounted) return;
    setState(() {
      _questions = questions;
      if (questions.isEmpty) {
        _phase = _Phase.finished;
      } else if (prev != null && prev.next > 0 && prev.next < questions.length) {
        _qIndex = prev.next;
        _correct = prev.correct;
        _points = prev.points;
        _streak = prev.streak;
        _phase = _Phase.playing;
        _startQuestion();
      } else {
        _phase = _Phase.intro;
      }
    });
  }

  Future<void> _loadStanding() async {
    final s = await EventService.instance.finalStanding(widget.event.id);
    if (mounted) setState(() => _standing = s);
  }

  void _startQuestion() {
    _shownAt = DateTime.now();
    _speed.forward(from: 0);
  }

  Question get _current => _questions[_qIndex];

  Future<void> _select(String opt) async {
    if (_answered) return;
    _speed.stop();
    final ms = DateTime.now().difference(_shownAt).inMilliseconds;
    final correct = opt == _current.answer;
    final gain = weeklyAnswerPoints(correct: correct, answerMs: ms, streakBefore: _streak);
    setState(() {
      _answered = true;
      _selected = opt;
      _lastGain = gain;
      if (correct) {
        _correct++;
        _points += gain;
        _streak++;
      } else {
        _streak = 0;
      }
    });
    correct ? Sfx.coinHit() : Sfx.heartHit();
    await StorageService.recordWeeklyRun(_dayKey,
        next: _qIndex + 1, correct: _correct, points: _points, streak: _streak);
    unawaited(EventService.instance.addRunAnswer(widget.event.id, points: gain, dayKey: _dayKey));
    await Future.delayed(Duration(milliseconds: correct ? 1100 : 1800));
    if (!mounted) return;
    if (_qIndex + 1 >= _questions.length) {
      await _finish();
    } else {
      setState(() {
        _qIndex++;
        _answered = false;
        _selected = null;
      });
      _startQuestion();
    }
  }

  Future<void> _finish() async {
    await StorageService.recordWeeklyRun(_dayKey,
        next: _questions.length, correct: _correct, points: _points, streak: _streak, done: true);
    await StorageService.addWeeklyDayPlayed(widget.event.id, _dayKey);
    final days = await StorageService.weeklyDaysPlayed(widget.event.id);
    // zilele la rând, numărate înapoi de azi
    var run = 0;
    for (var d = DateTime.now(); days.contains(dailyChallengeDateKey(d)); d = d.subtract(const Duration(days: 1))) {
      run++;
    }
    _consecutive = max(run, 1);
    _coins = weeklyDailyCoins(correct: _correct, consecutiveDays: _consecutive);
    if (!mounted) return;
    setState(() => _phase = _Phase.finished);
    _loadStanding();
  }

  Future<void> _collect() async {
    if (_collecting || _collected) return;
    setState(() => _collecting = true);
    await collectRewards(
      context,
      coins: _coins,
      xp: 0,
      lives: 0,
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
      body: SpaceBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                    ),
                    Expanded(
                      child: Text(tr('Cursa zilei', 'Daily race'),
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    if (_phase == _Phase.playing || _phase == _Phase.finished) _pointsBadge(),
                  ],
                ),
                Expanded(
                  child: switch (_phase) {
                    _Phase.loading => const Center(child: CircularProgressIndicator(color: AppColors.coin)),
                    _Phase.intro => _buildIntro(),
                    _Phase.playing => _buildPlaying(),
                    _Phase.finished => _buildFinished(),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pointsBadge() {
    return TweenAnimationBuilder<int>(
      tween: IntTween(end: _points),
      duration: const Duration(milliseconds: 600),
      builder: (context, v, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.orange.withAlpha(40),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.orange.withAlpha(150)),
        ),
        child: Text(tr('$v pct', '$v pts'),
            style: const TextStyle(color: AppColors.orange, fontSize: 15, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _buildIntro() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.flag_rounded, color: AppColors.orange, size: 72),
          const SizedBox(height: 16),
          Text(tr(widget.event.titleRo, widget.event.titleEn),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(18),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              tr('$weeklyRunQuestionCount întrebări, aceleași pentru toți azi. O singură încercare.\n'
                  'Corect = 20 pct · rapid = până la +20 · la rând = până la +10.',
                  '$weeklyRunQuestionCount questions, the same for everyone today. One attempt.\n'
                  'Correct = 20 pts · fast = up to +20 · in a row = up to +10.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.4),
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: () {
              setState(() => _phase = _Phase.playing);
              _startQuestion();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: Text(tr('START', 'GO'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaying() {
    final q = _current;
    final opts = [...q.choices]..shuffle(Random(q.id.hashCode + _qIndex));
    return Column(
      children: [
        const SizedBox(height: 6),
        Row(
          children: [
            Text(tr('${_qIndex + 1} / ${_questions.length}', '${_qIndex + 1} / ${_questions.length}'),
                style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (_streak >= 2)
              Text('🔥 $_streak', style: const TextStyle(color: AppColors.orange, fontSize: 14, fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 6),
        // bara de viteză: plină primele 3 s, apoi se golește până la 15 s
        AnimatedBuilder(
          animation: _speed,
          builder: (context, _) {
            final secs = _speed.value * 15;
            final left = secs <= 3 ? 1.0 : (1 - (secs - 3) / 12).clamp(0.0, 1.0);
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: left,
                minHeight: 6,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(Color.lerp(AppColors.danger, AppColors.play, left)!),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              BlurImage(
                color: q.color,
                answer: q.answer,
                revealed: _answered,
                hintsUsed: 2,
                imageAssetPath: q.imageAssetPath,
              ),
              if (_answered && _lastGain > 0)
                TweenAnimationBuilder<double>(
                  key: ValueKey('gain-$_qIndex'),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 900),
                  builder: (context, k, _) => Transform.translate(
                    offset: Offset(0, -40 * k),
                    child: Transform.scale(
                      scale: Curves.elasticOut.transform(k.clamp(0.0, 1.0)) * 0.6 + 0.6,
                      child: Opacity(
                        opacity: k < 0.75 ? 1 : (1 - (k - 0.75) / 0.25),
                        child: Text('+$_lastGain',
                            style: const TextStyle(
                              color: AppColors.coin,
                              fontSize: 46,
                              fontWeight: FontWeight.w900,
                              shadows: [Shadow(color: Colors.black, blurRadius: 12)],
                            )),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(q.prompt.isNotEmpty ? q.prompt : tr('Cine / ce este?', 'Who / what is it?'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ...opts.map((opt) {
          var bg = Colors.white.withAlpha(18);
          var border = Colors.white24;
          if (_answered) {
            if (opt == q.answer) {
              bg = const Color(0xFF1D9E75).withAlpha(90);
              border = const Color(0xFF1D9E75);
            } else if (opt == _selected) {
              bg = const Color(0xFFE24B4A).withAlpha(90);
              border = const Color(0xFFE24B4A);
            }
          }
          final adminHint = !_answered && adminAnswerRevealOn && opt == q.answer;
          if (adminHint) {
            bg = adminRevealColor.withAlpha(28);
            border = adminRevealColor;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: _answered ? null : () => _select(opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border, width: adminHint ? 2.2 : 1.5)),
                child: Text(opt,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFinished() {
    final s = _standing;
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 18),
          const Icon(Icons.flag_circle_rounded, color: AppColors.orange, size: 64),
          const SizedBox(height: 10),
          Text(tr('$_correct/$weeklyRunQuestionCount corecte · $_points pct',
                  '$_correct/$weeklyRunQuestionCount correct · $_points pts'),
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            s == null
                ? tr('Se calculează locul…', 'Working out your rank…')
                : tr('Locul tău acum: #${s.rank} din ${s.participants}', 'Your rank now: #${s.rank} of ${s.participants}'),
            style: const TextStyle(color: AppColors.coin, fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          if (_coins > 0) ...[
            Text(tr('+$_coins monede', '+$_coins coins'),
                style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700)),
            if (_consecutive > 1)
              Text(tr('inclusiv bonusul de $_consecutive zile la rând', 'including a $_consecutive-day streak bonus'),
                  style: const TextStyle(color: AppColors.orange, fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _miniBadge(_coinBadgeKey, Icons.monetization_on_rounded, AppColors.coin),
                const SizedBox(width: 14),
                _miniBadge(_xpBadgeKey, Icons.star_rounded, AppColors.purple),
                const SizedBox(width: 14),
                _miniBadge(_livesBadgeKey, Icons.favorite_rounded, AppColors.life),
              ],
            ),
            const SizedBox(height: 14),
            if (!_collected)
              ElevatedButton(
                onPressed: _collecting ? null : _collect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.coin,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text(_collecting ? '...' : tr('COLECTEAZĂ', 'COLLECT'),
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
              ),
          ] else
            Text(tr('Ai alergat deja azi. Următoarea cursă: mâine.', 'Already raced today. Next race: tomorrow.'),
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _miniBadge(GlobalKey key, IconData icon, Color color) {
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
}
