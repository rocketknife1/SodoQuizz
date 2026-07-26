import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/multiplayer_service.dart';
import '../../data/storage_service.dart';
import 'multiplayer_match_screen.dart';

/// Matchmaking public: te bagă în coada de așteptare și încearcă periodic să
/// formeze un meci de 5. Decizie simplă (menționată explicit, ajustabilă
/// ulterior): sub 5 jucători reali după 10s, restul locurilor se
/// completează cu jucători ficțivi — vezi
/// [MultiplayerService.attemptFormMatch].
class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> with SingleTickerProviderStateMixin {
  static const _timeoutBeforeBots = Duration(seconds: 10);

  late final AnimationController _bounceController;
  Timer? _formTimer;
  StreamSubscription<String?>? _queueSub;
  DateTime? _joinedAt;
  bool _matched = false;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _start();
  }

  Future<void> _start() async {
    final name = await StorageService.getDisplayName();
    await MultiplayerService.instance.joinMatchmakingQueue(displayName: name);
    if (!mounted) return;
    _joinedAt = DateTime.now();

    _queueSub = MultiplayerService.instance.watchOwnQueueEntry().listen((matchId) {
      if (matchId != null) _onMatched(matchId);
    });

    _formTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      final elapsed = DateTime.now().difference(_joinedAt!);
      MultiplayerService.instance.attemptFormMatch(allowBotFill: elapsed >= _timeoutBeforeBots);
    });
  }

  void _onMatched(String matchId) {
    if (_matched) return;
    _matched = true;
    _formTimer?.cancel();
    _queueSub?.cancel();
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
    await MultiplayerService.instance.leaveQueue();
    if (mounted) Navigator.pop(context);
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
                        const SizedBox(width: 72, height: 72, child: CircularProgressIndicator(strokeWidth: 5, color: AppColors.blue)),
                        const SizedBox(height: 28),
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
