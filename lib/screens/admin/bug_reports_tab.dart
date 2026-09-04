// Rapoartele tehnice trimise de aplicație („Trimite raportul").
//
// Parte din `admin_screen.dart` (vezi `part of` mai jos): panoul de Admin era
// un singur fișier de peste 3.000 de linii, imposibil de ținut în cap. E
// împărțit pe tab-uri, nu pe tipuri de clase, fiindcă asta e granița după
// care se lucrează la el în practică.
part of '../admin_screen.dart';

/// Rapoartele trimise din aplicație („Trimite raportul" / „Ceva nu merge").
///
/// Spre deosebire de tabul Raportări — care e despre COMPORTAMENTUL altor
/// jucători — astea sunt tehnice: le scrie sistemul, nu omul. Vezi
/// data/bug_report_service.dart pentru ce conține fiecare.
class _BugReportsTab extends StatefulWidget {
  const _BugReportsTab();

  @override
  State<_BugReportsTab> createState() => _BugReportsTabState();
}

class _BugReportsTabState extends State<_BugReportsTab> {
  late Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _load() async {
    final snap = await FirebaseFirestore.instance
        .collection('bug_reports')
        .orderBy('trimisLa', descending: true)
        .limit(100)
        .get();
    return snap.docs;
  }

  Future<void> _setResolved(String id, bool value) async {
    await FirebaseFirestore.instance
        .collection('bug_reports')
        .doc(id)
        .set({'rezolvat': value}, SetOptions(merge: true));
    if (mounted) setState(() => _future = _load());
  }

  Future<void> _delete(String id) async {
    await FirebaseFirestore.instance.collection('bug_reports').doc(id).delete();
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.orange));
        }
        if (snap.hasError) {
          return const _InfoCard(
            icon: Icons.wifi_off_rounded,
            text: 'Nu am putut citi rapoartele. Verifică internetul și încearcă din nou.',
          );
        }
        final docs = snap.data ?? const [];
        if (docs.isEmpty) {
          return const _InfoCard(
            icon: Icons.check_circle_outline_rounded,
            text: 'Niciun raport. Ori totul merge, ori nimeni nu a apăsat butonul.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _BugReportCard(
            doc: docs[i],
            onResolve: (v) => _setResolved(docs[i].id, v),
            onDelete: () => _delete(docs[i].id),
          ),
        );
      },
    );
  }
}

class _BugReportCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final ValueChanged<bool> onResolve;
  final VoidCallback onDelete;
  const _BugReportCard({
    required this.doc,
    required this.onResolve,
    required this.onDelete,
  });

  @override
  State<_BugReportCard> createState() => _BugReportCardState();
}

class _BugReportCardState extends State<_BugReportCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data();
    final rezolvat = d['rezolvat'] == true;
    final eroare = (d['eroare'] as String? ?? '').trim();
    final firimituri =
        (d['firimituri'] as List?)?.cast<String>() ?? const <String>[];
    final when = (d['trimisLa'] as Timestamp?)?.toDate();
    final manual = eroare.isEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: rezolvat ? Colors.white10 : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: rezolvat ? Colors.white24 : AppColors.play.withAlpha(90),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                manual ? Icons.flag_rounded : Icons.bug_report_rounded,
                color: rezolvat ? Colors.white38 : AppColors.play,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  manual ? 'Raportat manual' : 'Eroare în aplicație',
                  style: TextStyle(
                    color: rezolvat ? Colors.white54 : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    decoration: rezolvat ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (when != null)
                Text(_relative(when),
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          // Cine, pe ce, de unde — trei lucruri care restrâng imediat căutarea.
          Text(
            '${d['platforma'] ?? '?'} · v${d['versiune'] ?? '?'} · ecran: ${d['ecran'] ?? '?'}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          Text('uid: ${d['uid'] ?? '?'}',
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
          if (eroare.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              eroare,
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.danger, fontSize: 12, height: 1.4),
            ),
          ],
          if (_expanded) ...[
            const SizedBox(height: 12),
            const Text('CE A FĂCUT ÎNAINTE',
                style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                firimituri.isEmpty ? '(nimic notat)' : firimituri.join('\n'),
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    height: 1.5,
                    fontFamily: 'monospace'),
              ),
            ),
            if ((d['stiva'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('STIVA',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  d['stiva'] as String,
                  style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      height: 1.4,
                      fontFamily: 'monospace'),
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18),
                label: Text(_expanded ? 'Mai puțin' : 'Detalii'),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => widget.onResolve(!rezolvat),
                child: Text(rezolvat ? 'Redeschide' : 'Rezolvat',
                    style: const TextStyle(color: AppColors.teal)),
              ),
              IconButton(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.danger, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
