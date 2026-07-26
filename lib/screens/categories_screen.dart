import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/gamemodes.dart';
import '../core/theme.dart';
import '../data/questions.dart';
import '../data/storage_service.dart';
import '../widgets/planet_tile.dart';
import '../widgets/space_background.dart';
import 'loading_screen.dart';

/// Rangul de "măiestrie" pe categorie, calculat din procentul de întrebări
/// răspunse corect vreodată (vezi [StorageService.getAnsweredIds]).
String _rankLabel(double pct) {
  if (pct >= 1.0) return 'Maestru';
  if (pct >= 0.67) return 'Expert';
  if (pct >= 0.34) return 'Priceput';
  return 'Novice';
}

class _ModeStats {
  final int total;
  final int answered;
  const _ModeStats({required this.total, required this.answered});
  double get pct => total > 0 ? answered / total : 0.0;
}

/// Ecranul care apare când apeși PLAY: alegi unul dintre cele 4
/// gamemoduri. Cardurile sunt generate din [gameModes] — nu e nimic
/// hardcodat aici, un gamemod nou apare automat.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late final Future<Map<String, _ModeStats>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  Future<Map<String, _ModeStats>> _loadStats() async {
    final results = await Future.wait([loadAllQuestions(), StorageService.getAnsweredIds()]);
    final all = results[0] as List;
    final answeredIds = results[1] as Set<String>;
    return {
      for (final m in gameModes.where((m) => !m.locked))
        m.id: _ModeStats(
          total: all.where((q) => q.categoryId == m.id).length,
          answered: all.where((q) => q.categoryId == m.id && answeredIds.contains(q.id)).length,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SpaceBackground(
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
                    const Text('Alege o planetă', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<Map<String, _ModeStats>>(
                  future: _statsFuture,
                  builder: (context, snapshot) {
                    return GridView.count(
                      padding: const EdgeInsets.all(20),
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 18,
                      childAspectRatio: 0.8,
                      children: [
                        for (final mode in gameModes)
                          PlanetTile(
                            icon: mode.icon,
                            title: mode.title,
                            subtitle: mode.locked
                                ? mode.subtitle
                                : '${mode.subtitle} • ${snapshot.data?[mode.id]?.total ?? 0} întrebări',
                            color: mode.accentColor,
                            locked: mode.locked,
                            progress: mode.locked ? null : snapshot.data?[mode.id]?.pct,
                            rankLabel: (mode.locked || snapshot.data?[mode.id] == null)
                                ? null
                                : _rankLabel(snapshot.data![mode.id]!.pct),
                            onTap: mode.locked
                                ? () => ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Va urma în următorul update! 🚀')),
                                    )
                                : () {
                                    Sfx.tileSelect();
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => LoadingScreen(gameModeId: mode.id)),
                                    );
                                  },
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
