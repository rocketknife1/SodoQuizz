import 'dart:math';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/theme.dart';

/// O singură recompensă agregată (icon+total) pentru rezumatul din
/// [CollectAllOverlay] — [amount] e deja SUMA tuturor quest-urilor colectate
/// deodată pentru resursa asta, nu recompensa unui singur quest. [targetKey]
/// și [onImpact] sunt folosite DUPĂ ce jucătorul apasă "Grozav!", ca fiecare
/// resursă să-și zboare propria animație spre pastila ei din header (vezi
/// apelantul, QuestsScreen._launchCollectAllFlights).
class CollectAllEntry {
  final IconData icon;
  final Color color;
  final int amount;
  final GlobalKey targetKey;
  final VoidCallback? onImpact;
  const CollectAllEntry({
    required this.icon,
    required this.color,
    required this.amount,
    required this.targetKey,
    this.onImpact,
  });
}

/// Rezumatul butonului "Colectează tot": SPRE DEOSEBIRE de [collectRewards]
/// (o animație separată, secvențială, per resursă — la 5-6 quest-uri
/// colectate deodată "bubuie telefonul" cu zboruri succesive, la cererea
/// explicită a userului), aici e O SINGURĂ explozie de nori din care apar
/// SIMULTAN toate iconițele resurselor câștigate, fiecare cu totalul
/// dedesubt. Balanțele (storage) trebuie scrise ÎNAINTE de a arăta acest
/// dialog — vezi apelantul (QuestsScreen._collectAll). Când jucătorul apasă
/// "Grozav!" (dialogul se închide), apelantul lansează pentru fiecare
/// resursă câte o animație de zbor spre pastila ei din header — toate
/// pornesc aproape deodată, eșalonate cu doar 200ms între lansări (nu
/// așteptate secvențial), ca "explozia" să pară un singur moment, dar fără
/// ca traseele suprapuse perfect să se încurce vizual.
class CollectAllOverlay extends StatefulWidget {
  final List<CollectAllEntry> entries;
  final int questCount;
  const CollectAllOverlay({super.key, required this.entries, required this.questCount});

  static Future<void> show(
    BuildContext context, {
    required List<CollectAllEntry> entries,
    required int questCount,
  }) {
    Sfx.rewardPop();
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => CollectAllOverlay(entries: entries, questCount: questCount),
      transitionBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    );
  }

  @override
  State<CollectAllOverlay> createState() => _CollectAllOverlayState();
}

class _CollectAllOverlayState extends State<CollectAllOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  static const _cloudCount = 10;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.purple.withAlpha(140)),
              boxShadow: [BoxShadow(color: AppColors.purple.withAlpha(60), blurRadius: 30, spreadRadius: -6)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Colectat tot!', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '${widget.questCount} quest-uri revendicate dintr-o dată',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 170,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < _cloudCount; i++) _buildCloudPuff(i, t),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _buildEntries(t)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                ElevatedButton(
                  onPressed: t >= 1 ? () => Navigator.pop(context) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.play,
                    disabledBackgroundColor: Colors.white24,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('Grozav!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Un "puf" de nor — se umflă și se estompează din centru, ca recompensele
  /// să pară că "apar din nori", nu doar că se decupează pe fundal.
  Widget _buildCloudPuff(int i, double t) {
    final angle = (i / _cloudCount) * 2 * pi;
    final burst = Interval(0.0, 0.5, curve: Curves.easeOut).transform(t.clamp(0.0, 1.0));
    final fade = 1 - Interval(0.2, 0.75).transform(t.clamp(0.0, 1.0));
    if (fade <= 0) return const SizedBox.shrink();
    final dist = 20 + burst * 70;
    final pos = Offset(cos(angle), sin(angle)) * dist;
    final size = 30 + burst * 24;
    return Transform.translate(
      offset: pos,
      child: Opacity(
        opacity: (fade * 0.8).clamp(0.0, 1.0),
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
      ),
    );
  }

  Widget _buildEntries(double t) {
    final n = widget.entries.length;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 14,
      children: [
        for (var i = 0; i < n; i++) _buildEntry(widget.entries[i], i, n, t),
      ],
    );
  }

  /// Fiecare iconiță+total apare cu o mică întârziere una față de alta
  /// (staggered), ca să pară că "se materializează din nori" pe rând, nu
  /// toate deodată dintr-o singură bucată.
  Widget _buildEntry(CollectAllEntry e, int i, int n, double t) {
    const revealStart = 0.35;
    final stagger = revealStart + (i / n) * 0.25;
    final local = Interval(stagger.clamp(0.0, 0.9), (stagger + 0.35).clamp(0.0, 1.0), curve: Curves.easeOutBack)
        .transform(t.clamp(0.0, 1.0));
    final opacity = local.clamp(0.0, 1.0);
    final scale = (0.4 + local * 0.6).clamp(0.0, 1.3);
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: e.color.withAlpha(40), shape: BoxShape.circle),
              child: Icon(e.icon, color: e.color, size: 26),
            ),
            const SizedBox(height: 6),
            Text('+${e.amount}', style: TextStyle(color: e.color, fontSize: 16, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}
