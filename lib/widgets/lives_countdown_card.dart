import 'dart:async';
import 'package:flutter/material.dart';
import '../core/repeating_animation.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';

/// Contorul de reîncărcare a vieților, afișat pe Home DOAR când jucătorul e
/// pe 0 vieți — de îndată ce are măcar una, dispare complet (nu se vede
/// niciun timer). Cât e vizibil, arată exact cât mai e până se încarcă
/// următoarea viață, cu o inimă care pulsează și un inel de progres care se
/// umple în timp real.
///
/// Se autoascunde imediat ce contorul ajunge la zero și viața chiar a fost
/// creditată — [onLifeRecharged] lasă ecranul-gazdă să-și reîmprospăteze
/// balanțele în aceeași clipă, fără să aștepte o navigare.
class LivesCountdownCard extends StatefulWidget {
  final VoidCallback? onLifeRecharged;
  const LivesCountdownCard({super.key, this.onLifeRecharged});

  @override
  State<LivesCountdownCard> createState() => _LivesCountdownCardState();
}

class _LivesCountdownCardState extends State<LivesCountdownCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _ticker;
  int _lives = -1;
  Duration _remaining = Duration.zero;

  static const _period = Duration(minutes: StorageService.livesRechargeMinutes);

  @override
  void initState() {
    super.initState();
    _pulse = RepeatingAnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _refresh();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Viețile se pot schimba sub cardul afișat: un grant de la admin, un
    // premiu încasat în fundal, sau salvarea coborâtă din cloud. Vezi
    // StorageService.balanceRevision.
    StorageService.balanceRevision.addListener(_refresh);
  }

  @override
  void dispose() {
    StorageService.balanceRevision.removeListener(_refresh);
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  /// Citire completă din storage (inclusiv reîncărcarea pasivă, care se face
  /// în getLives/livesRechargeRemaining) — la pornire și ori de câte ori
  /// numărătoarea trece de zero.
  Future<void> _refresh() async {
    final lives = await StorageService.getLives();
    final remaining = await StorageService.livesRechargeRemaining();
    if (!mounted) return;
    final gained = _lives == 0 && lives > 0;
    setState(() {
      _lives = lives;
      _remaining = remaining;
    });
    if (gained) widget.onLifeRecharged?.call();
  }

  /// Scădem local, secundă cu secundă (fără să lovim storage-ul de 60 de ori
  /// pe minut) și recitim doar când expiră — atunci chiar s-a schimbat ceva.
  void _tick() {
    if (!mounted || _lives != 0) return;
    if (_remaining.inSeconds <= 1) {
      _refresh();
      return;
    }
    setState(() => _remaining -= const Duration(seconds: 1));
  }

  static String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // regula cerută explicit: contorul există DOAR pe 0 vieți.
    if (_lives != 0) return const SizedBox.shrink();
    final progress = _period.inSeconds == 0
        ? 0.0
        : (1 - _remaining.inSeconds / _period.inSeconds).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = 0.55 + 0.45 * _pulse.value;
        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.danger.withAlpha(28),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.danger.withAlpha((150 * glow).round())),
            boxShadow: [
              BoxShadow(
                color: AppColors.danger.withAlpha((70 * glow).round()),
                blurRadius: 20,
                spreadRadius: -6,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(AppColors.life),
                ),
                ScaleTransition(
                  scale: Tween<double>(begin: 0.82, end: 1.0).animate(
                      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                  child: const Icon(Icons.favorite_rounded,
                      color: AppColors.life, size: 16),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('Nu mai ai vieți', 'You are out of lives'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  tr('Următoarea se încarcă în', 'Next one recharges in'),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Text(
            _format(_remaining),
            style: const TextStyle(
              color: AppColors.life,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
