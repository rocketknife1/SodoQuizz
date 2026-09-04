// Camerele de multiplayer active și detaliul unei camere.
//
// Parte din `admin_screen.dart` (vezi `part of` mai jos): panoul de Admin era
// un singur fișier de peste 3.000 de linii, imposibil de ținut în cap. E
// împărțit pe tab-uri, nu pe tipuri de clase, fiindcă asta e granița după
// care se lucrează la el în practică.
part of '../admin_screen.dart';

/// Camerele terminate în ultimele [roomActivityRetention] — vezi
/// MultiplayerActivityService pentru de ce dispar singure și cum.
///
/// La fiecare încărcare se mătură întâi camerele expirate rămase de la
/// jucători care n-au mai deschis aplicația (clienții și le șterg singuri pe
/// ale lor, dar numai când mai pornesc jocul).
class _RoomsTab extends StatefulWidget {
  const _RoomsTab();

  @override
  State<_RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<_RoomsTab> {
  late Future<List<RoomActivity>> _future = _load();

  Future<List<RoomActivity>> _load() async {
    await MultiplayerActivityService.instance.sweepExpiredAsAdmin();
    return MultiplayerActivityService.instance.fetchRooms();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RoomActivity>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.orange));
        }
        final rooms = snap.data!;
        if (rooms.isEmpty) {
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
                      'Nicio cameră activă.\n\nAici apar meciurile multiplayer terminate, '
                      'cu ce a pus și ce a luat fiecare jucător. Fiecare cameră se șterge '
                      'singură la 10 minute după terminarea meciului.',
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
            itemCount: rooms.length,
            itemBuilder: (context, i) => _RoomCard(
              room: rooms[i],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => _RoomDetailScreen(room: rooms[i])),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RoomCard extends StatelessWidget {
  final RoomActivity room;
  final VoidCallback onTap;
  const _RoomCard({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.purple.withAlpha(40),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.meeting_room_rounded, color: AppColors.purple, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Cameră de ${room.playerCount} jucători',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_modeLabel(room.gameModeId)} · pot ${_grouped(room.pool)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _expiryLabel(room),
                    style: const TextStyle(color: AppColors.orange, fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

/// Tabloul complet al unei camere: id-ul camerei sus, apoi fiecare jucător cu
/// id-ul lui unic și cu cât a intrat / cu cât a ieșit.
class _RoomDetailScreen extends StatelessWidget {
  final RoomActivity room;
  const _RoomDetailScreen({required this.room});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
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
                  Text(
                    'Cameră de ${room.playerCount} jucători',
                    style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.purple.withAlpha(90)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ID CAMERĂ',
                            style: TextStyle(
                                color: AppColors.purple,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                room.roomId,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13, fontFamily: 'monospace', height: 1.35),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: room.roomId));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('ID cameră copiat.'), duration: Duration(seconds: 2)),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, color: AppColors.purple, size: 20),
                              tooltip: 'Copiază ID-ul camerei',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle('Meciul'),
                  _DetailRow(label: 'Mod de joc', value: _modeLabel(room.gameModeId)),
                  _DetailRow(
                      label: 'Terminat',
                      value: room.finishedAt == null ? '—' : _shortDate(room.finishedAt!.toDate())),
                  _DetailRow(label: 'Se șterge', value: _expiryLabel(room)),
                  _DetailRow(label: 'Pot total', value: _grouped(room.pool)),
                  _DetailRow(label: 'Miza camerei', value: _grouped(room.stake)),
                  const SizedBox(height: 22),
                  _SectionTitle('Jucători (${room.playerCount})'),
                  ...room.players.map((p) => _RoomPlayerCard(player: p)),
                  const SizedBox(height: 16),
                  const _InfoCard(
                    icon: Icons.info_outline_rounded,
                    text: 'Intrat = taxa fixă de intrare plus miza pusă. Ieșit = câștigul din pot '
                        'plus surplusul returnat de plafonul mesei. Diferența dintre ele e '
                        'câștigul sau pierderea reală.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomPlayerCard extends StatelessWidget {
  final RoomActivityPlayer player;
  const _RoomPlayerCard({required this.player});

  @override
  Widget build(BuildContext context) {
    final net = player.net;
    final netColor = net > 0 ? AppColors.play : (net < 0 ? AppColors.danger : Colors.white54);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: player.place == 1 ? AppColors.coin.withAlpha(50) : Colors.white12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${player.place}',
                  style: TextStyle(
                    color: player.place == 1 ? AppColors.coin : Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(player.name,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('${player.score} p', style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          // Id-ul jucătorului, la fel de vizibil ca numele — el e cheia prin
          // care se leagă rândul ăsta de restul bazei de date.
          SelectableText(
            player.uid,
            style: const TextStyle(color: Colors.white38, fontSize: 10.5, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Intrat cu', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
                    Text('−${_grouped(player.entry)}',
                        style: const TextStyle(color: AppColors.danger, fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ieșit cu', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
                    Text('+${_grouped(player.exit)}',
                        style: const TextStyle(color: AppColors.play, fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Net', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
                    Text('${net >= 0 ? '+' : ''}${_grouped(net)}',
                        style: TextStyle(color: netColor, fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Numele lizibil al unui mod de joc, din `gameModeId`-ul salvat.
String _modeLabel(String id) {
  switch (id) {
    case 'classic':
      return 'Clasic';
    case 'higherLower':
      return 'Higher or Lower';
    default:
      return id;
  }
}

/// "se șterge în 7 min" — cât mai are camera până dispare singură.
String _expiryLabel(RoomActivity r) {
  final left = r.timeLeft;
  if (left == null) return 'se șterge acum';
  if (left.inMinutes < 1) return 'se șterge în ${left.inSeconds}s';
  return 'se șterge în ${left.inMinutes + 1} min';
}
