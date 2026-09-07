import 'package:flutter/material.dart';

import '../core/category_mastery.dart';
import '../core/gamemodes.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';
import '../widgets/space_background.dart';

/// „Măiestrie pe categorii" (#4 retenție) — pentru fiecare categorie de quiz:
/// câte întrebări ai văzut, acuratețea, cel mai lung streak și cât mai ai
/// până o „stăpânești". Conținutul devine progres vizibil, nu doar o sursă de
/// monede.
class CategoryMasteryScreen extends StatefulWidget {
  const CategoryMasteryScreen({super.key});

  @override
  State<CategoryMasteryScreen> createState() => _CategoryMasteryScreenState();
}

class _CategoryMasteryScreenState extends State<CategoryMasteryScreen> {
  late Future<Map<String, ({int seen, int correct, int bestStreak})>> _future;

  List<GameMode> get _cats => gameModes.where((m) => !m.locked).toList();

  @override
  void initState() {
    super.initState();
    _future = StorageService.allCategoryStats(_cats.map((m) => m.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Măiestrie pe categorii', 'Category mastery')),
      ),
      extendBodyBehindAppBar: true,
      body: SpaceBackground(
        child: SafeArea(
          child: FutureBuilder<Map<String, ({int seen, int correct, int bestStreak})>>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final stats = snap.data!;
              final mastered = _cats
                  .where((m) => isCategoryMastered(
                      seen: stats[m.id]!.seen, correct: stats[m.id]!.correct))
                  .length;
              final sorted = [..._cats]..sort((a, b) {
                  final pa = masteryProgress(
                      seen: stats[a.id]!.seen, correct: stats[a.id]!.correct);
                  final pb = masteryProgress(
                      seen: stats[b.id]!.seen, correct: stats[b.id]!.correct);
                  return pb.compareTo(pa);
                });
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.teal.withAlpha(28),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.teal.withAlpha(110)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.workspace_premium_rounded,
                            color: AppColors.teal, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tr('$mastered din ${_cats.length} categorii stăpânite',
                                '$mastered of ${_cats.length} categories mastered'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                    child: Text(
                      tr('O categorie e „stăpânită" la $masterySeenTarget de răspunsuri cu cel puțin ${(masteryMinAccuracy * 100).round()}% corecte. 3 categorii → titlul „Colecționar de Diplome".',
                          'A category is "mastered" at $masterySeenTarget answers with at least ${(masteryMinAccuracy * 100).round()}% correct. 3 categories → the "Diploma Collector" title.'),
                      style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                    ),
                  ),
                  for (final m in sorted)
                    _CategoryRow(mode: m, s: stats[m.id]!),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final GameMode mode;
  final ({int seen, int correct, int bestStreak}) s;
  const _CategoryRow({required this.mode, required this.s});

  @override
  Widget build(BuildContext context) {
    final p = masteryProgress(seen: s.seen, correct: s.correct);
    final tier = masteryTier(seen: s.seen, correct: s.correct);
    final done = isCategoryMastered(seen: s.seen, correct: s.correct);
    final acc = s.seen == 0 ? 0 : (s.correct * 100 / s.seen).round();
    final tierLabel =
        tr(masteryTierLabelsRo[tier], masteryTierLabelsEn[tier]);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: done ? AppColors.teal.withAlpha(150) : Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(mode.icon, color: mode.accentColor, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(mode.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              if (done)
                const Icon(Icons.verified_rounded, color: AppColors.teal, size: 20)
              else
                Text(tierLabel,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 7,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(
                  done ? AppColors.teal : mode.accentColor),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.seen == 0
                ? tr('Încă n-ai jucat categoria asta.',
                    "You haven't played this one yet.")
                : tr('${s.seen} răspunsuri · $acc% corect · streak ${s.bestStreak}',
                    '${s.seen} answers · $acc% correct · streak ${s.bestStreak}'),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
