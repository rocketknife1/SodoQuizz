import 'package:flutter/material.dart';
import '../../core/reward_collector.dart';
import '../../core/theme.dart';
import '../../data/multiplayer_service.dart';
import '../../data/player_profile_service.dart';
import '../../data/storage_service.dart';
import '../../models/multiplayer_models.dart';
import '../../widgets/avatar.dart';
import '../home_screen.dart';
import '../loading_screen.dart';

/// Clasamentul final al jucătorilor reali dintr-un meci — stil consecvent
/// cu `leaderboard_screen.dart` (rânduri rang+avatar+nume+scor).
class MultiplayerResultsScreen extends StatefulWidget {
  final String matchId;
  final MatchGameMode gameMode;
  const MultiplayerResultsScreen({super.key, required this.matchId, this.gameMode = MatchGameMode.classic});

  @override
  State<MultiplayerResultsScreen> createState() => _MultiplayerResultsScreenState();
}

class _MultiplayerResultsScreenState extends State<MultiplayerResultsScreen> {
  late final Future<List<MatchPlayer>> _future = _load();
  int _coinsEarned = 0;
  int _xpEarned = 0;

  /// Bonusul "Prima victorie a zilei" — vezi StorageService.canClaimFirstWinOfDay.
  /// Suma efectivă (monede/XP) e adăugată de collectRewards chiar când
  /// pornește animația (vezi _maybePlayFirstWinAnimation), nu aici — la fel
  /// ca la orice alt apel collectRewards din aplicație (quests_screen.dart
  /// etc.), ca reîmprospătarea balanței să fie sincronă cu animația.
  static const _firstWinBonusCoins = 50;
  static const _firstWinBonusXp = 100;
  bool _firstWinBonus = false;
  bool _firstWinAnimationFired = false;
  final _coinBadgeKey = GlobalKey();
  final _xpBadgeKey = GlobalKey();

  /// Multiplayer înainte nu acorda NICIO recompensă economică — un meci
  /// real, cu adversar live și fără reluări, merită o primă peste modul
  /// solo fără risc (1,25× la coins/XP din scor) plus un bonus fix de
  /// victorie/participare, ca să existe mereu un motiv economic să joci
  /// contra altcuiva, nu doar contra listei de întrebări. Vezi reproiectarea
  /// economiei — comparația dintre gamemoduri.
  Future<List<MatchPlayer>> _load() async {
    final players = await MultiplayerService.instance.watchPlayers(widget.matchId).first;
    final sorted = List.of(players)..sort((a, b) => b.score.compareTo(a.score));
    final me = MultiplayerService.instance.currentPlayerId;
    final myIndex = sorted.indexWhere((p) => p.id == me);
    if (myIndex != -1) {
      final myScore = sorted[myIndex].score;
      // egalitate pentru locul 1 (mai mulți cu același scor maxim) numără
      // ca remiză, nu ca victorie NICI ca înfrângere, pentru statisticile
      // de profil (vezi PlayerProfileService.recordMatchResult) — restul
      // logicii economice de mai jos rămâne neschimbată.
      final draw = myIndex == 0 && sorted.length >= 2 && sorted[1].score == myScore;
      final won = myIndex == 0 && !draw;
      _coinsEarned = myScore ~/ 8 + (won ? 60 : 15);
      _xpEarned = (myScore * 1.1).round() + (won ? 120 : 30);
      await StorageService.addCoins(_coinsEarned);
      await StorageService.addXp(_xpEarned);
      if (won && await StorageService.canClaimFirstWinOfDay()) {
        await StorageService.claimFirstWinOfDay();
        _firstWinBonus = true;
      }
      await PlayerProfileService.instance.recordMatchResult(
        gameModeId: widget.gameMode.name,
        won: won,
        draw: draw,
      );
    }
    await MultiplayerService.instance.leaveMatch(widget.matchId);
    return sorted;
  }

  /// Pornește animația abia după ce pastilele de mai jos (targetKey-urile)
  /// chiar există în arbore — la fel ca la fluxul de reclamă recompensată
  /// din game_screen.dart, care așteaptă explicit endOfFrame înainte de
  /// collectRewards, altfel targetKey.currentContext e încă null și
  /// animația cade pe fallback-ul din dreapta-sus.
  Future<void> _maybePlayFirstWinAnimation() async {
    if (_firstWinAnimationFired || !_firstWinBonus) return;
    _firstWinAnimationFired = true;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await collectRewards(
      context,
      coins: _firstWinBonusCoins,
      xp: _firstWinBonusXp,
      lives: 0,
      coinBadgeKey: _coinBadgeKey,
      xpBadgeKey: _xpBadgeKey,
      livesBadgeKey: GlobalKey(),
    );
  }

  Widget _bonusBadge(GlobalKey key, IconData icon, Color color) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.white.withAlpha(15), shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
      child: Icon(icon, color: color, size: 16),
    );
  }

  void _goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoadingScreen(nextBuilder: (_) => const HomeScreen(), duration: const Duration(milliseconds: 900))),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goHome();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: FutureBuilder<List<MatchPlayer>>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppColors.blue));
              }
              if (_firstWinBonus) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _maybePlayFirstWinAnimation());
              }
              final me = MultiplayerService.instance.currentPlayerId;
              final players = snap.data!;
              return Column(
                children: [
                  const SizedBox(height: 20),
                  const Icon(Icons.emoji_events_rounded, color: AppColors.coin, size: 56),
                  const SizedBox(height: 8),
                  const Text('Clasament final', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  if (_coinsEarned > 0 || _xpEarned > 0) ...[
                    const SizedBox(height: 6),
                    Text('+$_coinsEarned monede  •  +$_xpEarned XP', style: const TextStyle(color: AppColors.coin, fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                  if (_firstWinBonus) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.coin.withAlpha(30),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.coin.withAlpha(120)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🎁 Prima victorie a zilei', style: TextStyle(color: AppColors.coin, fontWeight: FontWeight.w800, fontSize: 12)),
                          const SizedBox(width: 10),
                          _bonusBadge(_coinBadgeKey, Icons.monetization_on_rounded, AppColors.coin),
                          const SizedBox(width: 6),
                          _bonusBadge(_xpBadgeKey, Icons.star_rounded, AppColors.purple),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: players.length,
                      itemBuilder: (context, i) {
                        final p = players[i];
                        final isMe = p.id == me;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isMe ? AppColors.blue.withAlpha(40) : Colors.white.withAlpha(12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isMe ? AppColors.blue : Colors.white24),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 28,
                                child: Text('#${i + 1}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
                              ),
                              Avatar(size: 40, label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?', accentColor: pickAvatarColor(p.avatarSeed), photoUrl: p.photoUrl),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                              ),
                              if (widget.gameMode == MatchGameMode.higherLower) ...[
                                if (p.eliminated)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: Text('ELIMINAT', style: TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.w800)),
                                  )
                                else if (p.breads > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Text('🍞' * p.breads.clamp(0, 5), style: const TextStyle(fontSize: 12)),
                                  ),
                              ],
                              Text('${p.score} pct', style: const TextStyle(color: AppColors.coin, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _goHome,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.purple, padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: const Text('Acasă', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
