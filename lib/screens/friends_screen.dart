import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../core/leagues.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/friend_chat_service.dart';
import '../data/moderation_service.dart';
import '../data/multiplayer_service.dart';
import '../data/player_profile_service.dart';
import '../models/friend_chat.dart';
import '../models/multiplayer_models.dart' show pickAvatarColor;
import '../models/player_profile.dart';
import '../widgets/avatar.dart';
import '../widgets/league_badge.dart';
import 'friend_chat_screen.dart';

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
    // No-op dacă e deja încărcată pentru contul curent — e aici pentru cazul
    // în care userul tocmai s-a logat cu Google și uid-ul s-a schimbat.
    await ModerationService.instance.loadBlocked();
    final results = await Future.wait([
      PlayerProfileService.instance.getOrCreateFriendCode(),
      PlayerProfileService.instance.fetchIncomingRequests(),
      PlayerProfileService.instance.fetchFriends(),
    ]);
    final friends = results[2] as List<PlayerProfile>;
    // Rezumatele firelor private se cer DUPĂ ce se știe lista de prieteni
    // (una pe fir), nu în paralel cu ea. Sunt ce alimentează bulina de mesaj
    // nou și începutul ultimului mesaj de pe fiecare rând.
    final summaries = await FriendChatService.instance.fetchSummaries(friends.map((f) => f.uid).toList());
    return _FriendsData(
      myCode: results[0] as String?,
      // Cererile de la cineva blocat nu se mai arată deloc — altfel blocarea
      // ar fi lăsat deschis exact canalul pe care poate reveni cel blocat.
      requests: (results[1] as List<FriendRequest>)
          .where((r) => !ModerationService.instance.isBlocked(r.fromUid))
          .toList(),
      friends: friends,
      summaries: summaries,
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
      FriendRequestOutcome.sent => tr('Cerere trimisă!', 'Request sent!'),
      FriendRequestOutcome.autoAccepted => tr('V-ați adăugat reciproc!', 'You added each other!'),
      FriendRequestOutcome.alreadyFriends => tr('Sunteți deja prieteni.', 'You are already friends.'),
      FriendRequestOutcome.notFound => tr('Nu am găsit niciun jucător cu acest cod.', 'No player found with that code.'),
      FriendRequestOutcome.isSelf => tr('Nu te poți adăuga pe tine însuți.', 'You cannot add yourself.'),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Prieten eliminat.', 'Friend removed.'))));
    await _reload();
  }

  /// Deschide firul privat cu un prieten. La întoarcere se reîncarcă lista:
  /// firul tocmai a fost citit (deci bulina trebuie să dispară) și de obicei
  /// s-a și scris ceva (deci ultimul mesaj s-a schimbat).
  Future<void> _openChat(PlayerProfile friend) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FriendChatScreen(friend: friend)));
    if (mounted) await _reload();
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiat!')));
  }

  /// Link-ul de invitație e o schemă proprie (`guessit://addfriend/<cod>`),
  /// nu un Android App Link — vezi comentariul din AndroidManifest.xml
  /// pentru de ce. Compromisul cunoscut: unele aplicații de chat (WhatsApp,
  /// SMS) nu-l randează ca link apăsabil, de-aia mesajul include și codul
  /// simplu, de copiat manual, nu doar link-ul.
  void _shareCode(String code) {
    final link = 'guessit://addfriend/$code';
    Share.share(
      tr(
        'Hai să fim prieteni pe SodoQuizz! Apasă linkul (sau intră cu codul $code din Prieteni):\n$link',
        "Let's be friends on SodoQuizz! Tap the link (or enter code $code under Friends):\n$link",
      ),
    );
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
                  Text(tr('Prieteni', 'Friends'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
                        Text(tr('Prietenii tăi (${data.friends.length})', 'Your friends (${data.friends.length})'),
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        if (data.friends.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                tr('Nu ai niciun prieten încă.\nAdaugă-i după codul lor.',
                                    'No friends yet.\nAdd them using their code.'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white38, fontSize: 13),
                              ),
                            ),
                          )
                        else
                          for (final f in data.friends)
                            _FriendRow(
                              profile: f,
                              summary: data.summaries[f.uid],
                              onRemove: () => _remove(f.uid),
                              onOpenChat: () => _openChat(f),
                            ),
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
                Text(tr('Codul tău', 'Your code'), style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  code ?? '......',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 3, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          if (code != null) ...[
            IconButton(onPressed: () => _copyCode(code), icon: const Icon(Icons.copy_rounded, color: Colors.white70), tooltip: tr('Copiază', 'Copy')),
            IconButton(
              onPressed: () => _shareCode(code),
              icon: const Icon(Icons.share_rounded, color: AppColors.teal),
              tooltip: tr('Trimite invitație', 'Send invite'),
            ),
          ],
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
              : Text(tr('Adaugă', 'Add')),
        ),
      ],
    );
  }
}

/// Formatează [Timestamp] "ultima activitate" — la fel ca în leaderboard
/// (vezi leaderboard_screen.dart), reconstruit local aici ca să nu extindă
/// legăturile dintre ecrane pentru un helper de câteva linii.
String _formatLastActive(dynamic ts) {
  if (ts == null) return tr('niciodată online', 'never online');
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

  /// uid-ul prietenului → capul firului privat cu el. Lipsește pentru
  /// prietenii cu care nu s-a schimbat niciun mesaj.
  final Map<String, FriendChatSummary> summaries;

  const _FriendsData({
    required this.myCode,
    required this.requests,
    required this.friends,
    this.summaries = const {},
  });
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
            style: avatarStyleFromId(request.fromAvatarStyle),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(request.fromName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
          IconButton(onPressed: onAccept, icon: const Icon(Icons.check_circle_rounded, color: AppColors.play), tooltip: tr('Acceptă', 'Accept')),
          IconButton(onPressed: onDecline, icon: const Icon(Icons.cancel_rounded, color: AppColors.danger), tooltip: tr('Refuză', 'Decline')),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  final PlayerProfile profile;
  final FriendChatSummary? summary;
  final VoidCallback onRemove;
  final VoidCallback onOpenChat;

  const _FriendRow({
    required this.profile,
    required this.onRemove,
    required this.onOpenChat,
    this.summary,
  });

  @override
  Widget build(BuildContext context) {
    // Sezon, nu punctaj pe viață — la fel ca în clasament (vezi
    // core/leagues.dart#effectiveSeasonPoints), ca lista de Prieteni și
    // tab-ul Prieteni din Clasament să arate mereu ACELEAȘI numere pentru
    // aceeași persoană.
    final seasonPts = effectiveSeasonPoints(seasonKey: profile.seasonKey, seasonPoints: profile.seasonPoints);
    final league = leagueForPoints(seasonPts);
    final peakTierIdx = profile.seasonKey == currentSeasonKey() ? profile.seasonBestTierIndex : 0;
    final peakTier = LeagueTier.values[peakTierIdx.clamp(0, LeagueTier.values.length - 1)];
    final unread = summary?.hasUnreadFor(MultiplayerService.instance.currentPlayerId) ?? false;
    final preview = summary?.lastText ?? '';
    return GestureDetector(
      // Tot rândul deschide firul privat, nu doar iconița — e ținta cea mai
      // ușor de nimerit cu degetul, iar rândul n-avea până acum nicio altă
      // acțiune la tap.
      onTap: onOpenChat,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withAlpha(12), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24)),
        child: Row(
          children: [
            AvatarWithLeagueBadge(
              size: 36,
              label: profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
              accentColor: pickAvatarColor(profile.avatarSeed),
              photoUrl: profile.photoUrl,
              style: avatarStyleFromId(profile.avatarStyle),
              tier: peakTier,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(profile.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (unread) ...[const SizedBox(width: 6), const UnreadDot()],
                    ],
                  ),
                  // Ultimul mesaj ia locul rândului de ligă doar când există —
                  // altfel rândul ar fi crescut cu o linie goală pentru toți
                  // prietenii cu care n-ai vorbit niciodată.
                  if (preview.isNotEmpty)
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: unread ? Colors.white : Colors.white54,
                        fontSize: 11.5,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                      ),
                    )
                  else
                    Row(
                      children: [
                        Icon(league.icon, color: league.color, size: 12),
                        const SizedBox(width: 4),
                        Text('${league.name} · $seasonPts pct', style: TextStyle(color: league.color, fontSize: 11, fontWeight: FontWeight.w700)),
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
              onPressed: onOpenChat,
              icon: const Icon(Icons.chat_bubble_rounded, color: AppColors.teal, size: 19),
              tooltip: 'Scrie-i',
            ),
            IconButton(
              onPressed: () => _confirmRemove(context),
              icon: const Icon(Icons.person_remove_rounded, color: Colors.white38, size: 20),
              tooltip: tr('Elimină prieten', 'Remove friend'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Elimini prietenul?', style: TextStyle(color: Colors.white)),
        content: Text(tr('${profile.name} nu va mai apărea în lista ta de prieteni.', '${profile.name} will no longer appear in your friends list.'), style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('Anulează', 'Cancel'))),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onRemove();
            },
            child: Text(tr('Elimină', 'Remove'), style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}
