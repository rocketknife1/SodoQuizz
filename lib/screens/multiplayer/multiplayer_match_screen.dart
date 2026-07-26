import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/multiplayer_service.dart';
import '../../data/questions.dart';
import '../../models/multiplayer_models.dart';
import '../../models/question.dart';
import '../../widgets/avatar.dart';
import '../../widgets/blur_image.dart';
import '../../widgets/next_button.dart';
import 'multiplayer_results_screen.dart';

/// Meciul live de 5 jucători (privat sau matchmaking public — identic din
/// acest punct încolo). Fără alegere de categorie — toate întrebările din
/// toate categoriile (999 acum, oricâte vor mai fi adăugate) formează un
/// singur pool comun. Întrebările NU se sincronizează prin Firestore:
/// fiecare client încarcă local exact același pool prin `loadAllQuestions()`
/// și îl amestecă determinist cu `Random(matchId.hashCode)`, ca toți să vadă
/// exact aceeași ordine — doar scorul se scrie live (vezi planul de
/// arhitectură). Boții își simulează scorul 100% local, pe fiecare client.
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
  Timer? _botTimer;
  final Map<String, int> _botScores = {};

  Question get _current => _questions[_qIndex];

  @override
  void initState() {
    super.initState();
    _load();
    _botTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) => _simulateBots());
  }

  Future<void> _load() async {
    final all = List.of(await loadAllQuestions())..shuffle(Random(widget.matchId.hashCode));
    if (!mounted) return;
    setState(() {
      _questions = all;
      _loading = false;
    });
  }

  void _simulateBots() {
    // simulare simpla, locala: fiecare bot are ~55% sansa sa "raspunda
    // corect" la fiecare tick si primeste un scor plauzibil - nu trebuie sa
    // fie inteligenti, doar sa nu strice experienta (decizie explicita, MVP).
    final rnd = Random();
    setState(() {
      for (final id in _botScores.keys.toList()) {
        if (rnd.nextDouble() < 0.55) {
          _botScores[id] = (_botScores[id] ?? 0) + 200 + rnd.nextInt(500);
        }
      }
    });
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    super.dispose();
  }

  void _selectAnswer(String opt) {
    if (_answered) return;
    final correct = opt == _current.answer;
    setState(() {
      _answered = true;
      _selectedAnswer = opt;
      if (correct) _myScore += _current.maxPoints;
    });
    MultiplayerService.instance.updateScore(matchId: widget.matchId, score: _myScore);
  }

  void _next() {
    if (_qIndex + 1 >= _questions.length) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => MultiplayerResultsScreen(matchId: widget.matchId, botScores: Map.of(_botScores))),
      );
      return;
    }
    setState(() {
      _qIndex++;
      _answered = false;
      _selectedAnswer = null;
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

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [q.color.withAlpha(200), const Color(0xFF0F172A)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: SafeArea(
          child: Column(
            children: [
              _buildPlayersRow(),
              const SizedBox(height: 4),
              Text('Întrebarea ${_qIndex + 1} din ${_questions.length}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    children: [
                      BlurImage(color: q.color, answer: q.answer, revealed: _answered, hintsUsed: 0, imageAssetPath: q.imageAssetPath),
                      const SizedBox(height: 10),
                      if (_answered) NextButton(onTap: _next),
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
    );
  }

  Widget _buildPlayersRow() {
    return SizedBox(
      height: 92,
      child: StreamBuilder<List<MatchPlayer>>(
        stream: MultiplayerService.instance.watchPlayers(widget.matchId),
        builder: (context, snap) {
          final players = snap.data ?? const <MatchPlayer>[];
          for (final p in players) {
            if (p.isBot) _botScores.putIfAbsent(p.id, () => 0);
          }
          final me = MultiplayerService.instance.currentPlayerId;
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: players.map((p) {
              final score = p.id == me ? _myScore : (p.isBot ? (_botScores[p.id] ?? 0) : p.score);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Avatar(size: 44, label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?', accentColor: pickAvatarColor(p.avatarSeed)),
                    const SizedBox(height: 2),
                    Text('$score', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
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
    return Column(
      children: List.generate(opts.length, (i) {
        final opt = opts[i];
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
          padding: EdgeInsets.only(bottom: i == opts.length - 1 ? 0 : 6),
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
    );
  }
}
