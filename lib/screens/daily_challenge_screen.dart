import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/admin_reveal.dart';
import '../core/cosmetics.dart';
import '../core/daily_challenge.dart';
import '../core/lang.dart';
import '../core/quest_bump.dart';
import '../core/reward_collector.dart';
import '../core/theme.dart';
import '../data/daily_challenge_service.dart';
import '../data/multiplayer_service.dart';
import '../data/questions.dart';
import '../data/storage_service.dart';
import '../models/multiplayer_models.dart' show pickAvatarColor;
import '../models/question.dart';
import '../widgets/avatar_art.dart';
import '../widgets/blur_image.dart';
import '../widgets/cosmetic_title.dart';
import '../widgets/league_badge.dart';
import '../widgets/space_background.dart';

/// Provocarea Zilei — 5 întrebări fixe pe zi, o singură rulare, recompensă
/// mare, clasament „de azi". Vezi core/daily_challenge.dart pentru reguli.
class DailyChallengeScreen extends StatefulWidget {
  const DailyChallengeScreen({super.key});

  @override
  State<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

enum _Phase { loading, intro, playing, finished }

class _DailyChallengeScreenState extends State<DailyChallengeScreen> {
  _Phase _phase = _Phase.loading;
  late final String _dateKey = dailyChallengeDateKey(DateTime.now());

  List<Question> _questions = const [];
  int _qIndex = 0;
  int _correct = 0;
  bool _answered = false;
  String? _selected;

  int _coins = 0;
  bool _collected = false;
  bool _collecting = false;
  Timer? _autoCollect;

  DailyChallengeToday? _board;
  bool _alreadyPlayed = false;

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
    _autoCollect?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    final prev = await StorageService.dailyChallengeResultFor(_dateKey);
    if (prev != null) {
      _alreadyPlayed = true;
      _correct = prev;
      _coins = dailyChallengeReward(prev);
      _collected = true;
      await _loadBoard();
      if (!mounted) return;
      setState(() => _phase = _Phase.finished);
      return;
    }
    final all = await loadAllQuestions();
    if (!mounted) return;
    setState(() {
      _questions = pickDailyChallenge(all, DateTime.now());
      _phase = _questions.isEmpty ? _Phase.finished : _Phase.intro;
    });
  }

  Future<void> _loadBoard() async {
    final b = await DailyChallengeService.instance.today(dateKey: _dateKey);
    if (mounted) setState(() => _board = b);
  }

  Question get _current => _questions[_qIndex];

  Future<void> _select(String opt) async {
    if (_answered) return;
    setState(() {
      _answered = true;
      _selected = opt;
      if (opt == _current.answer) _correct++;
    });
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    if (_qIndex + 1 >= _questions.length) {
      await _finish();
    } else {
      setState(() {
        _qIndex++;
        _answered = false;
        _selected = null;
      });
    }
  }

  Future<void> _finish() async {
    _coins = dailyChallengeReward(_correct);
    await StorageService.recordDailyChallengeRun(_dateKey, _correct);
    // Provocarea Zilei satisface şi quest-ul „provocarea zilei".
    if (mounted) await bumpQuestMetric(context, 'daily_challenge_done', 1);
    unawaited(DailyChallengeService.instance
        .submitScore(dateKey: _dateKey, correct: _correct, coins: _coins)
        .then((_) => _loadBoard()));
    if (!mounted) return;
    setState(() => _phase = _Phase.finished);
    _autoCollect?.cancel();
    _autoCollect = Timer(const Duration(seconds: 10), () {
      if (mounted && !_collecting && !_collected) _collect();
    });
  }

  Future<void> _collect() async {
    if (_collecting || _collected) return;
    _autoCollect?.cancel();
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                    ),
                    const SizedBox(width: 4),
                    Text(tr('Provocarea Zilei', 'Daily Challenge'),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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

  Widget _buildIntro() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded, color: AppColors.coin, size: 72),
          const SizedBox(height: 20),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(20),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              children: [
                Text(
                  tr('$dailyChallengeQuestionCount întrebări, aceleaşi pentru toată lumea azi.',
                      '$dailyChallengeQuestionCount questions, the same for everyone today.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('O singură încercare. Fără risc — un răspuns greşit doar nu aduce monede. Perfect (5/5) = +150 bonus.',
                      'One attempt. No risk — a wrong answer just earns nothing. Perfect (5/5) = +150 bonus.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.coin, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: () => setState(() => _phase = _Phase.playing),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.coin,
              padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: Text(tr('ÎNCEPE', 'START'),
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
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
        const SizedBox(height: 8),
        Text(tr('Întrebarea ${_qIndex + 1} din ${_questions.length}', 'Question ${_qIndex + 1} of ${_questions.length}'),
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 12),
        Expanded(
          child: BlurImage(
            color: q.color,
            answer: q.answer,
            revealed: _answered,
            hintsUsed: 2,
            imageAssetPath: q.imageAssetPath,
          ),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildFinished() {
    final me = MultiplayerService.instance.currentPlayerId;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_correct >= dailyChallengeQuestionCount ? Icons.emoji_events_rounded : Icons.check_circle_rounded,
                    color: AppColors.coin, size: 40),
                const SizedBox(height: 8),
                Text(tr('$_correct/$dailyChallengeQuestionCount corecte', '$_correct/$dailyChallengeQuestionCount correct'),
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_alreadyPlayed
                    ? tr('Ai jucat deja azi. Revii mâine.', 'Already played today. Come back tomorrow.')
                    : tr('+$_coins monede', '+$_coins coins'),
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 12),
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
                const SizedBox(height: 14),
                if (!_alreadyPlayed && !_collected)
                  ElevatedButton(
                    onPressed: _collecting ? null : _collect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.coin,
                      disabledBackgroundColor: Colors.white24,
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text(_collecting ? '...' : tr('COLECTEAZĂ', 'COLLECT'),
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.leaderboard_rounded, color: Colors.white54, size: 16),
              const SizedBox(width: 6),
              Text(tr('Clasamentul de azi', "Today's leaderboard"),
                  style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          if (_board == null)
            const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(color: AppColors.coin, strokeWidth: 2),
            ))
          else if (_board!.top.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(tr('Nimeni n-a terminat provocarea azi. Eşti primul!',
                  'Nobody finished today yet. You are first!'),
                  style: const TextStyle(color: Colors.white38, fontSize: 13)),
            )
          else ...[
            for (var i = 0; i < _board!.top.length; i++)
              _boardRow(i + 1, _board!.top[i], _board!.top[i].uid == me),
            if (_board!.me != null && _board!.myRankBelowTop != null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('⋯', style: TextStyle(color: Colors.white38)),
              ),
              _boardRow(_board!.myRankBelowTop!, _board!.me!, true),
            ],
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _boardRow(int rank, DailyScoreEntry e, bool isMe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMe ? AppColors.coin.withAlpha(28) : Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isMe ? AppColors.coin.withAlpha(120) : Colors.white12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('$rank',
                style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w800)),
          ),
          AvatarWithLeagueBadge(
            size: 32,
            label: e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
            accentColor: pickAvatarColor(e.avatarSeed),
            photoUrl: e.photoUrl,
            style: avatarStyleFromId(e.avatarStyle),
            frame: validatedFrame(e.equippedFrame, level: e.level, leaguePoints: e.leaguePoints),
            tier: null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                CosmeticTitle(titleId: e.equippedTitle, fontSize: 9),
              ],
            ),
          ),
          Text(tr('${e.correct}/5', '${e.correct}/5'),
              style: const TextStyle(color: AppColors.coin, fontSize: 14, fontWeight: FontWeight.w800)),
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
