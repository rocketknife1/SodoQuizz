import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/admin_reveal.dart';
import '../core/analytics.dart';
import '../core/async_challenge.dart';
import '../core/lang.dart';
import '../core/progression.dart' show multiplayerXpForScore;
import '../core/quest_bump.dart';
import '../core/reward_collector.dart';
import '../core/theme.dart';
import '../data/async_challenge_service.dart';
import '../data/multiplayer_service.dart';
import '../data/questions.dart';
import '../data/storage_service.dart';
import '../models/question.dart';
import '../widgets/blur_image.dart';
import '../widgets/countdown_ring.dart';
import '../widgets/space_background.dart';

/// Async Challenge — „Provoacă un prieten". Vezi core/async_challenge.dart.
///
/// - `challengeId == null` → **flux CREATOR**: joacă 10 întrebări, apoi
///   se creează provocarea și se arată codul de trimis.
/// - `challengeId != null` → se încarcă provocarea:
///   - sunt creatorul → arăt starea (aștept adversarul / rezultatul);
///   - provocarea are deja adversar → arăt doar rezultatul (read-only);
///   - altfel → **flux ADVERSAR**: intro „X te-a provocat" → 10 întrebări →
///     rezultat comparativ + recompense.
class AsyncChallengeScreen extends StatefulWidget {
  final String? challengeId;
  const AsyncChallengeScreen({super.key, this.challengeId});

  @override
  State<AsyncChallengeScreen> createState() => _AsyncChallengeScreenState();
}

enum _Phase { loading, intro, playing, sending, waiting, result }

const int _secondsPerQuestion = 15;

class _AsyncChallengeScreenState extends State<AsyncChallengeScreen> {
  _Phase _phase = _Phase.loading;

  /// null cât timp sunt CREATOR și n-am creat încă provocarea.
  String? _id;
  AsyncChallenge? _challenge;
  StreamSubscription<AsyncChallenge?>? _watchSub;

  List<Question> _questions = const [];
  int _qIndex = 0;
  int _correct = 0;
  int _score = 0;
  bool _answered = false;
  String? _selected;
  int _secondsLeft = _secondsPerQuestion;
  Timer? _tick;

  bool get _amCreatorFlow => widget.challengeId == null;

  int _coinsWon = 0;
  bool _collected = false;
  bool _collecting = false;
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
    _tick?.cancel();
    _watchSub?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    final pool = await loadAllQuestions();
    if (!mounted) return;

    if (_amCreatorFlow) {
      _questions = pickAsyncChallenge(pool, 'placeholder');
      // pentru creator, id-ul (și deci întrebările reale) se fixează abia la
      // finalul jocului — dar folosim un set determinist pe un id temporar
      // ca jocul să pornească acum. Regenerăm cu id-ul real la _finishCreator.
      setState(() => _phase = _Phase.intro);
      return;
    }

    final id = widget.challengeId!;
    final ch = await AsyncChallengeService.instance.fetch(id);
    if (!mounted) return;
    if (ch == null) {
      setState(() => _phase = _Phase.result); // arată „nu mai e valabilă"
      return;
    }
    _id = id;
    _challenge = ch;
    _questions = pickAsyncChallenge(pool, id);

    if (ch.creatorUid == MultiplayerService.instance.currentPlayerId) {
      // sunt creatorul care revine pe link
      if (ch.isAnswered) {
        setState(() => _phase = _Phase.result);
      } else {
        _startWatching(id);
        setState(() => _phase = _Phase.waiting);
      }
      return;
    }
    if (ch.isAnswered) {
      setState(() => _phase = _Phase.result); // altcineva a răspuns deja
      return;
    }
    // flux adversar — reia dacă a început deja
    final prog = await StorageService.challengeProgressFor(id);
    if (!mounted) return;
    setState(() {
      if (prog != null && !prog.done && prog.nextIndex > 0 && prog.nextIndex < _questions.length) {
        _qIndex = prog.nextIndex;
        _correct = prog.correct;
        _score = prog.score;
        _phase = _Phase.playing;
        _startTick();
      } else if (prog != null && prog.done) {
        _phase = _Phase.result;
      } else {
        _phase = _Phase.intro;
      }
    });
  }

  void _startWatching(String id) {
    _watchSub?.cancel();
    _watchSub = AsyncChallengeService.instance.watch(id).listen((ch) {
      if (!mounted || ch == null) return;
      setState(() {
        _challenge = ch;
        if (ch.isAnswered) _phase = _Phase.result;
      });
    });
  }

  Question get _current => _questions[_qIndex];

  void _startTick() {
    _tick?.cancel();
    _secondsLeft = _secondsPerQuestion;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _answered) {
        t.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _select(null); // timp expirat = răspuns greșit
      }
    });
  }

  void _startPlaying() {
    setState(() {
      _phase = _Phase.playing;
      _qIndex = 0;
      _correct = 0;
      _score = 0;
    });
    _startTick();
  }

  Future<void> _select(String? opt) async {
    if (_answered) return;
    _tick?.cancel();
    final correct = opt != null && opt == _current.answer;
    setState(() {
      _answered = true;
      _selected = opt;
      if (correct) {
        _correct++;
        // 500 fix + bonus de viteză (max +450) — un răspuns rapid corect
        // valorează cât doi lenți, ca decalajul de scor să nu fie doar
        // „câte corecte" (unde egalitățile sunt dese).
        _score += 500 + (_secondsLeft.clamp(0, _secondsPerQuestion)) * 30;
      }
    });
    if (!_amCreatorFlow && _id != null) {
      await StorageService.recordChallengeProgress(_id!, _qIndex + 1, _score, _correct);
    }
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    if (_qIndex + 1 >= _questions.length) {
      _amCreatorFlow ? await _finishCreator() : await _finishOpponent();
    } else {
      setState(() {
        _qIndex++;
        _answered = false;
        _selected = null;
      });
      _startTick();
    }
  }

  Future<void> _finishCreator() async {
    setState(() => _phase = _Phase.sending);
    final id = await AsyncChallengeService.instance.create(score: _score, correct: _correct);
    if (!mounted) return;
    if (id == null) {
      setState(() => _phase = _Phase.result); // eroare de rețea
      return;
    }
    _id = id;
    Analytics.instance.multiplayerRematch(mod: 'challenge', tip: 'creat');
    _startWatching(id);
    setState(() {
      _challenge = AsyncChallenge(
        id: id,
        creatorUid: MultiplayerService.instance.currentPlayerId,
        creatorName: '',
        creatorScore: _score,
        creatorCorrect: _correct,
        creatorAvatarStyle: '',
        creatorPhotoUrl: null,
        creatorFrame: 'none',
        creatorTitle: 'novice',
      );
      _phase = _Phase.waiting;
    });
  }

  Future<void> _finishOpponent() async {
    final id = _id!;
    await StorageService.recordChallengeProgress(id, _questions.length, _score, _correct, done: true);
    final ok = await AsyncChallengeService.instance
        .submitOpponentScore(id: id, score: _score, correct: _correct);
    if (!mounted) return;
    if (ok) {
      _challenge = _challenge!;
      final outcome = challengeOutcome(myScore: _score, theirScore: _challenge!.creatorScore);
      await _applyRewards(outcome);
    }
    // dacă !ok (provocarea a fost revendicată între timp), reîncărcăm ca să
    // arătăm rezultatul real
    final fresh = await AsyncChallengeService.instance.fetch(id);
    if (!mounted) return;
    setState(() {
      if (fresh != null) _challenge = fresh;
      _phase = _Phase.result;
    });
  }

  Future<void> _applyRewards(ChallengeOutcome outcome) async {
    final xp = outcome == ChallengeOutcome.won
        ? multiplayerXpForScore(_correct, won: true)
        : outcome == ChallengeOutcome.draw
            ? multiplayerXpForScore(_correct, won: false)
            : challengeLoseXp;
    var coins = challengeCoinReward(outcome);
    // plafon anti-farm: doar primele challengeRewardedPerDay victorii/zi aduc
    // monede
    if (coins > 0 && !await StorageService.claimChallengeRewardSlot()) {
      coins = 0;
    }
    if (outcome == ChallengeOutcome.won && mounted) {
      await bumpQuestMetric(context, 'challenge_win', 1);
    }
    if (!mounted) return;
    _coinsWon = coins;
    _pendingXp = xp;
  }

  int _pendingXp = 0;

  Future<void> _collect() async {
    if (_collecting || _collected) return;
    setState(() => _collecting = true);
    await collectRewards(
      context,
      coins: _coinsWon,
      xp: _pendingXp,
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

  Future<void> _share() async {
    final id = _id;
    if (id == null) return;
    final link = 'guessit://challenge/$id';
    await Share.share(tr(
        'Te provoc la SodoQuizz! Am făcut $_correct/$asyncChallengeQuestionCount. '
            'Cod: $id  ·  $link',
        "I challenge you on SodoQuizz! I got $_correct/$asyncChallengeQuestionCount. "
            'Code: $id  ·  $link'));
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
                    Text(tr('Provocare', 'Challenge'),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                Expanded(
                  child: switch (_phase) {
                    _Phase.loading => const Center(child: CircularProgressIndicator(color: AppColors.teal)),
                    _Phase.intro => _buildIntro(),
                    _Phase.playing => _buildPlaying(),
                    _Phase.sending => const Center(child: CircularProgressIndicator(color: AppColors.teal)),
                    _Phase.waiting => _buildWaiting(),
                    _Phase.result => _buildResult(),
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
    final creatorName = _challenge?.creatorName ?? '';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sports_kabaddi_rounded, color: AppColors.teal, size: 72),
          const SizedBox(height: 18),
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
                  _amCreatorFlow
                      ? tr('$asyncChallengeQuestionCount întrebări. Le faci, apoi trimiți codul unui prieten.',
                          '$asyncChallengeQuestionCount questions. Play them, then send the code to a friend.')
                      : tr('$creatorName te-a provocat. Aceleași $asyncChallengeQuestionCount întrebări. Scorul lui e ascuns până termini.',
                          '$creatorName challenged you. The same $asyncChallengeQuestionCount questions. Their score is hidden until you finish.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('$_secondsPerQuestion secunde pe întrebare. Răspunsul rapid valorează mai mult.',
                      '$_secondsPerQuestion seconds per question. A fast answer is worth more.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.teal, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: _startPlaying,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teal,
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
        Row(
          children: [
            Text(tr('Întrebarea ${_qIndex + 1}/${_questions.length}', 'Question ${_qIndex + 1}/${_questions.length}'),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const Spacer(),
            Text('$_score', style: const TextStyle(color: AppColors.teal, fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(width: 10),
            CountdownRing(
              secondsLeft: _secondsLeft.clamp(0, _secondsPerQuestion),
              totalSeconds: _secondsPerQuestion,
              size: 26,
            ),
          ],
        ),
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

  Widget _buildWaiting() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.teal, size: 56),
          const SizedBox(height: 12),
          Text(tr('Scorul tău: $_score  ·  $_correct/$asyncChallengeQuestionCount corecte',
              'Your score: $_score  ·  $_correct/$asyncChallengeQuestionCount correct'),
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 18),
          if (_id != null) ...[
            Text(tr('Trimite codul unui prieten:', 'Send the code to a friend:'),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            SelectableText(_id!,
                style: const TextStyle(color: AppColors.teal, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 4)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(tr('TRIMITE PROVOCAREA', 'SEND CHALLENGE')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(tr('Primești o notificare când răspunde.', 'You get a notification when they answer.'),
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final ch = _challenge;
    if (ch == null) {
      return Center(
        child: Text(tr('Provocarea nu mai e valabilă.', "This challenge isn't valid anymore."),
            style: const TextStyle(color: Colors.white54)),
      );
    }
    final myUid = MultiplayerService.instance.currentPlayerId;
    final iAmCreator = ch.creatorUid == myUid;
    final myScore = iAmCreator ? ch.creatorScore : (ch.opponentScore ?? _score);
    final myCorrect = iAmCreator ? ch.creatorCorrect : (ch.opponentCorrect ?? _correct);
    final theirScore = iAmCreator ? (ch.opponentScore ?? 0) : ch.creatorScore;
    final theirCorrect = iAmCreator ? (ch.opponentCorrect ?? 0) : ch.creatorCorrect;
    final theirName = iAmCreator ? (ch.opponentName ?? '?') : ch.creatorName;

    if (!ch.isAnswered) {
      return _buildWaiting();
    }

    final outcome = challengeOutcome(myScore: myScore, theirScore: theirScore);
    final (title, color, icon) = switch (outcome) {
      ChallengeOutcome.won => (tr('AI CÂȘTIGAT', 'YOU WON'), AppColors.teal, Icons.emoji_events_rounded),
      ChallengeOutcome.lost => (tr('AI PIERDUT', 'YOU LOST'), const Color(0xFFE24B4A), Icons.sentiment_dissatisfied_rounded),
      ChallengeOutcome.draw => (tr('REMIZĂ', 'DRAW'), AppColors.orange, Icons.handshake_rounded),
    };

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Center(child: Icon(icon, color: color, size: 48)),
          const SizedBox(height: 6),
          Center(child: Text(title, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900))),
          const SizedBox(height: 18),
          _scoreRow(tr('Tu', 'You'), myScore, myCorrect, outcome == ChallengeOutcome.won),
          const SizedBox(height: 8),
          _scoreRow(theirName, theirScore, theirCorrect, outcome == ChallengeOutcome.lost),
          const SizedBox(height: 22),
          if (!iAmCreator && !_collected && (_coinsWon > 0 || _pendingXp > 0)) ...[
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _miniBadge(_coinBadgeKey, Icons.monetization_on_rounded, AppColors.coin),
                  const SizedBox(width: 14),
                  _miniBadge(_xpBadgeKey, Icons.star_rounded, AppColors.purple),
                  const SizedBox(width: 14),
                  _miniBadge(_livesBadgeKey, Icons.favorite_rounded, AppColors.life),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: ElevatedButton(
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
            ),
          ],
          if (!iAmCreator && _coinsWon == 0 && outcome == ChallengeOutcome.won)
            Center(
              child: Text(tr('Plafonul de $challengeRewardedPerDay provocări recompensate azi e atins.',
                  "Today's cap of $challengeRewardedPerDay rewarded challenges is reached."),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
            ),
          const SizedBox(height: 20),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const AsyncChallengeScreen()),
              ),
              icon: const Icon(Icons.replay_rounded, size: 18, color: Colors.white70),
              label: Text(tr('Provoacă din nou', 'Challenge again'),
                  style: const TextStyle(color: Colors.white70)),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _scoreRow(String name, int score, int correct, bool winner) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: winner ? AppColors.teal.withAlpha(30) : Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: winner ? AppColors.teal : Colors.white24),
      ),
      child: Row(
        children: [
          if (winner) const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Text('👑', style: TextStyle(fontSize: 16)),
          ),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          Text('$correct/$asyncChallengeQuestionCount',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(width: 12),
          Text('$score',
              style: const TextStyle(color: AppColors.teal, fontSize: 18, fontWeight: FontWeight.w900)),
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
