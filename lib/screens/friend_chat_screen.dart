import 'package:flutter/material.dart';
import '../core/chat_filter.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/friend_chat_service.dart';
import '../data/moderation_service.dart';
import '../data/multiplayer_service.dart';
import '../models/friend_chat.dart';
import '../models/multiplayer_models.dart' show pickAvatarColor;
import '../models/player_profile.dart';
import '../widgets/avatar.dart';
import '../widgets/moderation_sheet.dart';

/// Firul privat de chat cu un prieten. Se deschide DOAR de pe rândul lui din
/// ecranul de Prieteni — nu există listă de conversații și nu apare nicăieri
/// altundeva în joc. Chatul din camera multiplayer rămâne separat și
/// neschimbat (vezi RoomLobbyScreen).
class FriendChatScreen extends StatefulWidget {
  final PlayerProfile friend;

  const FriendChatScreen({super.key, required this.friend});

  @override
  State<FriendChatScreen> createState() => _FriendChatScreenState();
}

class _FriendChatScreenState extends State<FriendChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  String get _me => MultiplayerService.instance.currentPlayerId;

  @override
  void initState() {
    super.initState();
    // Marcat citit la deschidere, ca bulina de pe ecranul de Prieteni să
    // dispară. Mesajele care sosesc cât ecranul e deschis se marchează din
    // stream (vezi build) — altfel bulina ar reapărea pentru mesaje pe care
    // le-am văzut cu ochii mei.
    FriendChatService.instance.markRead(widget.friend.uid);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final raw = _controller.text;
    final cleaned = sanitizeChatMessage(raw);
    if (cleaned.isEmpty) return;
    setState(() => _sending = true);
    _controller.clear();
    if (containsProfanity(raw) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesajul a fost trimis cu cuvintele nepotrivite acoperite.')),
      );
    }
    await FriendChatService.instance.sendMessage(widget.friend.uid, raw);
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              // Într-un fir cu o singură persoană, ascunderea mesajelor unul
              // câte unul (ca în camera multiplayer) ar lăsa un ecran gol,
              // fără explicație. Aici se spune pe față că e blocat și cum se
              // dă înapoi.
              Expanded(
                child: ValueListenableBuilder<Set<String>>(
                  valueListenable: ModerationService.instance.blockedIds,
                  builder: (context, blocked, _) =>
                      blocked.contains(widget.friend.uid) ? _buildBlockedNotice() : _buildMessages(),
                ),
              ),
              _buildInput(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
          ),
          Avatar(
            size: 36,
            label: widget.friend.name.isNotEmpty ? widget.friend.name[0].toUpperCase() : '?',
            accentColor: pickAvatarColor(widget.friend.avatarSeed),
            photoUrl: widget.friend.photoUrl,
            style: avatarStyleFromId(widget.friend.avatarStyle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.friend.name,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () => showModerationSheet(
              context,
              targetUid: widget.friend.uid,
              targetName: widget.friend.name,
              contextId: 'friend_chat',
            ),
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white54),
            tooltip: tr('Raportează sau blochează', 'Report or block'),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedNotice() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block_rounded, color: AppColors.danger, size: 34),
            const SizedBox(height: 12),
            Text(
              tr('L-ai blocat pe ${widget.friend.name}.\nNu vezi mesajele lui cât timp e blocat.',
                  'You blocked ${widget.friend.name}.\nYou will not see their messages while they are blocked.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                await ModerationService.instance.unblockPlayer(widget.friend.uid);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${widget.friend.name} a fost deblocat.')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(tr('Deblochează', 'Unblock'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    return StreamBuilder<List<FriendMessage>>(
      stream: FriendChatService.instance.watchMessages(widget.friend.uid),
      builder: (context, snap) {
        final messages = snap.data;
        if (messages == null) {
          return Center(child: CircularProgressIndicator(color: AppColors.teal));
        }
        if (messages.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                tr('Niciun mesaj încă.\nScrie-i primul.', 'No messages yet.\nSay hi first.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 13, height: 1.4),
              ),
            ),
          );
        }
        // Mesajul sosit cât ecranul e deschis e deja văzut — se marchează pe
        // loc, altfel bulina din lista de prieteni ar apărea pentru el.
        if (messages.last.senderId != _me) {
          FriendChatService.instance.markRead(widget.friend.uid);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: messages.length,
          itemBuilder: (context, i) => _bubble(messages[i]),
        );
      },
    );
  }

  Widget _bubble(FriendMessage m) {
    final mine = m.senderId == _me;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: mine
            ? null
            : () => showModerationSheet(
                  context,
                  targetUid: widget.friend.uid,
                  targetName: widget.friend.name,
                  messageText: m.text,
                  contextId: 'friend_chat',
                ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: mine ? AppColors.teal.withAlpha(190) : Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.3)),
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLength: chatMessageMaxLength,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                counterText: '',
                hintText: tr('Mesaj...', 'Message...'),
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withAlpha(15),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(
            onPressed: _sending ? null : _send,
            icon: Icon(Icons.send_rounded, color: AppColors.teal),
          ),
        ],
      ),
    );
  }
}

/// Bulina de „mesaj nou" folosită pe rândul prietenului din FriendsScreen.
class UnreadDot extends StatelessWidget {
  const UnreadDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
    );
  }
}
