import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/auth_service.dart';
import '../../data/multiplayer_service.dart';
import '../../data/storage_service.dart';
import '../../widgets/avatar.dart';
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

  /// Numele/poza sunt legate live de contul Google (dacă e logat) — nu se
  /// mai pot edita manual în acest caz, vezi [_editName].
  bool get _isGoogleLinked => _photoUrl != null;

  @override
  void initState() {
    super.initState();
    AuthService.instance.multiplayerIdentity().then((identity) {
      if (!mounted) return;
      setState(() {
        _displayName = identity.name;
        _photoUrl = identity.photoUrl;
      });
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
        title: const Text('Numele tău', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLength: 16,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(counterStyle: TextStyle(color: Colors.white54)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Anulează')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Salvează')),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    await StorageService.setDisplayName(result);
    if (mounted) setState(() => _displayName = result);
  }

  Future<void> _createRoom() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // identitate proaspătă, nu starea din câmp — dacă userul apasă chiar
      // la deschiderea ecranului, `_photoUrl`/`_displayName` pot fi încă
      // valorile inițiale goale (fetch-ul din initState nu a apucat să
      // răspundă), iar camera ar rămâne PERMANENT fără poza reală în
      // Firestore (scrisă o singură dată, la creare — vezi bug-ul cu poza
      // de Google lipsă la un jucător logat).
      final identity = await AuthService.instance.multiplayerIdentity();
      final info = await MultiplayerService.instance.createRoom(displayName: identity.name, photoUrl: identity.photoUrl);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => RoomLobbyScreen(matchId: info.id, isHost: true)));
    } catch (e) {
      _showUnavailable(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinOnline() async {
    if (_busy) return;
    try {
      await MultiplayerService.instance.ensureInitialized();
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const MatchmakingScreen()));
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
        title: const Text('Cod cameră', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          maxLength: 5,
          style: const TextStyle(color: Colors.white, letterSpacing: 3, fontSize: 18),
          decoration: const InputDecoration(hintText: '7K4PX', hintStyle: TextStyle(color: Colors.white24), counterStyle: TextStyle(color: Colors.white54)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Anulează')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Intră')),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      // identitate proaspătă — vezi comentariul din [_createRoom].
      final identity = await AuthService.instance.multiplayerIdentity();
      final info = await MultiplayerService.instance.joinRoomByCode(code: code, displayName: identity.name, photoUrl: identity.photoUrl);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => RoomLobbyScreen(matchId: info.id, isHost: false)));
    } catch (e) {
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
                        Avatar(size: 100, photoUrl: _photoUrl),
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
