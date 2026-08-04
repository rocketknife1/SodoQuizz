import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/game_helpers.dart';
import '../../core/theme.dart';
import '../../data/multiplayer_service.dart';
import '../../data/practice_bot.dart';
import '../../data/questions.dart';
import '../../models/multiplayer_models.dart';
import '../../models/question.dart';
import '../../widgets/avatar.dart';
import '../../widgets/blur_image.dart';
import '../../widgets/next_button.dart';
import 'multiplayer_results_screen.dart';

/// Meciul live 1 vs 1 (matchmaking public) sau cu prietenii (cameră privată
/// — identic din acest punct încolo). Fără alegere de categorie — toate
/// întrebările din toate categoriile formează un singur pool comun.
/// Întrebările NU se sincronizează prin Firestore: fiecare client încarcă
/// local exact același pool prin `loadAllQuestions()` și îl amestecă
/// determinist cu `Random(matchId.hashCode)`, ca toți să vadă exact aceeași
/// ordine.
///
/// Meciul e o CURSĂ DE UN MINUT ([multiplayerMatchSeconds]), nu o parcurgere
/// a întregului pool: înainte, ecranul rula prin toate cele ~1.400 de
/// întrebări, deci nu se termina niciodată de la sine — singurul fel de a
/// ajunge la rezultate era ca cineva să iasă. Acum cronometrul e cel care
/// încheie meciul, iar câte întrebări apuci în minutul ăla ține de tine.
///
/// Fiecare acțiune are preț (vezi game_helpers.dart): corect adaugă punctele
/// întrebării, greșit scade [multiplayerWrongPenalty], iar hint-ul 50/50
/// scade [multiplayerHintPenalty]. Scorul POATE ieși negativ — e intenționat,
/// și e tratat corect la împărțirea pool-ului (vezi classicPerformances).
class MultiplayerMatchScreen extends StatefulWidget {
  final String matchId;
  const MultiplayerMatchScreen({super.key, required this.matchId});

  @override
  State<MultiplayerMatchScreen> createState() => _MultiplayerMatchScreenState();
}

class _MultiplayerMatchScreenState extends State<MultiplayerMatchScreen> {
  List<Question> _questions = const [];
  bool _loading = true;
  int _qIndex = 0;
  int _myScore = 0;
  bool _answered = false;
  String? _selectedAnswer;
  bool _left = false;

  /// Hint-uri rămase pe TOT meciul (nu pe întrebare) — nu se scad din stocul
  /// de hint-uri al jucătorului și nu costă monede, ca nimeni să nu poată
  /// cumpăra avantaj într-un mod unde se pariază bani. Vezi
  /// [multiplayerHintsPerMatch].
  int _hintsLeft = multiplayerHintsPerMatch;
  bool _hintUsedHere = false;
  Set<String> _hiddenOptions = const {};

  Timer? _ticker;
  DateTime? _deadline;
  int _secondsLeft = multiplayerMatchSeconds;
  bool _midSynced = false;
  bool _finishing = false;

  /// TEMP BOT — adversarul simulat, vezi data/practice_bot.dart.
  PracticeBotBrain? _bot;

  Question get _current => _questions[_qIndex];

  int get _elapsed => multiplayerMatchSeconds - _secondsLeft;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final all = List.of(await loadAllQuestions())..shuffle(Random(widget.matchId.hashCode));
    if (!mounted) return;
    setState(() {
      _questions = all;
      _loading = false;
      _bot = PracticeBotBrain(questions: all, seed: widget.matchId.hashCode); // TEMP BOT
    });
    await _startClock();
  }

  /// Cronometrul pornește de la momentul de SERVER în care hostul a apăsat
  /// START, nu de când s-a deschis ecranul — altfel cine intră mai greu în
  /// meci ar juca mai mult decât ceilalți. Diferența se limitează totuși la
  /// intervalul 0..60: dacă ceasul telefonului e complet aiurea, jucătorul
  /// primește un minut întreg, nu un meci deja terminat.
  Future<void> _startClock() async {
    DateTime? startedAt;
    try {
      startedAt = await MultiplayerService.instance
          .watchMatch(widget.matchId)
          .map((m) => m.startedAt?.toDate())
          .firstWhere((t) => t != null)
          .timeout(const Duration(seconds: 8), onTimeout: () => null);
    } catch (e) {
      debugPrint('MultiplayerMatchScreen._startClock: startedAt indisponibil: $e');
    }
    if (!mounted) return;
    final start = startedAt ?? DateTime.now();
    _deadline = start.add(const Duration(seconds: multiplayerMatchSeconds));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _onTick();
  }

  void _onTick() {
    final deadline = _deadline;
    if (deadline == null || !mounted) return;
    final left = deadline.difference(DateTime.now()).inSeconds.clamp(0, multiplayerMatchSeconds);
    setState(() {
      _secondsLeft = left;
      _bot?.tick(_elapsed); // TEMP BOT
    });

    // Singura împrospătare a scorurilor celorlalți din tot meciul, la
    // jumătatea minutului. Vezi MultiplayerService.updateScore pentru de ce
    // NU se scrie la fiecare răspuns.
    if (!_midSynced && left <= multiplayerMatchSeconds ~/ 2) {
      _midSynced = true;
      MultiplayerService.instance.updateScore(matchId: widget.matchId, score: _myScore);
      final bot = _bot; // TEMP BOT
      if (bot != null) {
        PracticeBot.publishScore(matchId: widget.matchId, score: bot.score, finished: false);
      }
    }

    if (left <= 0) _finish();
  }

  /// Ieșire manuală din meci (buton înapoi) — nu se apelează și la
  /// navigarea normală spre rezultate, acolo se ocupă
  /// [MultiplayerResultsScreen] de curățare la final. Ieșirea din ecran NU
  /// depinde de succesul curățării din Firestore — dacă aia eșuează (rețea,
  /// reguli etc.), userul tot trebuie să poată pleca, nu să rămână blocat.
  Future<void> _leave() async {
    if (_left) return;
    _left = true;
    _ticker?.cancel();
    try {
      await MultiplayerService.instance.leaveMatch(widget.matchId);
    } catch (e) {
      debugPrint('MultiplayerMatchScreen._leave: leaveMatch a esuat: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  /// Sfârșitul minutului: scorul final se scrie O DATĂ, marcat ca definitiv,
  /// ca ecranul de rezultate să știe pe cine mai are de așteptat înainte să
  /// împartă pool-ul.
  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    _ticker?.cancel();
    _left = true; // rezultatele preiau curatenia finala, nu mai trecem si prin leaveMatch
    final bot = _bot; // TEMP BOT
    if (bot != null) {
      await PracticeBot.publishScore(matchId: widget.matchId, score: bot.score, finished: true);
    }
    try {
      await MultiplayerService.instance.finishWithScore(matchId: widget.matchId, score: _myScore);
    } catch (e) {
      debugPrint('MultiplayerMatchScreen._finish: scrierea scorului final a esuat: $e');
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MultiplayerResultsScreen(matchId: widget.matchId)),
    );
  }

  void _selectAnswer(String opt) {
    if (_answered || _finishing) return;
    final q = _current;
    final correct = opt == q.answer;
    setState(() {
      _answered = true;
      _selectedAnswer = opt;
      _myScore += correct ? q.maxPoints : -multiplayerWrongPenalty(q.maxPoints);
    });
  }

  /// Hint-ul din multiplayer NU limpezește poza (ca în modul solo), ci lasă
  /// pe ecran doar două variante: cea corectă și una greșită la întâmplare.
  void _useHint() {
    if (_answered || _hintUsedHere || _hintsLeft <= 0 || _finishing) return;
    final q = _current;
    final wrong = q.choices.where((c) => c != q.answer).toList()
      ..shuffle(Random(q.id.hashCode + _qIndex));
    setState(() {
      _hiddenOptions = wrong.take(max(0, wrong.length - 1)).toSet();
      _hintUsedHere = true;
      _hintsLeft--;
      _myScore -= multiplayerHintPenalty(q.maxPoints);
    });
  }

  void _next() {
    if (_qIndex + 1 >= _questions.length) {
      _finish();
      return;
    }
    setState(() {
      _qIndex++;
      _answered = false;
      _selectedAnswer = null;
      _hintUsedHere = false;
      _hiddenOptions = const {};
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.blue)));
    }
    if (_questions.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Nicio întrebare disponibilă.', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Înapoi')),
            ],
          ),
        ),
      );
    }

    final q = _current;
    final opts = [...q.choices]..shuffle(Random(q.id.hashCode + _qIndex));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: [q.color.withAlpha(200), const Color(0xFF0F172A)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: SafeArea(
            child: Column(
              children: [
                _buildPlayersRow(),
                _buildTimerBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      children: [
                        BlurImage(color: q.color, answer: q.answer, revealed: _answered, hintsUsed: 0, imageAssetPath: q.imageAssetPath),
                        const SizedBox(height: 10),
                        if (_answered) NextButton(onTap: _next) else _buildHintButton(q),
                        const SizedBox(height: 10),
                        _buildOptionsGrid(q, opts),
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

  /// Bara de timp e și cronometru, și indicator de urgență: sub 10 secunde
  /// devine roșie, ca să se vadă din colțul ochiului fără să citești cifra.
  Widget _buildTimerBar() {
    final fraction = _secondsLeft / multiplayerMatchSeconds;
    final urgent = _secondsLeft <= 10;
    final color = urgent ? AppColors.danger : AppColors.play;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Întrebarea ${_qIndex + 1}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text('$_secondsLeft s',
                  style: TextStyle(
                      color: color, fontSize: 15, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: Colors.white.withAlpha(28),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHintButton(Question q) {
    final available = _hintsLeft > 0 && !_hintUsedHere;
    final cost = multiplayerHintPenalty(q.maxPoints);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: available ? _useHint : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          disabledBackgroundColor: Colors.white.withAlpha(20),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(Icons.lightbulb_rounded,
            size: 18, color: available ? Colors.white : Colors.white38),
        label: Text(
          available
              ? 'HINT 50/50  ·  −$cost pct  ·  $_hintsLeft rămase'
              : (_hintUsedHere ? 'Hint folosit la întrebarea asta' : 'Nu mai ai hint-uri'),
          style: TextStyle(
            color: available ? Colors.white : Colors.white38,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildPlayersRow() {
    return SizedBox(
      height: 92,
      child: StreamBuilder<List<MatchPlayer>>(
        stream: MultiplayerService.instance.watchPlayers(widget.matchId),
        builder: (context, snap) {
          final players = snap.data ?? const <MatchPlayer>[];
          final me = MultiplayerService.instance.currentPlayerId;
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: players.map((p) {
              // propriul scor e mereu cel local (instant), al celorlalți e
              // ultimul publicat — vezi sincronizarea de la jumătatea meciului
              final score = p.id == me ? _myScore : p.score;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Avatar(size: 44, label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?', accentColor: pickAvatarColor(p.avatarSeed), photoUrl: p.photoUrl),
                    const SizedBox(height: 2),
                    Text('$score',
                        style: TextStyle(
                            color: score < 0 ? AppColors.danger : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildOptionsGrid(Question q, List<String> opts) {
    const letters = ['A', 'B', 'C', 'D'];
    final visible = [
      for (var i = 0; i < opts.length; i++)
        if (!_hiddenOptions.contains(opts[i])) (letter: letters[i], text: opts[i]),
    ];
    return Column(
      children: List.generate(visible.length, (i) {
        final opt = visible[i].text;
        var btnColor = Colors.white.withAlpha(18);
        var borderColor = Colors.white24;
        var letterBg = Colors.white.withAlpha(30);

        if (_answered) {
          if (opt == q.answer) {
            btnColor = const Color(0xFF1D9E75).withAlpha(70);
            borderColor = const Color(0xFF1D9E75);
            letterBg = const Color(0xFF1D9E75);
          } else if (opt == _selectedAnswer) {
            btnColor = const Color(0xFFE24B4A).withAlpha(70);
            borderColor = const Color(0xFFE24B4A);
            letterBg = const Color(0xFFE24B4A);
          }
        }

        return Padding(
          padding: EdgeInsets.only(bottom: i == visible.length - 1 ? 0 : 6),
          child: GestureDetector(
            onTap: _answered ? null : () => _selectAnswer(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: btnColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor, width: 1.5)),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: letterBg, shape: BoxShape.circle),
                    child: Text(visible[i].letter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(opt, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
