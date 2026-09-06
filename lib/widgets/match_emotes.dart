import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/auth_service.dart';
import '../data/multiplayer_service.dart';
import '../models/multiplayer_models.dart';

/// Cele 6 reacții rapide — aceleași în lobby și în meci.
const List<String> matchEmotes = ['👋', '😂', '🔥', '😎', '😱', '🤝'];

/// True dacă textul e DOAR unul din [matchEmotes] — mesajele de chat obișnuite
/// rămân mesaje, un emote se desenează ca reacție plutitoare.
bool isEmoteMessage(String text) => matchEmotes.contains(text.trim());

/// Reacțiile din timpul meciului, ca strat peste ecranul de joc.
///
/// DE CE PE CANALUL DE CHAT existent (`matches/{id}/chat`), nu unul nou: e deja
/// creat, are deja reguli (`senderId == auth.uid`), se curăță odată cu meciul,
/// și un emote E un mesaj — doar că se DESENEAZĂ altfel. Zero infrastructură
/// nouă pentru o funcție de „prezență".
///
/// Se pune ca `floatingActionButton:` pe [Scaffold]-ul ecranului de joc —
/// slot existent, deci nu cere nicio operație pe arborele de widgeturi:
/// ```dart
/// Scaffold(floatingActionButton: MatchEmotesOverlay(matchId: id), ...)
/// ```
/// Numele îl află singur (`multiplayerIdentity`) — ecranele nu-l mai pasează.
/// Butonul stă în colțul din dreapta-jos; reacțiile primite urcă deasupra lui.
class MatchEmotesOverlay extends StatefulWidget {
  final String matchId;

  const MatchEmotesOverlay({super.key, required this.matchId});

  @override
  State<MatchEmotesOverlay> createState() => _MatchEmotesOverlayState();
}

class _MatchEmotesOverlayState extends State<MatchEmotesOverlay> {
  StreamSubscription<List<ChatMessage>>? _sub;
  bool _open = false;

  /// Reacțiile afișate acum, cel mai nou la final. Fiecare se stinge singură
  /// după [_lifetime].
  final List<_FloatingEmote> _floating = [];

  /// Id-urile deja arătate — la (re)abonare sosește tot istoricul recent, iar
  /// fără asta ar exploda pe ecran zeci de reacții vechi deodată.
  final Set<String> _seen = {};
  bool _primed = false;
  String _myName = '?';

  static const _lifetime = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _sub = MultiplayerService.instance.watchChat(widget.matchId).listen(_onChat);
    AuthService.instance.multiplayerIdentity().then((id) {
      if (mounted) _myName = id.name;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onChat(List<ChatMessage> all) {
    final emotes = all.where((m) => isEmoteMessage(m.text)).toList();
    // Primul snapshot doar „umple" setul de văzute: mesajele de dinainte de
    // intrarea mea în ecran nu au ce căuta ca reacții noi.
    if (!_primed) {
      _primed = true;
      for (final m in emotes) {
        _seen.add(m.id);
      }
      return;
    }
    final fresh = emotes.where((m) => _seen.add(m.id)).toList();
    if (fresh.isEmpty || !mounted) return;
    setState(() {
      for (final m in fresh) {
        _floating.add(_FloatingEmote(id: m.id, emoji: m.text.trim(), who: m.senderName));
      }
    });
    Timer(_lifetime, () {
      if (!mounted) return;
      setState(() {
        for (final m in fresh) {
          _floating.removeWhere((f) => f.id == m.id);
        }
      });
    });
  }

  void _send(String emoji) {
    setState(() => _open = false);
    MultiplayerService.instance.sendChatMessage(
      matchId: widget.matchId,
      senderName: _myName,
      text: emoji,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
          // Reacțiile primite, cea mai nouă jos, lângă buton.
          for (final f in _floating.reversed.take(4).toList().reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _EmoteBubble(emoji: f.emoji, who: f.who),
            ),
          if (_open)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xE60B1229),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in matchEmotes)
                    GestureDetector(
                      onTap: () => _send(e),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                        child: Text(e, style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                ],
              ),
            ),
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _open ? AppColors.teal : const Color(0xCC0B1229),
              border: Border.all(color: Colors.white30),
            ),
            child: Icon(_open ? Icons.close_rounded : Icons.add_reaction_rounded,
                color: Colors.white, size: 21),
          ),
        ),
      ],
    );
  }
}

class _FloatingEmote {
  final String id;
  final String emoji;
  final String who;
  const _FloatingEmote({required this.id, required this.emoji, required this.who});
}

class _EmoteBubble extends StatelessWidget {
  final String emoji;
  final String who;
  const _EmoteBubble({required this.emoji, required this.who});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.scale(scale: 0.6 + 0.4 * t, alignment: Alignment.bottomRight, child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xE60B1229),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
