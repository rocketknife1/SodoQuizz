// Dificultatea întrebărilor, ESTIMATĂ din telemetria de joc (question_stats)
// — nu setată manual. Vezi core/question_difficulty.dart.
//
// Parte din `admin_screen.dart` (vezi `part of` mai jos).

part of '../admin_screen.dart';

class _DifficultyTab extends StatefulWidget {
  const _DifficultyTab({super.key});

  @override
  State<_DifficultyTab> createState() => _DifficultyTabState();
}

class _DifficultyTabState extends State<_DifficultyTab> with _AdminRefreshable {
  @override
  Future<void> refresh() => _refresh();

  late Future<_DifficultyData> _future = _load();
  String _categoryFilter = '';
  QuestionDifficulty? _diffFilter;

  Future<_DifficultyData> _load() async {
    final results = await Future.wait([
      loadAllQuestions(),
      QuestionStatsService.instance.fetchAll(),
    ]);
    return _DifficultyData(
      questions: results[0] as List<Question>,
      stats: results[1] as Map<String, QuestionStat>,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DifficultyData>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = data.rows
            .where((r) =>
                _categoryFilter.isEmpty || r.q.categoryId == _categoryFilter)
            .where((r) => _diffFilter == null || r.difficulty == _diffFilter)
            .toList();
        final tierCounts = <QuestionDifficulty, int>{};
        for (final r in data.rows) {
          tierCounts[r.difficulty] = (tierCounts[r.difficulty] ?? 0) + 1;
        }
        final calibrated = data.rows.length -
            (tierCounts[QuestionDifficulty.necalibrat] ?? 0);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                '$calibrated / ${data.rows.length} calibrate '
                '(prag $difficultyMinSample răspunsuri)',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _diffChip(null, 'Toate', tierCounts.values.fold(0, (a, b) => a + b)),
                  for (final d in QuestionDifficulty.values)
                    _diffChip(d, difficultyLabelTr(d), tierCounts[d] ?? 0),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: _categoryFilter.isEmpty ? null : _categoryFilter,
                hint: const Text('Toate categoriile',
                    style: TextStyle(color: Colors.white70)),
                dropdownColor: const Color(0xFF141B36),
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('Toate categoriile')),
                  for (final m in gameModes.where((m) => !m.locked))
                    DropdownMenuItem(value: m.id, child: Text(m.title)),
                ],
                onChanged: (v) => setState(() => _categoryFilter = v ?? ''),
              ),
              const Divider(color: Colors.white24),
              for (final r in rows) _DifficultyRow(row: r),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('Nimic aici cu filtrele astea.',
                        style: TextStyle(color: Colors.white54)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _diffChip(QuestionDifficulty? d, String label, int count) {
    final selected = _diffFilter == d;
    return GestureDetector(
      onTap: () => setState(() => _diffFilter = d),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.purple : Colors.white12,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('$label · $count',
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }
}

class _DifficultyData {
  final List<_DiffRow> rows;
  _DifficultyData({
    required List<Question> questions,
    required Map<String, QuestionStat> stats,
  }) : rows = [
          for (final q in questions)
            _DiffRow(
              q: q,
              stat: stats[q.id],
              difficulty: difficultyFromStats(
                shown: stats[q.id]?.shown ?? 0,
                correct: stats[q.id]?.correct ?? 0,
                avgMs: stats[q.id]?.avgMs ?? 0,
              ),
            ),
        ]..sort((a, b) {
            // Calibrate întâi, cele mai grele sus.
            final byTier = b.difficulty.index.compareTo(a.difficulty.index);
            if (byTier != 0) return byTier;
            return (b.stat?.shown ?? 0).compareTo(a.stat?.shown ?? 0);
          });
}

class _DiffRow {
  final Question q;
  final QuestionStat? stat;
  final QuestionDifficulty difficulty;
  const _DiffRow({required this.q, required this.stat, required this.difficulty});
}

class _DifficultyRow extends StatelessWidget {
  final _DiffRow row;
  const _DifficultyRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final s = row.stat;
    final acc = s == null || s.shown == 0
        ? null
        : (s.accuracy * 100).round();
    final label = row.q.prompt.isNotEmpty
        ? row.q.prompt
        : '${row.q.category}: „${row.q.answer}"';
    final color = switch (row.difficulty) {
      QuestionDifficulty.necalibrat => Colors.white38,
      QuestionDifficulty.usoara => AppColors.play,
      QuestionDifficulty.medie => AppColors.coin,
      QuestionDifficulty.grea => AppColors.orange,
      QuestionDifficulty.extrema => AppColors.danger,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            s == null || s.shown == 0
                ? '${difficultyLabelTr(row.difficulty)} · fără date'
                : '${difficultyLabelTr(row.difficulty)} · $acc% corect · '
                    '${s.shown} răsp · ${(s.avgMs / 1000).toStringAsFixed(1)}s',
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
