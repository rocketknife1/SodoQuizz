import 'dart:math';

import 'package:flutter/material.dart';

import '../core/cosmetics.dart';
import '../core/daily_challenge.dart' show dailyChallengeDateKey;
import '../core/game_event.dart';
import '../core/progression.dart';
import '../core/weekly_event.dart';
import '../core/gamemodes.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/event_service.dart';
import '../data/multiplayer_service.dart';
import '../data/storage_service.dart';
import '../models/multiplayer_models.dart' show pickAvatarColor;
import '../widgets/avatar_art.dart';
import '../widgets/cosmetic_title.dart';
import '../widgets/league_badge.dart';
import '../widgets/space_background.dart';
import 'game_screen.dart';
import 'weekly_run_screen.dart';

/// Ecranul unui eveniment limitat (vezi core/game_event.dart): descriere,
/// zile rămase, categoria pusă în față + bonusul de monede, şi clasamentul
/// propriu al evenimentului.
class EventScreen extends StatefulWidget {
  final GameEvent event;
  const EventScreen({super.key, required this.event});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  EventLeaderboard? _board;

  /// Săptămâna tematică: zilele în care am terminat cursa, dacă am alergat
  /// azi și nivelul (premiile se afișează la valoarea mea reală).
  Set<String> _days = const {};
  bool _ranToday = false;
  int _level = 1;

  @override
  void initState() {
    super.initState();
    _loadBoard();
  }

  Future<void> _loadBoard() async {
    final b = await EventService.instance.leaderboard(eventId: widget.event.id);
    if (widget.event.dailyRunOnly) {
      final days = await StorageService.weeklyDaysPlayed(widget.event.id);
      final today = await StorageService.weeklyRunFor(dailyChallengeDateKey(DateTime.now()));
      final level = levelForXp(await StorageService.getXp());
      if (!mounted) return;
      setState(() {
        _days = days;
        _ranToday = today?.done ?? false;
        _level = level;
      });
    }
    if (mounted) setState(() => _board = b);
  }

  String? get _categoryTitle {
    final id = widget.event.categoryId;
    if (id.isEmpty) return null;
    final m = gameModes.where((g) => g.id == id);
    return m.isEmpty ? null : m.first.title;
  }

  Future<void> _play() async {
    if (widget.event.dailyRunOnly) {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => WeeklyRunScreen(event: widget.event)));
      _loadBoard();
      return;
    }
    final id = widget.event.categoryId;
    if (id.isEmpty) {
      Navigator.pop(context);
      return;
    }
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => GameScreen(gameModeId: id)));
    _loadBoard();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final me = MultiplayerService.instance.currentPlayerId;
    final daysLeft = e.daysLeftAt(DateTime.now());
    final cat = _categoryTitle;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SpaceBackground(
        child: SafeArea(
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
                  Expanded(
                    child: Text(tr(e.titleRo, e.titleEn),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            AppColors.purple.withAlpha(70),
                            AppColors.orange.withAlpha(40),
                          ]),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.orange.withAlpha(110)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.event_rounded, color: AppColors.coin, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  daysLeft > 0
                                      ? tr('încă $daysLeft ${daysLeft == 1 ? 'zi' : 'zile'}',
                                          '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left')
                                      : tr('ultima zi', 'last day'),
                                  style: const TextStyle(color: AppColors.coin, fontSize: 12, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            if (tr(e.descRo, e.descEn).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(tr(e.descRo, e.descEn),
                                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
                            ],
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (cat != null) _chip(Icons.category_rounded, cat),
                                if (e.coinBonus > 1.0)
                                  _chip(Icons.monetization_on_rounded,
                                      tr('×${e.coinBonus} monede', '×${e.coinBonus} coins')),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (e.dailyRunOnly) ...[
                        _dayStrip(),
                        const SizedBox(height: 12),
                      ],
                      ElevatedButton(
                        onPressed: _play,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: e.dailyRunOnly && _ranToday ? Colors.white24 : AppColors.coin,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        child: Text(
                            e.dailyRunOnly
                                ? (_ranToday
                                    ? tr('AI ALERGAT AZI ✓ — REVINO MÂINE', 'RACED TODAY ✓ — BACK TOMORROW')
                                    : tr('CURSA ZILEI', "TODAY'S RACE"))
                                : (cat != null ? tr('JOACĂ $cat', 'PLAY $cat') : tr('JOACĂ', 'PLAY')),
                            style: TextStyle(
                                color: e.dailyRunOnly && _ranToday ? Colors.white70 : Colors.black,
                                fontWeight: FontWeight.w900)),
                      ),
                      if (e.dailyRunOnly) ...[
                        const SizedBox(height: 16),
                        _prizeLadder(),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          const Icon(Icons.leaderboard_rounded, color: Colors.white54, size: 16),
                          const SizedBox(width: 6),
                          Text(tr('Clasamentul evenimentului', 'Event leaderboard'),
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
                        Text(tr('Nimeni n-a marcat puncte încă. Fii primul!',
                            'No points scored yet. Be first!'),
                            style: const TextStyle(color: Colors.white38, fontSize: 13))
                      else ...[
                        for (var i = 0; i < _board!.top.length; i++)
                          _row(i + 1, _board!.top[i], _board!.top[i].uid == me),
                        if (_board!.me != null && _board!.myRankBelowTop != null) ...[
                          const Padding(padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text('⋯', style: TextStyle(color: Colors.white38))),
                          _row(_board!.myRankBelowTop!, _board!.me!, true),
                        ],
                      ],
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

  /// Cele 7 zile ale săptămânii: bifate (am alergat), azi (pulsează dacă nu
  /// am alergat încă), trecute ratate, viitoare.
  Widget _dayStrip() {
    final start = widget.event.start;
    final now = DateTime.now();
    const names = ['L', 'Ma', 'Mi', 'J', 'V', 'S', 'D'];
    const namesEn = ['M', 'Tu', 'W', 'Th', 'F', 'Sa', 'Su'];
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(builder: (context) {
              final day = DateTime(start.year, start.month, start.day + i);
              final key = dailyChallengeDateKey(day);
              final played = _days.contains(key);
              final isToday = key == dailyChallengeDateKey(now);
              final past = day.isBefore(DateTime(now.year, now.month, now.day));
              final color = played
                  ? AppColors.play
                  : isToday
                      ? AppColors.orange
                      : past
                          ? AppColors.danger.withAlpha(140)
                          : Colors.white24;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  children: [
                    Container(
                      height: 30,
                      decoration: BoxDecoration(
                        color: color.withAlpha(played || isToday ? 60 : 25),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: color, width: isToday ? 2 : 1),
                      ),
                      alignment: Alignment.center,
                      child: played
                          ? const Icon(Icons.check_rounded, color: AppColors.play, size: 17)
                          : Text(isToday ? '!' : (past ? '×' : ''),
                              style: TextStyle(color: color, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(height: 3),
                    Text(tr(names[i], namesEn[i]),
                        style: TextStyle(
                            color: isToday ? AppColors.orange : Colors.white54,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              );
            }),
          ),
      ],
    );
  }

  /// Ce se câștigă la final, la valoarea MEA (premiile cresc cu nivelul). Ca
  /// fiecare să vadă cât mai are până la pragul următor.
  Widget _prizeLadder() {
    final participants = _board?.top.length ?? 0;
    WeeklyReward at(int rank) => weeklyRewardFor(
        rank: rank, participants: max(participants, 60), daysPlayed: weeklyMinDaysForRank, level: _level);
    final rows = <(String, WeeklyReward)>[
      (tr('Locul 1', '1st'), at(1)),
      (tr('Locurile 2–3', '2nd–3rd'), at(2)),
      (tr('Top 10', 'Top 10'), at(4)),
      (tr('Sfertul de sus', 'Top quarter'), at(10 + 1)),
      (tr('Oricine termină $weeklyMinDaysForRank zile', 'Anyone who finishes $weeklyMinDaysForRank days'), at(60)),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('PREMII DUMINICĂ SEARA', 'PRIZES ON SUNDAY NIGHT'),
              style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 8),
          for (final (label, r) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700))),
                  Text('+${r.coins}', style: const TextStyle(color: AppColors.coin, fontSize: 12.5, fontWeight: FontWeight.w900)),
                  const Icon(Icons.monetization_on_rounded, color: AppColors.coin, size: 14),
                  if (r.gems > 0) ...[
                    const SizedBox(width: 6),
                    Text('+${r.gems}', style: const TextStyle(color: AppColors.blue, fontSize: 12.5, fontWeight: FontWeight.w900)),
                    const Icon(Icons.diamond_rounded, color: AppColors.blue, size: 14),
                  ],
                  if (r.honor != null) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFD54F), size: 15),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white70, size: 13),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _row(int rank, EventScoreEntry e, bool isMe) {
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
          SizedBox(width: 26, child: Text('$rank',
              style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w800))),
          AvatarWithLeagueBadge(
            size: 32,
            label: e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
            accentColor: pickAvatarColor(e.uid),
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
                Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                CosmeticTitle(titleId: e.equippedTitle, fontSize: 9),
              ],
            ),
          ),
          Text('${e.points}', style: const TextStyle(color: AppColors.coin, fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
