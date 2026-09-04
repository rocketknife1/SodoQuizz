// Fișa unui jucător și acțiunile pe el (resurse, mesaj, ban, ștergere).
//
// Parte din `admin_screen.dart` (vezi `part of` mai jos): panoul de Admin era
// un singur fișier de peste 3.000 de linii, imposibil de ținut în cap. E
// împărțit pe tab-uri, nu pe tipuri de clase, fiindcă asta e granița după
// care se lucrează la el în practică.
part of '../admin_screen.dart';

/// Fișa completă a unui jucător, deschisă cu tap pe rândul din tab-urile
/// Jucători / Noi azi.
///
/// ORDINEA E INTENȚIONATĂ: primul lucru afișat, înaintea oricărei statistici,
/// e **id-ul unic**. Numele se poate schimba și se poate repeta între
/// jucători; uid-ul nu. Tot ce operează sistemul — grant-urile de resurse
/// (`admin_grants/{uid}`), banarea, ștergerea, legăturile de prietenie,
/// cloud-save-ul — se leagă de uid, niciodată de nickname. Butonul de copiere
/// e acolo tocmai ca id-ul să poată fi lipit într-o discuție de suport sau
/// într-un script, fără să fie transcris de mână.
///
/// Întoarce `true` prin Navigator.pop dacă a schimbat ceva (ban/ștergere), ca
/// lista din spate să se reîmprospăteze.
class _PlayerDetailScreen extends StatefulWidget {
  final PlayerProfile profile;
  const _PlayerDetailScreen({required this.profile});

  @override
  State<_PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<_PlayerDetailScreen> {
  late Future<_PlayerDetail> _future = _load();
  bool _changed = false;

  /// Numele nou, cât timp titlul de sus încă îl arată pe cel primit de la
  /// listă ([widget.profile] nu se poate schimba, e final).
  String? _renamedTo;

  /// Profilul recitit de pe server (vezi [_load]) — din el se știe dacă
  /// jucătorul are un nume impus de admin, ceea ce rândul primit de la listă
  /// n-avea de unde să spună.
  PlayerProfile? _fresh;

  /// Profilul se recitește, nu se folosește cel primit de la listă: după un
  /// reset (sau după orice a mai făcut jucătorul între timp) cifrele din
  /// rândul pe care s-a dat tap sunt deja vechi. Dacă recitirea eșuează,
  /// rămâne cel vechi — mai bine cifre învechite decât un ecran gol.
  Future<_PlayerDetail> _load() async {
    final results = await Future.wait([
      PlayerProfileService.instance.fetchFriendsOf(widget.profile.uid),
      PlayerProfileService.instance.fetchCloudSaveAsAdmin(widget.profile.uid),
      PlayerProfileService.instance.getProfile(widget.profile.uid),
      PlayerProfileService.instance.fetchSecurityFlagAsAdmin(widget.profile.uid),
    ]);
    final fresh = results[2] as PlayerProfile? ?? widget.profile;
    _fresh = fresh;
    return _PlayerDetail(
      friends: results[0] as List<PlayerProfile>,
      cloudSave: results[1] as Map<String, dynamic>?,
      profile: fresh,
      securityFlag: results[3] as Map<String, dynamic>?,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  /// Cererea pleacă de pe contul cu care e logat adminul — nu e o „cerere de
  /// sistem", ci una obișnuită, de la un jucător anume. Rezultatul se spune
  /// pe față, inclusiv cazul în care cererea s-a transformat în prietenie pe
  /// loc (pentru că exista deja una în sens invers).
  Future<void> _sendFriendRequest(BuildContext context, PlayerProfile p) async {
    final outcome = await PlayerProfileService.instance.sendFriendRequestToUid(p.uid);
    if (!context.mounted) return;
    final (text, color) = switch (outcome) {
      FriendRequestOutcome.sent => ('Cerere trimisă către ${p.name}. Îi apare în clopoțel.', AppColors.play),
      FriendRequestOutcome.autoAccepted => ('${p.name} îți trimisese deja cerere — sunteți prieteni acum.', AppColors.play),
      FriendRequestOutcome.alreadyFriends => ('Sunteți deja prieteni.', AppColors.blue),
      FriendRequestOutcome.isSelf => ('Ăsta e chiar contul tău.', AppColors.orange),
      FriendRequestOutcome.notFound => ('Nu am putut trimite cererea.', AppColors.danger),
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  /// Redenumirea jucătorului. Singura acțiune din fișa asta care schimbă ceva
  /// ce vede TOATĂ lumea imediat (clasament, prieteni, camere), de-aia scrie
  /// pe față și cât durează până ajunge pe telefonul lui: numele public se
  /// schimbă pe loc, dar propriul lui joc îl adoptă abia la următoarea
  /// deschidere a aplicației (vezi PlayerProfileService.renamePlayerAsAdmin).
  Future<void> _editName(PlayerProfile p) async {
    // profilul proaspăt, dacă a apucat să se încarce: el știe dacă numele e
    // deja unul impus, deci dacă are rost butonul de deblocare
    final target = _fresh ?? p;
    final controller = TextEditingController(text: _renamedTo ?? target.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Schimbă numele', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              maxLength: 16,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(counterStyle: TextStyle(color: Colors.white54)),
            ),
            const SizedBox(height: 6),
            // Redenumirea NU mai blochează nimic: oricine își poate schimba
            // singur numele din Profil/Multiplayer. Textul spune doar ce se
            // întâmplă acum și că jucătorul poate reveni oricând.
            Text(
              target.forcedName.isEmpty
                  ? 'Numele public se schimbă imediat. În jocul lui apare la următoarea '
                      'deschidere a aplicației. Poate reveni oricând singur la un nume ales de el.'
                  : 'Numele lui e acum pus de tine. Poate reveni oricând singur la unul ales de '
                      'el, din Profil. „Anulează redenumirea" îi șterge numele impus fără să mai aștepți.',
              style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.3),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Anulează')),
          // Singura cale de a anula o redenumire fără să știi numele original
          // al jucătorului. Numele impus rămâne public până la primul
          // heartbeat al telefonului lui, care îl înlocuiește cu al lui.
          if (target.forcedName.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, _unlockSentinel),
              child: const Text('Anulează redenumirea', style: TextStyle(color: AppColors.orange)),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Salvează'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;

    final unlock = result == _unlockSentinel;
    final ok = unlock
        ? await PlayerProfileService.instance.clearForcedNameAsAdmin(target.uid)
        : await PlayerProfileService.instance.renamePlayerAsAdmin(target.uid, result);
    if (!mounted) return;
    if (ok) {
      _changed = true;
      setState(() {
        if (!unlock) _renamedTo = result;
        _future = _load();
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ok ? AppColors.play : AppColors.danger,
        content: Text(
          ok
              ? (unlock
                  ? 'Își poate alege din nou numele. Îi revine al lui când redeschide jocul.'
                  : 'Redenumit în „$result".')
              : 'Nu am putut schimba numele.',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// Răspunsul butonului „Anulează redenumirea", ca dialogul să întoarcă tot un
  /// String. Nu se poate confunda cu un nume tastat: butonul „Salvează"
  /// întoarce mereu textul cu `trim()`, deci nimic din câmp nu poate ieși cu
  /// spații la capete.
  static const _unlockSentinel = ' ::unlock:: ';

  void _copyUid() {
    Clipboard.setData(ClipboardData(text: widget.profile.uid));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ID copiat.'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context, _changed),
                      icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                    ),
                    const SizedBox(width: 4),
                    // Numele + creionul: tot rândul e apăsabil, nu doar
                    // iconița — o țintă de 20px lățime, lipită de un text
                    // lung, se ratează des pe telefon.
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _editName(p),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                _renamedTo ?? p.name,
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.edit_rounded, color: AppColors.orange, size: 19),
                          ],
                        ),
                      ),
                    ),
                    // Deschide firul cu jucatorul asta. Merge si daca el n-a
                    // scris niciodata: firul se creeaza la primul mesaj, iar
                    // documentul-cap poarta uid-ul lui ca nume.
                    IconButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminChatScreen(
                            playerUid: p.uid,
                            title: _renamedTo ?? p.name,
                            asAdmin: true,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.forum_rounded, color: AppColors.teal, size: 20),
                      tooltip: 'Scrie-i un mesaj',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<_PlayerDetail>(
                  future: _future,
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator(color: AppColors.orange));
                    }
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      color: AppColors.orange,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                        children: _body(snap.data!.profile, snap.data!),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(PlayerProfile p, _PlayerDetail d) {
    final save = d.cloudSave;
    final xp = (save?['xp'] as num?)?.toInt() ?? 0;
    return [
      // ── ID-ul unic, primul lucru pe ecran ──
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.teal.withAlpha(90)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(
                  size: 44,
                  label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                  accentColor: pickAvatarColor(p.avatarSeed),
                  photoUrl: p.photoUrl,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(p.name,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis),
                      Text(
                        p.hasGoogleAccount ? 'Cont Google' : 'Guest',
                        style: TextStyle(
                          color: p.hasGoogleAccount ? AppColors.play : Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text('ID UNIC',
                style: TextStyle(color: AppColors.teal, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    p.uid,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace', height: 1.35),
                  ),
                ),
                IconButton(
                  onPressed: _copyUid,
                  icon: const Icon(Icons.copy_rounded, color: AppColors.teal, size: 20),
                  tooltip: 'Copiază ID-ul',
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Resursele, banarea și ștergerea se leagă de acest ID, nu de nume. '
              'Numele se poate schimba și se poate repeta; ID-ul nu.',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),

      // ── Balanța ──
      const _SectionTitle('Balanță'),
      // Semnalul stă DEASUPRA cifrelor, nu sub ele: dacă balanța e falsificată,
      // asta e prima informație care contează despre ea. Apare doar când chiar
      // există un semnal — un panou curat nu arată nimic aici.
      if (d.securityFlag != null) ...[
        _SecurityFlagCard(flag: d.securityFlag!),
        const SizedBox(height: 12),
      ],
      if (save == null)
        const _InfoCard(
          icon: Icons.lock_outline_rounded,
          text: 'Nu a urcat încă nimic în cloud. Prima sincronizare se face '
              'când trimite aplicația în fundal — până atunci nu există '
              'balanță de arătat aici, indiferent de felul contului.',
        )
      else ...[
        // ATENȚIE la valorile implicite: `exportAll` urcă doar cheile chiar
        // scrise în SharedPreferences, deci la un cont nou `coins`/`gems`/
        // `lives`/`hints` LIPSESC din cloud-save până când jucătorul câștigă
        // sau cheltuie ceva. Lipsa înseamnă "încă la valoarea de start", nu
        // zero — cu `?? 0` fișa arăta 0 monede unui jucător care avea 173.
        Row(
          children: [
            Expanded(
                child: _BalanceTile(
                    label: 'Monede',
                    value: (save['coins'] as num?)?.toInt() ?? StorageService.startingCoinsDefault,
                    color: AppColors.coin,
                    icon: Icons.monetization_on_rounded)),
            const SizedBox(width: 10),
            Expanded(
                child: _BalanceTile(
                    label: 'Gems',
                    value: (save['gems'] as num?)?.toInt() ?? starterGemGrant,
                    color: AppColors.gem,
                    icon: Icons.diamond_rounded)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _BalanceTile(
                    label: 'Inimi',
                    value: (save['lives'] as num?)?.toInt() ?? StorageService.startingLivesDefault,
                    color: AppColors.life,
                    icon: Icons.favorite_rounded)),
            const SizedBox(width: 10),
            Expanded(
                child: _BalanceTile(
                    label: 'Hints',
                    value: (save['hints_balance'] as num?)?.toInt() ?? StorageService.startingHintsDefault,
                    color: AppColors.hint,
                    icon: Icons.lightbulb_rounded)),
          ],
        ),
        const SizedBox(height: 10),
        // XP-ul brut e o cifră lungă și fără înțeles la prima vedere; nivelul
        // e ce înseamnă ea de fapt (vezi core/progression.dart).
        _DetailRow(label: 'Nivel', value: '${levelForXp(xp)}', highlight: true),
        _DetailRow(label: 'XP total', value: _grouped(xp)),
        const SizedBox(height: 8),
        const _InfoCard(
          icon: Icons.cloud_sync_rounded,
          text: 'Cifrele vin din ultima sincronizare cu cloud-ul, care se face '
              'când jucătorul trimite aplicația în fundal. Pot fi în urma față '
              'de ce are pe telefon chiar acum.',
        ),
      ],
      const SizedBox(height: 22),

      // ── Prietenii ──
      _SectionTitle('Prieteni (${d.friends.length})'),
      if (d.friends.isEmpty)
        const _InfoCard(icon: Icons.person_off_rounded, text: 'No friends — nu are nicio legătură de prietenie.')
      else
        ...d.friends.map((f) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Avatar(
                    size: 30,
                    label: f.name.isNotEmpty ? f.name[0].toUpperCase() : '?',
                    accentColor: pickAvatarColor(f.avatarSeed),
                    photoUrl: f.photoUrl,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(f.name,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('${f.leaguePoints} pct', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            )),
      const SizedBox(height: 22),

      // ── Restul datelor esențiale ──
      const _SectionTitle('Detalii'),
      _DetailRow(label: 'Cod de prieten', value: p.friendCode ?? 'încă negenerat', mono: p.friendCode != null),
      _DetailRow(label: 'Ultima activitate', value: p.lastActive == null ? '—' : _relative(p.lastActive!.toDate())),
      _DetailRow(label: 'Cont creat', value: p.createdAt == null ? '—' : _shortDate(p.createdAt!.toDate())),
      _DetailRow(label: 'Puncte de ligă', value: _grouped(p.leaguePoints)),
      _DetailRow(label: 'Meciuri', value: '${p.matchesPlayed}  (${p.wins}V / ${p.losses}Î)'),
      _DetailRow(
        label: 'Winrate',
        value: p.matchesPlayed == 0 ? '—' : '${(p.winrate * 100).toStringAsFixed(0)}%',
      ),
      _DetailRow(label: 'Serie curentă', value: '${p.currentStreak}  (record ${p.longestStreak})'),
      // Cifra care decide soarta unui cont Guest lăsat în pace: roți învârtite
      // + mișcări de balanță, urcate de telefonul lui la fiecare pornire.
      _DetailRow(label: 'Semne de activitate', value: _grouped(p.activityEvents)),
      _DetailRow(label: 'Se șterge automat?', value: _autoDeleteLabel(p)),
      const SizedBox(height: 26),

      // ── Acțiuni ──
      const _SectionTitle('Acțiuni'),
      _ActionButton(
        label: 'Trimite resurse',
        icon: Icons.card_giftcard_rounded,
        color: AppColors.teal,
        onPressed: () => _openGrantSheet(context, p),
      ),
      const SizedBox(height: 10),
      // Notificarea de „ai primit X" se scrie singură când resursele ajung la
      // el (vezi CloudSyncService); asta e pentru un mesaj scris de mână.
      _ActionButton(
        label: 'Trimite mesaj',
        icon: Icons.campaign_rounded,
        color: AppColors.blue,
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.bg,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          builder: (_) => _MessageSheet(profile: p),
        ),
      ),
      const SizedBox(height: 10),
      // Cererea pleacă pe UID, nu pe codul de prieten: un jucător care n-a
      // deschis niciodată ecranul de Prieteni n-are încă un cod generat, și
      // tocmai pe ăia vrei să-i poți contacta din panou. Îi apare în
      // clopoțel ca orice altă cerere (NotificationService.fetchLive).
      _ActionButton(
        label: 'Trimite cerere de prietenie',
        icon: Icons.person_add_rounded,
        color: AppColors.purple,
        onPressed: () => _sendFriendRequest(context, p),
      ),
      const SizedBox(height: 10),
      // Resetul stă lângă ban/ștergere fiindcă e tot ireversibil, dar nu e
      // distructiv la fel: contul rămâne, doar o ia de la capăt — de-aia e
      // portocaliu, nu roșu.
      _ActionButton(
        label: 'Resetează contul',
        icon: Icons.restart_alt_rounded,
        color: AppColors.orange,
        onPressed: () async {
          if (await _confirmReset(context, p)) {
            _changed = true;
            await _refresh();
          }
        },
      ),
      const SizedBox(height: 10),
      _ActionButton(
        label: 'Interzice contul',
        icon: Icons.block_rounded,
        color: AppColors.danger,
        onPressed: () async {
          if (await _confirmBan(context, p)) {
            _changed = true;
            if (mounted) Navigator.pop(context, true);
          }
        },
      ),
      const SizedBox(height: 10),
      _ActionButton(
        label: 'Șterge complet',
        icon: Icons.delete_forever_rounded,
        color: AppColors.danger,
        onPressed: () async {
          if (await _confirmAndPurge(context, p)) {
            _changed = true;
            if (mounted) Navigator.pop(context, true);
          }
        },
      ),
    ];
  }
}

class _PlayerDetail {
  final List<PlayerProfile> friends;

  /// null = încă n-a urcat nimic în cloud (vezi
  /// PlayerProfileService.fetchCloudSaveAsAdmin) — nu mai înseamnă "Guest".
  final Map<String, dynamic>? cloudSave;

  /// Profilul public recitit acum, nu cel din listă — vezi [_load].
  final PlayerProfile profile;

  /// null = curat, cazul normal. Altfel, ce a notat `onBalanceAudit`.
  final Map<String, dynamic>? securityFlag;
  const _PlayerDetail({
    required this.friends,
    required this.cloudSave,
    required this.profile,
    required this.securityFlag,
  });
}

/// Semnalul lăsat de Cloud Function `onBalanceAudit` (functions/index.js).
///
/// Deliberat NU e o acuzație: pragurile sunt generoase, dar un fals pozitiv
/// tot e posibil (o sesiune foarte lungă, un grant mare dat chiar de admin).
/// De-aia textul spune ce s-a văzut, nu ce înseamnă — decizia rămâne a
/// omului, care are oricum butoanele de ban/reset mai jos pe ecran.
class _SecurityFlagCard extends StatelessWidget {
  final Map<String, dynamic> flag;
  const _SecurityFlagCard({required this.flag});

  @override
  Widget build(BuildContext context) {
    final count = (flag['flagCount'] as num?)?.toInt() ?? 1;
    final reason = flag['lastReason'] as String? ?? '';
    final when = (flag['lastFlaggedAt'] as Timestamp?)?.toDate();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.orange.withAlpha(28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.orange.withAlpha(90)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gpp_maybe_rounded, color: AppColors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 1 ? 'Salt de balanță semnalat' : 'Balanță semnalată de $count ori',
                  style: const TextStyle(color: AppColors.orange, fontSize: 13, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                if (reason.isNotEmpty)
                  Text(reason, style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4)),
                if (when != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'ultima oară ${_relative(when)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sheet cu 5 câmpuri numerice (delta cu semn) — scrie în `admin_grants/{uid}`
/// cu `increment()`, ca grant-uri succesive netransmise încă să se adune,
/// nu să se suprascrie. Ridicat de telefonul jucătorului la următoarea
/// pornire, vezi CloudSyncService.consumePendingGrant.
class _GrantSheet extends StatefulWidget {
  final PlayerProfile profile;
  const _GrantSheet({required this.profile});

  @override
  State<_GrantSheet> createState() => _GrantSheetState();
}

class _GrantSheetState extends State<_GrantSheet> {
  final _hearts = TextEditingController();
  final _hints = TextEditingController();
  final _coins = TextEditingController();
  final _gems = TextEditingController();
  final _xp = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _hearts.dispose();
    _hints.dispose();
    _coins.dispose();
    _gems.dispose();
    _xp.dispose();
    super.dispose();
  }

  int _parse(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Future<void> _send() async {
    final hearts = _parse(_hearts);
    final hints = _parse(_hints);
    final coins = _parse(_coins);
    final gems = _parse(_gems);
    final xp = _parse(_xp);
    if (hearts == 0 && hints == 0 && coins == 0 && gems == 0 && xp == 0) {
      Navigator.pop(context);
      return;
    }
    setState(() => _sending = true);
    try {
      await FirebaseFirestore.instance.collection('admin_grants').doc(widget.profile.uid).set({
        if (hearts != 0) 'hearts': FieldValue.increment(hearts),
        if (hints != 0) 'hints': FieldValue.increment(hints),
        if (coins != 0) 'coins': FieldValue.increment(coins),
        if (gems != 0) 'gems': FieldValue.increment(gems),
        if (xp != 0) 'xp': FieldValue.increment(xp),
        // Momentul ultimei trimiteri — din el se face id-ul notificării de
        // „ai primit X" de pe telefonul jucătorului. Fără el, două cadouri
        // identice trimise la zile distanță ar fi arătat ca același cadou și
        // al doilea n-ar mai fi produs nicio notificare (vezi
        // CloudSyncService.consumePendingGrant).
        'sentAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Trimis către ${widget.profile.name} — se aplică la următoarea deschidere a jocului lui.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nu am putut trimite resursele.')));
    }
  }

  Widget _field(TextEditingController c, String label, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: color, size: 20),
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          hintText: 'ex: 50 sau -20',
          hintStyle: const TextStyle(color: Colors.white24),
          filled: true,
          fillColor: AppColors.card,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resurse pentru ${widget.profile.name}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Numere negative = luare. Se aplică data viitoare când deschide jocul.', style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 16),
          _field(_hearts, 'Inimi', Icons.favorite_rounded, AppColors.life),
          _field(_hints, 'Hint-uri', Icons.tips_and_updates_rounded, AppColors.hint),
          _field(_coins, 'Monede', Icons.monetization_on_rounded, AppColors.coin),
          _field(_gems, 'Gems', Icons.diamond_rounded, const Color(0xFF5EC8F2)),
          _field(_xp, 'XP', Icons.star_rounded, AppColors.purple),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Trimite'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrierea unui anunț — către un jucător anume ([profile] dat) sau către
/// toți ([profile] null, din tab-ul Jucători).
///
/// Ajunge la jucător la următoarea deschidere a jocului, nu instant: fără
/// Cloud Functions (plan gratuit) nu există notificări push, deci anunțul stă
/// într-o cutie poștală pe care telefonul lui o golește la pornire — vezi
/// NotificationService.pullFromCloud.
class _MessageSheet extends StatefulWidget {
  /// null = anunț pentru toți jucătorii.
  final PlayerProfile? profile;
  const _MessageSheet({this.profile});

  @override
  State<_MessageSheet> createState() => _MessageSheetState();
}

class _MessageSheetState extends State<_MessageSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;

  bool get _isBroadcast => widget.profile == null;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty && body.isEmpty) {
      Navigator.pop(context);
      return;
    }
    // Un anunț către toți scrie un document pentru fiecare jucător și nu se
    // poate lua înapoi din aplicație — de-aia se confirmă, spre deosebire de
    // mesajul către o singură persoană.
    if (_isBroadcast) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Trimiți către toți?', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Anunțul ajunge la toți jucătorii activi (max. 300), la următoarea '
            'deschidere a jocului. Nu poate fi retras după trimitere.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Renunță')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Trimite')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _sending = true);
    final String message;
    if (_isBroadcast) {
      final count = await PlayerProfileService.instance.broadcastNotification(title: title, body: body);
      message = count > 0 ? 'Anunț trimis către $count jucători.' : 'Nu am putut trimite anunțul.';
    } else {
      final ok = await PlayerProfileService.instance
          .sendNotification(widget.profile!.uid, title: title, body: body);
      message = ok
          ? 'Mesaj trimis către ${widget.profile!.name} — îl vede la următoarea deschidere a jocului.'
          : 'Nu am putut trimite mesajul.';
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isBroadcast ? 'Anunț pentru toți jucătorii' : 'Mesaj pentru ${widget.profile!.name}',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Apare în clopoțelul de notificări, la următoarea deschidere a jocului.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.title_rounded, color: AppColors.blue, size: 20),
              labelText: 'Titlu',
              labelStyle: const TextStyle(color: Colors.white54),
              hintText: 'ex: Actualizare nouă',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.sentences,
            maxLines: 4,
            maxLength: 400,
            decoration: InputDecoration(
              labelText: 'Mesaj',
              labelStyle: const TextStyle(color: Colors.white54),
              hintStyle: const TextStyle(color: Colors.white24),
              counterStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sending ? null : _send,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isBroadcast ? AppColors.orange : AppColors.blue,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_isBroadcast ? 'Trimite tuturor' : 'Trimite'),
            ),
          ),
        ],
      ),
    );
  }
}
