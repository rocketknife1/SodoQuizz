import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../core/theme.dart';
import '../../data/multiplayer_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/avatar.dart';
import '../../widgets/space_background.dart';
import 'matchmaking_screen.dart';
import 'multiplayer_electric_chair_screen.dart';
import 'multiplayer_higher_lower_screen.dart';
import 'multiplayer_match_screen.dart';
import 'multiplayer_obby_screen.dart';
import 'multiplayer_tanks_screen.dart';

/// Pasul de confirmare dintre "Meci Rapid te-a cuplat cu cineva" și
/// începerea efectivă a jocului — înainte, matchmaking-ul arunca direct în
/// meci, fără avertisment; acum AMÂNDOI jucătorii trebuie să apese Accept,
/// altfel oferta (vezi [QuickMatchOffer]) se anulează și fiecare reintră
/// singur în căutare. Modul de joc (Clasic sau Higher & Lower — vezi
/// [MultiplayerService.attemptFormMatch] pentru de ce nu și Quizz Tanks) e
/// deja ales aleator când apare ecranul ăsta, ca jucătorul să știe la ce
/// spune "da".
class QuickMatchConfirmScreen extends StatefulWidget {
  final String offerId;
  const QuickMatchConfirmScreen({super.key, required this.offerId});

  @override
  State<QuickMatchConfirmScreen> createState() => _QuickMatchConfirmScreenState();
}

class _QuickMatchConfirmScreenState extends State<QuickMatchConfirmScreen> with SingleTickerProviderStateMixin {
  static const _secondsToDecide = 12;

  late final Stream<QuickMatchOffer?> _offerStream = MultiplayerService.instance.watchQuickMatchOffer(widget.offerId);
  late final AnimationController _pulseCtrl;
  Timer? _countdown;
  int _secondsLeft = _secondsToDecide;

  bool _accepted = false;
  bool _launching = false;
  bool _resolved = false; // navigat sau anulat deja - nu mai reacționăm de două ori

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) _timeout();
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _timeout() {
    if (_resolved) return;
    _resolved = true;
    _countdown?.cancel();
    MultiplayerService.instance.declineQuickMatchOffer(widget.offerId).catchError((_) {});
    _backToSearch(tr('Nu a răspuns nimeni la timp — caut din nou...', 'Nobody answered in time — searching again...'));
  }

  Future<void> _accept() async {
    if (_accepted) return;
    setState(() => _accepted = true);
    try {
      await MultiplayerService.instance.acceptQuickMatchOffer(widget.offerId);
    } catch (e) {
      debugPrint('QuickMatchConfirmScreen._accept: acceptQuickMatchOffer a esuat: $e');
    }
  }

  void _decline() {
    if (_resolved) return;
    _resolved = true;
    _countdown?.cancel();
    MultiplayerService.instance.declineQuickMatchOffer(widget.offerId).catchError((_) {});
    _backToSearch(null);
  }

  /// Oferta a picat (refuzată de mine, de celălalt, sau expirată la
  /// oricare din cele două capete) — un client nou de Meci Rapid reia
  /// căutarea de la zero; miza rămâne plătită, nu se schimbă nimic financiar
  /// aici, doar continuăm să căutăm.
  void _backToSearch(String? message) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MatchmakingScreen()),
    );
    if (message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      });
    }
  }

  /// Rulează pe clientul primului jucător intrat în coadă — pornește meciul
  /// real în clipa în care amândoi au acceptat oferta.
  void _maybeLaunch(QuickMatchOffer offer) {
    if (_launching || offer.status != 'pending') return;
    final iAmLauncher = offer.participants.isNotEmpty &&
        offer.participants.first.id == MultiplayerService.instance.currentPlayerId;
    if (!iAmLauncher) return;
    final allAccepted = offer.participants.every((p) => offer.acceptedIds.contains(p.id));
    if (!allAccepted) return;
    _launching = true;
    MultiplayerService.instance.launchQuickMatch(offer).catchError((e) {
      _launching = false;
      debugPrint('QuickMatchConfirmScreen: launchQuickMatch a esuat: $e');
      return '';
    });
  }

  void _maybeNavigate(QuickMatchOffer offer) {
    if (_resolved || offer.status != 'started' || offer.newMatchId == null) return;
    _resolved = true;
    _countdown?.cancel();
    final matchId = offer.newMatchId!;
    final gameMode = offer.gameMode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => switch (gameMode) {
            MatchGameMode.higherLower => MultiplayerHigherLowerScreen(matchId: matchId),
            MatchGameMode.quizzTanks => MultiplayerTanksScreen(matchId: matchId),
            // matchmaking public nu formează niciodată o ofertă Obby sau
            // Scaunul Electric (vezi MultiplayerService._quickMatchModes) -
            // cazuri moarte, dar switch-ul trebuie exhaustiv.
            MatchGameMode.obby => MultiplayerObbyScreen(matchId: matchId),
            MatchGameMode.electricChair => MultiplayerElectricChairScreen(matchId: matchId),
            MatchGameMode.classic => MultiplayerMatchScreen(matchId: matchId),
          },
        ),
      );
    });
  }

  void _maybeHandleCancelled(QuickMatchOffer offer) {
    if (_resolved || offer.status != 'cancelled') return;
    _resolved = true;
    _countdown?.cancel();
    final declinedByMe = offer.declinedBy == MultiplayerService.instance.currentPlayerId;
    _backToSearch(declinedByMe
        ? null
        : tr('Adversarul a refuzat — caut din nou...', 'The opponent declined — searching again...'));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _decline();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SpaceBackground(
          child: SafeArea(
            child: StreamBuilder<QuickMatchOffer?>(
              stream: _offerStream,
              builder: (context, snap) {
                final offer = snap.data;
                if (offer == null) {
                  // Prima emisie a stream-ului vine ÎNAINTE ca Firestore să
                  // răspundă (ConnectionState.waiting, data null). A o trata
                  // ca „oferta a dispărut" închidea ecranul din primul cadru,
                  // iar cei doi jucători intrau într-o buclă invizibilă:
                  // caută → se formează oferta → ecranul ăsta se închide
                  // singur → caută din nou, la nesfârșit, cu „2 în căutare"
                  // pe ecran și fără să se întâmple nimic.
                  if (snap.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: AppColors.blue));
                  }
                  // aici documentul chiar lipsește (rar) — tratăm ca un refuz
                  if (!_resolved) {
                    _resolved = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) => _backToSearch(null));
                  }
                  return Center(child: CircularProgressIndicator(color: AppColors.blue));
                }
                _maybeLaunch(offer);
                _maybeNavigate(offer);
                _maybeHandleCancelled(offer);

                final me = MultiplayerService.instance.currentPlayerId;
                final opponent = offer.participants.firstWhere(
                  (p) => p.id != me,
                  orElse: () => const RematchParticipant(id: '', name: '?', avatarSeed: ''),
                );
                final opponentAccepted = offer.acceptedIds.contains(opponent.id);

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                      child: Row(
                        children: [
                          Text(tr('Adversar găsit!', 'Opponent found!'),
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildVersusRow(opponent, opponentAccepted),
                            const SizedBox(height: 22),
                            _buildModeBadge(offer.gameMode),
                            const SizedBox(height: 26),
                            _buildCountdownRing(),
                            const SizedBox(height: 26),
                            if (!_accepted) ...[
                              _buildAcceptButton(),
                              const SizedBox(height: 10),
                              _buildSkipButton(),
                            ] else
                              Column(
                                children: [
                                  CircularProgressIndicator(color: AppColors.play),
                                  const SizedBox(height: 10),
                                  Text(
                                    opponentAccepted
                                        ? tr('Amândoi ați acceptat — pornim...', 'Both accepted — starting...')
                                        : tr('Ai acceptat — aștept adversarul...', 'You accepted — waiting for the opponent...'),
                                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVersusRow(RematchParticipant opponent, bool opponentAccepted) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const MyAvatar(size: 76),
        const SizedBox(width: 14),
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, child) => Transform.scale(scale: 1 + _pulseCtrl.value * 0.08, child: child),
          child: Text('VS', style: TextStyle(color: AppColors.orange, fontSize: 22, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 14),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Avatar(
              size: 76,
              label: opponent.name.isNotEmpty ? opponent.name[0].toUpperCase() : '?',
              accentColor: pickAvatarColor(opponent.avatarSeed),
              photoUrl: opponent.photoUrl,
              style: avatarStyleFromId(opponent.avatarStyle),
            ),
            if (opponentAccepted)
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: AppColors.play, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildModeBadge(MatchGameMode mode) {
    final label = mode == MatchGameMode.higherLower ? 'Higher & Lower' : tr('Clasic', 'Classic');
    final icon = mode == MatchGameMode.higherLower ? Icons.compare_arrows_rounded : Icons.quiz_rounded;
    final color = mode == MatchGameMode.higherLower ? AppColors.danger : AppColors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(150)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildCountdownRing() {
    final fraction = (_secondsLeft / _secondsToDecide).clamp(0.0, 1.0);
    final urgent = _secondsLeft <= 4;
    final color = urgent ? AppColors.danger : AppColors.play;
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              value: fraction,
              strokeWidth: 4,
              backgroundColor: Colors.white.withAlpha(25),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Text('$_secondsLeft', style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  /// „Sari peste" — același efect ca un refuz (oferta se anulează pentru
  /// amândoi și fiecare reintră singur în căutare), dar prezentat ca ce
  /// face de fapt jucătorul: trece peste adversarul ăsta și caută altul.
  /// Aceeași formă ca ACCEPT (placă teșită, glow), doar în portocaliu →
  /// mov, ca perechea de butoane să arate ca o pereche, nu ca un buton și
  /// un link.
  Widget _buildSkipButton() {
    return GestureDetector(
      onTap: _decline,
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          gradient: LinearGradient(colors: [AppColors.orange, AppColors.purple]),
          shape: BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withAlpha(120), width: 1.2),
          ),
          shadows: [BoxShadow(color: AppColors.purple.withAlpha(160), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.skip_next_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(tr('SARI PESTE', 'SKIP'),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Widget _buildAcceptButton() {
    return GestureDetector(
      onTap: _accept,
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          gradient: LinearGradient(colors: [Color(0xFF34E27A), AppColors.play]),
          shape: BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withAlpha(120), width: 1.2),
          ),
          shadows: [BoxShadow(color: AppColors.play, blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(tr('ACCEPT', 'ACCEPT'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
