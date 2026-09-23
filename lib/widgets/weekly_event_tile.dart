import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/daily_challenge.dart' show dailyChallengeDateKey;
import '../core/lang.dart';
import '../core/theme.dart';
import '../core/weekly_event.dart';
import '../data/event_service.dart';
import '../data/storage_service.dart';
import '../screens/event_screen.dart';

/// Placa săptămânii tematice din Profil — intrarea în eveniment.
///
/// Trebuie să „cheme" fără să țipe: gradientul în culoarea categoriei curge
/// încet, cronometrul până duminică seara merge la secundă, iar cât cursa de
/// azi e încă disponibilă, placa pulsează și scrie „CURSA DE AZI TE AȘTEAPTĂ".
/// După ce ai alergat, se liniștește și arată locul tău.
class WeeklyEventTile extends StatefulWidget {
  const WeeklyEventTile({super.key});

  @override
  State<WeeklyEventTile> createState() => _WeeklyEventTileState();
}

class _WeeklyEventTileState extends State<WeeklyEventTile> with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(vsync: this, duration: const Duration(seconds: 4))
    ..repeat();
  Timer? _clock;
  bool _ranToday = true;
  int _daysPlayed = 0;
  int? _rank;

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _flow.dispose();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final event = weeklyEventFor(DateTime.now());
    final today = await StorageService.weeklyRunFor(dailyChallengeDateKey(DateTime.now()));
    final days = await StorageService.weeklyDaysPlayed(event.id);
    if (!mounted) return;
    setState(() {
      _ranToday = today?.done ?? false;
      _daysPlayed = days.length;
    });
    if (days.isNotEmpty) {
      final s = await EventService.instance.finalStanding(event.id);
      if (mounted && s != null) setState(() => _rank = s.rank);
    }
  }

  String _countdown(Duration d) {
    if (d.inDays >= 1) return tr('${d.inDays}z ${d.inHours % 24}h', '${d.inDays}d ${d.inHours % 24}h');
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final event = weeklyEventFor(now);
    final mode = weeklyThemeMode(now);
    final accent = mode?.accentColor ?? AppColors.orange;
    final dayIndex = now.difference(event.start).inDays + 1;
    final left = event.end.difference(now);

    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => EventScreen(event: event)));
        _load();
      },
      child: AnimatedBuilder(
        animation: _flow,
        builder: (context, child) {
          final k = _flow.value * 2 * pi;
          final pulse = _ranToday ? 0.0 : (0.5 + 0.5 * sin(k * 2));
          return Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment(cos(k), sin(k)),
                end: Alignment(-cos(k), -sin(k)),
                colors: [accent.withAlpha(120), AppColors.purple.withAlpha(70), accent.withAlpha(50)],
              ),
              border: Border.all(color: Color.lerp(accent.withAlpha(140), Colors.white, pulse * 0.6)!, width: 1.4 + pulse),
              boxShadow: [BoxShadow(color: accent.withAlpha((40 + 70 * pulse).round()), blurRadius: 18 + 10 * pulse, spreadRadius: -4)],
            ),
            child: child,
          );
        },
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: Colors.black.withAlpha(60), borderRadius: BorderRadius.circular(14)),
              child: Icon(mode?.icon ?? Icons.flag_rounded, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr(event.titleRo, event.titleEn).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                  const SizedBox(height: 3),
                  Text(
                    _ranToday
                        ? tr('Ziua ${min(dayIndex, 7)}/7 · $_daysPlayed zile jucate${_rank != null ? ' · locul #$_rank' : ''}',
                            'Day ${min(dayIndex, 7)}/7 · $_daysPlayed days played${_rank != null ? ' · rank #$_rank' : ''}')
                        : tr('CURSA DE AZI TE AȘTEAPTĂ', "TODAY'S RACE IS WAITING"),
                    style: TextStyle(
                        color: _ranToday ? Colors.white70 : AppColors.coin,
                        fontSize: 11.5,
                        fontWeight: _ranToday ? FontWeight.w600 : FontWeight.w900),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('se închide în', 'closes in'),
                    style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.w700)),
                Text(_countdown(left),
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
