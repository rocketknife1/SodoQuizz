import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../core/cosmetics.dart';
import '../core/leagues.dart';
import 'async_challenge_screen.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/live_sync.dart';
import '../data/moderation_service.dart';
import '../data/multiplayer_service.dart';
import '../data/player_profile_service.dart';
import '../data/storage_service.dart';
import '../models/friend_chat.dart';
import '../models/multiplayer_models.dart' show pickAvatarColor;
import '../models/player_profile.dart';
import '../widgets/avatar.dart';
import '../widgets/cosmetic_title.dart';
import '../widgets/league_badge.dart';
import 'friend_chat_screen.dart';
import 'multiplayer/leaderboard_screen.dart' show showPlayerProfileSheet;

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
  late Future<_FriendsData> _dataFuture = _runLoad();
  final _codeController = TextEditingController();
  bool _sending = false;

  /// Uid-urile de adversari recenţi cărora le-am trimis deja cerere în sesiunea
  /// asta — butonul „Adaugă" devine „Trimisă" fără o reîncărcare.
  final Set<String> _requestedRecent = {};

  /// Un `_load()` e în zbor acum. A doua cerere de reîncărcare cât asta rulează
  /// nu pornește un `_load()` paralel — se pliază prin [_reloadQueued].
  bool _loadInFlight = false;
  bool _reloadQueued = false;

  /// Capurile de fir, în timp real, din LiveSync — NU recitite aici. Ecranul
  /// era o poză făcută la intrare: stăteai cu el deschis, prietenul îți scria
  /// (sau îți scria al doilea mesaj), și nu apărea nimic. Acum rândurile de
  /// chat se iau direct de aici și se mișcă la orice schimbare de fir.
  Map<String, FriendChatSummary> _summaries = LiveSync.instance.friendSummaries.value;

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
    // Prietenii activi acum sus în listă (ca să vezi imediat cu cine poţi
    // juca), restul după cât de recent au fost online.
    friends.sort((a, b) {
      final onA = a.isRecentlyActive, onB = b.isRecentlyActive;
      if (onA != onB) return onA ? -1 : 1;
      final ta = a.lastActive?.millisecondsSinceEpoch ?? 0;
      final tb = b.lastActive?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta);
    });
    // Adversari recenţi care nu-s deja prieteni / cu cerere primită / blocaţi.
    final friendUids = {for (final f in friends) f.uid};
    final requestUids = {for (final r in (results[1] as List<FriendRequest>)) r.fromUid};
    final recent = (await StorageService.getRecentOpponents())
        .where((o) {
          final uid = o['uid'] ?? '';
          return uid.isNotEmpty &&
              !friendUids.contains(uid) &&
              !requestUids.contains(uid) &&
              !ModerationService.instance.isBlocked(uid);
        })
        .take(6)
        .toList();
    // Rezumatele firelor NU se mai cer aici (erau N citiri la fiecare
    // reîncărcare) — vin live prin [_summaries] din LiveSync.
    return _FriendsData(
      myCode: results[0] as String?,
      // Cererile de la cineva blocat nu se mai arată deloc — altfel blocarea
      // ar fi lăsat deschis exact canalul pe care poate reveni cel blocat.
      requests: (results[1] as List<FriendRequest>)
          .where((r) => !ModerationService.instance.isBlocked(r.fromUid))
          .toList(),
      friends: friends,
      recentOpponents: recent,
    );
  }

  /// `_load()` înfășurat cu coalescere: dacă o schimbare mai sosește cât asta
  /// rulează, se marchează [_reloadQueued] și se face O SINGURĂ reîncărcare la
  /// final — nu se înghite (starea chiar s-a schimbat), dar nici nu se lansează
  /// două `_load()` suprapuse.
  Future<_FriendsData> _runLoad() async {
    _loadInFlight = true;
    try {
      // Ultimul rezultat bun se ține separat ca ecranul să NU se golească
      // într-un spinner la fiecare reîncărcare — vezi [_lastData].
      final data = await _load();
      _lastData = data;
      return data;
    } finally {
      _loadInFlight = false;
      if (_reloadQueued && mounted) {
        _reloadQueued = false;
        setState(() => _dataFuture = _runLoad());
      }
    }
  }

  /// Ultimul set de date încărcat cu succes. `FutureBuilder` are `data == null`
  /// cât timp noul `future` e în zbor, deci fără asta orice cerere primită sau
  /// schimbare de listă ștergea tot ecranul (codul meu, câmpul de adăugare,
  /// lista) și pierdea poziția de derulare. O acceptare produce chiar DOUĂ
  /// semnale — cererea dispare ȘI lista crește — adică două clipiri la rând.
  /// Acum spinnerul apare doar la prima încărcare (recenzie 2026-09-01).
  _FriendsData? _lastData;

  void _scheduleReload() {
    if (!mounted) return;
    if (_loadInFlight) {
      _reloadQueued = true;
      return;
    }
    setState(() => _dataFuture = _runLoad());
  }

  Future<void> _reload() async {
    _scheduleReload();
    await _dataFuture;
  }

  @override
  void initState() {
    super.initState();
    LiveSync.instance.friendSummaries.addListener(_onSummariesChanged);
    LiveSync.instance.incomingRequestUids.addListener(_onRequestsChanged);
    LiveSync.instance.friendUids.addListener(_onFriendListChanged);
    // După ce ramura asta a închis toate celelalte canale prin care un blocat
    // ajungea pe ecran (bulina de notificări, cererile, fetchLive), rândul de
    // prieten cu previzualizarea de chat + bulina de necitit a rămas singurul.
    // Ascultăm lista de blocați ca rândul lui să se cureţe pe loc la blocare/
    // deblocare din altă parte, fără o reîncărcare Firestore.
    ModerationService.instance.blockedIds.addListener(_onBlockedChanged);
  }

  void _onBlockedChanged() {
    if (mounted) setState(() {});
  }

  /// Un fir s-a schimbat: mesaj nou sau marcaj de citit. Doar `setState` cu ce
  /// e deja în memorie — zero citiri Firestore.
  ///
  /// NU acoperă „prieten adăugat/șters" (cum pretindea comentariul de dinainte):
  /// pentru asta e [_onFriendListChanged], fiindcă un prieten nou cere date pe
  /// care nu le avem în memorie.
  void _onSummariesChanged() {
    if (!mounted) return;
    setState(() => _summaries = LiveSync.instance.friendSummaries.value);
  }

  /// O cerere de prietenie a sosit/dispărut cât stăteai pe ecran. Reîncărcăm
  /// tot prin [_load] — la fel ca accept/refuz/adăugare, care deja cheamă
  /// [_reload]. `_load` e ieftin acum (nu mai cheamă `fetchSummaries`), iar
  /// cererile sunt evenimente rare, deci nu merită o cale separată doar pentru
  /// `fetchIncomingRequests`.
  void _onRequestsChanged() => _scheduleReload();

  /// LISTA de prieteni s-a schimbat (cineva ți-a ACCEPTAT cererea, sau te-a
  /// șters). Reîncărcăm, fiindcă numele/liga/scorul noului prieten nu sunt în
  /// memorie — spre deosebire de [_onSummariesChanged], care doar redesenează.
  ///
  /// Fără asta, cine îți accepta cererea nu-ți apărea în listă până nu ieșeai
  /// și intrai la loc: ecranul asculta firele de chat și cererile PRIMITE, iar
  /// acceptarea cererii TALE nu mișcă niciuna. Găsit pe viu, cu doi jucători.
  void _onFriendListChanged() => _scheduleReload();

  @override
  void dispose() {
    LiveSync.instance.friendSummaries.removeListener(_onSummariesChanged);
    LiveSync.instance.incomingRequestUids.removeListener(_onRequestsChanged);
    LiveSync.instance.friendUids.removeListener(_onFriendListChanged);
    ModerationService.instance.blockedIds.removeListener(_onBlockedChanged);
    _codeController.dispose();
    _challengeCodeController.dispose();
    super.dispose();
  }

  /// „Adaugă" pe un adversar recent (are deja uid-ul, nu trece prin cod).
  Future<void> _addRecent(String uid, String name) async {
    if (uid.isEmpty || _requestedRecent.contains(uid)) return;
    setState(() => _requestedRecent.add(uid));
    final outcome = await PlayerProfileService.instance.sendFriendRequestToUid(uid);
    if (!mounted) return;
    final message = switch (outcome) {
      FriendRequestOutcome.sent => tr('Cerere trimisă către $name.', 'Request sent to $name.'),
      FriendRequestOutcome.autoAccepted => tr('V-ați adăugat reciproc!', 'You added each other!'),
      FriendRequestOutcome.alreadyFriends => tr('Sunteți deja prieteni.', 'You are already friends.'),
      FriendRequestOutcome.notFound => tr('Jucătorul nu mai există.', 'That player is gone.'),
      FriendRequestOutcome.isSelf => tr('Ăsta ești tu.', "That's you."),
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    if (outcome == FriendRequestOutcome.notFound || outcome == FriendRequestOutcome.isSelf) {
      setState(() => _requestedRecent.remove(uid));
    } else if (outcome == FriendRequestOutcome.autoAccepted ||
        outcome == FriendRequestOutcome.alreadyFriends) {
      _scheduleReload();
    }
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
      // A treia cale care reîncarcă după o acțiune pe cereri. Rămâne explicită,
      // spre deosebire de [_accept]/[_decline]: pe `sent` nu se șterge nicio
      // cerere de-a mea, deci abonamentul NU emite nimic, iar pe `autoAccepted`
      // `sendFriendRequest` nu poate spune dacă acceptarea din interior a reușit
      // (întoarce `autoAccepted` și când scrierea a eșuat). Fără reîncărcare aici
      // ar rămâne ecranul nemișcat.
      await _reload();
    }
  }

  /// Accept/refuz: O SINGURĂ cale de reîncărcare. Amândouă șterg documentul
  /// cererii, deci abonamentul din LiveSync emite oricum → [_onRequestsChanged]
  /// → o reîncărcare. Un `_reload()` explicit aici ar fi însemnat două `_load()`
  /// (~2N citiri fiecare) la un singur tap.
  ///
  /// Calea de EȘEC e singura care mai reîncarcă: dacă scrierea n-a ajuns în
  /// Firestore (fără rețea, permisiuni) nu vine niciun snapshot, deci ecranul
  /// ar fi rămas neschimbat fără nicio explicație. Atunci arătăm mesajul și
  /// reîncărcăm ca lista să arate adevărul de pe server.
  Future<void> _accept(String fromUid) async {
    final ok = await PlayerProfileService.instance.acceptFriendRequest(fromUid);
    if (!ok) await _onActionFailed();
  }

  Future<void> _decline(String fromUid) async {
    final ok = await PlayerProfileService.instance.declineFriendRequest(fromUid);
    if (!ok) await _onActionFailed();
  }

  Future<void> _onActionFailed() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr('Nu am reușit. Verifică internetul și încearcă din nou.',
          'That failed. Check your connection and try again.')),
    ));
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
                  final data = snap.data ?? _lastData;
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
                        const SizedBox(height: 12),
                        _buildChallengeCodeField(),
                        const SizedBox(height: 24),
                        if (data.requests.isNotEmpty) ...[
                          Text('Cereri primite (${data.requests.length})',
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          for (final r in data.requests)
                            _RequestRow(request: r, onAccept: () => _accept(r.fromUid), onDecline: () => _decline(r.fromUid)),
                          const SizedBox(height: 24),
                        ],
                        if (data.recentOpponents.isNotEmpty) ...[
                          Text(tr('Jucători recenţi', 'Recent players'),
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(tr('Ai jucat cu ei. Adaugă-i ca prieteni.',
                              "You've played against them. Add them as friends."),
                              style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          const SizedBox(height: 10),
                          for (final o in data.recentOpponents)
                            _RecentOpponentRow(
                              opponent: o,
                              requested: _requestedRecent.contains(o['uid']),
                              onAdd: () => _addRecent(o['uid'] ?? '', o['name'] ?? '?'),
                            ),
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
                              // Prietenul rămâne în listă (îl poţi elimina), dar
                              // dacă e blocat nu-şi mai arată ultimul mesaj şi
                              // nici bulina de necitit.
                              summary: ModerationService.instance.isBlocked(f.uid)
                                  ? null
                                  : _summaries[f.uid],
                              onRemove: () => _remove(f.uid),
                              onOpenChat: () => _openChat(f),
                              onChallenge: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AsyncChallengeScreen()),
                              ),
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

  final _challengeCodeController = TextEditingController();

  /// „Provoacă un prieten" — două acțiuni într-un rând: butonul mare pornește
  /// o provocare NOUĂ (joci → primești un cod de trimis), câmpul primește un
  /// cod de la altcineva (deep link-ul `guessit://challenge/<id>` merge doar
  /// pe Android; codul merge peste tot).
  Widget _buildChallengeCodeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AsyncChallengeScreen()),
          ),
          icon: const Icon(Icons.sports_kabaddi_rounded, size: 18),
          label: Text(tr('PROVOACĂ UN PRIETEN', 'CHALLENGE A FRIEND')),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.orange,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _challengeCodeController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                style: const TextStyle(color: Colors.white, letterSpacing: 2),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: tr('Ai primit un cod?', 'Got a code?'),
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _openChallengeCode(),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _openChallengeCode,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.orange,
                side: const BorderSide(color: AppColors.orange),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              ),
              child: Text(tr('Intră', 'Enter')),
            ),
          ],
        ),
      ],
    );
  }

  void _openChallengeCode() {
    final code = _challengeCodeController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    _challengeCodeController.clear();
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AsyncChallengeScreen(challengeId: code)),
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
              hintText: tr('Cod prieten', 'Friend code'),
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

  /// Adversari din meciuri recente care NU sunt deja prieteni — pentru
  /// secţiunea „Adaugă-i" (vezi StorageService.getRecentOpponents).
  final List<Map<String, String>> recentOpponents;

  const _FriendsData({
    required this.myCode,
    required this.requests,
    required this.friends,
    this.recentOpponents = const [],
  });
}

class _RecentOpponentRow extends StatelessWidget {
  final Map<String, String> opponent;
  final bool requested;
  final VoidCallback onAdd;

  const _RecentOpponentRow({required this.opponent, required this.requested, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final name = opponent['name'] ?? '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Avatar(
            size: 32,
            label: name.isNotEmpty ? name[0].toUpperCase() : '?',
            accentColor: pickAvatarColor(opponent['seed'] ?? name),
            photoUrl: opponent['photo'],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          if (requested)
            Text(tr('Trimisă', 'Sent'),
                style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w700))
          else
            TextButton(
              onPressed: onAdd,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.teal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
              ),
              child: Text(tr('Adaugă', 'Add'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ),
        ],
      ),
    );
  }
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
  final VoidCallback onChallenge;

  const _FriendRow({
    required this.profile,
    required this.onRemove,
    required this.onOpenChat,
    required this.onChallenge,
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
    final online = profile.isRecentlyActive;
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
            // Tap pe avatar = fișa publică a prietenului (nivel, statistici,
            // ramă, titlu); restul rândului rămâne pe deschiderea firului.
            GestureDetector(
              onTap: () => showPlayerProfileSheet(context, profile),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AvatarWithLeagueBadge(
                    size: 36,
                    label: profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                    accentColor: pickAvatarColor(profile.avatarSeed),
                    photoUrl: profile.photoUrl,
                    style: avatarStyleFromId(profile.avatarStyle),
                    frame: validatedFrame(profile.equippedFrame, level: profile.level, leaguePoints: profile.leaguePoints),
                    tier: peakTier,
                  ),
                  if (online)
                    Positioned(
                      left: -1,
                      bottom: -1,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2ECC71),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.bg, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
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
                  CosmeticTitle(titleId: profile.equippedTitle, fontSize: 10),
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
                      Icon(online ? Icons.circle : Icons.access_time_rounded,
                          color: online ? const Color(0xFF2ECC71) : Colors.white38, size: online ? 8 : 12),
                      const SizedBox(width: 4),
                      Text(
                        online ? tr('Activ acum', 'Active now') : _formatLastActive(profile.lastActive),
                        style: TextStyle(
                            color: online ? const Color(0xFF2ECC71) : Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onChallenge,
              icon: const Icon(Icons.sports_kabaddi_rounded, color: AppColors.orange, size: 19),
              tooltip: tr('Provoacă', 'Challenge'),
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
