import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/auth_service.dart';
import '../../data/multiplayer_service.dart';
import '../../widgets/network_scan_animation.dart';
import 'multiplayer_match_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _start();
  }

  Future<void> _start() async {
    final identity = await AuthService.instance.multiplayerIdentity();
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
}
