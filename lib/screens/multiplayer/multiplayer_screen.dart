import 'package:flutter/material.dart';
import '../../core/betting.dart';
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
import '../../widgets/match_stake_dialog.dart';
import '../../widgets/multiplayer_info_dialog.dart';
import '../../widgets/solid_menu_button.dart';
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

class _MultiplayerScreenState extends State<MultiplayerScreen> {
  String _displayName = '';
  String? _photoUrl;
  bool _busy = false;

  /// Numele pus de administrator (vezi StorageService.getForcedName) — bate
  /// tot, inclusiv contul Google, deci blochează și el editarea de aici.
  bool _nameSetByAdmin = false;

  /// Numele/poza sunt legate live de contul Google (dacă e logat) — nu se
  /// mai pot edita manual în acest caz, vezi [_editName]. La fel și când
  /// numele a fost stabilit de administrator: dacă butonul ar rămâne activ,
  /// jucătorul ar scrie altceva, ar salva și n-ar vedea nicio schimbare.
  bool get _isGoogleLinked => _photoUrl != null || _nameSetByAdmin;

  @override
  void initState() {
    super.initState();
    StorageService.getForcedName().then((forced) {
      if (mounted && forced.isNotEmpty) setState(() => _nameSetByAdmin = true);
    });
    AuthService.instance.multiplayerIdentity().then((identity) {
      if (!mounted) return;
      setState(() {
        _displayName = identity.name;
        _photoUrl = identity.photoUrl;
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
  }

  void _showUnavailable(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error is MultiplayerUnavailableException ? error.message : 'Multiplayer indisponibil momentan.')),
    );
  }

  Future<void> _editName() async {
    if (_isGoogleLinked) return; // numele vine din contul Google, nu e editabil aici
    final controller = TextEditingController(text: _displayName);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: Text(tr('Numele tău', 'Your name'), style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLength: 16,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(counterStyle: TextStyle(color: Colors.white54)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('Anulează', 'Cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: Text(tr('Salvează', 'Save'))),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    await StorageService.setDisplayName(result);
    // fara asta, numele nou ar ramane doar local - leaderboard-ul/profilul
    // public ar afisa in continuare numele vechi pana la urmatoarea
    // pornire/revenire din fundal a aplicatiei (cand ruleaza heartbeat-ul
    // din main.dart). Vezi acelasi fix in profile_screen.dart._signIn.
    await PlayerProfileService.instance.ensureProfileHeartbeat();
    if (mounted) setState(() => _displayName = result);
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
      // la deschiderea ecranului, `_photoUrl`/`_displayName` pot fi încă
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
        backgroundColor: const Color(0xFF1a1a2e),
        title: Text(tr('Alege modul de joc', 'Pick the game mode'), style: const TextStyle(color: Colors.white)),
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
              subtitle: tr('4 tancuri, $tanksRoundSeconds secunde, fără miză',
                  '4 tanks, $tanksRoundSeconds seconds, no stake'),
              color: AppColors.orange,
              onTap: () => Navigator.pop(dialogContext, MatchGameMode.quizzTanks),
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
        backgroundColor: const Color(0xFF1a1a2e),
        title: Text(tr('Cod cameră', 'Room code'), style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          maxLength: 5,
          style: const TextStyle(color: Colors.white, letterSpacing: 3, fontSize: 18),
          decoration: const InputDecoration(hintText: '7K4PX', hintStyle: TextStyle(color: Colors.white24), counterStyle: TextStyle(color: Colors.white54)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('Anulează', 'Cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: Text(tr('Intră', 'Join'))),
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
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
                    const Text('Multiplayer', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => MultiplayerInfoDialog.show(context),
                      icon: const Icon(Icons.info_outline_rounded, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // MyAvatar, nu Avatar(photoUrl:) — ține cont și de
                        // avatarul desenat ales din Profil, și se
                        // împrospătează singur când îl schimbi
                        const MyAvatar(size: 100),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: _editName,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_displayName.isEmpty ? '...' : _displayName,
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                              if (!_isGoogleLinked) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.edit_rounded, color: Colors.white54, size: 16),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        SolidMenuButton(
                          icon: Icons.meeting_room_rounded,
                          label: 'CREATE ROOM',
                          color: AppColors.blue,
                          big: true,
                          onTap: _createRoom,
                        ),
                        const SizedBox(height: 12),
                        SolidMenuButton(
                          icon: Icons.public_rounded,
                          label: 'JOIN ONLINE',
                          color: AppColors.play,
                          big: true,
                          onTap: _joinOnline,
                        ),
                        const SizedBox(height: 12),
                        SolidMenuButton(
                          icon: Icons.keyboard_rounded,
                          label: 'JOIN WITH CODE',
                          color: AppColors.gray,
                          onTap: _joinWithCode,
                        ),
                        if (_busy) ...[
                          const SizedBox(height: 20),
                          const CircularProgressIndicator(color: AppColors.blue),
                        ],
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

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withAlpha(140)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
