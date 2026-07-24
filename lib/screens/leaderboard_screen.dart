import 'package:flutter/material.dart';
import '../core/gamemodes.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';
import '../widgets/level_header.dart';

/// Clasament personal: recordul tău la fiecare gamemod + scorul maxim
/// general. Aplicația nu are server/cont, deci nu există clasament
/// multiplayer real — arătăm cinstit doar recordurile tale locale,
/// nu inventăm alți jucători falși.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late final Future<_LeaderboardData> _dataFuture = _load();

  Future<_LeaderboardData> _load() async {
    final xp = await StorageService.getXp();
    final coins = await StorageService.getCoins();
    final lives = await StorageService.getLives();
    final overall = await StorageService.getHighScore();
    final perMode = <String, int>{};
    for (final m in gameModes.where((m) => !m.locked)) {
      perMode[m.id] = await StorageService.getModeHighScore(m.id);
    }
    return _LeaderboardData(xp: xp, coins: coins, lives: lives, overall: overall, perMode: perMode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: FutureBuilder<_LeaderboardData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                  child: Row(
                    children: [
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70)),
                      const SizedBox(width: 4),
                      const Text('Clasamentul tău', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: LevelHeader(xp: data?.xp ?? 0, coins: data?.coins ?? 0, lives: data?.lives ?? 5),
                ),
                if (data == null)
                  const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.orange)))
                else
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [AppColors.orange, Color(0xFFFFB020)]),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 36),
                              const SizedBox(width: 14),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Recordul tău general', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                  Text('${data.overall} puncte', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text('Recorduri pe gamemod', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        for (final m in gameModes.where((m) => !m.locked)) _ModeScoreRow(color: m.accentColor, icon: m.icon, title: m.title, score: data.perMode[m.id] ?? 0),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LeaderboardData {
  final int xp;
  final int coins;
  final int lives;
  final int overall;
  final Map<String, int> perMode;
  _LeaderboardData({required this.xp, required this.coins, required this.lives, required this.overall, required this.perMode});
}

class _ModeScoreRow extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final int score;

  const _ModeScoreRow({required this.color, required this.icon, required this.title, required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withAlpha(40), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
          Text('$score pct', style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
