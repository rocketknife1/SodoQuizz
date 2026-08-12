import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/betting.dart';
import '../../core/lang.dart';
import '../../core/theme.dart';
import '../../data/auth_service.dart';
import '../../data/multiplayer_service.dart';
import '../../data/storage_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/avatar.dart';
import '../../widgets/match_stake_dialog.dart';
import '../../widgets/network_scan_animation.dart';
import 'multiplayer_match_screen.dart';
import 'room_lobby_screen.dart';

/// Matchmaking public: te bagă în coada de așteptare și încearcă periodic să
/// te cupleze cu un adversar real (1 vs 1) — fără completare cu jucători
/// ficțivi, se așteaptă cât e nevoie până apare cineva real în coadă. Vezi
/// [MultiplayerService.attemptFormMatch].
///
/// Miza e fixă aici ([publicMatchStake]) și a fost deja plătită la intrarea în
/// ecran — se returnează integral dacă pleci din coadă fără să fii cuplat cu
/// nimeni.
class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;
  Timer? _formTimer;
  StreamSubscription<String?>? _queueSub;
  bool _matched = false;
  bool _left = false;
  bool _joiningRoom = false;
  ({String name, String? photoUrl, String avatarStyle})? _identity;

  /// Cât am plătit deja. Pornește de la [publicMatchStake] (plătit înainte de
  /// a ajunge aici), dar se poate schimba dacă alegem din listă o cameră cu
  /// altă miză — vezi [_joinRoom], unde se plătește doar DIFERENȚA.
  int _stakePaid = publicMatchStake;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _start();
  }

  Future<void> _start() async {
    final identity = await AuthService.instance.multiplayerIdentity();
    _identity = identity;
    await MultiplayerService.instance.joinMatchmakingQueue(
      displayName: identity.name,
      photoUrl: identity.photoUrl,
      avatarStyle: identity.avatarStyle,
    );
    if (!mounted) return;

    _queueSub = MultiplayerService.instance.watchOwnQueueEntry().listen((matchId) {
      if (matchId != null) _onMatched(matchId);
    });

    _formTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      MultiplayerService.instance.attemptFormMatch();
    });
  }

  void _onMatched(String matchId) {
    if (_matched) return;
    _matched = true;
    _formTimer?.cancel();
    _queueSub?.cancel();
    // intrarea din coadă nu mai are treabă odată ce am fost cuplați -
    // altfel ar rămâne orfană în matchmaking_queue la nesfârșit.
    MultiplayerService.instance.leaveQueue();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MultiplayerMatchScreen(matchId: matchId)),
    );
  }

  /// Alternativa la matchmaking-ul automat: userul alege direct o cameră
  /// deschisă din listă (vezi [MultiplayerService.watchOpenRooms]).
  ///
  /// Ieșim din coada de matchmaking ÎNAINTE de orice, inclusiv înainte de
  /// dialogul de confirmare: altfel puteam fi cuplați automat cu altcineva
  /// exact cât stă dialogul deschis, iar ecranul de meci ar fi înlocuit
  /// dialogul, nu ecranul ăsta. Dacă userul se răzgândește, [_resumeQueue] ne
  /// pune la loc în coadă.
  Future<void> _joinRoom(MatchInfo room) async {
    if (_matched || _left || _joiningRoom) return;
    setState(() => _joiningRoom = true);
    _formTimer?.cancel();
    await _queueSub?.cancel();
    try {
      await MultiplayerService.instance.leaveQueue();
    } catch (e) {
      debugPrint('MatchmakingScreen._joinRoom: leaveQueue a esuat: $e');
    }
    if (!mounted) return;

    // Camera are miza EI, aleasă de gazda ei, care poate fi alta decât cea
    // fixă de la Join Online. Nu se plătește a doua oară: se reglează doar
    // diferența față de cât e deja plătit pentru coadă.
    final ok = await confirmMatchStake(
      context,
      stake: room.stake,
      title: 'Camera lui ${room.hostName ?? '?'}',
      subtitle: tr(
          'Miza e stabilită de cine a făcut camera. Cu cât intră mai '
              'mulți, cu atât premiile cresc.',
          'The stake is set by whoever created the room. The more players join, '
              'the bigger the prizes.'),
      alreadyPaid: _stakePaid,
    );
    if (!mounted || _left) return;
    if (!ok) {
      await _resumeQueue();
      return;
    }
    final diff = room.stake - _stakePaid;
    if (diff > 0 && !await StorageService.spendCoins(diff)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nu ai destule monede pentru camera asta.')),
      );
      await _resumeQueue();
      return;
    }
    if (diff < 0) await StorageService.addCoins(-diff);
    _stakePaid = room.stake;

    try {
      final identity = _identity ?? await AuthService.instance.multiplayerIdentity();
      final info = await MultiplayerService.instance.joinRoomById(
        matchId: room.id,
        displayName: identity.name,
        photoUrl: identity.photoUrl,
        avatarStyle: identity.avatarStyle,
      );
      if (!mounted) return;
      _matched = true;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => RoomLobbyScreen(matchId: info.id, isHost: false, stakePaid: _stakePaid)),
      );
    } catch (e) {
      // nu am reusit sa intram in camera - userul se intoarce in coada de
      // matchmaking, cu miza reglata inapoi la cat costa ea.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is MultiplayerUnavailableException ? e.message : tr('Camera nu mai e disponibilă.', 'That room is no longer available.'))),
      );
      await _resumeQueue();
    }
  }

  /// Înapoi în coada publică după ce intrarea într-o cameră anume a picat sau
  /// a fost anulată. Matchmaking-ul automat trebuie să continue, altfel userul
  /// rămâne pe un ecran care nu-l mai cuplează cu nimeni, fără să știe.
  ///
  /// Reglează și miza: coada costă [publicMatchStake], cea mai mică din joc,
  /// deci dacă plătisem în plus pentru camera aleasă, diferența se dă înapoi.
  Future<void> _resumeQueue() async {
    if (_matched || _left) return;
    if (_stakePaid > publicMatchStake) {
      await StorageService.addCoins(_stakePaid - publicMatchStake);
      _stakePaid = publicMatchStake;
    }
    final identity = _identity ?? await AuthService.instance.multiplayerIdentity();
    try {
      await MultiplayerService.instance.joinMatchmakingQueue(
        displayName: identity.name,
        photoUrl: identity.photoUrl,
        avatarStyle: identity.avatarStyle,
      );
    } catch (e) {
      debugPrint('MatchmakingScreen._resumeQueue: joinMatchmakingQueue a esuat: $e');
    }
    if (!mounted || _matched || _left) return;
    setState(() => _joiningRoom = false);
    _queueSub = MultiplayerService.instance.watchOwnQueueEntry().listen((matchId) {
      if (matchId != null) _onMatched(matchId);
    });
    _formTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      MultiplayerService.instance.attemptFormMatch();
    });
  }

  Future<void> _leave() async {
    if (_left || _matched) return;
    _left = true;
    _formTimer?.cancel();
    await _queueSub?.cancel();
    try {
      await MultiplayerService.instance.leaveQueue();
    } catch (e) {
      debugPrint('MatchmakingScreen._leave: leaveQueue a esuat: $e');
    } finally {
      // n-a început niciun meci — miza se întoarce integral.
      if (_stakePaid > 0) {
        await StorageService.addCoins(_stakePaid);
      }
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _formTimer?.cancel();
    _queueSub?.cancel();
    _bounceController.dispose();
    if (!_matched && !_left) MultiplayerService.instance.leaveQueue();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
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
                      IconButton(onPressed: _leave, icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70)),
                      const SizedBox(width: 4),
                      const Text('Join Online', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const NetworkScanAnimation(size: 220),
                        const SizedBox(height: 12),
                        AnimatedBuilder(
                          animation: _bounceController,
                          builder: (context, child) {
                            final offsetY = -10 * Curves.easeInOut.transform(_bounceController.value);
                            return Transform.translate(offset: Offset(0, offsetY), child: child);
                          },
                          child: const Text(
                            'Waiting for players...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              shadows: [
                                Shadow(color: AppColors.blue, blurRadius: 22),
                                Shadow(color: AppColors.blue, blurRadius: 10),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr('Miza ta: 💰$_stakePaid  •  câștigătorul ia 💰${matchPrizes(stake: _stakePaid, players: 2).first}',
                              'Your stake: 💰$_stakePaid  •  the winner takes 💰${matchPrizes(stake: _stakePaid, players: 2).first}'),
                          style: const TextStyle(color: AppColors.coin, fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 16),
                        _buildOpenRooms(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Camere private aflate în lobby, deschise oricui — alternativă mică, sub
  /// animație, la a aștepta cuplarea automată sau la a primi un cod de la un
  /// prieten. Doar o bandă orizontală compactă, ca să nu domine ecranul.
  Widget _buildOpenRooms() {
    return StreamBuilder<List<MatchInfo>>(
      stream: MultiplayerService.instance.watchOpenRooms(),
      builder: (context, snap) {
        final rooms = snap.data ?? const <MatchInfo>[];
        if (rooms.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          // 64 ajungea exact pentru avatar+nume; pastila roșie "H&L" adaugă
          // un rând în plus deasupra avatarului, iar miza încă unul dedesubt.
          height: 96,
          width: 260,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: rooms.length,
            itemBuilder: (context, i) => _buildRoomChip(rooms[i]),
          ),
        );
      },
    );
  }

  Widget _buildRoomChip(MatchInfo room) {
    return Opacity(
      opacity: _joiningRoom ? 0.5 : 1,
      child: GestureDetector(
        onTap: _joiningRoom ? null : () => _joinRoom(room),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (room.gameMode == MatchGameMode.higherLower)
                Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(6)),
                  child: const Text('H&L', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                ),
              Avatar(
                size: 40,
                label: (room.hostName?.isNotEmpty ?? false) ? room.hostName![0].toUpperCase() : '?',
                accentColor: pickAvatarColor(room.hostId),
                photoUrl: room.hostPhotoUrl,
                style: avatarStyleFromId(room.hostAvatarStyle),
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 56,
                child: Text(
                  room.hostName?.isNotEmpty == true ? room.hostName! : '?',
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ),
              // Miza camerei, direct pe chip: de când n-o mai alege cel care
              // intră, e singurul lucru care diferențiază două camere din
              // listă și trebuie văzut ÎNAINTE de tap.
              Text('💰${room.stake}',
                  style: const TextStyle(color: AppColors.coin, fontSize: 10, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}
