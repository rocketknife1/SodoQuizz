// Cifrele de ansamblu ale jocului.
//
// Parte din `admin_screen.dart` (vezi `part of` mai jos): panoul de Admin era
// un singur fișier de peste 3.000 de linii, imposibil de ținut în cap. E
// împărțit pe tab-uri, nu pe tipuri de clase, fiindcă asta e granița după
// care se lucrează la el în practică.
part of '../admin_screen.dart';

class _StatsTab extends StatefulWidget {
  const _StatsTab();

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  late Future<_StatsData> _future = _load();

  Future<_StatsData> _load() async {
    final results = await Future.wait([
      PlayerProfileService.instance.fetchAllPlayers(),
      PlayerProfileService.instance.fetchCompletedMatchesCount(),
      PlayerProfileService.instance.fetchPendingAuthDeletions(),
    ]);
    return _StatsData(
      players: results[0] as List<PlayerProfile>,
      completedMatches: results[1] as int,
      pendingAuthDeletions: results[2] as List<PendingAuthDeletion>,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StatsData>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        final players = snap.data!.players;
        final total = players.length;
        final google = players.where((p) => p.hasGoogleAccount).length;
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.orange,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            children: [
              _StatCard(icon: Icons.groups_rounded, label: 'Total jucători', value: '$total', color: AppColors.orange),
              const SizedBox(height: 12),
              _StatCard(icon: Icons.verified_user_rounded, label: 'Google / Guest', value: '$google / ${total - google}', color: AppColors.play),
              const SizedBox(height: 12),
              _StatCard(
                icon: Icons.sports_esports_rounded,
                label: 'Meciuri multiplayer jucate',
                value: '${snap.data!.completedMatches}',
                color: AppColors.blue,
              ),
              // Conturile sterse din joc care mai asteapta stergerea din
              // Firebase Authentication — pasul care cere cheia de service
              // account, deci scriptul de pe calculator (vezi
              // PendingAuthDeletion pentru de ce). Apar pe nume, nu doar
              // numarate: coada se goleste cu o stergere DEFINITIVA, iar
              // inainte de asa ceva trebuie sa se vada exact cine e in ea.
              // Sectiunea intreaga lipseste cand nu e nimic de facut.
              if (snap.data!.pendingAuthDeletions.isNotEmpty) ...[
                const SizedBox(height: 22),
                _SectionTitle('De șters din Auth (${snap.data!.pendingAuthDeletions.length})'),
                ...snap.data!.pendingAuthDeletions.map(
                  (p) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withAlpha(20),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.danger.withAlpha(70)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.delete_sweep_rounded, color: AppColors.danger, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(p.name,
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis),
                              Text(
                                p.uid,
                                style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          p.requestedAt == null ? '—' : _relative(p.requestedAt!.toDate()),
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                const _InfoCard(
                  icon: Icons.desktop_windows_rounded,
                  text: 'Datele lor din joc sunt deja șterse; a rămas doar identitatea din '
                      'Firebase Authentication, inertă. Se curăță de pe calculator, cu '
                      '"Curata conturi Auth.bat" — ștergerea cere o cheie de administrator, '
                      'care n-are ce căuta în aplicație.',
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Meciuri: total real, încheiate normal, cu minim 2 jucători. Total jucători/Google-Guest: calculate din primii 300, ordonați după puncte de ligă.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Datele agregate ale tabului Statistici — jucătorii (primii 300, pentru
/// total/Google-vs-Guest) și numărul REAL de meciuri încheiate (agregare
/// server-side, fără plafon — vezi PlayerProfileService.fetchCompletedMatchesCount).
class _StatsData {
  final List<PlayerProfile> players;
  final int completedMatches;

  /// Conturile care asteapta stergerea din Authentication — pe nume, nu doar
  /// numarate, ca sa se vada cine e in coada inainte de a rula scriptul.
  final List<PendingAuthDeletion> pendingAuthDeletions;
  const _StatsData({
    required this.players,
    required this.completedMatches,
    required this.pendingAuthDeletions,
  });
}
