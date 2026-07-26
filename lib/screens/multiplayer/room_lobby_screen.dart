import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/multiplayer_service.dart';
import '../../data/storage_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/avatar.dart';
import 'multiplayer_match_screen.dart';

/// Lobby-ul unei camere private: cod vizibil, jucători live, chat live, și
/// (doar pentru host) butonul Start. Toți jucătorii ascultă statusul
/// meciului — când hostul apasă Start, fiecare client navighează automat la
/// [MultiplayerMatchScreen].
class RoomLobbyScreen extends StatefulWidget {
  final String matchId;
  final bool isHost;
  const RoomLobbyScreen({super.key, required this.matchId, required this.isHost});

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  final _chatController = TextEditingController();
  final _scrollController = ScrollController();
  String _displayName = '';
  bool _navigated = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    StorageService.getDisplayName().then((n) {
      if (mounted) setState(() => _displayName = n);
    });
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await MultiplayerService.instance.leaveMatch(widget.matchId);
    if (mounted) Navigator.pop(context);
  }

  void _maybeNavigateToMatch(MatchInfo info) {
    if (_navigated || info.status != MatchStatus.playing) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => MultiplayerMatchScreen(matchId: widget.matchId)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.bgGradient),
          child: SafeArea(
            child: StreamBuilder<MatchInfo>(
              stream: MultiplayerService.instance.watchMatch(widget.matchId),
              builder: (context, matchSnap) {
                final info = matchSnap.data;
                if (info != null) _maybeNavigateToMatch(info);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                      child: Row(
                        children: [
                          IconButton(onPressed: _leave, icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70)),
                          const SizedBox(width: 4),
                          const Text('Cameră privată', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    _buildCodeBanner(info?.code),
                    const SizedBox(height: 8),
                    _buildPlayers(),
                    Expanded(child: _buildChat()),
                    _buildChatInput(),
                    if (widget.isHost) _buildStartButton(),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeBanner(String? code) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.blue.withAlpha(30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.blue.withAlpha(120)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Cod: ', style: TextStyle(color: Colors.white70, fontSize: 14)),
          Text(
            code ?? '-----',
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayers() {
    return SizedBox(
      height: 96,
      child: StreamBuilder<List<MatchPlayer>>(
        stream: MultiplayerService.instance.watchPlayers(widget.matchId),
        builder: (context, snap) {
          final players = snap.data ?? const <MatchPlayer>[];
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: players
                .map((p) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Avatar(
                            size: 56,
                            label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                            accentColor: pickAvatarColor(p.avatarSeed),
                          ),
                          const SizedBox(height: 4),
                          Text(p.isHost ? '${p.name} 👑' : p.name,
                              style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildChat() {
    return StreamBuilder<List<ChatMessage>>(
      stream: MultiplayerService.instance.watchChat(widget.matchId),
      builder: (context, snap) {
        final messages = snap.data ?? const <ChatMessage>[];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          itemCount: messages.length,
          itemBuilder: (context, i) {
            final m = messages[i];
            final me = m.senderId == MultiplayerService.instance.currentPlayerId;
            return Align(
              alignment: me ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                decoration: BoxDecoration(
                  color: me ? AppColors.blue.withAlpha(180) : Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!me) Text(m.senderName, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChatInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Mesaj...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withAlpha(15),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(onPressed: _send, icon: const Icon(Icons.send_rounded, color: AppColors.blue)),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    _chatController.clear();
    await MultiplayerService.instance.sendChatMessage(matchId: widget.matchId, senderName: _displayName, text: text);
  }

  Widget _buildStartButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => MultiplayerService.instance.startMatch(widget.matchId),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.play, padding: const EdgeInsets.symmetric(vertical: 14)),
          child: const Text('START', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ),
      ),
    );
  }
}
