// Reclamațiile trimise de jucători despre ALȚI jucători (moderare).
//
// Parte din `admin_screen.dart` (vezi `part of` mai jos): panoul de Admin era
// un singur fișier de peste 3.000 de linii, imposibil de ținut în cap. E
// împărțit pe tab-uri, nu pe tipuri de clase, fiindcă asta e granița după
// care se lucrează la el în practică.
part of '../admin_screen.dart';

/// Raportările trimise de jucători din chat (vezi ModerationService).
///
/// Aici se închide bucla pornită de butonul „Raportează": mesajul reclamat se
/// vede ca text, iar de pe card se poate deschide direct fișa celui reclamat,
/// de unde există deja ban și ștergere completă. Fără pasul ăsta, raportarea
/// ar fi fost un buton care nu duce nicăieri — adică exact ce nu se poate
/// declara la Content rating.
///
/// Cele rezolvate NU se șterg singure: un jucător reclamat de cinci ori,
/// fiecare „rezolvată" la timpul ei, arată altfel decât unul reclamat o dată,
/// și doar istoricul păstrat face diferența vizibilă.
class _ReportsTab extends StatefulWidget {
  const _ReportsTab();

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  late Future<List<PlayerReport>> _future = ModerationService.instance.fetchReports();

  Future<void> _refresh() async {
    setState(() => _future = ModerationService.instance.fetchReports());
    await _future;
  }

  /// Deschide fișa celui reclamat — profilul se citește după uid, nu se
  /// reconstruiește din numele copiat în raportare: numele e doar cum se
  /// chema atunci, uid-ul e cine e.
  Future<void> _openTarget(PlayerReport report) async {
    final profile = await PlayerProfileService.instance.getProfile(report.targetUid);
    if (!mounted) return;
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jucătorul nu mai există (cont șters sau banat).')),
      );
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _PlayerDetailScreen(profile: profile)),
    );
    if (changed == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PlayerReport>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        final reports = snap.data!;
        if (reports.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.orange,
            child: ListView(
              children: const [
                SizedBox(height: 100),
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Nicio raportare.\n\nAici ajung reclamațiile trimise de jucători din chatul '
                      'camerelor sau din firele private de prieteni.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.orange,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            itemCount: reports.length,
            itemBuilder: (context, i) => _ReportCard(
              report: reports[i],
              onOpenTarget: () => _openTarget(reports[i]),
              onToggleHandled: () async {
                await ModerationService.instance.markReportHandled(reports[i].id, handled: !reports[i].handled);
                await _refresh();
              },
              onDelete: () async {
                await ModerationService.instance.deleteReport(reports[i].id);
                await _refresh();
              },
            ),
          ),
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  final PlayerReport report;
  final VoidCallback onOpenTarget;
  final VoidCallback onToggleHandled;
  final VoidCallback onDelete;

  const _ReportCard({
    required this.report,
    required this.onOpenTarget,
    required this.onToggleHandled,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final handled = report.handled;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        // Nerezolvatele ies în evidență; cele bifate se retrag vizual, dar
        // rămân în listă ca istoric.
        color: handled ? Colors.white.withAlpha(8) : AppColors.danger.withAlpha(22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: handled ? Colors.white12 : AppColors.danger.withAlpha(110)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(handled ? Icons.check_circle_rounded : Icons.flag_rounded,
                  color: handled ? AppColors.play : AppColors.danger, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  report.reason.label,
                  style: TextStyle(
                    color: handled ? Colors.white54 : Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                _reportTime(report.createdAt),
                style: const TextStyle(color: Colors.white38, fontSize: 10.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: report.reporterName,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: '  l-a reclamat pe  ', style: TextStyle(color: Colors.white38, fontSize: 12)),
                TextSpan(
                  text: report.targetName,
                  style: const TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          if (report.messageText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.black.withAlpha(60), borderRadius: BorderRadius.circular(10)),
              child: Text(
                report.messageText,
                style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35, fontStyle: FontStyle.italic),
              ),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onOpenTarget,
                child: const Text('Fișa lui', style: TextStyle(color: AppColors.blue, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: onToggleHandled,
                child: Text(handled ? 'Redeschide' : 'Rezolvat',
                    style: const TextStyle(color: AppColors.play, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 19),
                tooltip: 'Șterge raportarea',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _reportTime(Timestamp? ts) {
  if (ts == null) return '';
  final dt = ts.toDate().toLocal();
  final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  final now = DateTime.now();
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) return 'azi $time';
  return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} $time';
}
