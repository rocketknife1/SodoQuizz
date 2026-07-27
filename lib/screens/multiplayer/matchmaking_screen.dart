import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/auth_service.dart';
import '../../data/multiplayer_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/avatar.dart';
import '../../widgets/network_scan_animation.dart';
import 'multiplayer_match_screen.dart';
import 'room_lobby_screen.dart';

/// Matchmaking public: te bagă în coada de așteptare și încearcă periodic să
/// te cupleze cu un adversar real (1 vs 1) — fără completare cu jucători
/// ficțivi, se așteaptă cât e nevoie până apare cineva real în coadă. Vezi
/// [MultiplayerService.attemptFormMatch].
class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;
  Timer? _formTimer;
  StreamSubscription<String?>? _queueSub;
  bool _matched = false;
  bool _left = false;
  bool _joiningRoom = false;
  ({String name, String? photoUrl})? _identity;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _start();
  }

  Future<void> _start() async {
    final identity = await AuthService.instance.multiplayerIdentity();
    _identity = identity;
    await MultiplayerService.instance.joinMatchmakingQueue(displayName: identity.name, photoUrl: identity.photoUrl);
    if (!mounted) return;

    _queueSub = MultiplayerService.instance.watchOwnQueueEntry().listen((matchId) {
      if (matchId != null) _onMatched(matchId);
    });

    _formTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      MultiplayerService.instance.attemptFormMatch();
    });
  }

  void _onMatched(String matchId) {
    if (_matched) return;
    _matched = true;
    _formTimer?.cancel();
    _queueSub?.cancel();
    // intrarea din coadă nu mai are treabă odată ce am fost cuplați -
    // altfel ar rămâne orfană în matchmaking_queue la nesfârșit.
    MultiplayerService.instance.leaveQueue();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MultiplayerMatchScreen(matchId: matchId)),
    );
  }

  /// Alternativa la matchmaking-ul automat: userul alege direct o cameră
  /// deschisă din listă (vezi [MultiplayerService.watchOpenRooms]). Oprim
  /// coada de matchmaking înainte să intrăm, ca să nu rămânem cuplați
  /// automat cu altcineva chiar când tocmai am ales o cameră anume.
  Future<void> _joinRoom(MatchInfo room) async {
    if (_matched || _left || _joiningRoom) return;
    setState(() => _joiningRoom = true);
    _formTimer?.cancel();
    await _queueSub?.cancel();
    try {
      await MultiplayerService.instance.leaveQueue();
    } catch (e) {
      debugPrint('MatchmakingScreen._joinRoom: leaveQueue a esuat: $e');
    }
    try {
      final identity = _identity ?? await AuthService.instance.multiplayerIdentity();
      final info = await MultiplayerService.instance.joinRoomById(
        matchId: room.id,
        displayName: identity.name,
        photoUrl: identity.photoUrl,
      );
      if (!mounted) return;
      _matched = true;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => RoomLobbyScreen(matchId: info.id, isHost: false)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _joiningRoom = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is MultiplayerUnavailableException ? e.message : 'Camera nu mai e disponibilă.')),
      );
      // matchmaking-ul automat continuă în fundal, ca userul să nu rămână
      // blocat fără nicio șansă de meci după o încercare eșuată — trebuie
      // re-adăugat în coadă, pentru că am ieșit din ea mai sus.
      final identity = _identity ?? await AuthService.instance.multiplayerIdentity();
      try {
        await MultiplayerService.instance.joinMatchmakingQueue(displayName: identity.name, photoUrl: identity.photoUrl);
      } catch (e) {
        debugPrint('MatchmakingScreen._joinRoom: re-joinMatchmakingQueue a esuat: $e');
      }
      if (!mounted) return;
      _queueSub = MultiplayerService.instance.watchOwnQueueEntry().listen((matchId) {
        if (matchId != null) _onMatched(matchId);
      });
      _formTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        MultiplayerService.instance.attemptFormMatch();
      });
    }
  }

  Future<void> _leave() async {
    if (_left || _matched) return;
    _left = true;
    _formTimer?.cancel();
    await _queueSub?.cancel();
    try {
      await MultiplayerService.instance.leaveQueue();
    } catch (e) {
      debugPrint('MatchmakingScreen._leave: leaveQueue a esuat: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _formTimer?.cancel();
    _queueSub?.cancel();
    _bounceController.dispose();
    if (!_matched && !_left) MultiplayerService.instance.leaveQueue();
    super.dispose();
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
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                  child: Row(
                    children: [
                      IconButton(onPressed: _leave, icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70)),
                      const SizedBox(width: 4),
                      const Text('Join Online', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const NetworkScanAnimation(size: 220),
                        const SizedBox(height: 12),
                        AnimatedBuilder(
                          animation: _bounceController,
                          builder: (context, child) {
                            final offsetY = -10 * Curves.easeInOut.transform(_bounceController.value);
                            return Transform.translate(offset: Offset(0, offsetY), child: child);
                          },
                          child: const Text(
                            'Waiting for players...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              shadows: [
                                Shadow(color: AppColors.blue, blurRadius: 22),
                                Shadow(color: AppColors.blue, blurRadius: 10),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildOpenRooms(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Camere private aflate în lobby, deschise oricui — alternativă mică, sub
  /// animație, la a aștepta cuplarea automată sau la a primi un cod de la un
  /// prieten. Doar o bandă orizontală compactă, ca să nu domine ecranul.
  Widget _buildOpenRooms() {
    return StreamBuilder<List<MatchInfo>>(
      stream: MultiplayerService.instance.watchOpenRooms(),
      builder: (context, snap) {
        final rooms = snap.data ?? const <MatchInfo>[];
        if (rooms.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 64,
          width: 260,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: rooms.length,
            itemBuilder: (context, i) => _buildRoomChip(rooms[i]),
          ),
        );
      },
    );
  }

  Widget _buildRoomChip(MatchInfo room) {
    return Opacity(
      opacity: _joiningRoom ? 0.5 : 1,
      child: GestureDetector(
        onTap: _joiningRoom ? null : () => _joinRoom(room),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(
                size: 40,
                label: (room.hostName?.isNotEmpty ?? false) ? room.hostName![0].toUpperCase() : '?',
                accentColor: pickAvatarColor(room.hostId),
                photoUrl: room.hostPhotoUrl,
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 56,
                child: Text(
                  room.hostName?.isNotEmpty == true ? room.hostName! : '?',
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
