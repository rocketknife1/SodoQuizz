import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/game_helpers.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/higher_lower_data.dart';
import '../data/storage_service.dart';
import '../widgets/countdown_ring.dart';
import '../widgets/report_question_button.dart';
import 'home_screen.dart';
import 'loading_screen.dart';

/// "Higher or Lower" — variantă proprie a conceptului clasic
/// (higherlowergame.com): două subiecte oarecare (un brand, un animal, o
/// țară, orice), unul cu popularitatea deja dezvăluită ("campionul"),
/// celălalt ascuns ("provocatorul"). Ai [_roundSeconds] secunde să ghicești
/// dacă provocatorul e căutat MAI MULT sau MAI PUȚIN — fără nicio logică
/// între subiecte, doar popularitatea contează (vezi higher_lower_data.dart).
///
/// Ghicit corect → provocatorul devine noul campion, streak-ul crește, +1
/// punct de Clasament (aceeași infrastructură cumulativă pe 48h ca la
/// celelalte gamemoduri). Ghicit greșit SAU timpul expiră → Game Over;
/// recordul per-mod (StorageService.updateModeHighScore) se actualizează
/// DOAR dacă streak-ul e mai mare decât cel salvat.
class HigherLowerScreen extends StatefulWidget {
  const HigherLowerScreen({super.key});

  @override
  State<HigherLowerScreen> createState() => _HigherLowerScreenState();
}

class _HigherLowerScreenState extends State<HigherLowerScreen> with SingleTickerProviderStateMixin {
  static const _roundSeconds = 10;

  late final AnimationController _shakeController;
  List<HigherLowerItem> _pool = [];
  late HigherLowerItem _champion;
  late HigherLowerItem _challenger;
  int _streak = 0;
  int _bestScore = 0;
  bool _revealed = false;
  bool? _wasCorrect;
  int _secondsLeft = _roundSeconds;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    // primul "campion" nu are față de ce să evite duplicat (vezi [_draw],
    // care compară cu [_champion] — încă neinițializat la acest prim tras),
    // deci tragem direct din rezervă, fără verificarea de duplicat.
    _refillPool();
    _champion = _pool.removeLast();
    _challenger = _draw();
    _loadBest();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _loadBest() async {
    final best = await StorageService.getModeHighScore(higherLowerModeId);
    if (mounted) setState(() => _bestScore = best);
  }

  void _refillPool() {
    _pool = List.of(higherLowerItems)..shuffle(Random());
  }

  /// Scoate un subiect din rezervă, diferit de campionul curent — reface
  /// rezerva (reamestecată) când se golește, ca sesiunea să poată continua
  /// la nesfârșit fără să repete aceleași perechi mereu în aceeași ordine.
  HigherLowerItem _draw() {
    if (_pool.isEmpty) _refillPool();
    var next = _pool.removeLast();
    if (_pool.isEmpty) _refillPool();
    while (next.name == _champion.name && _pool.isNotEmpty) {
      final swap = _pool.removeLast();
      _pool.insert(0, next);
      next = swap;
    }
    return next;
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = _roundSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _revealed) {
        timer.cancel();
        return;
      }
      final next = _secondsLeft - 1;
      if (next <= 0) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
        _choose(null);
      } else {
        setState(() => _secondsLeft = next);
      }
    });
  }

  /// guessHigher == null înseamnă că a expirat timpul fără alegere — tratat
  /// ca răspuns greșit, la fel ca la celelalte gamemoduri cronometrate.
  /// Egalitate exactă de popularitate (foarte rar, given dataset-ul) nu
  /// penalizează jucătorul, indiferent ce a ales.
  void _choose(bool? guessHigher) {
    if (_revealed || _busy) return;
    _timer?.cancel();
    final tie = _challenger.popularity == _champion.popularity;
    final correct = tie || (guessHigher != null && (guessHigher ? _challenger.popularity > _champion.popularity : _challenger.popularity < _champion.popularity));
    setState(() {
      _revealed = true;
      _wasCorrect = correct;
      _busy = true;
    });
    if (correct) {
      Sfx.tileSelect();
    } else {
      _shakeController.forward(from: 0);
    }
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      if (correct) {
        _advance();
      } else {
        _gameOver();
      }
    });
  }

  /// Cât s-a câștigat în seria curentă — afișat la Game Over. Modul ăsta nu
  /// acorda deloc monede/XP înainte (singurul din joc), deși are riscul cel
  /// mai mare: o singură greșeală termină totul. De-aia plătește progresiv
  /// cu lungimea seriei (vezi higherLowerCoinsForStep).
  int _coinsEarned = 0;
  int _xpEarned = 0;

  Future<void> _advance() async {
    _streak++;
    final coins = higherLowerCoinsForStep(_streak);
    final xp = higherLowerXpForStep(_streak);
    _coinsEarned += coins;
    _xpEarned += xp;
    await StorageService.addCoins(coins);
    await StorageService.addXp(xp);
    await StorageService.addLeaderboardPoints(higherLowerModeId, 1);
    if (!mounted) return;
    setState(() {
      _champion = _challenger;
      _challenger = _draw();
      _revealed = false;
      _wasCorrect = null;
      _busy = false;
    });
    _startTimer();
  }

  Future<void> _gameOver() async {
    final isNewBest = _streak > _bestScore;
    if (isNewBest) await StorageService.updateModeHighScore(higherLowerModeId, _streak);
    if (!mounted) return;
    if (isNewBest) setState(() => _bestScore = _streak);
    _showGameOverDialog(isNewBest: isNewBest);
  }

  void _showGameOverDialog({required bool isNewBest}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Ai ales greșit! 📉', 'Wrong pick! 📉'), style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Ai ghicit corect de $_streak ori la rând.', 'You guessed right $_streak times in a row.'), style: const TextStyle(color: Colors.white70)),
            if (_coinsEarned > 0) ...[
              const SizedBox(height: 8),
              Text('+$_coinsEarned monede  •  +$_xpEarned XP',
                  style: const TextStyle(color: AppColors.coin, fontWeight: FontWeight.w800, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            if (isNewBest)
              const Text('🏆 Record nou!', style: TextStyle(color: AppColors.coin, fontWeight: FontWeight.w800))
            else
              Text(tr('Recordul tău rămâne $_bestScore.', 'Your best stays at $_bestScore.'), style: const TextStyle(color: Colors.white38, fontSize: 12.5)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _goHome();
            },
            child: Text(tr('Acasă', 'Home'), style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.purple),
            onPressed: () {
              Navigator.pop(dialogContext);
              _restart();
            },
            child: Text(tr('Joacă din nou', 'Play again'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _restart() {
    setState(() {
      _streak = 0;
      _refillPool();
      _champion = _draw();
      _challenger = _draw();
      _revealed = false;
      _wasCorrect = null;
      _busy = false;
    });
    _startTimer();
  }

  void _goHome() => Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LoadingScreen(nextBuilder: (_) => const HomeScreen(), duration: const Duration(milliseconds: 900)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.spaceGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    children: [
                      Expanded(child: _buildCard(_champion, revealedNumber: true, resultBorder: null)),
                      _buildMiddle(),
                      Expanded(
                        child: _buildCard(
                          _challenger,
                          revealedNumber: _revealed,
                          resultBorder: _revealed ? _wasCorrect : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildArrowButtons(),
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
      padding: const EdgeInsets.fromLTRB(8, 6, 20, 4),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
            onPressed: _goHome,
          ),
          const SizedBox(width: 4),
          const Text('Higher or Lower', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Text('🏆 $_bestScore', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFEF9F27).withAlpha(51),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFEF9F27).withAlpha(128)),
            ),
            child: Text('🔥 $_streak', style: const TextStyle(color: Color(0xFFEF9F27), fontSize: 13, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          ReportQuestionButton(
            questionId: _challenger.name,
            questionText: _challenger.name,
            category: 'Higher or Lower',
          ),
        ],
      ),
    );
  }

  Widget _buildMiddle() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Colors.white12, height: 1)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: AppColors.bg, shape: BoxShape.circle),
            child: CountdownRing(secondsLeft: _secondsLeft, totalSeconds: _roundSeconds, size: 44),
          ),
          const Expanded(child: Divider(color: Colors.white12, height: 1)),
        ],
      ),
    );
  }

  Widget _buildCard(HigherLowerItem item, {required bool revealedNumber, required bool? resultBorder}) {
    final borderColor = switch (resultBorder) {
      true => AppColors.play,
      false => AppColors.danger,
      null => Colors.white24,
    };
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (_, child) {
        if (resultBorder != false) return child!;
        final shake = sin(_shakeController.value * pi * 6) * 6;
        return Transform.translate(offset: Offset(shake, 0), child: child);
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(16),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor, width: resultBorder == null ? 1.4 : 2.2),
          boxShadow: resultBorder != null
              ? [BoxShadow(color: borderColor.withAlpha(90), blurRadius: 16, spreadRadius: -2)]
              : null,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 8),
            Text(
              item.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: revealedNumber
                  ? Container(
                      key: const ValueKey('revealed'),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: AppColors.coin.withAlpha(40), borderRadius: BorderRadius.circular(14)),
                      child: Text(
                        formatSearchVolume(item.popularity),
                        style: const TextStyle(color: AppColors.coin, fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    )
                  : const Text('❓ ❓ ❓', key: ValueKey('hidden'), style: TextStyle(color: Colors.white38, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 3)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArrowButtons() {
    final disabled = _revealed || _busy;
    return Row(
      children: [
        Expanded(child: _arrowButton(label: tr('MAI PUȚIN', 'LOWER'), icon: Icons.arrow_downward_rounded, color: AppColors.danger, onTap: disabled ? null : () => _choose(false))),
        const SizedBox(width: 12),
        Expanded(child: _arrowButton(label: tr('MAI MULT', 'HIGHER'), icon: Icons.arrow_upward_rounded, color: AppColors.play, onTap: disabled ? null : () => _choose(true))),
      ],
    );
  }

  Widget _arrowButton({required String label, required IconData icon, required Color color, required VoidCallback? onTap}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: enabled ? color.withAlpha(45) : Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: enabled ? color : Colors.white12, width: 1.6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: enabled ? color : Colors.white24, size: 26),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: enabled ? color : Colors.white24, fontSize: 12.5, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
