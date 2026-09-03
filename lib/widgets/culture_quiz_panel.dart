import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/admin_reveal.dart';
import '../core/ads_service.dart';
import '../core/game_helpers.dart';
import '../core/quest_bump.dart';
import '../core/reward_collector.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/culture_questions.dart';
import '../data/storage_service.dart';
import 'countdown_ring.dart';
import 'report_question_button.dart';

enum _Phase { teaser, cooldown, playing, justFinished }

/// Panou compact, integrat direct în Home (nu navighează spre alt ecran):
/// un mini-quiz de cultură generală (BETA), fără imagine, cronometrat
/// (35s/întrebare). O fereastră = [StorageService.cultureQuizPlayLimit] runde
/// de [cultureQuizQuestionCount] întrebări (curent 3) — între runde e o
/// pauză cu un buton "Pregătit pentru runda X" (nu pornește automat), iar
/// la finalul rundei finale recompensa se aplică prin tap pe COLECTEAZĂ
/// (sau automat, după 10s, dacă utilizatorul nu apasă — vezi
/// [_autoCollectFinalRound]), moment în care pornește și cooldown-ul de
/// [StorageService.cultureQuizWindowMinutes] minute. markDailyChallengeDone
/// se apelează la finalul fiecărei runde, pentru contorul de quiz-uri
/// terminate și quest-uri.
///
/// Recompensele NU se acordă după fiecare răspuns — se acumulează local pe
/// durata TUTUROR celor 3 runde și se aplică o singură dată, la finalul
/// rundei finale, cu aceeași animație/sunet ca la revendicarea unui quest
/// (vezi [CoinRewardOverlay] + [Sfx]).
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
  Duration? _cooldownRemaining;
  Timer? _cooldownTicker;
  Timer? _autoRecordTimer;
  bool _playRecorded = false;
  bool _watchingAd = false;

  /// Runda curentă (1-based) din fereastra activă — vezi
  /// [StorageService.cultureQuizPlaysInWindow]. Cu [StorageService.cultureQuizPlayLimit]
  /// runde per fereastră, "runda finală" e mereu ultima dintre ele.
  int _roundNumber = 1;
  int get _totalRounds => StorageService.cultureQuizPlayLimit;
  bool get _isFinalRound => _roundNumber >= _totalRounds;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  @override
  void dispose() {
    _questionTimer?.cancel();
    _cooldownTicker?.cancel();
    _autoRecordTimer?.cancel();
    super.dispose();
  }

  /// Înregistrează runda curentă (1 sau 2) o singură dată — fie la tap pe
  /// "Pregătit pentru runda X", fie automat, oricare vine prima. Fără asta,
  /// un utilizator care iese din aplicație fără să apese butonul ar rămâne
  /// blocat la nesfârșit pe ecranul de pauză dintre runde.
  Future<void> _recordPlayOnce() async {
    if (_playRecorded) return;
    _playRecorded = true;
    _autoRecordTimer?.cancel();
    await StorageService.recordCultureQuizPlay();
  }

  /// Pornește cooldown-ul de [StorageService.cultureQuizWindowMinutes] o
  /// singură dată — fie la tap pe COLECTEAZĂ, fie automat după 10s, oricare
  /// vine prima (vezi [_collect]). Separat de [_recordPlayOnce]: doar runda
  /// FINALĂ pornește efectiv cooldown-ul, ca numărătoarea afișată jucătorului
  /// să înceapă mereu de la [StorageService.cultureQuizWindowMinutes] întregi,
  /// nu de la momentul rundei 1.
  Future<void> _startCooldownOnce() async {
    if (_playRecorded) return;
    _playRecorded = true;
    _autoRecordTimer?.cancel();
    await StorageService.startCultureQuizCooldown();
  }

  Future<void> _checkAvailability() async {
    final canPlay = await StorageService.canPlayCultureQuiz();
    if (!mounted || canPlay) return;
    await _enterCooldown();
  }

  /// Arată numărătoarea inversă până la următoarea sesiune disponibilă —
  /// același tipar de ticker local (1s, fără interogare repetată a
  /// storage-ului) ca la RingMascot._startCountdown.
  Future<void> _enterCooldown() async {
    final remaining = await StorageService.cultureQuizCooldownRemaining();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.cooldown;
      _cooldownRemaining = remaining;
    });
    _cooldownTicker?.cancel();
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final next = (_cooldownRemaining ?? Duration.zero) - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        timer.cancel();
        setState(() {
          _phase = _Phase.teaser;
          _cooldownRemaining = null;
        });
        return;
      }
      setState(() => _cooldownRemaining = next);
    });
  }

  /// Reclamă recompensată (sau simulare dacă nu e încărcată — vezi
  /// [AdsService.watchOrSimulate]) care sare direct peste cooldown-ul de
  /// [StorageService.cultureQuizWindowMinutes] minute, în loc să aștepți.
  Future<void> _skipCooldownWithAd() async {
    if (_watchingAd) return;
    setState(() => _watchingAd = true);
    final earned = await AdsService.instance.watchOrSimulate();
    if (!mounted) return;
    if (!earned) {
      setState(() => _watchingAd = false);
      return;
    }
    await StorageService.skipCultureQuizCooldown();
    if (!mounted) return;
    _cooldownTicker?.cancel();
    setState(() {
      _watchingAd = false;
      _phase = _Phase.teaser;
      _cooldownRemaining = null;
    });
  }

  /// Pornește o rundă nouă — dar doar dacă mai e loc în fereastra de
  /// [StorageService.cultureQuizPlayLimit] runde / [StorageService.cultureQuizWindowMinutes]
  /// minute; altfel arată cooldown-ul în loc să pornească. Runda curentă se
  /// deduce din câte runde s-au jucat deja în fereastră — robust la restart
  /// de aplicație în mijlocul ciclului de 3 runde (nu ținem noi contorul).
  Future<void> _start() async {
    if (!await StorageService.canPlayCultureQuiz()) {
      await _enterCooldown();
      return;
    }
    final playsSoFar = await StorageService.cultureQuizPlaysInWindow();
    if (!mounted) return;
    final round = playsSoFar + 1;
    // sesiune nouă = alt set aleatoriu din pool-ul global unic de întrebări.
    _questions = (List.of(cultureQuestions)..shuffle(Random()))
        .take(cultureQuizQuestionCount)
        .toList();
    setState(() {
      _phase = _Phase.playing;
      qIndex = 0;
      correctCount = 0;
      _roundNumber = round;
      // recompensele se acumulează pe TOATE cele 3 runde ale ferestrei —
      // resetate doar la runda 1, nu la fiecare rundă (vezi _buildFinished:
      // rundele 1-2 doar continuă, fără să colecteze, colectarea reală se
      // face o singură dată, la runda finală).
      if (round == 1) {
        _coinsEarned = 0;
        _xpEarned = 0;
        _livesEarned = 0;
      }
      _collecting = false;
      _playRecorded = false;
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
      // fără risc aici (nu se pierd vieți) — după plafonul zilnic de
      // răspunsuri corecte, rata scade mult; altfel "Daily Challenge" ar
      // putea rula la nesfârșit la rată integrală. Vezi game_helpers.dart.
      final correctToday = await StorageService.getDailyCounter('culture_correct');
      final fullRate = correctToday < cultureFullRateDailyCorrectCap;
      _coinsEarned += fullRate ? cultureCoinsPerCorrect : cultureReducedCoinsPerCorrect;
      _xpEarned += fullRate ? cultureXpPerCorrect : cultureReducedXpPerCorrect;
      await StorageService.incrementDailyCounter('culture_correct');
      if (mounted) await bumpQuestMetric(context, 'culture_quiz_correct', 1);
      // Bonus de viață la fiecare [cultureCorrectPerLife] răspunsuri corecte,
      // cel mult [cultureMaxLivesPerDay] pe zi — înainte era 1 la 3 corecte
      // fără niciun plafon, adică 10 vieți gratuite pe zi doar de aici.
      if (correctCount % cultureCorrectPerLife == 0) {
        final livesToday = await StorageService.getDailyCounter('culture_lives');
        if (livesToday < cultureMaxLivesPerDay) {
          await StorageService.incrementDailyCounter('culture_lives');
          _livesEarned++;
        }
      }
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
    const completionCoins = cultureBatchCompletionCoins;
    const completionXp = cultureBatchCompletionXp;
    // contorul de quiz-uri terminate + progresul de quest se înregistrează
    // la final indiferent de colectare — doar monede/XP/vieți așteaptă tap-ul
    // pe COLECTEAZĂ.
    await StorageService.markDailyChallengeDone();
    if (mounted) await bumpQuestMetric(context, 'daily_challenge_done', 1);
    if (mounted) await bumpQuestMetric(context, 'culture_quiz_batches', 1);
    // bonusul de finalizare a lotului există doar pentru primele loturi ale
    // zilei — dincolo de plafon, lotul tot contează (contorul de mai sus),
    // dar fără bonusul suplimentar de completare.
    final batchesToday = await StorageService.getDailyCounter('culture_batches');
    final withinDailyBatchCap = batchesToday < cultureFullRateDailyBatchCap;
    await StorageService.incrementDailyCounter('culture_batches');
    if (!mounted) return;
    setState(() {
      _phase = _Phase.justFinished;
      if (withinDailyBatchCap) {
        _coinsEarned += completionCoins;
        _xpEarned += completionXp;
      }
    });
    // cooldown-ul de rate-limit pornește doar acum, la finalul lotului — nu
    // la apăsarea START — dar nu așteptăm nedefinit tap-ul pe COLECTEAZĂ:
    // dacă utilizatorul iese din aplicație fără să colecteze, sesiunea tot
    // se înregistrează după 10s, ca să nu rămână blocată la nesfârșit. La
    // runda finală, cele 10s chiar aplică recompensa și pornesc cooldown-ul
    // (nu doar consumă slotul din fereastră) — jucătorul nu pierde ce a
    // câștigat doar fiindcă a ieșit din aplicație fără să apese COLECTEAZĂ.
    _autoRecordTimer?.cancel();
    _autoRecordTimer = Timer(const Duration(seconds: 10), _isFinalRound ? _autoCollectFinalRound : _recordPlayOnce);
  }

  void _autoCollectFinalRound() {
    if (!mounted || _collecting) return;
    _collect();
  }

  /// Rundele 1-2 nu colectează nimic — recompensa rămâne acumulată local
  /// (vezi [_start]) și doar trece la runda următoare. Tot aici se
  /// înregistrează slotul din fereastra de rate-limit (nu la 10s auto, ca
  /// să nu rămână "disponibilă la nesfârșit" dacă utilizatorul stă mult pe
  /// ecranul de pauză înainte să apese).
  Future<void> _continueRound() async {
    await _recordPlayOnce();
    if (!mounted) return;
    await _start();
  }

  /// Aplică toată recompensa acumulată, în 3 etape separate și în ordine
  /// fixă (monede → XP → vieți) — vezi [collectRewards]. Apelat doar la
  /// finalul rundei finale (vezi [_buildFinished]).
  Future<void> _collect() async {
    if (_collecting) return;
    setState(() => _collecting = true);
    await _startCooldownOnce();
    if (!mounted) return;
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
    // continuă automat cu un set nou de întrebări — dar doar cât mai ai
    // sesiuni disponibile în fereastra curentă (vezi [_start]); altfel
    // trece în cooldown, în loc de "START" manual.
    await _start();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // înălțime minimă generoasă — panoul trebuie să coboare vizibil sub
      // butonul Setări, nu doar cât încape strict conținutul din faza
      // curentă (altfel faza "teaser", mai scurtă, făcea cardul să pară mic).
      constraints: const BoxConstraints(minHeight: 340),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      alignment: Alignment.center,
      child: switch (_phase) {
        _Phase.teaser => _buildTeaser(),
        _Phase.cooldown => _buildCooldown(),
        _Phase.playing => _buildPlaying(),
        _Phase.justFinished => _buildFinished(),
      },
    );
  }

  Widget _buildCooldown() {
    final r = _cooldownRemaining ?? Duration.zero;
    final m = r.inMinutes.toString().padLeft(2, '0');
    final s = (r.inSeconds % 60).toString().padLeft(2, '0');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.hourglass_bottom_rounded, color: Colors.white38, size: 32),
        const SizedBox(height: 10),
        Text(
          tr('Cultură Generală', 'General Knowledge'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          tr('Ai jucat de ${StorageService.cultureQuizPlayLimit} ori în ultimele ${StorageService.cultureQuizWindowMinutes} minute',
              'You played ${StorageService.cultureQuizPlayLimit} times in the last ${StorageService.cultureQuizWindowMinutes} minutes'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 12),
        Text('$m:$s', style: const TextStyle(color: Colors.white70, fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(tr('până la următoarea sesiune', 'until the next session'), style: const TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _watchingAd ? null : _skipCooldownWithAd,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _watchingAd ? Colors.white10 : AppColors.coin.withAlpha(35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _watchingAd ? Colors.white24 : AppColors.coin),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_display_rounded, size: 14, color: _watchingAd ? Colors.white38 : AppColors.coin),
                const SizedBox(width: 6),
                // Flexible + ellipsis, nu Text simplu — pe carduri înguste
                // (panoul e doar o parte din lățimea ecranului, vezi
                // home_screen.dart) textul lung depășea butonul (overflow).
                Flexible(
                  child: Text(
                    _watchingAd
                        ? tr('Se încarcă reclama...', 'Loading the ad...')
                        : tr('Reclamă • Sari peste așteptare', 'Watch ad • Skip the wait'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _watchingAd ? Colors.white38 : AppColors.coin),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTeaser() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.public_rounded, color: AppColors.coin, size: 34),
        const SizedBox(height: 8),
        Text(
          tr('Cultură Generală', 'General Knowledge'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
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
          tr('${StorageService.cultureQuizPlayLimit} runde • ${cultureSecondsPerQuestion}s/întrebare',
              '${StorageService.cultureQuizPlayLimit} rounds • ${cultureSecondsPerQuestion}s/question'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 10),
        ),
        Text(
          tr('Recompensă la finalul rundei ${StorageService.cultureQuizPlayLimit}',
              'Reward at the end of round ${StorageService.cultureQuizPlayLimit}'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white38, fontSize: 8.5),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _start,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: ShapeDecoration(
              color: AppColors.coin,
              shape: const BeveledRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
              shadows: [BoxShadow(color: AppColors.coin.withAlpha(110), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: const Text('START', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
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
            ReportQuestionButton(
              questionId: q.question,
              questionText: q.question,
              category: 'Cultură Generală',
            ),
            CountdownRing(secondsLeft: secondsLeft, totalSeconds: cultureSecondsPerQuestion, size: 34),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          q.question,
          textAlign: TextAlign.center,
          // fără maxLines/ellipsis — panoul nu mai e limitat la înălțimea
          // butoanelor din stânga, deci întrebările lungi se pot afișa
          // complet, crescând înălțimea cardului cât e nevoie.
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, height: 1.25),
        ),
        const SizedBox(height: 10),
        ...List.generate(q.choices.length, (i) {
          final opt = q.choices[i];
          var bg = Colors.white.withAlpha(18);
          var border = Colors.white24;
          // la timeout fără tap, selectedAnswer rămâne null — nu se
          // dezvăluie răspunsul corect, doar trece mai departe în tăcere.
          if (answered && selectedAnswer != null) {
            if (opt == q.answer) {
              bg = const Color(0xFF1D9E75).withAlpha(110);
              border = const Color(0xFF1D9E75);
            } else if (opt == selectedAnswer) {
              bg = const Color(0xFFE24B4A).withAlpha(110);
              border = const Color(0xFFE24B4A);
            }
          }

          // Toggle-ul de admin „vezi răspunsul corect" (core/admin_reveal.dart).
          final adminHint =
              !answered && adminAnswerRevealOn && opt == q.answer;
          if (adminHint) {
            bg = adminRevealColor.withAlpha(28);
            border = adminRevealColor;
          }
          return Padding(
            padding: EdgeInsets.only(bottom: i == q.choices.length - 1 ? 0 : 6),
            child: GestureDetector(
              onTap: answered ? null : () => _select(opt),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border, width: adminHint ? 2.2 : 1)),
                child: Text(
                  opt,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Pauza dintre runde (rundele 1-2): nu colectează nimic — doar arată un
  /// rezumat scurt și un buton "Pregătit pentru runda X" care pornește
  /// direct runda următoare. Recompensa acumulată se arată doar la runda
  /// finală (vezi [_buildFinished]), ca să nu pară că s-a "pierdut" ceva
  /// între runde.
  Widget _buildFinished() {
    if (!_isFinalRound) {
      final nextLabel = _roundNumber == 1
          ? tr('Pregătit pentru runda a II-a', 'Ready for round two')
          : tr('Pregătit pentru runda finală', 'Ready for the final round');
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.celebration_rounded, color: AppColors.coin, size: 26),
          const SizedBox(height: 8),
          Text(
            tr('Runda $_roundNumber/$_totalRounds terminată — $correctCount/${_questions.length} corecte',
                'Round $_roundNumber/$_totalRounds done — $correctCount/${_questions.length} correct'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _continueRound,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(color: AppColors.coin, borderRadius: BorderRadius.circular(20)),
              child: Text(
                nextLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.celebration_rounded, color: AppColors.coin, size: 26),
        const SizedBox(height: 8),
        Text(
          tr('Runda finală terminată!', 'Final round done!'),
          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          tr('+$_coinsEarned monede\n+$_xpEarned XP${_livesEarned > 0 ? '\n+$_livesEarned viață/vieți' : ''}',
              '+$_coinsEarned coins\n+$_xpEarned XP${_livesEarned > 0 ? '\n+$_livesEarned ${_livesEarned == 1 ? 'life' : 'lives'}' : ''}'),
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
              _collecting ? '...' : tr('COLECTEAZĂ', 'COLLECT'),
              style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

}
