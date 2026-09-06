import 'dart:async';

import 'package:flutter/material.dart';

import '../core/lang.dart';
import '../data/multiplayer_service.dart';
import '../models/multiplayer_models.dart';
import 'match_emotes.dart';

/// Ce se pune peste ORICE ecran de joc multiplayer: semnalul „adversarul se
/// reconectează" plus reacțiile rapide.
///
/// DE CE UN SINGUR WIDGET: cele 6 ecrane de joc au arbori de widgeturi foarte
/// diferite și delicate. Ambele funcții sunt strat peste joc, nu parte din el,
/// deci intră împreună prin slotul `floatingActionButton:` al [Scaffold]-ului —
/// o singură linie pe ecran, fără nicio operație pe arbore:
/// ```dart
/// Scaffold(floatingActionButton: MatchOverlay(matchId: id), ...)
/// ```
class MatchOverlay extends StatelessWidget {
  final String matchId;

  const MatchOverlay({super.key, required this.matchId});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        MatchReconnectingBanner(matchId: matchId),
        MatchEmotesOverlay(matchId: matchId),
      ],
    );
  }
}

/// „X se reconectează..." — pentru fiecare jucător de la masă al cărui semn de
/// viață ([MatchPlayer.lastSeenAt], scris de `matchHeartbeat`) a îmbătrânit.
///
/// Firestore trimite snapshot NOU doar când se scrie ceva, iar un jucător care
/// a picat exact asta nu mai face — de-aia mai există și un ceas local, altfel
/// avertismentul n-ar apărea niciodată tocmai în cazul care contează.
class MatchReconnectingBanner extends StatefulWidget {
  final String matchId;

  const MatchReconnectingBanner({super.key, required this.matchId});

  @override
  State<MatchReconnectingBanner> createState() => _MatchReconnectingBannerState();
}

class _MatchReconnectingBannerState extends State<MatchReconnectingBanner> {
  late final Stream<List<MatchPlayer>> _players =
      MultiplayerService.instance.watchPlayers(widget.matchId);
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = MultiplayerService.instance.currentPlayerId;
    return StreamBuilder<List<MatchPlayer>>(
      stream: _players,
      builder: (context, snap) {
        final gone = (snap.data ?? const <MatchPlayer>[])
            .where((p) => p.id != me && !p.eliminated && p.isReconnecting)
            .toList();
        if (gone.isEmpty) return const SizedBox.shrink();
        final names = gone.map((p) => p.name).join(', ');
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xE60B1229),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.withAlpha(140)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    tr('$names se reconectează...', '$names reconnecting...'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
