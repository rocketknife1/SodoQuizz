import 'package:flutter/material.dart';

import '../core/cosmetics.dart';
import '../core/game_event.dart';
import '../core/gamemodes.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/event_service.dart';
import '../data/multiplayer_service.dart';
import '../models/multiplayer_models.dart' show pickAvatarColor;
import '../widgets/avatar_art.dart';
import '../widgets/cosmetic_title.dart';
import '../widgets/league_badge.dart';
import '../widgets/space_background.dart';
import 'game_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadBoard();
  }

  Future<void> _loadBoard() async {
    final b = await EventService.instance.leaderboard(eventId: widget.event.id);
    if (mounted) setState(() => _board = b);
  }

  String? get _categoryTitle {
    final id = widget.event.categoryId;
    if (id.isEmpty) return null;
    final m = gameModes.where((g) => g.id == id);
    return m.isEmpty ? null : m.first.title;
  }

  Future<void> _play() async {
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
                      ElevatedButton(
                        onPressed: _play,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.coin,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        child: Text(cat != null ? tr('JOACĂ $cat', 'PLAY $cat') : tr('JOACĂ', 'PLAY'),
                            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
                      ),
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
