import 'dart:math';

import 'package:flutter/material.dart';

import '../core/cosmetics.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../core/weekly_event.dart';

/// Dialogul de final al săptămânii tematice — FĂRĂ skip: nici back, nici tap
/// în afară. Se închide doar cu „COLECTEAZĂ", apăsabil abia după ce s-a
/// dezvăluit tot, ca premiul să fie văzut, nu doar încasat.
///
/// Coregrafia, pe un singur ceas:
///  • 0,0–1,4 s — locul se numără în jos, de la ultimul până la al tău;
///  • 1,4 s    — pocnet: medalia (top 3) sau insigna locului;
///  • 1,9 s    — premiul: monede, gems, titlul deblocat;
///  • 2,6 s    — apare butonul.
///
/// Întoarce `true` la colectare (singurul fel de a-l închide).
Future<bool?> showWeeklyRewardDialog(
  BuildContext context, {
  required String themeName,
  required int rank,
  required int participants,
  required int daysPlayed,
  required WeeklyReward reward,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withAlpha(215),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (ctx, _, __) => PopScope(
      canPop: false,
      child: _WeeklyRewardBody(
        themeName: themeName,
        rank: rank,
        participants: participants,
        daysPlayed: daysPlayed,
        reward: reward,
      ),
    ),
  );
}

class _WeeklyRewardBody extends StatefulWidget {
  final String themeName;
  final int rank;
  final int participants;
  final int daysPlayed;
  final WeeklyReward reward;
  const _WeeklyRewardBody({
    required this.themeName,
    required this.rank,
    required this.participants,
    required this.daysPlayed,
    required this.reward,
  });

  @override
  State<_WeeklyRewardBody> createState() => _WeeklyRewardBodyState();
}

class _WeeklyRewardBodyState extends State<_WeeklyRewardBody> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..forward();

  static const double _countEnd = 1.4;
  static const double _popAt = 1.4;
  static const double _rewardAt = 1.9;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color get _medal => switch (widget.reward.tier) {
        WeeklyTier.champion => const Color(0xFFFFD54F),
        WeeklyTier.second => const Color(0xFFCFD8DC),
        WeeklyTier.third => const Color(0xFFD7995B),
        WeeklyTier.top10 => AppColors.purple,
        _ => AppColors.teal,
      };

  String get _headline => switch (widget.reward.tier) {
        WeeklyTier.champion => tr('CAMPIONUL SĂPTĂMÂNII!', 'CHAMPION OF THE WEEK!'),
        WeeklyTier.second || WeeklyTier.third => tr('PE PODIUM!', 'ON THE PODIUM!'),
        WeeklyTier.top10 => tr('ÎN TOP 10!', 'TOP 10!'),
        WeeklyTier.top25 => tr('ÎN SFERTUL DE SUS!', 'TOP QUARTER!'),
        WeeklyTier.participant => tr('AI DUS-O PÂNĂ LA CAPĂT', 'YOU SAW IT THROUGH'),
        WeeklyTier.tried => tr('AI FOST ÎN CURSĂ', 'YOU WERE IN THE RACE'),
      };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value * 2.6;
          final counting = t < _countEnd;
          // numărătoarea: repede la început, încetinește spre locul tău
          final k = Curves.easeOutCubic.transform((t / _countEnd).clamp(0.0, 1.0));
          final from = max(widget.participants, widget.rank);
          final shownRank = (from - (from - widget.rank) * k).round().clamp(widget.rank, from);
          final pop = t >= _popAt ? Curves.elasticOut.transform(((t - _popAt) / 0.7).clamp(0.0, 1.0)) : 0.0;
          final rewardIn = ((t - _rewardAt) / 0.4).clamp(0.0, 1.0);
          final podium = widget.reward.tier.index <= WeeklyTier.third.index;

          return Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 22),
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              decoration: BoxDecoration(
                color: const Color(0xFF15122B),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _medal.withAlpha(160), width: 1.6),
                boxShadow: [BoxShadow(color: _medal.withAlpha((90 * pop).round().clamp(0, 90)), blurRadius: 40, spreadRadius: 2)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('SĂPTĂMÂNA ${widget.themeName.toUpperCase()} S-A ÎNCHEIAT',
                          '${widget.themeName.toUpperCase()} WEEK IS OVER'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 130,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (pop > 0)
                          // raze care se deschid în spatele medaliei
                          Transform.rotate(
                            angle: t * 0.4,
                            child: CustomPaint(size: const Size(200, 200), painter: _RaysPainter(color: _medal, strength: pop.clamp(0.0, 1.0))),
                          ),
                        Transform.scale(
                          scale: counting ? 1.0 : 0.7 + 0.3 * pop,
                          child: Container(
                            width: 108,
                            height: 108,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: [
                                (counting ? Colors.white24 : _medal).withAlpha(counting ? 60 : 255),
                                (counting ? Colors.white10 : _medal).withAlpha(counting ? 30 : 140),
                              ]),
                              border: Border.all(color: counting ? Colors.white30 : Colors.white, width: 3),
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!counting && podium)
                                  Icon(Icons.emoji_events_rounded, color: Colors.black.withAlpha(170), size: 30),
                                Text('#$shownRank',
                                    style: TextStyle(
                                      color: counting ? Colors.white : Colors.black87,
                                      fontSize: podium && !counting ? 26 : 34,
                                      fontWeight: FontWeight.w900,
                                    )),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: pop.clamp(0.0, 1.0),
                    child: Column(
                      children: [
                        Text(_headline,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _medal, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 1)),
                        const SizedBox(height: 4),
                        Text(
                          tr('Locul ${widget.rank} din ${widget.participants} · ${widget.daysPlayed}/7 zile jucate',
                              'Rank ${widget.rank} of ${widget.participants} · ${widget.daysPlayed}/7 days played'),
                          style: const TextStyle(color: Colors.white60, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Opacity(
                    opacity: rewardIn,
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - rewardIn)),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(Icons.monetization_on_rounded, AppColors.coin, '+${widget.reward.coins}'),
                          if (widget.reward.gems > 0) _chip(Icons.diamond_rounded, AppColors.blue, '+${widget.reward.gems}'),
                          if (widget.reward.honor != null) _titleChip(),
                        ],
                      ),
                    ),
                  ),
                  if (widget.reward.tier == WeeklyTier.tried) ...[
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: rewardIn,
                      child: Text(
                        tr('Joacă cel puțin $weeklyMinDaysForRank zile săptămâna asta ca să intri la premiile pe loc.',
                            'Play at least $weeklyMinDaysForRank days this week to compete for rank prizes.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _c.isCompleted ? 1 : 0,
                    child: ElevatedButton(
                      onPressed: _c.isCompleted ? () => Navigator.pop(context, true) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.coin,
                        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: Text(tr('COLECTEAZĂ', 'COLLECT'),
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ConstrainedBox, nu doar Row+mainAxisSize.min: într-un Wrap fiecare copil
  // primește lățimea maximă a rândului, nu una proprie — un titlu lung
  // ("Titlu: Campionul Săptămânii") ar depăși dialogul în loc să se taie.
  Widget _chip(IconData icon, Color color, String text) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withAlpha(36),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withAlpha(150)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
      );

  Widget _titleChip() {
    final title = widget.reward.honor == weeklyChampionHonor ? PlayerTitle.campionulSaptamanii : PlayerTitle.pePodium;
    final (ro, en) = titleLabel(title);
    return _chip(Icons.workspace_premium_rounded, _medal, tr('Titlu: $ro', 'Title: $en'));
  }
}

class _RaysPainter extends CustomPainter {
  final Color color;
  final double strength;
  _RaysPainter({required this.color, required this.strength});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()..color = color.withAlpha((70 * strength).round());
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + cos(a - 0.1) * size.width / 2, c.dy + sin(a - 0.1) * size.width / 2)
        ..lineTo(c.dx + cos(a + 0.1) * size.width / 2, c.dy + sin(a + 0.1) * size.width / 2)
        ..close();
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) => old.strength != strength || old.color != color;
}
