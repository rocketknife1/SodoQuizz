import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/betting.dart';
import '../../core/electric_chair.dart';
import '../../core/obby.dart';
import '../../core/progression.dart';
import '../../core/quest_bump.dart';
import '../../core/reward_collector.dart';
import '../../core/lang.dart';
import '../../core/tanks.dart';
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
import 'multiplayer_electric_chair_screen.dart';
import 'multiplayer_higher_lower_screen.dart';
import 'multiplayer_match_screen.dart';
import 'multiplayer_obby_screen.dart';
import 'multiplayer_tanks_screen.dart';

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
  bool _rewardAnimationFired = false;
  final _coinBadgeKey = GlobalKey();
  final _xpBadgeKey = GlobalKey();

  /// Prada de la un meci de Quizz Tanks — modul fără miză, unde nu se
  /// împarte niciun pot, ci „fier vechi recuperat din epave", proporțional cu
  /// daunele făcute (vezi core/tanks.dart pentru de ce nu se ia din balanța
  /// celorlalți). Rămâne goală în toate celelalte moduri.
  TanksSalvage _salvage = const TanksSalvage();
  bool _salvageTopDamage = false;
  final _salvageCoinKey = GlobalKey();
  final _salvageHeartKey = GlobalKey();
  final _salvageHintKey = GlobalKey();
  final _salvageGemKey = GlobalKey();

  /// Miza pusă de jucătorul curent și locul pe care a ieșit — folosite în
  /// antetul ecranului, ca rezultatul să fie explicit ("ai pus X, ai luat Y"),
  /// nu doar "ai primit X monede".
  int _myBet = 0;
  int _myPlace = 0;
  int _pot = 0;

  /// Masa așa cum era ÎNAINTE ca [leaveMatch] să înceapă să o golească —
  /// captura de care are nevoie o cerere de revanșă (vezi [_requestRematch]),
  /// fiindcă `matches/{matchId}` poate fi șters până apuci să apeși butonul.
  List<MatchPlayer> _originalPlayers = const [];
  bool _amHost = false;
  late final Stream<RematchOffer?> _rematchStream =
      MultiplayerService.instance.watchRematchOffer(widget.matchId);
  bool _launchingRematch = false;
  bool _navigatedToRematch = false;

  /// Predă mai departe rădăcinii aplicației meciul tocmai părăsit, ca oferta
  /// de revanșă să fie ascultată și după ce ecranul ăsta dispare — vezi
  /// [MultiplayerService.lastFinishedMatchId] și main.dart. Fără asta, cine
  /// ieșea în meniu înainte ca gazda să apese „Cere revanșă" nu mai primea
  /// nimic, iar gazda aștepta un accept care n-avea de unde să vină.
  ///
  /// NU și când plecăm chiar în revanșă ([_navigatedToRematch]): acolo oferta
  /// veche e deja consumată, iar rădăcina n-are ce urmări în ea.
  @override
  void dispose() {
    MultiplayerService.instance.lastFinishedMatchId.value =
        _navigatedToRematch ? null : widget.matchId;
    super.dispose();
  }

  /// Monedele nu vin "din partea casei": la final se împarte grămada de mize
  /// (vezi core/betting.dart) între locurile din jumătatea de sus a
  /// clasamentului. XP-ul rămâne o recompensă normală, acordată de joc.
  ///
  /// Fiecare client calculează ACELEAȘI plăți din aceleași date publice
  /// (mizele și scorurile tuturor, din Firestore) și își creditează doar
  /// propriul cont — la fel ca la scor, nu există autoritate de server.
  /// Valoarea după care se sortează/departajează clasamentul — `score` brut
  /// pentru orice mod, CU EXCEPȚIA Scaunului Electric, unde `score` rămâne
  /// intenționat mic (bun pentru XP) și nu reflectă cine a rezistat mai mult
  /// (vezi core/electric_chair.dart `electricChairRankKey` pentru de ce nu
  /// se poate sorta direct după `score` acolo).
  int _rankValue(MatchPlayer p) => widget.gameMode == MatchGameMode.electricChair
      ? electricChairRankKey(eliminated: p.eliminated, eliminatedAtRound: p.eliminatedAtRound, score: p.score)
      : p.score;

  Future<List<MatchPlayer>> _load() async {
    final players = await _awaitFinalScores();
    final sorted = List.of(players)..sort((a, b) => _rankValue(b).compareTo(_rankValue(a)));
    final me = MultiplayerService.instance.currentPlayerId;
    final myIndex = sorted.indexWhere((p) => p.id == me);
    _originalPlayers = sorted;
    _amHost = myIndex != -1 && sorted[myIndex].isHost;
    if (myIndex != -1) {
      // `score` rămas mic, pentru XP; `myRank` e cifra folosită la
      // sortare/premii — la orice mod în afară de Scaunul Electric sunt
      // aceeași valoare.
      final myScore = sorted[myIndex].score;
      final myRank = _rankValue(sorted[myIndex]);
      // BUG REPARAT (2026-08-23): varianta veche verifica doar `myIndex == 0`
      // comparat cu `sorted[1]`, deci la o remiză pe primul loc între doi
      // jucători, doar cel de la indexul 0 din lista sortată primea
      // `draw=true` — celălalt (același scor, dar `myIndex == 1`) cădea pe
      // `won=false, draw=false`, adică era scris ca ÎNFRÂNGERE. Logica
      // corectă e în `matchOutcomeForScore` (core/betting.dart), testată
      // separat de sortare/index.
      final outcome = matchOutcomeForScore(myScore: myRank, allScores: [for (final p in sorted) _rankValue(p)]);
      final draw = outcome.draw;
      final won = outcome.won;

      final stake = _tableStake(sorted);
      final prizes = matchPrizesForRanking(
        stake: stake,
        sortedScores: [for (final p in sorted) _rankValue(p)],
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
      if (widget.gameMode == MatchGameMode.quizzTanks) {
        _computeSalvage(sorted, sorted[myIndex]);
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

  /// Cine ia prada de la un meci de Quizz Tanks. Criteriul e cel cerut de
  /// mod: DAUNELE făcute, nu locul din clasament — deși azi cele două
  /// coincid, fiindcă scorul unui meci de tancuri chiar E totalul daunelor.
  ///
  /// Egalitatea la vârf (mai mulți cu exact aceleași daune, cel mai des
  /// zero, într-un meci în care nimeni n-a nimerit nimic) NU se departajează
  /// artificial: primesc toți sau, la zero daune, nu primește nimeni — vezi
  /// [tanksSalvageFor], care nu dă nimic celui care n-a lovit și n-a
  /// supraviețuit.
  void _computeSalvage(List<MatchPlayer> table, MatchPlayer me) {
    final topDamage = table.fold<int>(0, (best, p) => p.damageDealt > best ? p.damageDealt : best);
    _salvageTopDamage = topDamage > 0 && me.damageDealt == topDamage;
    _salvage = tanksSalvageFor(
      damageDealt: me.damageDealt,
      isTopDamage: _salvageTopDamage,
      survived: !me.eliminated,
    );
  }

  /// Pornește animațiile de recompensă abia după ce pastilele de mai jos
  /// (targetKey-urile) chiar există în arbore — la fel ca la fluxul de
  /// reclamă recompensată din game_screen.dart, care așteaptă explicit
  /// endOfFrame înainte de collectRewards, altfel targetKey.currentContext e
  /// încă null și animația cade pe fallback-ul din dreapta-sus.
  ///
  /// Cele două recompense posibile (bonusul de primă victorie și prada de la
  /// Quizz Tanks) rulează UNA DUPĂ ALTA, în același `await`: pornite în
  /// paralel, cele două șiruri de monede ar zbura peste aceleași pastile în
  /// același timp și nu s-ar mai înțelege ce de unde vine.
  ///
  /// ATENȚIE: `collectRewards` e cel care SCRIE recompensa în balanță, deci
  /// sumele NU se adaugă și în [_load] — s-ar dubla.
  Future<void> _playRewardAnimations() async {
    if (_rewardAnimationFired) return;
    _rewardAnimationFired = true;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (_firstWinBonus) {
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
    if (!mounted || _salvage.isEmpty) return;
    await collectRewards(
      context,
      coins: _salvage.coins,
      xp: 0,
      lives: _salvage.hearts,
      coinBadgeKey: _salvageCoinKey,
      // xp: 0 — cheia nu e folosită, dar parametrul e obligatoriu.
      xpBadgeKey: GlobalKey(),
      livesBadgeKey: _salvageHeartKey,
      hints: _salvage.hints,
      hintsBadgeKey: _salvageHintKey,
      gems: _salvage.gems,
      gemsBadgeKey: _salvageGemKey,
    );
  }

  /// Prada de la Quizz Tanks. Pastilele au GlobalKey pentru că sunt ȚINTELE
  /// animației de colectare (vezi [_playRewardAnimations]) — fiecare monedă,
  /// inimă, hint sau gem zboară exact spre pastila lui.
  Widget _buildSalvagePanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.orange.withAlpha(28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.orange.withAlpha(130)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _salvageTopDamage
                ? tr('🔧 PRADĂ DIN EPAVE • cele mai multe daune', '🔧 SALVAGE • most damage dealt')
                : tr('🔧 PRADĂ DIN EPAVE', '🔧 SALVAGE'),
            style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _salvageItem(_salvageCoinKey, Icons.monetization_on_rounded, AppColors.coin, _salvage.coins),
              _salvageItem(_salvageHeartKey, Icons.favorite_rounded, AppColors.life, _salvage.hearts),
              _salvageItem(_salvageHintKey, Icons.tips_and_updates_rounded, AppColors.hint, _salvage.hints),
              _salvageItem(_salvageGemKey, Icons.diamond_rounded, AppColors.gem, _salvage.gems),
            ],
          ),
          if (_salvageTopDamage && _salvage.gems == 0) ...[
            const SizedBox(height: 6),
            Text(
              tr('Gems n-au ieșit de data asta — sunt rare chiar și pentru primul.',
                  'No gems this time — they are rare even for the top gunner.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 10.5),
            ),
          ],
        ],
      ),
    );
  }

  /// Pastilele cu 0 rămân vizibile, doar stinse: golul e informație („n-am
  /// luat inimi"), iar dacă ar dispărea, rândul ar sări de la un meci la
  /// altul și n-ai mai ști ce se putea câștiga.
  Widget _salvageItem(GlobalKey key, IconData icon, Color color, int amount) {
    final has = amount > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Opacity(
        opacity: has ? 1 : 0.32,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: key,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: color.withAlpha(has ? 40 : 16),
                shape: BoxShape.circle,
                border: Border.all(color: has ? color.withAlpha(150) : Colors.white24),
              ),
              child: Icon(icon, color: color, size: 15),
            ),
            const SizedBox(width: 4),
            Text('$amount', style: TextStyle(color: has ? Colors.white : Colors.white54, fontWeight: FontWeight.w900, fontSize: 13)),
          ],
        ),
      ),
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
    // Cea mai bună încercare, nu blocantă: dacă plecăm chiar noi (gazda) cu o
    // cerere încă în așteptare, o anulăm, ca ceilalți să nu rămână agățați de
    // un banner care n-o să mai pornească niciodată nimic (fără gazdă în
    // ecran, nimeni nu mai apelează launchRematch).
    if (_amHost) {
      MultiplayerService.instance.cancelRematchOffer(widget.matchId).catchError((_) {});
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoadingScreen(nextBuilder: (_) => const HomeScreen(), duration: const Duration(milliseconds: 900))),
      (route) => false,
    );
  }

  Future<void> _requestRematch() async {
    await MultiplayerService.instance.offerRematch(
      matchId: widget.matchId,
      gameMode: widget.gameMode,
      stake: _tableStake(_originalPlayers),
      participants: [
        for (final p in _originalPlayers)
          RematchParticipant(id: p.id, name: p.name, avatarSeed: p.avatarSeed, photoUrl: p.photoUrl, avatarStyle: p.avatarStyle),
      ],
    );
  }

  /// Rulează pe clientul gazdei la fiecare schimbare a ofertei — pornește
  /// camera nouă în clipa în care toți foștii participanți au acceptat.
  /// `_launchingRematch` oprește o a doua pornire dacă mai ajunge un
  /// eveniment din stream cât timp [launchRematch] e încă în zbor.
  void _maybeLaunchRematch(RematchOffer offer) {
    if (!_amHost || offer.status != 'pending' || _launchingRematch) return;
    final allAccepted = offer.participants.every((p) => offer.acceptedIds.contains(p.id));
    if (!allAccepted) return;
    _launchingRematch = true;
    MultiplayerService.instance.launchRematch(offer).catchError((e) {
      _launchingRematch = false;
      debugPrint('MultiplayerResultsScreen: launchRematch a esuat: $e');
      return '';
    });
  }

  void _maybeNavigateToRematch(RematchOffer offer) {
    if (_navigatedToRematch || offer.status != 'started' || offer.newMatchId == null) return;
    _navigatedToRematch = true;
    final newMatchId = offer.newMatchId!;
    final gameMode = offer.gameMode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => switch (gameMode) {
            MatchGameMode.higherLower => MultiplayerHigherLowerScreen(matchId: newMatchId),
            MatchGameMode.quizzTanks => MultiplayerTanksScreen(matchId: newMatchId),
            MatchGameMode.obby => MultiplayerObbyScreen(matchId: newMatchId),
            MatchGameMode.electricChair => MultiplayerElectricChairScreen(matchId: newMatchId),
            MatchGameMode.classic => MultiplayerMatchScreen(matchId: newMatchId),
          },
        ),
      );
    });
  }

  /// Banda de revanșă de sub clasament — o singură secțiune, ramificată pe
  /// stare, ca gazda și ceilalți jucători să nu aibă nevoie de widget-uri
  /// separate. Vezi [RematchOffer.status] pentru semnificația fiecărei ramuri.
  Widget _buildRematchSection() {
    // Sub 2 foști jucători n-are cu cine se relua meciul.
    if (_originalPlayers.length < 2) return const SizedBox.shrink();
    final me = MultiplayerService.instance.currentPlayerId;
    return StreamBuilder<RematchOffer?>(
      stream: _rematchStream,
      builder: (context, snap) {
        final offer = snap.data;
        if (offer != null) {
          _maybeLaunchRematch(offer);
          _maybeNavigateToRematch(offer);
        }
        if (offer == null || offer.status == 'cancelled') {
          if (!_amHost) return const SizedBox.shrink();
          final declinedName = offer?.declinedBy == null
              ? null
              : offer!.participants.firstWhere((p) => p.id == offer.declinedBy, orElse: () => const RematchParticipant(id: '', name: '?', avatarSeed: '')).name;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Column(
              children: [
                if (declinedName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      tr('$declinedName a refuzat revanșa.', '$declinedName declined the rematch.'),
                      style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                    ),
                  ),
                _rematchButton(tr('🔁 Cere revanșă', '🔁 Request rematch'), _requestRematch),
              ],
            ),
          );
        }
        if (offer.status == 'started') {
          return const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Center(child: CircularProgressIndicator(color: AppColors.blue)),
          );
        }
        // 'pending'
        final accepted = offer.acceptedIds.length;
        final total = offer.participants.length;
        if (_amHost) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Column(
              children: [
                Text(
                  tr('Aștept jucătorii... $accepted/$total au acceptat', 'Waiting for players... $accepted/$total accepted'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => MultiplayerService.instance.cancelRematchOffer(widget.matchId),
                  child: Text(tr('Anulează', 'Cancel'), style: const TextStyle(color: Colors.white54)),
                ),
              ],
            ),
          );
        }
        if (offer.acceptedIds.contains(me)) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              tr('Ai acceptat revanșa — aștept ceilalți jucători ($accepted/$total)', 'Rematch accepted — waiting for the others ($accepted/$total)'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          );
        }
        final hostName = offer.participants.firstWhere((p) => p.id == offer.hostId, orElse: () => const RematchParticipant(id: '', name: '?', avatarSeed: '')).name;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.blue.withAlpha(35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.blue.withAlpha(130)),
            ),
            child: Column(
              children: [
                Text(
                  tr('🔁 $hostName vrea revanșă!', '🔁 $hostName wants a rematch!'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => MultiplayerService.instance.declineRematchOffer(widget.matchId),
                        child: Text(tr('Refuz', 'Decline'), style: const TextStyle(color: Colors.white70)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => MultiplayerService.instance.acceptRematchOffer(widget.matchId),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.play),
                        child: Text(tr('Accept', 'Accept'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _rematchButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, padding: const EdgeInsets.symmetric(vertical: 14)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
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
              if (_firstWinBonus || !_salvage.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _playRewardAnimations());
              }
              final me = MultiplayerService.instance.currentPlayerId;
              final players = snap.data!;
              return Column(
                children: [
                  const SizedBox(height: 20),
                  Icon(
                    widget.gameMode == MatchGameMode.quizzTanks
                        ? Icons.military_tech_rounded
                        : Icons.emoji_events_rounded,
                    color: widget.gameMode == MatchGameMode.quizzTanks ? AppColors.orange : AppColors.coin,
                    size: 56,
                  ),
                  const SizedBox(height: 8),
                  const Text('Clasament final', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  if (widget.gameMode == MatchGameMode.quizzTanks)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        tr('Ordinea o dau daunele făcute', 'Ranked by damage dealt'),
                        style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                      ),
                    ),
                  if (widget.gameMode == MatchGameMode.electricChair)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        tr('Ordinea o dă cine a rezistat mai mult', 'Ranked by who lasted longest'),
                        style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                      ),
                    ),
                  if (_coinsEarned > 0 || _xpEarned > 0) ...[
                    const SizedBox(height: 6),
                    // La Quizz Tanks nu există pot, deci monedele de aici sunt
                    // mereu 0 — iar un „+0 monede" lângă XP arată a bug, nu a
                    // regulă. Monedele modului vin din pradă, mai jos.
                    Text(
                      _coinsEarned > 0 ? '+$_coinsEarned monede  •  +$_xpEarned XP' : '+$_xpEarned XP',
                      style: const TextStyle(color: AppColors.coin, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
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
                  if (!_salvage.isEmpty) _buildSalvagePanel(),
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
                              if (widget.gameMode == MatchGameMode.quizzTanks)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    p.eliminated ? '💥 KO' : '❤ ${p.hp}',
                                    style: TextStyle(
                                      color: p.eliminated ? AppColors.danger : AppColors.play,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              if (widget.gameMode == MatchGameMode.obby)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    p.obstaclesCleared >= obbyObstacleCount ? '🏁' : '🏃 ${p.obstaclesCleared}/$obbyObstacleCount',
                                    style: const TextStyle(color: AppColors.play, fontSize: 11.5, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              if (widget.gameMode == MatchGameMode.electricChair)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    p.eliminated ? '💀 ELIMINAT' : '⚡ ${p.lives}',
                                    style: TextStyle(
                                      color: p.eliminated ? AppColors.danger : AppColors.coin,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              // La Quizz Tanks "punctele" chiar SUNT daunele
                              // (vezi resolveTanksRound), deci se scriu ca
                              // atare — „82 pct" n-ar fi spus nimic despre ce
                              // s-a întâmplat în meci.
                              Text(
                                widget.gameMode == MatchGameMode.quizzTanks ? '${p.damageDealt} dmg' : '${p.score} pct',
                                style: const TextStyle(color: AppColors.coin, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  _buildRematchSection(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
