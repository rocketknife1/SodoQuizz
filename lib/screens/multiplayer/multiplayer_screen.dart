import 'package:flutter/material.dart';
import '../../core/obby.dart';
import '../../core/betting.dart';
import '../../core/electric_chair.dart';
import '../../core/lang.dart';
import '../../core/tanks.dart';
import '../../core/theme.dart';
import '../../data/auth_service.dart';
import '../../data/multiplayer_presence_service.dart';
import '../../data/multiplayer_service.dart';
import '../../data/player_profile_service.dart';
import '../../data/storage_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/avatar.dart';
import '../../widgets/edit_name_dialog.dart';
import '../../widgets/entrance_item.dart';
import '../../widgets/match_stake_dialog.dart';
import '../../widgets/multiplayer_info_dialog.dart';
import '../../widgets/space_background.dart';
import 'matchmaking_screen.dart';
import 'room_lobby_screen.dart';

/// Ecranul de intrare în Multiplayer: Create Room (cameră privată cu cod),
/// Join Online (matchmaking public) sau Join with code (intri într-o cameră
/// a unui prieten). Fiecare acțiune reală trece prin
/// [MultiplayerService.ensureInitialized] — dacă Firebase nu e încă
/// configurat (vezi lib/firebase_options.dart), arătăm un mesaj prietenos în
/// loc să lăsăm aplicația să crape.
class MultiplayerScreen extends StatefulWidget {
  const MultiplayerScreen({super.key});

  @override
  State<MultiplayerScreen> createState() => _MultiplayerScreenState();
}

class _MultiplayerScreenState extends State<MultiplayerScreen> with TickerProviderStateMixin {
  String _displayName = '';
  bool _busy = false;

  /// Intrarea pe ecran: avatarul, numele și cele 3 plăci apar în cascadă,
  /// alunecând alternativ din stânga/dreapta, cu un mic „supra-arc" la
  /// final — un meniu care „se întâmplă", nu unul care apare brusc, static.
  late final AnimationController _introCtrl;
  /// Respirația continuă a aurei din jurul avatarului — buclă lentă,
  /// discretă, ca ecranul să nu pară înghețat cât timp jucătorul citește.
  late final AnimationController _pulseCtrl;
  /// Cele două inele „de portal" din jurul avatarului, care se rotesc lent
  /// în sensuri opuse — accentul central de „wow" al ecranului.
  late final AnimationController _ringCtrl;

  /// `true` dacă numele curent a fost impus din Admin — dialogul de schimbare
  /// a numelui îl ridică înainte de salvare ca primul heartbeat să nu-l pună
  /// la loc.
  bool _nameSetByAdmin = false;

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _ringCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
    StorageService.getForcedName().then((forced) {
      if (mounted && forced.isNotEmpty) setState(() => _nameSetByAdmin = true);
    });
    AuthService.instance.multiplayerIdentity().then((identity) {
      if (!mounted) return;
      setState(() {
        _displayName = identity.name;
      });
      // „Am intrat în Multiplayer" — anunțul scurt care le apare celorlalți
      // oriunde ar fi în joc (vezi MultiplayerPresenceService pentru de ce
      // există și cât de rar se scrie). Aici, nu la Create Room: rostul e
      // să se adune lume în același interval de timp, iar pentru asta
      // trebuie anunțat momentul în care CAUȚI un meci, nu cel în care ai
      // deschis deja o cameră.
      MultiplayerPresenceService.instance.announceEntered(
        name: identity.name,
        photoUrl: identity.photoUrl,
        avatarStyle: identity.avatarStyle,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) MultiplayerInfoDialog.maybeShow(context);
    });
    // Redenumirea făcută din panoul de Admin ajunge live pe telefon (vezi
    // PlayerProfileService.startLive) — reciteste numele afișat și starea
    // „nume impus din Admin" fără să aștepte repornirea ecranului.
    PlayerProfileService.instance.profileChanged.addListener(_onProfileChanged);
    _checkConnection();
  }

  Future<void> _onProfileChanged() async {
    if (!mounted) return;
    try {
      final forced = await StorageService.getForcedName();
      final identity = await AuthService.instance.multiplayerIdentity();
      if (!mounted) return;
      setState(() {
        _nameSetByAdmin = forced.isNotEmpty;
        _displayName = identity.name;
      });
    } catch (e) {
      debugPrint('MultiplayerScreen._onProfileChanged a esuat: $e');
    }
  }

  /// Multiplayer-ul are nevoie de internet — verificat AICI, la intrarea în
  /// ecran, nu abia când userul apasă un buton.
  ///
  /// DE CE ÎN AVANS: fără asta, singurul semn că ești offline venea după ce
  /// alegeai modul ȘI miza, plăteai, iar abia scrierea în Firestore pica —
  /// moment în care miza se întoarce (vezi [_createRoom]), dar userul a
  /// trecut degeaba prin trei dialoguri și rămâne cu senzația că „s-a stricat
  /// jocul". Așa află din prima, iar butoanele sunt oprite cât timp n-are
  /// conexiune.
  ///
  /// Restul jocului (solo, quest-uri, magazin) merge NEATINS offline —
  /// progresul se ține local și urcă singur la următoarea conectare, vezi
  /// CloudSyncService. Doar multiplayer-ul chiar nu poate funcționa fără
  /// rețea, fiindcă întreaga lui stare stă în Firestore.
  Future<void> _checkConnection() async {
    try {
      await MultiplayerService.instance.ensureInitialized();
      if (mounted) setState(() => _offlineReason = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _offlineReason = e is MultiplayerUnavailableException
          ? e.message
          : tr('Ai nevoie de internet ca să joci multiplayer.',
              'You need an internet connection to play multiplayer.'));
    }
  }

  /// `null` = totul e în regulă. Altfel, mesajul de arătat în locul
  /// butoanelor (vezi [_checkConnection]).
  String? _offlineReason;

  /// Banda de „n-ai internet" — explică DE CE nu merge și dă un buton de
  /// reîncercare, ca userul să nu fie nevoit să iasă și să reintre în ecran
  /// după ce își pornește datele mobile.
  Widget _buildOfflineBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.danger.withAlpha(35),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.danger.withAlpha(140)),
        ),
        child: Column(
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.danger, size: 26),
            const SizedBox(height: 8),
            Text(
              _offlineReason ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.35),
            ),
            const SizedBox(height: 6),
            Text(
              tr('Restul jocului merge normal fără internet — progresul se salvează pe telefon și urcă singur când te reconectezi.',
                  'The rest of the game works fine offline — your progress is saved on the phone and uploads itself once you reconnect.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.3),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _checkConnection,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
              label: Text(tr('Încearcă din nou', 'Try again'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    PlayerProfileService.instance.profileChanged.removeListener(_onProfileChanged);
    _introCtrl.dispose();
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  void _showUnavailable(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error is MultiplayerUnavailableException ? error.message : 'Multiplayer indisponibil momentan.')),
    );
  }

  Future<void> _editName() async {
    final result = await editDisplayName(context, currentName: _displayName, nameSetByAdmin: _nameSetByAdmin);
    if (result == null || !mounted) return;
    setState(() {
      _displayName = result;
      _nameSetByAdmin = false;
    });
  }

  /// Singurul loc din aplicație unde se alege o sumă: cel care creează camera
  /// fixează miza pentru toți. Cine intră după aceea (cod, listă, Join Online)
  /// doar vede cât costă și confirmă.
  /// Quizz Tanks e SINGURUL mod fără miză (vezi core/tanks.dart): acolo nu se
  /// pune și nu se pierde nimic din balanță, se câștigă doar prada de la
  /// final. Deci pentru el nu se deschide dialogul de mize deloc — a-l arăta
  /// cu „0" ar fi sugerat că miza există, dar e goală.
  Future<void> _createRoom() async {
    if (_busy) return;
    final gameMode = await _pickGameMode();
    if (gameMode == null || !mounted) return;
    final int stake;
    if (gameMode == MatchGameMode.quizzTanks) {
      stake = 0;
    } else {
      final picked = await pickMatchStake(context);
      if (picked == null || !mounted) return;
      stake = picked;
    }
    setState(() => _busy = true);
    final spent = await StorageService.spendCoins(stake);
    if (!spent) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      // identitate proaspătă, nu starea din câmp — dacă userul apasă chiar
      // la deschiderea ecranului, `_displayName` poate fi încă
      // valorile inițiale goale (fetch-ul din initState nu a apucat să
      // răspundă), iar camera ar rămâne PERMANENT fără poza reală în
      // Firestore (scrisă o singură dată, la creare — vezi bug-ul cu poza
      // de Google lipsă la un jucător logat).
      final identity = await AuthService.instance.multiplayerIdentity();
      final info = await MultiplayerService.instance.createRoom(
        displayName: identity.name,
        photoUrl: identity.photoUrl,
        avatarStyle: identity.avatarStyle,
        gameMode: gameMode,
        stake: stake,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RoomLobbyScreen(matchId: info.id, isHost: true, stakePaid: stake)),
      );
    } catch (e) {
      // camera nu s-a creat cu adevărat - miza nu a "cumparat" nimic.
      await StorageService.addCoins(stake);
      _showUnavailable(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Alegerea modului de joc pentru camera nou creată — vezi
  /// [MatchGameMode]. Dialogul urmează stilul celorlalte din acest ecran
  /// (fundal 0xFF1a1a2e).
  Future<MatchGameMode?> _pickGameMode() {
    return showDialog<MatchGameMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF141B36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: Colors.white.withAlpha(30)),
        ),
        title: Text(tr('Alege modul de joc', 'Pick the game mode'),
            style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GameModeOption(
              icon: Icons.quiz_rounded,
              label: tr('Clasic', 'Classic'),
              subtitle: tr('Fiecare răspunde în ritmul lui', 'Everyone answers at their own pace'),
              color: AppColors.blue,
              onTap: () => Navigator.pop(dialogContext, MatchGameMode.classic),
            ),
            const SizedBox(height: 10),
            _GameModeOption(
              icon: Icons.compare_arrows_rounded,
              label: 'Higher & Lower',
              subtitle: tr('Voturi secrete, eliminare progresivă', 'Secret votes, progressive elimination'),
              color: AppColors.danger,
              onTap: () => Navigator.pop(dialogContext, MatchGameMode.higherLower),
            ),
            const SizedBox(height: 10),
            _GameModeOption(
              icon: Icons.military_tech_rounded,
              label: 'Quizz Tanks',
              subtitle: tr('până la $tanksPlayerCount tancuri, $tanksRoundSeconds secunde, fără miză',
                  'up to $tanksPlayerCount tanks, $tanksRoundSeconds seconds, no stake'),
              color: AppColors.orange,
              onTap: () => Navigator.pop(dialogContext, MatchGameMode.quizzTanks),
            ),
            const SizedBox(height: 10),
            _GameModeOption(
              icon: Icons.directions_run_rounded,
              label: 'Obby',
              subtitle: tr('2-$obbyMaxPlayers concurenți, cursă de obstacole, $obbyObstacleCount întrebări',
                  '2-$obbyMaxPlayers racers, obstacle course, $obbyObstacleCount questions'),
              color: AppColors.play,
              onTap: () => Navigator.pop(dialogContext, MatchGameMode.obby),
            ),
            const SizedBox(height: 10),
            _GameModeOption(
              icon: Icons.electric_bolt_rounded,
              label: tr('Scaunul Electric', 'Electric Chair'),
              subtitle: tr('până la $electricChairPlayerCount jucători, $electricChairMaxLives vieți fiecare, alegi cine merge pe scaun',
                  'up to $electricChairPlayerCount players, $electricChairMaxLives lives each, pick who goes on the chair'),
              color: AppColors.danger,
              onTap: () => Navigator.pop(dialogContext, MatchGameMode.electricChair),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('Anulează', 'Cancel'))),
        ],
      ),
    );
  }

  /// La Join Online nu se alege nimic: miza e fixă ([publicMatchStake]) și e
  /// cea mai mică din joc, fiindcă aici nu există gazdă care să decidă. Se
  /// întoarce integral dacă ieși din coadă fără să fii cuplat cu nimeni — vezi
  /// MatchmakingScreen._leave.
  Future<void> _joinOnline() async {
    if (_busy) return;
    try {
      await MultiplayerService.instance.ensureInitialized();
      if (!mounted) return;
      final ok = await confirmMatchStake(
        context,
        stake: publicMatchStake,
        title: 'Join Online',
        subtitle: tr(
            'Te cuplăm cu un adversar real, unu la unu. Miza e mereu '
                'aceeași aici — nu ai ce alege.',
            'We match you with a real opponent, one on one. The stake is always '
                'the same here — there is nothing to pick.'),
      );
      if (!ok || !mounted) return;
      final spent = await StorageService.spendCoins(publicMatchStake);
      if (!spent || !mounted) return;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => const MatchmakingScreen()));
    } catch (e) {
      _showUnavailable(e);
    }
  }

  Future<void> _joinWithCode() async {
    if (_busy) return;
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF141B36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: Colors.white.withAlpha(30)),
        ),
        title: Text(tr('Cod cameră', 'Room code'),
            style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          maxLength: 5,
          autofocus: true,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, letterSpacing: 6, fontSize: 22, fontWeight: FontWeight.w900),
          decoration: InputDecoration(
            hintText: '7K4PX',
            hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 6),
            counterStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withAlpha(15),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withAlpha(30))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withAlpha(30))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.orange)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('Anulează', 'Cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orange,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(tr('Intră', 'Join'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    setState(() => _busy = true);
    // Camera se caută ÎNAINTE de orice plată: miza n-o mai alege cel care
    // intră, deci trebuie s-o citim de pe cameră ca să i-o putem arăta.
    final MatchInfo room;
    try {
      room = await MultiplayerService.instance.lookupRoomByCode(code);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _showUnavailable(e);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final roomTitle = tr('Camera lui ${room.hostName ?? '?'}', '${room.hostName ?? '?'}\'s room');
    // Quizz Tanks nu are miză deloc, deci nici dialog de miză — vezi
    // confirmTanksRoom pentru de ce nu merge cel obișnuit cu 0.
    final bool ok;
    if (room.gameMode == MatchGameMode.quizzTanks) {
      ok = await confirmTanksRoom(context, title: roomTitle);
    } else {
      ok = await confirmMatchStake(
        context,
        stake: room.stake,
        title: roomTitle,
        subtitle: tr(
            'Miza e stabilită de cine a făcut camera. Cu cât intră mai '
                'mulți, cu atât premiile cresc.',
            'The stake is set by whoever created the room. The more players join, '
                'the bigger the prizes.'),
      );
    }
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final spent = await StorageService.spendCoins(room.stake);
    if (!spent) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      // identitate proaspătă — vezi comentariul din [_createRoom].
      final identity = await AuthService.instance.multiplayerIdentity();
      final info = await MultiplayerService.instance.joinRoomByCode(
        code: code,
        displayName: identity.name,
        photoUrl: identity.photoUrl,
        avatarStyle: identity.avatarStyle,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RoomLobbyScreen(matchId: info.id, isHost: false, stakePaid: info.stake)),
      );
    } catch (e) {
      // nu am reusit sa intram cu adevarat - miza nu a "cumparat" nimic.
      await StorageService.addCoins(room.stake);
      _showUnavailable(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Poarta de ban: cat timp `amIBanned` e adevarat, in locul continutului de
    // multiplayer se arata mesajul. Notifier-ul e alimentat de abonamentul din
    // PlayerProfileService, deci ridicarea unui ban ajunge instant — daca
    // jucatorul e deblocat cat sta pe ecran, ecranul se deschide singur.
    return ValueListenableBuilder<bool>(
      valueListenable: PlayerProfileService.instance.amIBanned,
      builder: (context, banned, _) {
        if (banned) return _buildBannedScreen(context);
        return _buildMultiplayerScreen(context);
      },
    );
  }

  Widget _buildBannedScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 0, 0),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.block_rounded, color: Colors.white54, size: 72),
                        const SizedBox(height: 20),
                        Text(
                          bannedFromOnlineMessage(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMultiplayerScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SpaceBackground(
        child: SafeArea(
          child: Column(
            children: [
              EntranceItem(
                controller: _introCtrl,
                interval: const Interval(0.0, 0.45, curve: Curves.easeOut),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                      ),
                      const SizedBox(width: 2),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.white, AppColors.purple],
                        ).createShader(bounds),
                        child: const Text(
                          'MULTIPLAYER',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.4),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => MultiplayerInfoDialog.show(context),
                        icon: const Icon(Icons.info_outline_rounded, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        EntranceItem(
                          controller: _introCtrl,
                          interval: const Interval(0.05, 0.55, curve: Curves.easeOutBack),
                          child: SizedBox(
                            width: 168,
                            height: 168,
                            child: AnimatedBuilder(
                              animation: Listenable.merge([_pulseCtrl, _ringCtrl]),
                              builder: (context, child) {
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Transform.rotate(
                                      angle: _ringCtrl.value * 6.28318,
                                      child: CustomPaint(
                                        size: const Size(168, 168),
                                        painter: _PortalRingPainter(color: AppColors.blue, dashCount: 22, gapFraction: 0.55),
                                      ),
                                    ),
                                    Transform.rotate(
                                      angle: -_ringCtrl.value * 6.28318 * 0.7,
                                      child: CustomPaint(
                                        size: const Size(140, 140),
                                        painter: _PortalRingPainter(color: AppColors.purple, dashCount: 16, gapFraction: 0.5),
                                      ),
                                    ),
                                    Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.purple.withAlpha(100 + (_pulseCtrl.value * 60).round()),
                                            blurRadius: 20 + _pulseCtrl.value * 16,
                                            spreadRadius: 1 + _pulseCtrl.value * 3,
                                          ),
                                        ],
                                      ),
                                      // MyAvatar, nu Avatar(photoUrl:) — ține cont și de
                                      // avatarul desenat ales din Profil, și se
                                      // împrospătează singur când îl schimbi
                                      child: child,
                                    ),
                                  ],
                                );
                              },
                              child: const MyAvatar(size: 96),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        EntranceItem(
                          controller: _introCtrl,
                          interval: const Interval(0.15, 0.6, curve: Curves.easeOut),
                          child: GestureDetector(
                            onTap: _editName,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(18),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.white.withAlpha(40)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_displayName.isEmpty ? '...' : _displayName,
                                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.edit_rounded, color: Colors.white54, size: 15),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (_offlineReason != null) _buildOfflineBanner(),
                        EntranceItem(
                          controller: _introCtrl,
                          interval: const Interval(0.3, 0.8, curve: Curves.easeOutBack),
                          slideFrom: -1,
                          child: _ActionTile(
                            icon: Icons.meeting_room_rounded,
                            title: tr('CAMERĂ NOUĂ', 'CREATE ROOM'),
                            subtitle: tr('Tu alegi modul, tu ești gazda', 'You pick the mode, you host'),
                            color: AppColors.blue,
                            onTap: _createRoom,
                            disabled: _offlineReason != null,
                          ),
                        ),
                        const SizedBox(height: 14),
                        EntranceItem(
                          controller: _introCtrl,
                          interval: const Interval(0.42, 0.9, curve: Curves.easeOutBack),
                          slideFrom: 1,
                          // Numărul de jucători deja în căutare, live — ca
                          // nimeni să nu fie cuplat "din senin": dacă vezi
                          // aici că mai e cineva în coadă, știi dinainte că
                          // meci rapid o să vă cupleze în câteva secunde.
                          child: StreamBuilder<int>(
                            stream: MultiplayerService.instance.watchQueueCount(),
                            builder: (context, snap) {
                              final searching = snap.data ?? 0;
                              return _ActionTile(
                                icon: Icons.public_rounded,
                                title: tr('MECI RAPID', 'JOIN ONLINE'),
                                subtitle: searching > 0
                                    ? tr('🔎 $searching caută acum un meci', '🔎 $searching searching right now')
                                    : tr('Te cuplăm cu un adversar real', 'Matched with a real opponent'),
                                color: AppColors.play,
                                onTap: _joinOnline,
                                disabled: _offlineReason != null,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        EntranceItem(
                          controller: _introCtrl,
                          interval: const Interval(0.54, 1.0, curve: Curves.easeOutBack),
                          slideFrom: -1,
                          child: _ActionTile(
                            icon: Icons.keyboard_rounded,
                            title: tr('COD CAMERĂ', 'JOIN WITH CODE'),
                            subtitle: tr('Intri în camera unui prieten', 'Enter a friend\'s room'),
                            color: AppColors.orange,
                            onTap: _joinWithCode,
                            disabled: _offlineReason != null,
                          ),
                        ),
                        if (_busy) ...[
                          const SizedBox(height: 20),
                          const CircularProgressIndicator(color: AppColors.blue),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placă mare, cu colțuri teșite (stil HUD sci-fi), pentru cele 3 acțiuni de
/// pe ecranul Multiplayer — icon în pătrat cu gradient, titlu + subtitlu,
/// săgeată la final, și un mic „strângere" la apăsare (feedback tactil
/// vizual), nu doar culoare care se schimbă.
class _ActionTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  /// Fără internet, cele trei acțiuni nu pot face nimic — vezi
  /// `_MultiplayerScreenState._checkConnection`. Rămân vizibile (ca userul
  /// să vadă ce l-ar aștepta), dar stinse și fără efect la apăsare.
  final bool disabled;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.disabled = false,
  });

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _pressed = false;

  static Color _lighten(Color c, double dl) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + dl).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    if (widget.disabled) {
      return Opacity(
        opacity: 0.4,
        child: IgnorePointer(child: _buildTile(color)),
      );
    }
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: _buildTile(color),
      ),
    );
  }

  Widget _buildTile(Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: ShapeDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_lighten(color, 0.04), color, _lighten(color, -0.14)],
        ),
        shape: BeveledRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _lighten(color, 0.25).withAlpha(160), width: 1.2),
        ),
        shadows: [
          BoxShadow(color: color.withAlpha(120), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_lighten(color, 0.3), _lighten(color, 0.05)],
              ),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withAlpha(70)),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Colors.white.withAlpha(200), size: 26),
        ],
      ),
    );
  }
}

/// Inel punctat rotativ folosit ca decor „de portal" în jurul avatarului —
/// două instanțe suprapuse (raze și viteze diferite) dau senzația unui
/// scanner activ, viu, nu doar un cerc static.
class _PortalRingPainter extends CustomPainter {
  final Color color;
  final int dashCount;
  final double gapFraction;

  const _PortalRingPainter({required this.color, required this.dashCount, required this.gapFraction});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = color.withAlpha(160)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final sweepPerDash = (360 / dashCount) * (1 - gapFraction) * 3.14159265 / 180;
    final sweepPerGap = (360 / dashCount) * gapFraction * 3.14159265 / 180;
    var angle = 0.0;
    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), angle, sweepPerDash, false, paint);
      angle += sweepPerDash + sweepPerGap;
    }
  }

  @override
  bool shouldRepaint(covariant _PortalRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dashCount != dashCount || oldDelegate.gapFraction != gapFraction;
}

/// O opțiune din dialogul de alegere a modului de joc — buton lat cu
/// icon+titlu+subtitlu, colorat pe tema modului (albastru pentru Clasic,
/// roșu pentru Higher & Lower).
class _GameModeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _GameModeOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  static Color _lighten(Color c, double dl) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + dl).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withAlpha(55), color.withAlpha(20)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withAlpha(150)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_lighten(color, 0.25), color],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withAlpha(70)),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
