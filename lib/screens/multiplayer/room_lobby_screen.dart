import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/auth_service.dart';
import '../../data/multiplayer_service.dart';
import '../../data/storage_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/avatar.dart';
import '../../widgets/network_scan_animation.dart';
import 'multiplayer_higher_lower_screen.dart';
import 'multiplayer_match_screen.dart';

/// Lobby-ul unei camere private: cod vizibil, jucători live, chat live, și
/// (doar pentru host) butonul Start. Toți jucătorii ascultă statusul
/// meciului — când hostul apasă Start, fiecare client navighează automat la
/// [MultiplayerMatchScreen].
class RoomLobbyScreen extends StatefulWidget {
  final String matchId;
  final bool isHost;

  /// Miza plătită ca să ajungi în acest lobby — taxa fixă PLUS pariul (vezi
  /// pickMatchStake / core/betting.dart). Returnată integral dacă pleci
  /// înainte ca meciul să apuce să înceapă, vezi [_leave].
  final int stakePaid;

  const RoomLobbyScreen({super.key, required this.matchId, required this.isHost, this.stakePaid = 0});

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
    AuthService.instance.multiplayerIdentity().then((identity) {
      if (mounted) setState(() => _displayName = identity.name);
    });
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Ieșirea din ecran NU depinde de succesul curățării din Firestore —
  /// dacă aia eșuează, userul tot trebuie să poată pleca, nu să rămână blocat.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      await MultiplayerService.instance.leaveMatch(widget.matchId);
    } catch (e) {
      debugPrint('RoomLobbyScreen._leave: leaveMatch a esuat: $e');
    } finally {
      // _navigated rămâne false dacă (din perspectiva acestui client) meciul
      // nu a apucat să înceapă efectiv - miza n-a "cumparat" nimic, se
      // returnează integral (taxă + pariu), vezi pickMatchStake.
      if (!_navigated && widget.stakePaid > 0) {
        await StorageService.addCoins(widget.stakePaid);
      }
      if (mounted) Navigator.pop(context);
    }
  }

  void _maybeNavigateToMatch(MatchInfo info) {
    if (_navigated || info.status != MatchStatus.playing) return;
    _navigated = true;
    final gameMode = info.gameMode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => gameMode == MatchGameMode.higherLower
              ? MultiplayerHigherLowerScreen(matchId: widget.matchId)
              : MultiplayerMatchScreen(matchId: widget.matchId),
        ),
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
            child: Stack(
              children: [
                // fundal decorativ, ca lobby-ul să nu pară "mort" cât se
                // așteaptă — aceeași poziționare/dimensiune ca în Join
                // Online (centrată, 220), nu întinsă pe tot ecranul;
                // needecodabilă la atingere (IgnorePointer) și estompată,
                // ca să nu se suprapună vizual peste jucători/chat.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Opacity(
                        opacity: 0.28,
                        child: const NetworkScanAnimation(size: 220),
                      ),
                    ),
                  ),
                ),
                StreamBuilder<MatchInfo>(
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
                        if (info?.gameMode == MatchGameMode.higherLower) _buildGameModeBanner(),
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
              ],
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

  Widget _buildGameModeBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withAlpha(35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withAlpha(140)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🍞', style: TextStyle(fontSize: 16)),
          SizedBox(width: 8),
          Text('Mod: Higher & Lower', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
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
                            photoUrl: p.photoUrl,
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

  /// Hostul nu poate porni meciul singur — trebuie cel puțin un prieten
  /// intrat în cameră, altfel butonul e dezactivat cu un mesaj explicativ.
  Widget _buildStartButton() {
    return StreamBuilder<List<MatchPlayer>>(
      stream: MultiplayerService.instance.watchPlayers(widget.matchId),
      builder: (context, snap) {
        final canStart = (snap.data?.length ?? 0) >= 2;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              if (!canStart)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Așteaptă cel puțin un prieten să intre în cameră...',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canStart ? () => MultiplayerService.instance.startMatch(widget.matchId) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.play,
                    disabledBackgroundColor: Colors.white24,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('START', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
