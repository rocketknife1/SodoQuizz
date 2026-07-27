import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/gamemodes.dart';
import '../core/theme.dart';
import '../data/questions.dart';
import '../data/storage_service.dart';
import '../widgets/category_card.dart';
import '../widgets/space_background.dart';
import 'loading_screen.dart';

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
          child: FutureBuilder<Map<String, _ModeStats>>(
            future: _statsFuture,
            builder: (context, snapshot) {
              final stats = snapshot.data;
              final totalAnswered = stats?.values.fold<int>(0, (sum, s) => sum + s.answered) ?? 0;
              final totalQuestions = stats?.values.fold<int>(0, (sum, s) => sum + s.total) ?? 0;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 20, 6),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                        ),
                        const SizedBox(width: 4),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShaderMask(
                              shaderCallback: (r) => const LinearGradient(colors: [Colors.white, Color(0xFFC9B8FF)])
                                  .createShader(r),
                              child: const Text(
                                'Alege o categorie',
                                style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
                              ),
                            ),
                            if (totalQuestions > 0)
                              Text(
                                '$totalAnswered/$totalQuestions întrebări cucerite',
                                style: const TextStyle(color: Colors.white54, fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                      itemCount: gameModes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final mode = gameModes[i];
                        final s = stats?[mode.id];
                        return CategoryCard(
                          index: i + 1,
                          icon: mode.icon,
                          title: mode.title,
                          color: mode.accentColor,
                          locked: mode.locked,
                          totalQuestions: s?.total ?? 0,
                          answered: s?.answered ?? 0,
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
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
