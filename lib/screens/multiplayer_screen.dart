import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../widgets/avatar.dart';

/// Ecranul de Multiplayer: contul tău + buton Connect. Momentan doar
/// caută jucători la infinit (nu există backend încă) — pregătit ca loc
/// unde se conectează matchmaking-ul real pe viitor.
class MultiplayerScreen extends StatefulWidget {
  const MultiplayerScreen({super.key});

  @override
  State<MultiplayerScreen> createState() => _MultiplayerScreenState();
}

class _MultiplayerScreenState extends State<MultiplayerScreen> with SingleTickerProviderStateMixin {
  bool _connecting = false;
  late final AnimationController _bounceController;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                    ),
                    const SizedBox(width: 4),
                    const Text('Multiplayer', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: _connecting ? _buildWaiting() : _buildConnect(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnect() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Avatar(size: 110),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => setState(() => _connecting = true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.blue,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: AppColors.blue.withAlpha(110), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: const Text(
              'CONNECT',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWaiting() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 72,
          height: 72,
          child: CircularProgressIndicator(strokeWidth: 5, color: AppColors.blue),
        ),
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
    );
  }
}
