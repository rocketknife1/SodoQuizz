import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/betting.dart';
import '../../core/progression.dart';
import '../../core/quest_bump.dart';
import '../../core/reward_collector.dart';
import '../../core/lang.dart';
import '../../core/theme.dart';
import '../../data/multiplayer_activity_service.dart';
import '../../data/multiplayer_service.dart';
import '../../data/player_profile_service.dart';
import '../../data/storage_service.dart';
import '../../models/multiplayer_activity.dart';
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
  bool _firstWinBonus = false;
  bool _firstWinAnimationFired = false;
  final _coinBadgeKey = GlobalKey();
  final _xpBadgeKey = GlobalKey();

  /// Miza pusă de jucătorul curent și locul pe care a ieșit — folosite în
  /// antetul ecranului, ca rezultatul să fie explicit ("ai pus X, ai luat Y"),
  /// nu doar "ai primit X monede".
  int _myBet = 0;
  int _myPlace = 0;
  int _pot = 0;

  /// Monedele nu vin "din partea casei": la final se împarte grămada de mize
  /// (vezi core/betting.dart) între locurile din jumătatea de sus a
  /// clasamentului. XP-ul rămâne o recompensă normală, acordată de joc.
  ///
  /// Fiecare client calculează ACELEAȘI plăți din aceleași date publice
  /// (mizele și scorurile tuturor, din Firestore) și își creditează doar
  /// propriul cont — la fel ca la scor, nu există autoritate de server.
  Future<List<MatchPlayer>> _load() async {
    final players = await _awaitFinalScores();
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

      final stake = _tableStake(sorted);
      final prizes = matchPrizesForRanking(
        stake: stake,
        sortedScores: [for (final p in sorted) p.score],
      );
      _myBet = stake;
      _myPlace = myIndex + 1;
      _pot = matchPot(stake: stake, players: sorted.length);
      _coinsEarned = prizes[myIndex];
      _xpEarned = multiplayerXpForScore(myScore, won: won);
      await StorageService.addCoins(_coinsEarned);
      await StorageService.addXp(_xpEarned);
      if (_myBet > 0 && mounted) {
        await bumpQuestMetric(context, 'mp_bet_played', 1);
      }
      // O remiză pe locul 1 NU e victorie (aceeași convenție ca la
      // statisticile de profil de mai jos), altfel două conturi care termină
      // la egalitate ar bifa amândouă quest-ul de victorii la fiecare meci.
      if (won && mounted) {
        await bumpQuestMetric(context, 'mp_win', 1);
      }
      if (won && await StorageService.canClaimFirstWinOfDay()) {
        await StorageService.claimFirstWinOfDay();
        _firstWinBonus = true;
      }
      await PlayerProfileService.instance.recordMatchResult(
        gameModeId: widget.gameMode.name,
        won: won,
        draw: draw,
      );
      // sorted.length = câți jucători reali au ajuns până la finalul acestui
      // meci — vezi PlayerProfileService.recordCompletedMatch (no-op sub 2).
      await PlayerProfileService.instance.recordCompletedMatch(
        matchId: widget.matchId,
        gameModeId: widget.gameMode.name,
        playerCount: sorted.length,
      );
      // Tabloul complet al mesei, pentru tab-ul Camere din AdminScreen — se
      // șterge singur după roomActivityRetention. Aici e singurul loc din
      // aplicație unde se știu simultan mizele puse și plățile calculate.
      await MultiplayerActivityService.instance.recordRoom(
        matchId: widget.matchId,
        gameModeId: widget.gameMode.name,
        pool: _pot,
        stake: stake,
        players: [
          for (var i = 0; i < sorted.length; i++)
            RoomActivityPlayer(
              uid: sorted[i].id,
              name: sorted[i].name,
              place: i + 1,
              score: sorted[i].score,
              entry: stake,
              exit: prizes[i],
            ),
        ],
      );
      // Curăță camerele expirate scrise de telefonul ăsta la meciurile
      // anterioare (ștergere țintită, fără listare — vezi serviciul).
      await MultiplayerActivityService.instance.sweepMine();
    }
    await MultiplayerService.instance.leaveMatch(widget.matchId);
    return sorted;
  }

  /// Cât așteptăm ca toată lumea de la masă să-și scrie scorul final înainte
  /// să împărțim pool-ul. Necesar de când modul Clasic e o cursă cronometrată:
  /// toți termină în aceeași secundă, iar cine ajunge primul aici ar citi
  /// altfel scoruri încă nescrise ale celorlalți și ar calcula alte plăți
  /// decât ei. Peste termen mergem mai departe cu ce există — un jucător
  /// căruia i-a picat rețeaua nu are voie să blocheze decontarea celorlalți.
  static const _finalScoreWait = Duration(seconds: 12);

  Future<List<MatchPlayer>> _awaitFinalScores() async {
    final stream = MultiplayerService.instance.watchPlayers(widget.matchId);
    // Higher or Lower nu are "scor final scris la fluier": acolo meciul se
    // încheie prin eliminare, iar scorurile sunt deja definitive în Firestore.
    if (widget.gameMode != MatchGameMode.classic) return stream.first;
    try {
      return await stream
          .firstWhere((players) => players.isNotEmpty && players.every((p) => p.finished))
          .timeout(_finalScoreWait);
    } on TimeoutException {
      debugPrint('MultiplayerResultsScreen: cineva nu si-a scris scorul final, decontez cu ce am.');
      return stream.first;
    }
  }

  /// Miza mesei. Toți jucătorii au plătit exact aceeași sumă (e miza camerei,
  /// vezi core/betting.dart), deci în mod normal orice `bet` de la masă e
  /// răspunsul. Luăm totuși maximul, ca o singură fișă de jucător rămasă fără
  /// câmpul `bet` — scrisă de un client mai vechi — să nu tragă toată masa la
  /// zero și să anuleze premiile tuturor.
  int _tableStake(List<MatchPlayer> players) =>
      players.fold<int>(0, (best, p) => p.bet > best ? p.bet : best);

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
      coins: multiplayerFirstWinBonusCoins,
      xp: multiplayerFirstWinBonusXp,
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

  /// "Ai pus X, ai luat Y — deci ești pe plus/minus cu Z." Textul compară cu
  /// miza, nu cu zero: 300 de monede primite după o miză de 500 nu e un
  /// câștig, oricât ar arăta plusul de deasupra a bine.
  String _betSummary() {
    final delta = _coinsEarned - _myBet;
    final sign = delta >= 0 ? '+' : '';
    return 'Ai pus 💰$_myBet, ai luat 💰$_coinsEarned  →  $sign$delta';
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
                  if (_myBet > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      _betSummary(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: _coinsEarned >= _myBet ? AppColors.play : AppColors.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        tr('Locul $_myPlace din ${players.length}  •  pe masă erau 💰$_pot',
                            'Place $_myPlace of ${players.length}  •  💰$_pot was on the table'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                      ),
                    ),
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
                              Avatar(size: 40, label: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?', accentColor: pickAvatarColor(p.avatarSeed), photoUrl: p.photoUrl, style: avatarStyleFromId(p.avatarStyle)),
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
                        child: Text(tr('Acasă', 'Home'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
