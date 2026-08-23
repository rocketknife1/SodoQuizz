import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/chat_filter.dart';
import '../../core/lang.dart';
import '../../core/obby.dart';
import '../../core/tanks.dart';
import '../../core/theme.dart';
import '../../data/auth_service.dart';
import '../../data/moderation_service.dart';
import '../../data/multiplayer_service.dart';
import '../../data/storage_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/entrance_item.dart';
import '../../widgets/match_stake_dialog.dart';
import '../../widgets/moderation_sheet.dart';
import '../../widgets/network_scan_animation.dart';
import '../../widgets/player_badge.dart';
import '../../widgets/space_background.dart';
import 'multiplayer_higher_lower_screen.dart';
import 'multiplayer_match_screen.dart';
import 'multiplayer_obby_screen.dart';
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

class _RoomLobbyScreenState extends State<RoomLobbyScreen> with SingleTickerProviderStateMixin {
  final _chatController = TextEditingController();
  final _scrollController = ScrollController();

  /// Intrarea în lobby, în cascadă — codul camerei, jucătorii, chatul —
  /// aceeași senzație de „se întâmplă" ca la ecranul de meniu Multiplayer,
  /// nu doar aici un ecran static în plus.
  late final AnimationController _introCtrl;

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

  /// „Mai sunt aici" cât timp lobby-ul e deschis — vezi
  /// MultiplayerService.matchHeartbeat. Fără el, o aplicație închisă brusc
  /// din lobby lasă un jucător-fantomă care nu mai pleacă niciodată singur.
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
    AuthService.instance.multiplayerIdentity().then((identity) {
      if (mounted) setState(() => _displayName = identity.name);
    });
    _heartbeatTimer = Timer.periodic(MultiplayerService.matchHeartbeatInterval, (_) {
      MultiplayerService.instance.matchHeartbeat(widget.matchId);
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _chatController.dispose();
    _scrollController.dispose();
    _introCtrl.dispose();
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
            MatchGameMode.obby => MultiplayerObbyScreen(matchId: widget.matchId),
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
        body: SpaceBackground(
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
                        opacity: 0.22,
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
                            EntranceItem(
                              controller: _introCtrl,
                              interval: const Interval(0.0, 0.45, curve: Curves.easeOut),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                                child: Row(
                                  children: [
                                    IconButton(
                                      onPressed: () => widget.isHost ? _leaveAsHost(players.length - 1) : _leave(),
                                      icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(tr('Cameră privată', 'Private room'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                    const Spacer(),
                                    _buildLiveBadge(players.length),
                                  ],
                                ),
                              ),
                            ),
                            EntranceItem(
                              controller: _introCtrl,
                              interval: const Interval(0.08, 0.55, curve: Curves.easeOutBack),
                              child: _buildCodeBanner(info?.code),
                            ),
                            if (info?.gameMode == MatchGameMode.higherLower) _buildGameModeBanner(),
                            if (info?.gameMode == MatchGameMode.obby) _buildObbyBanner(players.length),
                            if (info?.gameMode == MatchGameMode.quizzTanks)
                              _buildTanksBanner(players.length)
                            else
                              MatchPrizeStrip(
                                stake: info?.stake ?? widget.stakePaid,
                                players: players.length,
                              ),
                            EntranceItem(
                              controller: _introCtrl,
                              interval: const Interval(0.18, 0.65, curve: Curves.easeOut),
                              child: _buildPlayers(players),
                            ),
                            Expanded(child: _buildChat()),
                            _buildChatInput(),
                            if (widget.isHost)
                              EntranceItem(
                                controller: _introCtrl,
                                interval: const Interval(0.3, 0.8, curve: Curves.easeOutBack),
                                child: _buildStartButton(players.length),
                              ),
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

  /// Codul camerei, prezentat ca un „bilet" — colțuri teșite, gradient
  /// albastru, aceeași familie vizuală cu plăcile de pe ecranul de intrare în
  /// Multiplayer, ca lobby-ul să pară continuarea firească a aceluiași loc,
  /// nu un ecran croit separat.
  Widget _buildCodeBanner(String? code) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: ShapeDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blue.withAlpha(60), AppColors.blue.withAlpha(20)],
        ),
        shape: BeveledRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.blue.withAlpha(160), width: 1.2),
        ),
        shadows: [BoxShadow(color: AppColors.blue.withAlpha(60), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.blue.withAlpha(70),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Colors.white.withAlpha(70)),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('CODUL CAMEREI', 'ROOM CODE'),
                    style: const TextStyle(color: Colors.white60, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
                Text(
                  code ?? '-----',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 5),
                ),
              ],
            ),
          ),
          Text(tr('dă-l unui prieten', 'share it'),
              style: const TextStyle(color: Colors.white38, fontSize: 10.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// Bulina pulsatilă „live" cu numărul de jucători din cameră chiar acum —
  /// pusă în header, ca lobby-ul să simtă viu chiar dacă nimeni nu a scris
  /// nimic încă în chat.
  Widget _buildLiveBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(color: AppColors.play),
          const SizedBox(width: 6),
          Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)),
          const SizedBox(width: 3),
          Icon(Icons.groups_rounded, color: Colors.white.withAlpha(180), size: 15),
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

  Widget _buildObbyBanner(int playerCount) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.play.withAlpha(35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.play.withAlpha(140)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🏃', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text('Mod: Obby • $playerCount/$obbyMaxPlayers',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
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
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: players
            .map((p) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: PlayerBadge(
                    name: p.name,
                    photoUrl: p.photoUrl,
                    avatarSeed: p.avatarSeed,
                    avatarStyle: p.avatarStyle,
                    size: 58,
                    ringColor: p.isHost
                        ? AppColors.coin
                        : (p.id == MultiplayerService.instance.currentPlayerId ? AppColors.blue : null),
                    topBadge: p.isHost ? const PlayerTopBadge.crown() : null,
                    // Tap pe un jucător = meniul de raportare/blocare. Aici,
                    // nu doar pe mesaje, fiindcă cineva se poate purta urât
                    // și fără să scrie nimic în chat.
                    onTap: p.id == MultiplayerService.instance.currentPlayerId
                        ? null
                        : () => showModerationSheet(
                              context,
                              targetUid: p.id,
                              targetName: p.name,
                              contextId: widget.matchId,
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
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                      decoration: BoxDecoration(
                        gradient: me
                            ? const LinearGradient(colors: [AppColors.blue, Color(0xFF2563EB)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                            : null,
                        color: me ? null : Colors.white.withAlpha(20),
                        border: me ? null : Border.all(color: Colors.white.withAlpha(25)),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(me ? 16 : 4),
                          bottomRight: Radius.circular(me ? 4 : 16),
                        ),
                        boxShadow: me ? [BoxShadow(color: AppColors.blue.withAlpha(70), blurRadius: 8, offset: const Offset(0, 3))] : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!me)
                            Text(m.senderName,
                                style: const TextStyle(color: AppColors.teal, fontSize: 10, fontWeight: FontWeight.w800)),
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.white.withAlpha(30))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.white.withAlpha(30))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.blue)),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [AppColors.blue, Color(0xFF2563EB)]),
                boxShadow: [BoxShadow(color: AppColors.blue, blurRadius: 10)],
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 19),
            ),
          ),
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
          GestureDetector(
            onTap: canStart ? () => MultiplayerService.instance.startMatch(widget.matchId) : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                gradient: canStart
                    ? const LinearGradient(colors: [Color(0xFF34E27A), AppColors.play], begin: Alignment.topLeft, end: Alignment.bottomRight)
                    : null,
                color: canStart ? null : Colors.white.withAlpha(20),
                shape: BeveledRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: canStart ? Colors.white.withAlpha(120) : Colors.white.withAlpha(30), width: 1.2),
                ),
                shadows: canStart ? [const BoxShadow(color: AppColors.play, blurRadius: 18, offset: Offset(0, 6))] : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow_rounded, color: canStart ? Colors.white : Colors.white38, size: 22),
                  const SizedBox(width: 6),
                  Text('START',
                      style: TextStyle(
                          color: canStart ? Colors.white : Colors.white38, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 15)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bulina verde care pulsează încet — semnul universal de „live" folosit
/// lângă numărul de jucători din lobby.
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [BoxShadow(color: widget.color.withAlpha(120 + (_ctrl.value * 100).round()), blurRadius: 4 + _ctrl.value * 4)],
        ),
      ),
    );
  }
}
