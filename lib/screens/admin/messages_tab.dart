// Firele de discuție dintre admin și jucători.
//
// Parte din `admin_screen.dart` (vezi `part of` mai jos): panoul de Admin era
// un singur fișier de peste 3.000 de linii, imposibil de ținut în cap. E
// împărțit pe tab-uri, nu pe tipuri de clase, fiindcă asta e granița după
// care se lucrează la el în practică.
part of '../admin_screen.dart';

/// Tab-ul Mesaje: toate firele admin↔jucator, cel mai recent primul.
///
/// Un singur abonament pe colectia `admin_threads` — de-aia rezumatul
/// (ultimul mesaj, numele jucatorului, bulinele de necitit) e copiat in
/// documentul-cap al firului: altfel lista ar fi cerut un query ordonat in
/// subcolectia fiecarui fir, la fiecare deschidere a tabului.
class _MessagesTab extends StatelessWidget {
  const _MessagesTab();

  static String _when(Timestamp? ts) {
    if (ts == null) return '';
    final d = DateTime.now().difference(ts.toDate());
    if (d.inMinutes < 1) return 'acum';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}z';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminThreadSummary>>(
      stream: AdminChatService.instance.watchAllThreads(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Firele nu au putut fi citite.\n\n${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        final threads = snap.data!;
        if (threads.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Niciun mesaj de la jucatori.\n\nAici ajunge ce scriu din '
                'Setari → "Mesaj catre admin". Poti deschide un fir si tu, din '
                'fisa oricarui jucator (tab-ul Jucatori).',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: threads.length,
          itemBuilder: (context, i) => _row(context, threads[i]),
        );
      },
    );
  }

  Widget _row(BuildContext context, AdminThreadSummary t) {
    final unread = t.hasUnreadForAdmin;
    final name = t.playerName.isNotEmpty ? t.playerName : t.playerUid;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: unread ? AppColors.orange.withAlpha(26) : Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminChatScreen(playerUid: t.playerUid, title: name, asAdmin: true),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Avatar(
                  size: 34,
                  label: name.isNotEmpty ? name[0].toUpperCase() : '?',
                  accentColor: pickAvatarColor(t.playerUid),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: unread ? FontWeight.w900 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // Prefixul spune dintr-o privire daca astept raspuns
                        // de la mine sau daca mingea e la jucator.
                        (t.lastFromAdmin ? 'Tu: ' : '') + t.lastText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_when(t.lastMessageAt),
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    const SizedBox(height: 6),
                    if (unread)
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                            color: AppColors.danger, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
