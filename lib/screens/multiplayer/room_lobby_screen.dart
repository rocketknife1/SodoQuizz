import 'package:flutter/material.dart';
import '../../core/chat_filter.dart';
import '../../core/lang.dart';
import '../../core/tanks.dart';
import '../../core/theme.dart';
import '../../data/auth_service.dart';
import '../../data/moderation_service.dart';
import '../../data/multiplayer_service.dart';
import '../../data/storage_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/avatar.dart';
import '../../widgets/match_stake_dialog.dart';
import '../../widgets/moderation_sheet.dart';
import '../../widgets/network_scan_animation.dart';
import 'multiplayer_higher_lower_screen.dart';
import 'multiplayer_match_screen.dart';
import 'multiplayer_tanks_screen.dart';

/// Lobby-ul unei camere private: cod vizibil, jucători live, premiile mesei
/// (actualizate pe măsură ce intră lume), chat live, și (doar pentru gazdă)
/// butonul Start. Toți jucătorii ascultă statusul meciului — când gazda apasă
/// Start, fiecare client navighează automat la [MultiplayerMatchScreen].
class RoomLobbyScreen extends StatefulWidget {
  final String matchId;
  final bool isHost;

  /// Miza plătită ca să ajungi în acest lobby — miza camerei, aceeași pentru
  /// toți (vezi core/betting.dart). Returnată integral dacă pleci înainte ca
  /// meciul să apuce să înceapă, vezi [_leave].
  final int stakePaid;

  const RoomLobbyScreen({super.key, required this.matchId, required this.isHost, this.stakePaid = 0});

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  final _chatController = TextEditingController();
  final _scrollController = ScrollController();

  /// Ținute în state, nu chemate din build: [MultiplayerService.watchPlayers]
  /// & co. întorc un stream NOU la fiecare apel, deci un StreamBuilder hrănit
  /// direct din build se reabonează la Firestore la fiecare redesenare.
  late final Stream<MatchInfo> _matchStream = MultiplayerService.instance.watchMatch(widget.matchId);
  late final Stream<List<MatchPlayer>> _playersStream = MultiplayerService.instance.watchPlayers(widget.matchId);
  late final Stream<List<ChatMessage>> _chatStream = MultiplayerService.instance.watchChat(widget.matchId);

  String _displayName = '';
  bool _navigated = false;
  bool _leaving = false;

  /// Ultimul număr de jucători văzut — necesar butonului fizic de Înapoi, care
  /// nu are acces la snapshot-ul din build, dar trebuie să știe dacă gazda mai
  /// are pe cineva de dat afară înainte să închidă camera.
  int _playerCount = 0;

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
  ///
  /// [closedByHost] e drumul pe care nu-l alege userul: camera a dispărut sub
  /// el fiindcă gazda a plecat (vezi [_handleRoomClosed]).
  Future<void> _leave({bool closedByHost = false}) async {
    if (_leaving) return;
    _leaving = true;
    try {
      await MultiplayerService.instance.leaveMatch(widget.matchId);
    } catch (e) {
      debugPrint('RoomLobbyScreen._leave: leaveMatch a esuat: $e');
    } finally {
      // _navigated rămâne false dacă (din perspectiva acestui client) meciul
      // nu a apucat să înceapă efectiv - miza n-a "cumparat" nimic, se
      // returnează integral.
      if (!_navigated && widget.stakePaid > 0) {
        await StorageService.addCoins(widget.stakePaid);
      }
      if (mounted) {
        if (closedByHost) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.danger,
              content: Text(
                widget.stakePaid > 0
                    ? tr('Gazda a părăsit camera. Ți-am dat înapoi cele 💰${widget.stakePaid}.',
                        'The host left the room. Your 💰${widget.stakePaid} has been refunded.')
                    : tr('Gazda a părăsit camera.', 'The host left the room.'),
                // explicit alb: culoarea implicită a textului din SnackBar e
                // închisă și se pierde complet pe fundalul roșu de mai sus.
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          );
        }
        Navigator.pop(context);
      }
    }
  }

  /// Gazda închide camera când pleacă (vezi [MultiplayerService.leaveMatch]),
  /// deci merită întrebată o dată dacă chiar vrea — altfel un tap greșit pe
  /// Înapoi dă toată lumea afară.
  Future<void> _leaveAsHost(int otherPlayers) async {
    if (_leaving) return;
    if (otherPlayers > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a2e),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(tr('Închizi camera?', 'Close the room?'), style: const TextStyle(color: Colors.white)),
          content: Text(
            tr(
                'Camera e a ta: dacă pleci, se închide și '
                    '${otherPlayers == 1 ? 'celălalt jucător iese' : 'ceilalți $otherPlayers jucători ies'} '
                    'automat. Toată lumea își primește miza înapoi.',
                'The room is yours: if you leave, it closes and '
                    '${otherPlayers == 1 ? 'the other player is kicked out' : 'the other $otherPlayers players are kicked out'} '
                    'automatically. Everyone gets their stake back.'),
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('Rămân', 'Stay'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              child: Text(tr('Închid camera', 'Close the room'), style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _leave();
  }

  /// Camera a dispărut din Firestore în timp ce eram în ea — singurul lucru
  /// care o poate șterge cât e în lobby e plecarea gazdei. Înainte, clientul
  /// rămânea blocat într-un lobby fantomă: fără cod, fără jucători, fără Start
  /// (nu e host) și invizibil pentru oricine ar fi vrut să intre.
  void _handleRoomClosed() {
    if (_leaving || _navigated || widget.isHost) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _leave(closedByHost: true);
    });
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
          builder: (_) => switch (gameMode) {
            MatchGameMode.higherLower => MultiplayerHigherLowerScreen(matchId: widget.matchId),
            MatchGameMode.quizzTanks => MultiplayerTanksScreen(matchId: widget.matchId),
            MatchGameMode.classic => MultiplayerMatchScreen(matchId: widget.matchId),
          },
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (widget.isHost) {
          _leaveAsHost(_playerCount - 1);
        } else {
          _leave();
        }
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
                  stream: _matchStream,
                  builder: (context, matchSnap) {
                    final info = matchSnap.data;
                    if (info != null) {
                      // Ordinea contează: dacă meciul a pornit, plecăm la
                      // meci; abia dacă NU a pornit, un document lipsă
                      // înseamnă cu adevărat „gazda a închis camera".
                      _maybeNavigateToMatch(info);
                      if (!info.exists) _handleRoomClosed();
                    }
                    // Un singur abonament la lista de jucători, folosit de tot
                    // ecranul: și de rândul de avatare, și de tabelul de
                    // premii, și de butonul Start.
                    return StreamBuilder<List<MatchPlayer>>(
                      stream: _playersStream,
                      builder: (context, playersSnap) {
                        final players = playersSnap.data ?? const <MatchPlayer>[];
                        _playerCount = players.length;
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                              child: Row(
                                children: [
                                  IconButton(
                                    onPressed: () => widget.isHost ? _leaveAsHost(players.length - 1) : _leave(),
                                    icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(tr('Cameră privată', 'Private room'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            _buildCodeBanner(info?.code),
                            if (info?.gameMode == MatchGameMode.higherLower) _buildGameModeBanner(),
                            if (info?.gameMode == MatchGameMode.quizzTanks)
                              _buildTanksBanner(players.length)
                            else
                              MatchPrizeStrip(
                                stake: info?.stake ?? widget.stakePaid,
                                players: players.length,
                              ),
                            _buildPlayers(players),
                            Expanded(child: _buildChat()),
                            _buildChatInput(),
                            if (widget.isHost) _buildStartButton(players.length),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
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

  /// Ce ține locul tabelului de premii la Quizz Tanks: acolo nu există pot,
  /// deci n-are ce împărți. În loc de asta, cifra care chiar contează în
  /// lobby — câte locuri mai sunt libere din cele [tanksPlayerCount].
  Widget _buildTanksBanner(int playerCount) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.orange.withAlpha(30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.orange.withAlpha(140)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.military_tech_rounded, color: AppColors.orange, size: 16),
              const SizedBox(width: 8),
              const Text('Quizz Tanks', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
              Text('$playerCount/$tanksPlayerCount',
                  style: const TextStyle(color: AppColors.orange, fontSize: 13, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            tr('Fără miză. Prada de la final se împarte după daunele făcute.',
                'No stake. The salvage at the end is split by damage dealt.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayers(List<MatchPlayer> players) {
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: players
            .map((p) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: GestureDetector(
                        // Tap pe un jucător = meniul de raportare/blocare.
                        // Aici, nu doar pe mesaje, fiindcă cineva se poate
                        // purta urât și fără să scrie nimic în chat.
                        onTap: p.id == MultiplayerService.instance.currentPlayerId
                            ? null
                            : () => showModerationSheet(
                                  context,
                                  targetUid: p.id,
                                  targetName: p.name,
                                  contextId: widget.matchId,
                                ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Avatar(
                              size: 56,
                              label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                              accentColor: pickAvatarColor(p.avatarSeed),
                              photoUrl: p.photoUrl,
                              style: avatarStyleFromId(p.avatarStyle),
                            ),
                            const SizedBox(height: 4),
                            Text(p.isHost ? '${p.name} 👑' : p.name,
                                style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ))
            .toList(),
      ),
    );
  }

  Widget _buildChat() {
    return StreamBuilder<List<ChatMessage>>(
      stream: _chatStream,
      builder: (context, snap) {
        final all = snap.data ?? const <ChatMessage>[];
        // Mesajele celor blocați dispar la afișare — vezi ModerationService
        // pentru de ce filtrarea NU se poate face pe server. ValueListenable,
        // ca lista să se rearanjeze în clipa în care blochezi pe cineva, fără
        // să fie nevoie să ieși și să reintri în cameră.
        return ValueListenableBuilder<Set<String>>(
          valueListenable: ModerationService.instance.blockedIds,
          builder: (context, blocked, _) {
            final messages = all.where((m) => !blocked.contains(m.senderId)).toList();
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
                  child: GestureDetector(
                    // Apăsare lungă pe mesajul altcuiva = raportare/blocare.
                    // Nu e un buton vizibil pe fiecare bulă, ca să nu umple
                    // chatul de iconițe pe care nu le apasă nimeni.
                    onLongPress: me
                        ? null
                        : () => showModerationSheet(
                              context,
                              targetUid: m.senderId,
                              targetName: m.senderName,
                              messageText: m.text,
                              contextId: widget.matchId,
                            ),
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
                          if (!me)
                            Text(m.senderName,
                                style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                          Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                );
              },
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
          IconButton(onPressed: _send, icon: const Icon(Icons.send_rounded, color: AppColors.blue)),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final raw = _chatController.text;
    // Cenzura se aplică ÎNAINTE de trimitere (vezi core/chat_filter.dart), și
    // i se spune autorului că mesajul lui a fost modificat — altfel s-ar
    // trezi cu asteriscuri pe ecran fără nicio explicație și ar crede că e un
    // bug.
    final text = sanitizeChatMessage(raw);
    if (text.isEmpty) return;
    _chatController.clear();
    if (text != raw.trim() && containsProfanity(raw)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesajul a fost trimis cu cuvintele nepotrivite acoperite.')),
      );
    }
    await MultiplayerService.instance.sendChatMessage(matchId: widget.matchId, senderName: _displayName, text: text);
  }

  /// Gazda nu poate porni meciul singură — trebuie cel puțin un jucător în
  /// plus, altfel butonul e dezactivat.
  ///
  /// Textul de sub buton spune EXPLICIT pe unde poate intra lumea. Fără el,
  /// singurul lucru pe care îl vedea o gazdă rămasă singură era un START gri,
  /// fără să afle vreodată că nu-și vede propria cameră în lista din Join
  /// Online (e filtrată tocmai ca să nu intre în ea singură) — părea că nu s-a
  /// creat sau că e stricat ceva.
  Widget _buildStartButton(int playerCount) {
    final canStart = playerCount >= 2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          if (!canStart)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                tr(
                    'Ești singur în cameră. Dă codul de mai sus unui prieten sau '
                        'așteaptă: camera ta apare la ceilalți în lista din Join Online '
                        '(ție nu ți se arată).',
                    'You are alone in the room. Give the code above to a friend or '
                        'just wait: your room shows up for others in the Join Online list '
                        '(you do not see your own).'),
                style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.3),
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
  }
}
