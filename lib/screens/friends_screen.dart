import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/leagues.dart';
import '../core/theme.dart';
import '../data/player_profile_service.dart';
import '../models/multiplayer_models.dart' show pickAvatarColor;
import '../models/player_profile.dart';
import '../widgets/avatar.dart';

/// Ecran de Prieteni — codul propriu (generat lazy, vezi
/// PlayerProfileService.getOrCreateFriendCode), adăugare prin cod (cerere +
/// acceptare), cereri primite în așteptare, și lista prietenilor acceptați
/// cu statistici live (nu denormalizate — vezi PlayerProfileService.fetchFriends).
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late Future<_FriendsData> _dataFuture = _load();
  final _codeController = TextEditingController();
  bool _sending = false;

  Future<_FriendsData> _load() async {
    final results = await Future.wait([
      PlayerProfileService.instance.getOrCreateFriendCode(),
      PlayerProfileService.instance.fetchIncomingRequests(),
      PlayerProfileService.instance.fetchFriends(),
    ]);
    return _FriendsData(
      myCode: results[0] as String?,
      requests: results[1] as List<FriendRequest>,
      friends: results[2] as List<PlayerProfile>,
    );
  }

  Future<void> _reload() async {
    setState(() => _dataFuture = _load());
    await _dataFuture;
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || _sending) return;
    setState(() => _sending = true);
    final outcome = await PlayerProfileService.instance.sendFriendRequest(code);
    if (!mounted) return;
    setState(() => _sending = false);
    final message = switch (outcome) {
      FriendRequestOutcome.sent => 'Cerere trimisă!',
      FriendRequestOutcome.autoAccepted => 'V-ați adăugat reciproc!',
      FriendRequestOutcome.alreadyFriends => 'Sunteți deja prieteni.',
      FriendRequestOutcome.notFound => 'Nu am găsit niciun jucător cu acest cod.',
      FriendRequestOutcome.isSelf => 'Nu te poți adăuga pe tine însuți.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    if (outcome == FriendRequestOutcome.sent || outcome == FriendRequestOutcome.autoAccepted) {
      _codeController.clear();
      await _reload();
    }
  }

  Future<void> _accept(String fromUid) async {
    await PlayerProfileService.instance.acceptFriendRequest(fromUid);
    await _reload();
  }

  Future<void> _decline(String fromUid) async {
    await PlayerProfileService.instance.declineFriendRequest(fromUid);
    await _reload();
  }

  Future<void> _remove(String friendUid) async {
    await PlayerProfileService.instance.removeFriend(friendUid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prieten eliminat.')));
    await _reload();
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiat!')));
  }

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
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70)),
                  const SizedBox(width: 4),
                  const Text('Prieteni', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<_FriendsData>(
                future: _dataFuture,
                builder: (context, snap) {
                  final data = snap.data;
                  if (data == null) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.teal));
                  }
                  return RefreshIndicator(
                    onRefresh: _reload,
                    color: AppColors.teal,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      children: [
                        _buildMyCodeCard(data.myCode),
                        const SizedBox(height: 20),
                        _buildAddField(),
                        const SizedBox(height: 24),
                        if (data.requests.isNotEmpty) ...[
                          Text('Cereri primite (${data.requests.length})',
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          for (final r in data.requests)
                            _RequestRow(request: r, onAccept: () => _accept(r.fromUid), onDecline: () => _decline(r.fromUid)),
                          const SizedBox(height: 24),
                        ],
                        Text('Prietenii tăi (${data.friends.length})',
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        if (data.friends.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'Nu ai niciun prieten încă.\nAdaugă-i după codul lor.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white38, fontSize: 13),
                              ),
                            ),
                          )
                        else
                          for (final f in data.friends) _FriendRow(profile: f, onRemove: () => _remove(f.uid)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyCodeCard(String? code) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Row(
        children: [
          const Icon(Icons.badge_rounded, color: AppColors.teal, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Codul tău', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  code ?? '......',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 3, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          if (code != null)
            IconButton(onPressed: () => _copyCode(code), icon: const Icon(Icons.copy_rounded, color: Colors.white70), tooltip: 'Copiază'),
        ],
      ),
    );
  }

  Widget _buildAddField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 9,
            style: const TextStyle(color: Colors.white, letterSpacing: 2),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Cod prieten',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
            onSubmitted: (_) => _sendRequest(),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: _sending ? null : _sendRequest,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
          child: _sending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Adaugă'),
        ),
      ],
    );
  }
}

/// Formatează [Timestamp] "ultima activitate" — la fel ca în leaderboard
/// (vezi leaderboard_screen.dart), reconstruit local aici ca să nu extindă
/// legăturile dintre ecrane pentru un helper de câteva linii.
String _formatLastActive(dynamic ts) {
  if (ts == null) return 'niciodată online';
  final dt = (ts.toDate() as DateTime).toLocal();
  final now = DateTime.now();
  final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (sameDay(dt, now)) return 'azi $time';
  if (sameDay(dt, now.subtract(const Duration(days: 1)))) return 'ieri $time';
  final date = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}';
  return dt.year == now.year ? '$date $time' : '$date.${dt.year} $time';
}

class _FriendsData {
  final String? myCode;
  final List<FriendRequest> requests;
  final List<PlayerProfile> friends;
  const _FriendsData({required this.myCode, required this.requests, required this.friends});
}

class _RequestRow extends StatelessWidget {
  final FriendRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _RequestRow({required this.request, required this.onAccept, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withAlpha(12), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24)),
      child: Row(
        children: [
          Avatar(
            size: 36,
            label: request.fromName.isNotEmpty ? request.fromName[0].toUpperCase() : '?',
            accentColor: pickAvatarColor(request.fromAvatarSeed),
            photoUrl: request.fromPhotoUrl,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(request.fromName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          IconButton(onPressed: onAccept, icon: const Icon(Icons.check_circle_rounded, color: AppColors.play), tooltip: 'Acceptă'),
          IconButton(onPressed: onDecline, icon: const Icon(Icons.cancel_rounded, color: AppColors.danger), tooltip: 'Refuză'),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  final PlayerProfile profile;
  final VoidCallback onRemove;
  const _FriendRow({required this.profile, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final league = leagueForPoints(profile.leaguePoints);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withAlpha(12), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24)),
      child: Row(
        children: [
          Avatar(size: 36, label: profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?', accentColor: pickAvatarColor(profile.avatarSeed), photoUrl: profile.photoUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(profile.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                Row(
                  children: [
                    Icon(league.icon, color: league.color, size: 12),
                    const SizedBox(width: 4),
                    Text('${league.name} · ${profile.leaguePoints} pct', style: TextStyle(color: league.color, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded, color: Colors.white38, size: 12),
                    const SizedBox(width: 4),
                    Text(_formatLastActive(profile.lastActive), style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _confirmRemove(context),
            icon: const Icon(Icons.person_remove_rounded, color: Colors.white38, size: 20),
            tooltip: 'Elimină prieten',
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Elimini prietenul?', style: TextStyle(color: Colors.white)),
        content: Text('${profile.name} nu va mai apărea în lista ta de prieteni.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Anulează')),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onRemove();
            },
            child: const Text('Elimină', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}
