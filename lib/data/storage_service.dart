import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/gamemodes.dart';
import '../core/progression.dart';
import 'shop.dart';

/// Ce s-a acordat efectiv la o vizionare de reclamă recompensată — vezi
/// [StorageService.claimRewardedAdReward].
class AdRewardResult {
  final int hints;
  final int hearts;
  final int coins;
  const AdRewardResult(
      {required this.hints, required this.hearts, this.coins = 0});
}

/// Gestionează datele salvate local (vieți, monede, progres, highscore,
/// XP/nivel, quest-uri, provocarea zilnică).
class StorageService {
  static const _livesKey = 'lives';
  static const _livesTimestampKey = 'lives_timestamp';
  static const _coinsKey = 'coins';
  static const _answeredKey = 'answered_ids';
  static const _highScoreKey = 'high_score';
  static const _dailyClaimKey = 'daily_claim_date';
  static const _xpKey = 'xp';
  static const _dailyChallengeKey = 'daily_challenge_date';
  static const _noBlurKey = 'no_blur_mode';
  static const _introSeenKey = 'intro_tutorial_seen';
  static const _multiplayerInfoSeenKey = 'multiplayer_info_seen';
  static const _musicEnabledKey = 'music_enabled';
  static const _musicVolumeKey = 'music_volume';
  static const _hintsKey = 'hints_balance';

  // ─── Zestrea unui jucător nou (vezi reproiectarea economiei v3) ──────────
  // Înainte: 5 vieți, 3 hints, 0 monede, 0 gems — prea puține vieți și
  // hint-uri pentru primul playthrough. Monedele de start acoperă taxa de
  // intrare plus câteva hint-uri în prima sesiune, fără să facă jucătorul
  // bogat; gems-ul de start (vezi [starterGemGrant]) e exact cât să
  // deblocheze el însuși o categorie la alegere.
  static const _startingHints = 9;
  static const _startingCoins = 173;
  static const _startingLives = 7;

  /// Aceleași valori, publice, pentru cine citește un cloud-save din afară
  /// (AdminScreen). E nevoie de ele fiindcă [exportAll] urcă DOAR cheile
  /// chiar scrise în SharedPreferences: la un cont nou, `coins`/`gems`/
  /// `lives`/`hints` lipsesc complet din `users/{uid}` până când jucătorul
  /// câștigă sau cheltuie ceva. Absența cheii înseamnă deci "încă la valoarea
  /// de start", NU zero — citită ca zero, fișa din admin arăta 0 monede unui
  /// jucător care avea 173.
  static const startingCoinsDefault = _startingCoins;
  static const startingLivesDefault = _startingLives;
  static const startingHintsDefault = _startingHints;

  static const _lastPlayedDateKey = 'last_played_date';
  static const _streakCountKey = 'streak_count';
  static const _streakMilestonesKey = 'streak_milestones_claimed';
  static const _hintsUsedTotalKey = 'hints_used_total';
  static const _questsClaimedTotalKey = 'quests_claimed_total';
  static const _dailyChallengesTotalKey = 'daily_challenges_total';
  static const _modesEverPlayedKey = 'modes_ever_played';
  static const _ringSpinTimestampKey = 'ring_spin_timestamp';
  static const _clippyNextReadyKey = 'clippy_next_ready_at';
  static const _displayNameKey = 'display_name';
  static const _gemsKey = 'gems';
  static const _lastClaimedRewardLevelKey = 'last_claimed_reward_level';
  static const _xpCurveMigratedKey = 'xp_curve_migrated_v2';
  static const _xpCurveV3MigratedKey = 'xp_curve_migrated_v3';
  static const _maxLives = 6;
  static const ringSpinCooldownHours = 24;
  static const _unlimitedLivesUntilKey = 'unlimited_lives_until';
  static const _cultureQuizRoundKey = 'culture_quiz_round_in_cycle';
  static const _cultureQuizNextReadyKey = 'culture_quiz_next_ready_at';
  static const cultureQuizPlayLimit = 3;
  static const cultureQuizWindowMinutes = 15;
  static const _leaderboardPeriodStartKey = 'leaderboard_period_start';
  static const _leaderboardModesKey = 'leaderboard_modes_with_points';
  static const leaderboardPeriodHours = 48;
  static const _starterCategoriesKey = 'starter_unlocked_categories';
  static const _firstMultiplayerWinKey = 'first_mp_win_date';

  /// Câte categorii sunt deblocate gratuit, random, la prima intrare în joc
  /// (vezi [getStarterCategories]) — restul pornesc complet blocate (tier 0).
  static const int starterCategoryCount = 3;

  /// Plafon de stoc pentru hint-uri — peste acest prag, sursele suplimentare
  /// nu se mai adaugă (vezi reproiectarea economiei: hint-urile trebuie
  /// folosite, nu doar strânse la nesfârșit). Ridicat de la 20, fiindcă
  /// folosirea unui hint costă acum și monede (vezi [hintCoinCost]).
  static const _hintsCap = 26;

  /// Câte vizionări de reclamă recompensată sunt permise pe zi calendaristică
  /// — reclama devine un supliment, nu principala sursă de hints/vieți.
  static const _adRewardCap = 4;

  /// Praguri (în zile consecutive) la care se acordă un bonus automat.
  /// Recompensa e mult mai mare decât înainte pe monede (era 5×prag) și mai
  /// mică pe XP (era 10×prag, pe o scară de ~15× mai inflată) — a intra zilnic
  /// în joc trebuie să fie una dintre cele mai bune investiții de timp.
  static const List<int> streakMilestones = [3, 7, 14, 30, 60, 100];

  static int streakMilestoneCoins(int milestone) => milestone * 27;
  static int streakMilestoneXp(int milestone) => milestone * 8;
  static int streakMilestoneGems(int milestone) => (milestone ~/ 7) + 1;
  static const livesRechargeMinutes = 23; // o viată la 23 min

  // ─── Vieți ───────────────────────────────────────────────────────────────

  static Future<int> getLives() async {
    final prefs = await SharedPreferences.getInstance();
    await _rechargeLives(prefs);
    return prefs.getInt(_livesKey) ?? _startingLives;
  }

  /// Cât mai e până se reîncarcă pasiv următoarea viață — zero dacă ești deja
  /// la plafon sau dacă nu există încă un timestamp de la care să numeri.
  /// Folosit de contorul afișat pe Home când rămâi pe 0 vieți (vezi
  /// LivesCountdownCard).
  static Future<Duration> livesRechargeRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    await _rechargeLives(prefs);
    final current = prefs.getInt(_livesKey) ?? _startingLives;
    if (current >= _maxLives) return Duration.zero;
    final ts = prefs.getInt(_livesTimestampKey);
    if (ts == null) return Duration.zero;
    final elapsed = DateTime.now().millisecondsSinceEpoch - ts;
    final period = const Duration(minutes: livesRechargeMinutes).inMilliseconds;
    final remaining = period - (elapsed % period);
    return Duration(milliseconds: remaining);
  }

  /// Plafonul de 5 e doar cel "standard" (regenerare pasivă, reset la
  /// zi/game-over) — nu e impus aici, ca vieți câștigate ca bonus (vezi
  /// [addLivesUncapped]) să nu fie retezate la următorul apel cu o valoare
  /// deja calculată de apelant (ex: decrementul dintr-un răspuns greșit).
  static Future<void> setLives(int lives) async {
    final prefs = await SharedPreferences.getInstance();
    final clamped = lives < 0 ? 0 : lives;
    await prefs.setInt(_livesKey, clamped);
    // salvează timestamp-ul când vieților scad
    if (clamped < _maxLives) {
      prefs.setInt(_livesTimestampKey, DateTime.now().millisecondsSinceEpoch);
    }
  }

  /// Adaugă vieți peste plafonul standard ([_maxLives]) — folosit de
  /// recompensele de colectare (Cultură Generală, Level Up, achievements)
  /// unde inimile câștigate se pot acumula peste maximul obișnuit
  /// (regenerarea pasivă tot se oprește la plafon). Fără plafon superior.
  static Future<void> addLivesUncapped(int amount) async {
    if (amount <= 0) return;
    final current = await getLives();
    await setLives(current + amount);
  }

  /// Reîncarcă vieți automat în funcție de timp trecut
  static Future<void> _rechargeLives(SharedPreferences prefs) async {
    final current = prefs.getInt(_livesKey) ?? _startingLives;
    if (current >= _maxLives) return;

    final ts = prefs.getInt(_livesTimestampKey);
    if (ts == null) return;

    final elapsed = DateTime.now().millisecondsSinceEpoch - ts;
    final minutesPassed = elapsed ~/ 60000;
    final livesToAdd = minutesPassed ~/ livesRechargeMinutes;

    if (livesToAdd > 0) {
      final newLives = (current + livesToAdd).clamp(0, _maxLives);
      await prefs.setInt(_livesKey, newLives);
      if (newLives < _maxLives) {
        // actualizează timestamp-ul cu restul de timp
        final remainder = minutesPassed % livesRechargeMinutes;
        final newTs = DateTime.now().millisecondsSinceEpoch - (remainder * 60000);
        await prefs.setInt(_livesTimestampKey, newTs);
      }
    }
  }

  // ─── Vieți nelimitate (premiu rar de la Roata norocului, 24h) ─────────────
  // Cât timp e activ, un răspuns greșit nu mai scade nicio viață (vezi
  // GameScreen._resolveAnswer) — nu doar un plafon foarte mare, chiar
  // nelimitat, la cererea explicită a jucătorului.

  static Future<void> activateUnlimitedLives(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_unlimitedLivesUntilKey, DateTime.now().add(duration).millisecondsSinceEpoch);
  }

  static Future<bool> hasUnlimitedLives() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_unlimitedLivesUntilKey);
    return until != null && DateTime.now().millisecondsSinceEpoch < until;
  }

  /// Timpul rămas până expiră bonusul (zero dacă nu e activ).
  static Future<Duration> unlimitedLivesRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_unlimitedLivesUntilKey);
    if (until == null) return Duration.zero;
    final remaining = until - DateTime.now().millisecondsSinceEpoch;
    return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
  }

  // ─── Monede ──────────────────────────────────────────────────────────────

  static Future<int> getCoins() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_coinsKey) ?? _startingCoins;
  }

  static Future<void> addCoins(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_coinsKey) ?? _startingCoins;
    await prefs.setInt(_coinsKey, current + amount);
  }

  static Future<bool> spendCoins(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_coinsKey) ?? _startingCoins;
    if (current < amount) return false;
    await prefs.setInt(_coinsKey, current - amount);
    return true;
  }

  /// Delta cu semn (pozitiv sau negativ), plafonat doar inferior la 0 — spre
  /// deosebire de [addCoins]/[spendCoins], care presupun un sens fix.
  /// Folosit DOAR de CloudSyncService.consumePendingGrant (grant-uri de
  /// admin), unde cantitatea poate fi și o "luare" de monede.
  static Future<void> adjustCoins(int delta) async {
    if (delta == 0) return;
    final prefs = await SharedPreferences.getInstance();
    final updated = (prefs.getInt(_coinsKey) ?? _startingCoins) + delta;
    await prefs.setInt(_coinsKey, updated < 0 ? 0 : updated);
  }

  // ─── Gems (monedă premium — rară, din achievements/nivel, cheltuită în
  // secțiunea Premium a Shop-ului) ────────────────────────────────────────

  static Future<int> getGems() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_gemsKey) ?? starterGemGrant;
  }

  static Future<void> addGems(int amount) async {
    if (amount <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_gemsKey) ?? starterGemGrant;
    await prefs.setInt(_gemsKey, current + amount);
  }

  static Future<bool> spendGems(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_gemsKey) ?? starterGemGrant;
    if (current < amount) return false;
    await prefs.setInt(_gemsKey, current - amount);
    return true;
  }

  /// Vezi [adjustCoins] — același tipar, pentru gems.
  static Future<void> adjustGems(int delta) async {
    if (delta == 0) return;
    final prefs = await SharedPreferences.getInstance();
    final updated = (prefs.getInt(_gemsKey) ?? starterGemGrant) + delta;
    await prefs.setInt(_gemsKey, updated < 0 ? 0 : updated);
  }

  /// Acordă gems dintr-un quest, respectând plafonul zilnic
  /// [dailyQuestGemCap] — întoarce cât s-a acordat EFECTIV (0 dacă plafonul
  /// e deja atins), ca apelantul să anime exact suma reală. Restul
  /// recompensei quest-ului (monede/XP/hints/vieți) nu e afectat.
  static Future<int> grantQuestGems(int requested) async {
    if (requested <= 0) return 0;
    final usedToday = await getDailyCounter('quest_gems');
    final left = dailyQuestGemCap - usedToday;
    if (left <= 0) return 0;
    final granted = requested < left ? requested : left;
    await incrementDailyCounter('quest_gems', granted);
    return granted;
  }

  /// Cât din plafonul zilnic de gems din quest-uri a mai rămas — afișat pe
  /// ecranul de Quests, ca jucătorul să înțeleagă de ce un card arată 0 💎.
  static Future<int> questGemsLeftToday() async {
    final used = await getDailyCounter('quest_gems');
    final left = dailyQuestGemCap - used;
    return left > 0 ? left : 0;
  }

  // ─── Hints (resursă separată, ca vieți/monede — vezi Home + shop) ─────────
  // Jucătorii noi pornesc cu [_startingHints] gratuit, ca hint-ul din prima
  // întrebare să nu coste nimic din prima sesiune.

  static Future<int> getHints() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_hintsKey) ?? _startingHints;
  }

  /// Plafonat la [_hintsCap] — hint-urile trebuie folosite, nu doar strânse.
  /// Plafonul se aplică DOAR cât balanța e încă sub el. Dacă jucătorul are
  /// deja mai mult (grant admin, UNLIMITED de test, achiziție — toate
  /// necapate, vezi [addHintsUncapped]), un `clamp(0, _hintsCap)` orb ar
  /// avea DOUĂ efecte greșite: (1) i-ar TĂIA balanța înapoi la cap la
  /// următorul quest capat (bug real semnalat: 994 -> 20 după un singur
  /// quest) — și dacă doar am fi ridicat plafonul efectiv la `current`,
  /// (2) orice recompensă capată ulterioară ar deveni un no-op silențios,
  /// balanța părând din nou "înghețată" (994 -> 994 la infinit) — exact
  /// simptomul semnalat, doar la alt prag. De-aia, o dată depășit
  /// plafonul, recompensele capate se comportă ca cele necapate (se adună
  /// mereu); doar SUB plafon rămâne cu adevărat plafonat.
  static Future<void> addHints(int amount) async {
    if (amount <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_hintsKey) ?? _startingHints;
    final updated = current >= _hintsCap ? current + amount : (current + amount).clamp(0, _hintsCap);
    await prefs.setInt(_hintsKey, updated);
  }

  /// Fără plafon — folosit DOAR pentru achiziții cu bani reali (vezi Shop).
  /// Plafonul [_hintsCap] există ca hint-urile gratuite "să fie folosite, nu
  /// doar strânse" — regula aia n-ar trebui să trunchieze un pachet plătit.
  static Future<void> addHintsUncapped(int amount) async {
    if (amount <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_hintsKey) ?? _startingHints;
    await prefs.setInt(_hintsKey, current + amount);
  }

  /// Vezi [adjustCoins] — același tipar, pentru hint-uri (fără plafonul
  /// [_hintsCap], la fel ca [addHintsUncapped]).
  static Future<void> adjustHints(int delta) async {
    if (delta == 0) return;
    final prefs = await SharedPreferences.getInstance();
    final updated = (prefs.getInt(_hintsKey) ?? _startingHints) + delta;
    await prefs.setInt(_hintsKey, updated < 0 ? 0 : updated);
  }

  /// Consumă 1 hint din balanța persistată — întoarce false dacă nu mai ai.
  static Future<bool> spendHint() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_hintsKey) ?? _startingHints;
    if (current <= 0) return false;
    await prefs.setInt(_hintsKey, current - 1);
    return true;
  }

  // ─── XP / Nivel ────────────────────────────────────────────────────────────

  static Future<int> getXp() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateXpCurveIfNeeded(prefs);
    return prefs.getInt(_xpKey) ?? 0;
  }

  static Future<void> addXp(int amount) async {
    if (amount <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await _migrateXpCurveIfNeeded(prefs);
    final current = prefs.getInt(_xpKey) ?? 0;
    await prefs.setInt(_xpKey, current + amount);
  }

  /// Vezi [adjustCoins] — același tipar, pentru XP (deci poate scădea și
  /// nivelul afișat, spre deosebire de restul jocului unde XP-ul nu scade
  /// niciodată — acceptabil doar aici, un grant de admin poate fi corectat).
  static Future<void> adjustXp(int delta) async {
    if (delta == 0) return;
    final prefs = await SharedPreferences.getInstance();
    await _migrateXpCurveIfNeeded(prefs);
    final updated = (prefs.getInt(_xpKey) ?? 0) + delta;
    await prefs.setInt(_xpKey, updated < 0 ? 0 : updated);
  }

  /// Curba de XP/nivel s-a schimbat (de la liniar 1000/nivel, la o curbă
  /// pătratică — vezi [levelForXp]). Rulează o singură dată: dacă XP-ul deja
  /// salvat ar corespunde unui nivel mai mic sub noua curbă decât nivelul pe
  /// care jucătorul îl avea deja sub cea veche, XP-ul e ridicat exact până la
  /// pragul noii curbe pentru acel nivel — nivelul afișat nu scade niciodată
  /// din cauza migrării. lastClaimedRewardLevel pornește de la nivelul curent
  /// (nu retroactiv), ca să nu apară dintr-o dată zeci de reward-uri
  /// "necolectate" pentru niveluri deja trecute înainte de acest update.
  static Future<void> _migrateXpCurveIfNeeded(SharedPreferences prefs) async {
    if (!(prefs.getBool(_xpCurveMigratedKey) ?? false)) {
      final xp = prefs.getInt(_xpKey) ?? 0;
      const oldXpPerLevel = 1000;
      final oldLevel = (xp ~/ oldXpPerLevel) + 1;
      final newFloor = cumulativeXpForLevel(oldLevel);
      final migratedXp = xp < newFloor ? newFloor : xp;
      if (migratedXp != xp) {
        await prefs.setInt(_xpKey, migratedXp);
      }
      await prefs.setInt(_lastClaimedRewardLevelKey, levelForXp(migratedXp));
      await prefs.setBool(_xpCurveMigratedKey, true);
    }
    await _migrateXpRateV3(prefs);
  }

  /// A doua migrare (economia v3): XP-ul acordat la o întrebare a scăzut de
  /// ~8,5 ori (era egal cu punctele întrebării, 140-200; acum e 11-37 — vezi
  /// xpForCorrectAnswer). Un total vechi lăsat neatins ar însemna un nivel
  /// umflat pe curba nouă, așa că îl aducem la aceeași scară. Nu e o
  /// pedeapsă: fiecare punct de XP valorează acum de ~15 ori mai mult, deci
  /// nivelul afișat rămâne aproximativ același.
  static const double _xpRateV3Divisor = 8.5;

  static Future<void> _migrateXpRateV3(SharedPreferences prefs) async {
    if (prefs.getBool(_xpCurveV3MigratedKey) ?? false) return;
    final xp = prefs.getInt(_xpKey) ?? 0;
    if (xp > 0) {
      await prefs.setInt(_xpKey, (xp / _xpRateV3Divisor).round());
    }
    await prefs.setInt(
        _lastClaimedRewardLevelKey, levelForXp(prefs.getInt(_xpKey) ?? 0));
    await prefs.setBool(_xpCurveV3MigratedKey, true);
  }

  // ─── Reward-uri de Level Up ─────────────────────────────────────────────
  // Fiecare nivel are un reward dedicat (vezi [levelReward]) — nu se acordă
  // automat, ci se colectează manual (bara de XP din LevelHeader). Nimic nu
  // se pierde dacă treci mai multe niveluri fără să colectezi: se ține minte
  // doar ultimul nivel revendicat, restul se calculează la cerere.

  static Future<int> getLastClaimedRewardLevel() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateXpCurveIfNeeded(prefs);
    return prefs.getInt(_lastClaimedRewardLevelKey) ?? levelForXp(prefs.getInt(_xpKey) ?? 0);
  }

  static Future<int> getPendingLevelRewardsCount() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateXpCurveIfNeeded(prefs);
    final currentLevel = levelForXp(prefs.getInt(_xpKey) ?? 0);
    final lastClaimed = prefs.getInt(_lastClaimedRewardLevelKey) ?? currentLevel;
    return (currentLevel - lastClaimed).clamp(0, 1000000);
  }

  /// Calculează suma recompenselor TUTUROR nivelurilor trecute și încă
  /// nerevendicate (poate fi mai multe deodată dacă jucătorul nu a mai
  /// intrat de o vreme) și marchează-le drept revendicate — dar NU scrie
  /// efectiv coins/hints/hearts/gems în balanțe (asta rămâne în grija
  /// apelantului, prin [collectRewards], ca să nu se acorde de două ori —
  /// aceeași convenție ca la [claimRewardedAdReward]).
  static Future<LevelReward> claimAllPendingLevelRewards() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateXpCurveIfNeeded(prefs);
    final currentLevel = levelForXp(prefs.getInt(_xpKey) ?? 0);
    final lastClaimed = prefs.getInt(_lastClaimedRewardLevelKey) ?? currentLevel;
    if (currentLevel <= lastClaimed) return const LevelReward();

    var coins = 0, hints = 0, hearts = 0, gems = 0;
    for (var level = lastClaimed + 1; level <= currentLevel; level++) {
      final r = levelReward(level);
      coins += r.coins;
      hints += r.hints;
      hearts += r.hearts;
      gems += r.gems;
    }
    await prefs.setInt(_lastClaimedRewardLevelKey, currentLevel);
    return LevelReward(coins: coins, hints: hints, hearts: hearts, gems: gems);
  }

  // ─── Progres întrebări ────────────────────────────────────────────────────

  static Future<Set<String>> getAnsweredIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_answeredKey)?.toSet() ?? {};
  }

  static Future<void> addAnsweredId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_answeredKey) ?? [];
    if (!current.contains(id)) {
      current.add(id);
      await prefs.setStringList(_answeredKey, current);
    }
  }

  static Future<void> resetProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_answeredKey);
  }

  /// Șterge tot progresul salvat (folosit din ecranul de profil).
  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // ─── Recompensă zilnică gratuită (vieți) ───────────────────────────────────

  static Future<bool> canClaimDailyReward() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_dailyClaimKey);
    return last != _dateKey(DateTime.now());
  }

  /// Adaugă [freeDailyLivesTarget] vieți, o dată pe zi calendaristică —
  /// aditiv, peste orice ai deja acumulat (regenerare pasivă, bonusuri etc.),
  /// fără plafon. Întoarce câte vieți s-au acordat.
  static Future<int> claimDailyReward() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyClaimKey, _dateKey(DateTime.now()));
    await addLivesUncapped(freeDailyLivesTarget);
    return freeDailyLivesTarget;
  }

  // ─── First Win of the Day (bonus la prima victorie multiplayer a zilei) ───
  // Mirror exact pe canClaimDailyReward/claimDailyReward de mai sus — doar
  // marchează ziua, recompensa efectivă (monede/XP) e acordată de apelant
  // (MultiplayerResultsScreen) prin collectRewards, la fel ca la quest-uri.

  static Future<bool> canClaimFirstWinOfDay() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_firstMultiplayerWinKey);
    return last != _dateKey(DateTime.now());
  }

  static Future<void> claimFirstWinOfDay() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_firstMultiplayerWinKey, _dateKey(DateTime.now()));
  }

  // ─── Wheel-spin la inel (roată cu premii, o dată la 24h reale) ─────────────
  // Spre deosebire de recompensa zilnică (resetată la miezul nopții), aici
  // cooldown-ul e strict pe timp scurs (24h de la ultimul spin), nu pe zi
  // calendaristică — de-asta ținem un timestamp, nu o dată.

  static Future<bool> canSpinRing() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_ringSpinTimestampKey);
    if (last == null) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    return elapsed >= const Duration(hours: ringSpinCooldownHours).inMilliseconds;
  }

  /// Timpul rămas până la următorul spin disponibil (zero dacă e deja gata).
  static Future<Duration> ringSpinTimeRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_ringSpinTimestampKey);
    if (last == null) return Duration.zero;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    final remaining = const Duration(hours: ringSpinCooldownHours).inMilliseconds - elapsed;
    return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
  }

  static Future<void> recordRingSpin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_ringSpinTimestampKey, DateTime.now().millisecondsSinceEpoch);
  }

  // ─── Notificarea lui Clippy (bonus cu 3 întrebări, la fiecare 5 minute) ────
  // Persistat (nu doar în memoria widget-ului), ca să supraviețuiască
  // navigării între tab-uri (Home se recreează la fiecare schimbare de tab
  // din bottom nav) — altfel notificarea se pierdea/reseta la revenirea pe
  // Home, deși încă era valabilă.

  static const clippyReadyIntervalSeconds = 5 * 60;

  static Future<bool> isClippyReady() async {
    final prefs = await SharedPreferences.getInstance();
    final next = prefs.getInt(_clippyNextReadyKey);
    if (next == null) return true; // prima dată — notificare imediată
    return DateTime.now().millisecondsSinceEpoch >= next;
  }

  /// Timpul rămas până la următoarea notificare (zero dacă e deja gata).
  static Future<Duration> clippyReadyRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final next = prefs.getInt(_clippyNextReadyKey);
    if (next == null) return Duration.zero;
    final remaining = next - DateTime.now().millisecondsSinceEpoch;
    return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
  }

  /// Repornește așteptarea pentru următoarea notificare — apelat DOAR când
  /// jucătorul termină efectiv bonusul (nu la simpla intrare), ca notificarea
  /// să rămână activă dacă a intrat și a ieșit fără să termine.
  static Future<void> resetClippyCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_clippyNextReadyKey, DateTime.now().millisecondsSinceEpoch + clippyReadyIntervalSeconds * 1000);
  }

  // ─── Daily Challenge (mini-quiz special, o dată pe zi) ─────────────────────

  static Future<bool> canPlayDailyChallenge() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_dailyChallengeKey);
    return last != _dateKey(DateTime.now());
  }

  static Future<void> markDailyChallengeDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyChallengeKey, _dateKey(DateTime.now()));
    await prefs.setInt(_dailyChallengesTotalKey, (prefs.getInt(_dailyChallengesTotalKey) ?? 0) + 1);
  }

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  // ─── Rate-limit Cultură Generală ([cultureQuizPlayLimit] runde pe ciclu,
  // apoi [cultureQuizWindowMinutes] minute de cooldown) ───────────────────
  // Cooldown-ul de [cultureQuizWindowMinutes] pornește o SINGURĂ dată, la
  // finalul efectiv al ciclului (runda finală colectată — tap pe COLECTEAZĂ
  // sau auto-colectare, vezi CultureQuizPanel._collect), NU la runda 1 —
  // altfel numărătoarea afișată jucătorului ar începe deja "consumată" cu
  // timpul petrecut jucând rundele 1-3, nu de la 15:00 întregi. Runda
  // curentă (0-3) e ținută separat de cooldown, ca să supraviețuiască unui
  // restart de aplicație în mijlocul ciclului (vezi cultureQuizPlaysInWindow).

  static Future<bool> canPlayCultureQuiz() async {
    final prefs = await SharedPreferences.getInstance();
    final next = prefs.getInt(_cultureQuizNextReadyKey);
    return next == null || DateTime.now().millisecondsSinceEpoch >= next;
  }

  /// Câte runde s-au jucat deja în ciclul curent — folosit ca număr de
  /// rundă pentru runda care urmează să pornească (vezi CultureQuizPanel,
  /// care are [cultureQuizPlayLimit] runde per ciclu).
  static Future<int> cultureQuizPlaysInWindow() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_cultureQuizRoundKey) ?? 0;
  }

  /// Timpul rămas până la următorul ciclu (zero dacă poți juca deja).
  static Future<Duration> cultureQuizCooldownRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final next = prefs.getInt(_cultureQuizNextReadyKey);
    if (next == null) return Duration.zero;
    final remaining = next - DateTime.now().millisecondsSinceEpoch;
    return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
  }

  /// Înregistrează o rundă (1 sau 2) jucată în ciclul curent — NU pornește
  /// cooldown-ul, doar avansează numărul rundei (vezi [startCultureQuizCooldown]
  /// pentru runda finală).
  static Future<void> recordCultureQuizPlay() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_cultureQuizRoundKey) ?? 0;
    await prefs.setInt(_cultureQuizRoundKey, current + 1);
  }

  /// Repornește așteptarea pentru următorul ciclu — apelat DOAR când runda
  /// finală e efectiv colectată (buton sau auto după 10s), ca numărătoarea
  /// să pornească mereu de la [cultureQuizWindowMinutes] întregi. Resetează
  /// și runda curentă la 0, pentru ciclul următor.
  static Future<void> startCultureQuizCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    final windowMs = const Duration(minutes: cultureQuizWindowMinutes).inMilliseconds;
    await prefs.setInt(_cultureQuizNextReadyKey, DateTime.now().millisecondsSinceEpoch + windowMs);
    await prefs.setInt(_cultureQuizRoundKey, 0);
  }

  /// Șterge cooldown-ul activ — folosit de butonul de reclamă din faza de
  /// cooldown (vezi CultureQuizPanel._buildCooldown), ca să sară direct
  /// peste așteptare.
  static Future<void> skipCultureQuizCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cultureQuizNextReadyKey);
  }

  // ─── Contoare zilnice generice (plafoane anti-farm) ────────────────────────
  // Aceleași chei, scoped pe zi calendaristică, ca la quest-uri — folosite
  // pentru plafonul reclamei recompensate și pentru diminishing returns pe
  // modurile fără risc (Unlimited Quiz, Cultură Generală), vezi reproiectarea
  // economiei: niciun mod nu trebuie să poată fi "farmat" la nesfârșit.

  static String _dailyCounterKey(String name) => 'daily_${name}_${_dateKey(DateTime.now())}';

  static Future<int> getDailyCounter(String name) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_dailyCounterKey(name)) ?? 0;
  }

  static Future<int> incrementDailyCounter(String name, [int amount = 1]) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _dailyCounterKey(name);
    final updated = (prefs.getInt(key) ?? 0) + amount;
    await prefs.setInt(key, updated);
    return updated;
  }

  // ─── Reclamă recompensată (Game Over) ──────────────────────────────────────
  // Singurul loc din joc unde apare — e un buton de "continuă" după 0 vieți,
  // deci trebuie să acorde mereu cel puțin o viață (altfel "continuă" n-ar
  // avea sens). Plafonată la [_adRewardCap]/zi și redusă față de +2 vieți/+5
  // hints necapat, cât acorda înainte de reproiectare.

  static Future<bool> canClaimRewardedAdReward() async {
    return (await getDailyCounter('ad_reward')) < _adRewardCap;
  }

  /// Doar înregistrează vizionarea de azi și întoarce cât acordă — NU scrie
  /// direct în balanțe, ca să nu se dubleze cu [collectRewards] (apelantul
  /// e cel care aplică efectiv reward-ul, cu animația lui proprie).
  static Future<AdRewardResult> claimRewardedAdReward() async {
    await incrementDailyCounter('ad_reward');
    return rewardedAdReward;
  }

  /// Aceeași valoare e și afișată pe butonul de reclamă (vezi GameScreen) —
  /// o singură sursă, ca eticheta să nu poată rămâne în urma recompensei.
  static const rewardedAdReward =
      AdRewardResult(hints: 3, hearts: 2, coins: 43);

  // ─── Cumpărături din Shop (Coins / Gems) ────────────────────────────────────
  // Shop-ul e principalul currency sink al economiei — vezi reproiectarea:
  // înainte, niciun articol nu se putea cumpăra efectiv cu Coins.

  static Future<int> getHeartsBoughtToday() => getDailyCounter('hearts_bought');
  static Future<int> getHintPacksBoughtToday() => getDailyCounter('hint_packs_bought');

  /// Cumpără o inimă bonus cu Coins, la prețul progresiv al achiziției de
  /// azi (crește cu fiecare cumpărare, se resetează a doua zi) — întoarce
  /// false dacă s-a atins plafonul zilnic sau nu sunt destule monede.
  static Future<bool> buyHeartWithCoins() async {
    final boughtToday = await getDailyCounter('hearts_bought');
    if (boughtToday >= heartCoinPrices.length) return false;
    if (!await spendCoins(heartCoinPrices[boughtToday])) return false;
    await incrementDailyCounter('hearts_bought');
    await addLivesUncapped(1);
    return true;
  }

  /// Umple instant viețile la maximul standard, cu Gems — fără plafon
  /// zilnic (Gems fiind deja o resursă rară, nu are nevoie de un al doilea
  /// gate). Întoarce false dacă ești deja plin sau nu ai destule gems.
  static Future<bool> buyHeartRefillWithGems() async {
    final current = await getLives();
    if (current >= _maxLives) return false;
    if (!await spendGems(heartRefillGemsPrice)) return false;
    await setLives(_maxLives);
    return true;
  }

  /// Cumpără un pachet de hints cu Coins — plafonul zilnic e pe NUMĂRUL de
  /// pachete cumpărate, indiferent de mărimea fiecăruia, iar prețul crește cu
  /// fiecare pachet luat azi (vezi [hintPackPriceToday]).
  static Future<bool> buyHintPackWithCoins(HintPack pack) async {
    final boughtToday = await getDailyCounter('hint_packs_bought');
    if (boughtToday >= hintPackDailyLimit) return false;
    if (!await spendCoins(hintPackPriceToday(pack, boughtToday))) return false;
    await incrementDailyCounter('hint_packs_bought');
    await addHints(pack.amount);
    return true;
  }

  // ─── Bani reali (achiziții premium, simulate — vezi shop.dart/shop_screen.dart) ─
  // Fără SDK real de plăți conectat încă — vezi shop.dart pentru detalii.

  static const _noAdsForeverKey = 'no_ads_forever';
  static const _starterPackBoughtKey = 'starter_pack_bought';

  static Future<bool> getNoAdsForever() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_noAdsForeverKey) ?? false;
  }

  static Future<void> setNoAdsForever() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_noAdsForeverKey, true);
  }

  static Future<bool> getStarterPackBought() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_starterPackBoughtKey) ?? false;
  }

  static Future<void> setStarterPackBought() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_starterPackBoughtKey, true);
  }

  // ─── Deblocare treptată a categoriilor + întrebărilor (vezi shop.dart) ────

  /// Cele [starterCategoryCount] categorii deblocate gratuit, random, unic
  /// per instalare — alese o singură dată (persistate), la prima citire.
  /// Fiecare user nou are deci alt set (ex. 3 utilizatori diferiți, 3
  /// combinații diferite de categorii deblocate din start).
  static Future<List<String>> getStarterCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_starterCategoriesKey);
    if (existing != null) return existing;
    final ids = gameModes.where((m) => !m.locked).map((m) => m.id).toList()..shuffle(Random());
    final picked = ids.take(starterCategoryCount).toList();
    await prefs.setStringList(_starterCategoriesKey, picked);
    return picked;
  }

  /// Tier 0 = categorie complet blocată (0 întrebări jucabile) — implicit
  /// pentru toate categoriile, în afară de cele 3 alese random la instalare
  /// (vezi [getStarterCategories]), care pornesc direct la tier 1.
  static Future<int> getUnlockedTier(String gameModeId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'question_unlock_tier_$gameModeId';
    final stored = prefs.getInt(key);
    if (stored != null) return stored;
    final starters = await getStarterCategories();
    return starters.contains(gameModeId) ? 1 : 0;
  }

  /// Câte întrebări sunt efectiv jucabile acum într-o categorie cu
  /// [totalInCategory] întrebări în total — plafonat la total (nu are sens
  /// să "deblochezi" peste câte există efectiv). Categoriile cu mai puține
  /// întrebări decât [initialUnlockedQuestions] rămân mereu complet
  /// deblocate, fără gating.
  static Future<int> getUnlockedQuestionCount(String gameModeId, int totalInCategory) async {
    if (totalInCategory <= initialUnlockedQuestions) return totalInCategory;
    final tier = await getUnlockedTier(gameModeId);
    final unlocked = tier * questionUnlockBatch;
    return unlocked < totalInCategory ? unlocked : totalInCategory;
  }

  /// Cumpără următoarea treaptă pentru o categorie, cu Gems (tier 0→1
  /// deblochează chiar categoria) — întoarce false dacă nu ai destule gems
  /// sau ai atins deja [maxUnlockTier].
  static Future<bool> unlockNextQuestionBatch(String gameModeId) async {
    final tier = await getUnlockedTier(gameModeId);
    if (tier >= maxUnlockTier) return false;
    final price = questionUnlockGemsPrice(tier + 1);
    if (!await spendGems(price)) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('question_unlock_tier_$gameModeId', tier + 1);
    return true;
  }

  // ─── Modul "fără blur" (accesibilitate / preview) ─────────────────────────

  static Future<bool> getNoBlurMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_noBlurKey) ?? false;
  }

  static Future<void> setNoBlurMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_noBlurKey, value);
  }

  // ─── Popup de introducere la prima intrare în joc ─────────────────────────

  static Future<bool> getIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_introSeenKey) ?? false;
  }

  static Future<void> setIntroSeen(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introSeenKey, value);
  }

  // ─── Popup explicativ pentru ecranul de Multiplayer ───────────────────────

  static Future<bool> getMultiplayerInfoSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_multiplayerInfoSeenKey) ?? false;
  }

  static Future<void> setMultiplayerInfoSeen(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_multiplayerInfoSeenKey, value);
  }

  // ─── Muzică de fundal (separată de volumul efectelor sonore) ──────────────

  static Future<bool> getMusicEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_musicEnabledKey) ?? true;
  }

  static Future<void> setMusicEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_musicEnabledKey, value);
  }

  /// Volum muzică 0.0-1.0, separat de sunetele de UI (vezi [Sfx]).
  static Future<double> getMusicVolume() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_musicVolumeKey) ?? 0.5;
  }

  static Future<void> setMusicVolume(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_musicVolumeKey, value.clamp(0.0, 1.0));
  }

  // ─── Streak zilnic (zile consecutive jucate) ──────────────────────────────

  static Future<int> getStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_streakCountKey) ?? 0;
  }

  /// Apelat o dată pe sesiune de joc (orice gamemod) — actualizează zilele
  /// consecutive jucate. O zi ratată întrerupe seria, care repornește la 1.
  static Future<void> recordDailyStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dateKey(DateTime.now());
    final last = prefs.getString(_lastPlayedDateKey);
    if (last == today) return;
    final yesterday = _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    final current = prefs.getInt(_streakCountKey) ?? 0;
    final newStreak = (last == yesterday) ? current + 1 : 1;
    await prefs.setInt(_streakCountKey, newStreak);
    await prefs.setString(_lastPlayedDateKey, today);
  }

  /// Acordă automat bonusul pentru orice prag de streak nou atins (o
  /// singură dată per prag, ținut minte permanent) și întoarce pragurile
  /// noi atinse — de obicei gol sau un singur element.
  static Future<List<int>> claimNewStreakMilestones() async {
    final prefs = await SharedPreferences.getInstance();
    final streak = prefs.getInt(_streakCountKey) ?? 0;
    final claimed = prefs.getStringList(_streakMilestonesKey)?.map(int.parse).toSet() ?? <int>{};
    final newlyHit = <int>[];
    for (final milestone in streakMilestones) {
      if (streak >= milestone && !claimed.contains(milestone)) {
        newlyHit.add(milestone);
        claimed.add(milestone);
      }
    }
    if (newlyHit.isNotEmpty) {
      await prefs.setStringList(_streakMilestonesKey, claimed.map((e) => e.toString()).toList());
      for (final milestone in newlyHit) {
        await addCoins(streakMilestoneCoins(milestone));
        await addXp(streakMilestoneXp(milestone));
        await addGems(streakMilestoneGems(milestone));
      }
    }
    return newlyHit;
  }

  // ─── Quest-uri zilnice ──────────────────────────────────────────────────────
  // Progresul unui quest se resetează automat quand se schimbă ziua, pentru că
  // e stocat sub o cheie care include data ("quest_<id>_<data>").

  static Future<int> getQuestProgress(String questId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_questProgressKey(questId)) ?? 0;
  }

  /// Întoarce progresul actualizat, ca apelantul să poată detecta dacă
  /// tocmai s-a atins ținta quest-ului (pentru notificarea in-app).
  static Future<int> addQuestProgress(String questId, int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _questProgressKey(questId);
    final current = prefs.getInt(key) ?? 0;
    final updated = current + amount;
    await prefs.setInt(key, updated);
    return updated;
  }

  /// Ține minte în ce gamemoduri s-a jucat azi (pentru quest-ul "joacă în
  /// 2 moduri diferite"). Întoarce true dacă modul e nou pentru ziua asta.
  static Future<bool> recordModePlayedToday(String gameModeId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'played_modes_${_dateKey(DateTime.now())}';
    final played = prefs.getStringList(key) ?? [];
    if (played.contains(gameModeId)) return false;
    played.add(gameModeId);
    await prefs.setStringList(key, played);
    return true;
  }

  static Future<bool> isQuestClaimed(String questId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_questClaimedKey(questId)) ?? false;
  }

  /// Marchează quest-ul ca revendicat — NU scrie efectiv coins/xp/gems/vieți/
  /// hints în balanțe (aceeași convenție ca la [claimAllPendingLevelRewards]/
  /// [claimRewardedAdReward]: apelantul aplică recompensa prin
  /// collectRewards, ca să nu se acorde de două ori). Hrănește și metricul
  /// quest-ului "meta" care numără câte quest-uri s-au revendicat azi.
  static Future<void> claimQuest(String questId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_questClaimedKey(questId), true);
    await prefs.setInt(_questsClaimedTotalKey, (prefs.getInt(_questsClaimedTotalKey) ?? 0) + 1);
    await addQuestProgress('quests_claimed_today', 1);
  }

  /// True dacă vreun quest activ AZI are ținta atinsă și încă nerevendicată
  /// — folosit pentru punctul roșu de notificare de pe tab-ul Quests.
  static Future<bool> hasClaimableQuests() async {
    for (final q in todaysQuests()) {
      final progress = await getQuestProgress(q.metricKey);
      if (progress >= q.target && !await isQuestClaimed(q.id)) return true;
    }
    return false;
  }

  static String _questProgressKey(String id) => 'quest_${id}_${_dateKey(DateTime.now())}';
  static String _questClaimedKey(String id) => 'quest_claimed_${id}_${_dateKey(DateTime.now())}';

  // ─── High Score ───────────────────────────────────────────────────────────

  static Future<int> getHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_highScoreKey) ?? 0;
  }

  static Future<void> updateHighScore(int score) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_highScoreKey) ?? 0;
    if (score > current) {
      await prefs.setInt(_highScoreKey, score);
    }
  }

  /// Recordul all-time (per sesiune) pentru un gamemod anume — nu mai e
  /// folosit de Clasament (vezi mai jos, total cumulativ pe cicluri de 48h),
  /// păstrat totuși ca istoric brut, eventual util în Profil.
  static Future<int> getModeHighScore(String gameModeId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('high_score_$gameModeId') ?? 0;
  }

  static Future<void> updateModeHighScore(String gameModeId, int score) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'high_score_$gameModeId';
    final current = prefs.getInt(key) ?? 0;
    if (score > current) {
      await prefs.setInt(key, score);
    }
  }

  // ─── Clasament — total cumulativ pe cicluri de 48h ─────────────────────────
  // Diferit de High Score de mai sus (maximul unei singure sesiuni, ținut
  // pentru totdeauna): aici punctele se ADUNĂ pe măsură ce răspunzi corect,
  // pe toată durata unui ciclu de [leaderboardPeriodHours] — la reset,
  // punctele vechi dispar complet, nu se combină niciodată cu cele noi,
  // nici măcar în aceeași categorie. Nu importăm gamemodes.dart aici (la
  // fel ca getModeHighScore, gameModeId e tratat ca string opac) — ținem
  // separat lista modurilor cu puncte în ciclul curent, ca reset-ul să știe
  // exact ce chei să șteargă, fără să depindă de lista completă de moduri.

  static Future<void> _ensureLeaderboardPeriod(SharedPreferences prefs) async {
    final start = prefs.getInt(_leaderboardPeriodStartKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (start == null) {
      await prefs.setInt(_leaderboardPeriodStartKey, now);
      return;
    }
    final elapsed = now - start;
    if (elapsed < const Duration(hours: leaderboardPeriodHours).inMilliseconds) return;
    final modes = prefs.getStringList(_leaderboardModesKey) ?? [];
    for (final id in modes) {
      await prefs.remove('leaderboard_pts_$id');
    }
    await prefs.setStringList(_leaderboardModesKey, []);
    await prefs.setInt(_leaderboardPeriodStartKey, now);
  }

  static Future<void> addLeaderboardPoints(String gameModeId, int points) async {
    if (points <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await _ensureLeaderboardPeriod(prefs);
    final key = 'leaderboard_pts_$gameModeId';
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + points);
    final modes = prefs.getStringList(_leaderboardModesKey)?.toSet() ?? <String>{};
    if (modes.add(gameModeId)) {
      await prefs.setStringList(_leaderboardModesKey, modes.toList());
    }
  }

  static Future<int> getLeaderboardPoints(String gameModeId) async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureLeaderboardPeriod(prefs);
    return prefs.getInt('leaderboard_pts_$gameModeId') ?? 0;
  }

  /// Punctele din ciclul curent pentru toate modurile care au primit măcar
  /// un punct — modurile fără puncte încă pur și simplu lipsesc din hartă.
  static Future<Map<String, int>> getAllLeaderboardPoints() async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureLeaderboardPeriod(prefs);
    final modes = prefs.getStringList(_leaderboardModesKey) ?? [];
    return {for (final id in modes) id: prefs.getInt('leaderboard_pts_$id') ?? 0};
  }

  /// Timpul rămas până la resetul ciclului curent.
  static Future<Duration> leaderboardPeriodRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    await _ensureLeaderboardPeriod(prefs);
    final start = prefs.getInt(_leaderboardPeriodStartKey)!;
    final elapsed = DateTime.now().millisecondsSinceEpoch - start;
    final remaining = const Duration(hours: leaderboardPeriodHours).inMilliseconds - elapsed;
    return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
  }

  // ─── Contoare permanente (folosite de Achievements) ───────────────────────

  static Future<int> getHintsUsedTotal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_hintsUsedTotalKey) ?? 0;
  }

  static Future<void> incrementHintsUsedTotal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hintsUsedTotalKey, (prefs.getInt(_hintsUsedTotalKey) ?? 0) + 1);
  }

  static Future<int> getQuestsClaimedTotal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_questsClaimedTotalKey) ?? 0;
  }

  static Future<int> getDailyChallengesTotal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_dailyChallengesTotalKey) ?? 0;
  }

  static Future<Set<String>> getModesEverPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_modesEverPlayedKey)?.toSet() ?? {};
  }

  static Future<void> recordModeEverPlayed(String gameModeId) async {
    final prefs = await SharedPreferences.getInstance();
    final set = prefs.getStringList(_modesEverPlayedKey)?.toSet() ?? <String>{};
    if (set.add(gameModeId)) {
      await prefs.setStringList(_modesEverPlayedKey, set.toList());
    }
  }

  // ─── Achievements (realizări permanente) ──────────────────────────────────

  static Future<bool> isAchievementClaimed(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('achievement_claimed_$id') ?? false;
  }

  /// Marchează realizarea ca revendicată — NU scrie efectiv coins/xp/gems/
  /// vieți/hints în balanțe (aceeași convenție ca la [claimQuest]: apelantul
  /// aplică recompensa prin collectRewards, ca să nu se acorde de două ori
  /// și ca fiecare resursă să aibă animația ei, nu doar monedele).
  static Future<void> claimAchievement(String achievementId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('achievement_claimed_$achievementId', true);
  }

  static const _achievementsDoneKnownKey = 'achievements_done_known';

  /// Construiește funcția care dă progresul curent al fiecărei realizări,
  /// citind toate contoarele o singură dată — sursă unică folosită atât de
  /// [checkNewlyCompletedAchievements] cât și de [hasClaimableAchievements].
  static Future<int Function(Achievement)> _achievementProgressResolver() async {
    final prefs = await SharedPreferences.getInstance();
    final answeredCount = (prefs.getStringList(_answeredKey) ?? []).length;
    final level = levelForXp(prefs.getInt(_xpKey) ?? 0);
    final modesPlayed = (prefs.getStringList(_modesEverPlayedKey) ?? []).length;
    final hintsUsed = prefs.getInt(_hintsUsedTotalKey) ?? 0;
    final questsClaimed = prefs.getInt(_questsClaimedTotalKey) ?? 0;
    final dailyChallenges = prefs.getInt(_dailyChallengesTotalKey) ?? 0;
    final starterPackBought = prefs.getBool(_starterPackBoughtKey) ?? false;
    return (Achievement a) => switch (a.id) {
          'correct_50' || 'correct_150' || 'correct_400' => answeredCount,
          'level_5' || 'level_15' => level,
          'all_modes' => modesPlayed,
          'hints_50' => hintsUsed,
          'quests_25' => questsClaimed,
          'daily_10' => dailyChallenges,
          'starter_pack_bought' => starterPackBought ? 1 : 0,
          _ => 0,
        };
  }

  /// Recalculează progresul tuturor realizărilor și le compară cu ultima
  /// stare cunoscută — întoarce cele care tocmai au trecut de țintă (de
  /// obicei gol sau un singur element), ca să poți arăta o notificare
  /// in-app exact în momentul în care se întâmplă, indiferent de ecran.
  /// Nu marchează nimic ca revendicat — doar ca "deja anunțat".
  static Future<List<Achievement>> checkNewlyCompletedAchievements() async {
    final prefs = await SharedPreferences.getInstance();
    final progressFor = await _achievementProgressResolver();

    final knownDone = prefs.getStringList(_achievementsDoneKnownKey)?.toSet() ?? <String>{};
    final newlyDone = <Achievement>[];
    for (final a in achievements) {
      final done = progressFor(a) >= a.target;
      if (done && !knownDone.contains(a.id)) {
        newlyDone.add(a);
        knownDone.add(a.id);
      }
    }
    if (newlyDone.isNotEmpty) {
      await prefs.setStringList(_achievementsDoneKnownKey, knownDone.toList());
    }
    return newlyDone;
  }

  /// True dacă vreo realizare are ținta atinsă și încă nerevendicată —
  /// folosit pentru punctul roșu de notificare de pe tab-ul Profil și de pe
  /// rândul "Realizări" din profil.
  static Future<bool> hasClaimableAchievements() async {
    final progressFor = await _achievementProgressResolver();
    for (final a in achievements) {
      if (progressFor(a) >= a.target && !await isAchievementClaimed(a.id)) return true;
    }
    return false;
  }

  /// DEV: aduce progresul TUTUROR quest-urilor zilnice și realizărilor
  /// permanente la prag (gata de "Revendică"), fără să marcheze nimic ca
  /// deja revendicat — apelat de butonul "UNLIMITED" din Settings, ca
  /// animațiile de recompensă să poată fi testate fără să mai fie nevoie să
  /// joci efectiv pentru fiecare quest în parte.
  ///
  /// Quest-urile zilnice împart adesea același metricKey cu ținte diferite
  /// (ex. "answer_15"/"answer_25" pe "answer_count") — de-aia calculăm mai
  /// întâi MAXIMUL țintelor per metricKey, nu doar ultimul quest procesat,
  /// altfel cel cu ținta mai mare ar rămâne sub prag.
  ///
  /// Realizările nu au un progres stocat separat — se calculează live din
  /// contoarele reale (vezi [_achievementProgressResolver]), deci aici doar
  /// aducem acele contoare la nivelul necesar (niciodată în jos, doar dacă
  /// sunt deja sub prag).
  ///
  /// XP-ul NU se mai atinge (înainte era pus pe 100.000, ceea ce arunca
  /// jucătorul direct la nivelul 17) — cerut explicit. Consecință acceptată:
  /// realizările pe nivel (level_5 / level_15) nu se mai pot aduce la prag
  /// din acest buton, trebuie jucat până acolo.
  static Future<void> debugUnlockAllQuestsAndAchievements() async {
    final prefs = await SharedPreferences.getInstance();

    final maxTargetByMetric = <String, int>{};
    for (final q in todaysQuests()) {
      final current = maxTargetByMetric[q.metricKey] ?? 0;
      if (q.target > current) maxTargetByMetric[q.metricKey] = q.target;
    }
    for (final entry in maxTargetByMetric.entries) {
      await prefs.setInt(_questProgressKey(entry.key), entry.value);
    }

    final answered = prefs.getStringList(_answeredKey) ?? [];
    if (answered.length < 400) {
      final padded = List<String>.of(answered);
      for (var i = answered.length; i < 400; i++) {
        padded.add('debug_answered_$i');
      }
      await prefs.setStringList(_answeredKey, padded);
    }
    final modes = (prefs.getStringList(_modesEverPlayedKey) ?? []).toSet();
    modes.addAll(gameModes.map((m) => m.id));
    await prefs.setStringList(_modesEverPlayedKey, modes.toList());
    if ((prefs.getInt(_hintsUsedTotalKey) ?? 0) < 50) {
      await prefs.setInt(_hintsUsedTotalKey, 50);
    }
    if ((prefs.getInt(_questsClaimedTotalKey) ?? 0) < 25) {
      await prefs.setInt(_questsClaimedTotalKey, 25);
    }
    if ((prefs.getInt(_dailyChallengesTotalKey) ?? 0) < 10) {
      await prefs.setInt(_dailyChallengesTotalKey, 10);
    }
    await prefs.setBool(_starterPackBoughtKey, true);
  }

  // ─── Nume afișat (multiplayer) ─────────────────────────────────────────────
  // Jocul n-are cont/profil — doar un nume local, generat o singură dată,
  // folosit ca sa te recunoasca ceilalti jucatori intr-o camera/meci.

  static Future<String> getDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_displayNameKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = 'Jucator${100 + DateTime.now().millisecondsSinceEpoch % 900}';
    await prefs.setString(_displayNameKey, generated);
    return generated;
  }

  static Future<void> setDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name);
  }

  // ─── Sincronizare cloud (cont Google) ──────────────────────────────────────
  // Generic, nu camp-cu-camp: orice cheie noua adaugata in viitor (achievement
  // nou, quest nou etc.) se sincronizeaza automat, fara alt cod aici.

  static Future<Map<String, dynamic>> exportAll() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      map[key] = prefs.get(key);
    }
    return map;
  }

  static Future<void> importAll(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is String) {
        await prefs.setString(entry.key, value);
      } else if (value is int) {
        await prefs.setInt(entry.key, value);
      } else if (value is double) {
        await prefs.setDouble(entry.key, value);
      } else if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else if (value is List) {
        await prefs.setStringList(entry.key, value.cast<String>());
      }
    }
  }
}
