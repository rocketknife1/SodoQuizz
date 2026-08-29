import 'package:flutter/material.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/moderation_service.dart';
import '../models/moderation.dart';

/// Lista jucătorilor blocați de contul de pe telefonul ăsta, cu deblocare.
///
/// De ce e un ecran separat, în Setări: blocarea se face din chat, unde te
/// deranjează cineva — dar exact acolo nu mai ajungi după ce i-ai ascuns
/// mesajele. Fără locul ăsta, o blocare dată din greșeală ar fi fost
/// definitivă.
class BlockedPlayersScreen extends StatefulWidget {
  const BlockedPlayersScreen({super.key});

  @override
  State<BlockedPlayersScreen> createState() => _BlockedPlayersScreenState();
}

class _BlockedPlayersScreenState extends State<BlockedPlayersScreen> {
  late Future<List<BlockedPlayer>> _future = ModerationService.instance.fetchBlocked();

  Future<void> _unblock(BlockedPlayer player) async {
    await ModerationService.instance.unblockPlayer(player.uid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${player.name} a fost deblocat.')));
    setState(() => _future = ModerationService.instance.fetchBlocked());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                    ),
                    const SizedBox(width: 4),
                    Text(tr('Jucători blocați', 'Blocked players'),
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<BlockedPlayer>>(
                  future: _future,
                  builder: (context, snap) {
                    final players = snap.data;
                    if (players == null) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.teal));
                    }
                    if (players.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            tr(
                                'Nu ai blocat pe nimeni.\n\nPoți bloca un jucător ținând apăsat pe mesajul lui, '
                                    'în chatul unei camere sau într-un fir de prieten.',
                                'You have not blocked anyone.\n\nYou can block a player by long-pressing their message, '
                                    'either in a room chat or in a friend thread.'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      itemCount: players.length,
                      itemBuilder: (context, i) => _BlockedRow(player: players[i], onUnblock: () => _unblock(players[i])),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedRow extends StatelessWidget {
  final BlockedPlayer player;
  final VoidCallback onUnblock;

  const _BlockedRow({required this.player, required this.onUnblock});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const Icon(Icons.block_rounded, color: AppColors.danger, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              player.name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onUnblock,
            child: Text(tr('Deblochează', 'Unblock'), style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
