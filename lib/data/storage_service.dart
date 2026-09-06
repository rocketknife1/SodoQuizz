import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/game_helpers.dart';
import '../core/gamemodes.dart';
import '../core/progression.dart';
import 'device_notification_service.dart';
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
  static const _adminAnswerRevealKey = 'admin_answer_reveal';
  static const _equippedFrameKey = 'equipped_frame';
  static const _equippedTitleKey = 'equipped_title';
  static const _multiplayerInfoSeenKey = 'multiplayer_info_seen';
  static const _musicEnabledKey = 'music_enabled';
  static const _musicVolumeKey = 'music_volume';
  static const _hintsKey = 'hints_balance';
  static const _musicTrackKey = 'music_track_id';
  static const _languageKey = 'app_language';
  static const _notificationsKey = 'notifications_inbox';
  static const _notificationsReadKey = 'notifications_read_at';

  /// Crește la FIECARE schimbare de balanță (monede, gems, vieți, hint-uri,
  /// XP), indiferent de cauză: cumpărătură, premiu, roată, grant de la admin,
  /// reset, sau salvarea coborâtă din cloud. Ecranele care afișează resurse
  /// ascultă direct valoarea asta.
  ///
  /// A înlocuit `CloudSyncService.grantsApplied`, care anunța doar
  /// grant-urile de la admin și era ascultat doar de HomeScreen — un jucător
  /// aflat în Magazin rămânea cu cifrele vechi și primea „n-ai destui bani"
  /// pentru bani pe care îi avea deja.
  static final ValueNotifier<int> balanceRevision = ValueNotifier<int>(0);

  /// Cât timp e > 0, scrierile de balanță NU declanșează [balanceRevision] —
  /// marchează doar un bump în așteptare, eliberat la [releaseBalanceNotifications].
  ///
  /// De ce: animația de colectare a recompenselor (core/reward_collector.dart)
  /// scrie în storage ÎNAINTE de animație, intenționat (ca recompensa să nu se
  /// piardă dacă jucătorul iese din ecran). Fără pauza asta, badge-ul sărea la
  /// valoarea nouă imediat, cu ~1-2s înainte ca jetoanele animate să atingă
  /// pastila — colectarea părea ruptă („moneda n-a crescut", de fapt sărise
  /// deja când privirea era pe jetoane). Cu pauza, fiecare etapă a animației
  /// declanșează bump-ul explicit la IMPACT, prin [notifyBalanceChanged].
  static int _notifyHold = 0;
  static bool _bumpPending = false;

  static void holdBalanceNotifications() => _notifyHold++;

  static void releaseBalanceNotifications() {
    if (_notifyHold > 0) _notifyHold--;
    if (_notifyHold == 0 && _bumpPending) {
      _bumpPending = false;
      balanceRevision.value++;
    }
  }

  /// Doar pentru teste: golește pauza, oricâte `hold`-uri ar fi rămase.
  /// Fără ea, un test care pică în mijlocul unui hold lasă `_notifyHold > 0`
  /// și TOATE testele ulterioare din același proces care se bazează pe
  /// `balanceRevision` pică în cascadă, mascând cauza reală.
  @visibleForTesting
  static void resetBalanceNotificationsForTest() {
    _notifyHold = 0;
    _bumpPending = false;
  }

  /// Bump forțat, ignoră pauza — folosit la IMPACTUL fiecărei etape de
  /// colectare, ca badge-ul să se miște exact când jetonul aterizează.
  static void notifyBalanceChanged() {
    _bumpPending = false;
    balanceRevision.value++;
  }

  /// SINGURA cale prin care se scrie o cheie de balanță. Regula, pe termen
  /// lung: `prefs.setInt` pe `_coinsKey`/`_gemsKey`/`_livesKey`/`_hintsKey`/
  /// `_xpKey` nu se mai folosește nicăieri. Așa nu poate exista o funcție
  /// nouă care schimbă balanța și uită să anunțe ecranele.
  static Future<void> _writeBalance(SharedPreferences prefs, String key, int value) async {
    await prefs.setInt(key, value);
    if (_notifyHold > 0) {
      _bumpPending = true;
      return;
    }
    balanceRevision.value++;
  }

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

  // ─── Meciul multiplayer activ (pentru butonul de reconectare) ────────────
  // Scris de fiecare ecran de meci la intrare, sters la iesire normala. La
  // pornire / revenire in prim-plan, MultiplayerService.checkReconnect il
  // citeste si verifica pe server daca meciul mai e in desfasurare.
  static const _activeMatchIdKey = 'active_match_id';
  static const _activeMatchModeKey = 'active_match_mode';

  static Future<void> setActiveMatch(String matchId, String modeName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeMatchIdKey, matchId);
    await prefs.setString(_activeMatchModeKey, modeName);
  }

  /// `(matchId, modeName)` sau `null`.
  static Future<(String, String)?> getActiveMatch() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_activeMatchIdKey);
    final mode = prefs.getString(_activeMatchModeKey);
    if (id == null || id.isEmpty || mode == null) return null;
    return (id, mode);
  }

  static Future<void> clearActiveMatch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeMatchIdKey);
    await prefs.remove(_activeMatchModeKey);
  }
  static const _gemGiftTimestampKey = 'gem_gift_timestamp';
  static const _clippyNextReadyKey = 'clippy_next_ready_at';
  static const _displayNameKey = 'display_name';
  static const _displayNameChosenKey = 'display_name_chosen';
  static const _forcedNameKey = 'forced_name';
  static const _avatarStyleKey = 'avatar_style';
  static const _gemsKey = 'gems';
  static const _lastClaimedRewardLevelKey = 'last_claimed_reward_level';
  static const _xpCurveMigratedKey = 'xp_curve_migrated_v2';
  static const _xpCurveV3MigratedKey = 'xp_curve_migrated_v3';
  static const _pixelatToCartoonMigratedKey = 'pixelat_to_cartoon_migrated';

  /// Tutorialul de la prima pornire a fost văzut (sau sărit). Vezi
  /// screens/welcome_screen.dart — apare O SINGURĂ DATĂ.
  static const _introSeenKey = 'intro_seen';
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
  static const _activityEventsKey = 'activity_events';
  static const _planetRunsUsedKey = 'planet_runs_used';
  static const _planetAdUnlockedKey = 'planet_ad_unlocked';
  static const _planetCooldownUntilKey = 'planet_cooldown_until';
  static const _cloudPushSnapshotKey = 'cloud_push_snapshot';

  /// Chei pur locale, care NU pleacă niciodată în cloud (vezi [exportAll]).
  /// [_cloudPushSnapshotKey] e amprenta ultimei urcări, deci e derivată din
  /// export: dacă ar face parte din el, s-ar auto-invalida la fiecare urcare
  /// (amprenta nouă schimbă exportul, care cere altă urcare, la nesfârșit) —
  /// exact optimizarea pe care o servește ar deveni imposibilă.
  static const _localOnlyKeys = <String>[_cloudPushSnapshotKey];

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
    await _writeBalance(prefs, _livesKey, clamped);
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
      // NU prin [_writeBalance]: regenerarea pasivă e declanșată din CITIRI
      // (getLives / livesRechargeRemaining), iar un `balanceRevision++` sincron
      // acolo face ca un ecran care tocmai recitea balanța (ca reacție la o
      // notificare anterioară) să reintre și să-și arunce propria încărcare.
      // Scriem direct și marcăm bump-ul; îl culege următoarea notificare reală
      // sau următoarea încărcare de ecran.
      await prefs.setInt(_livesKey, newLives);
      _bumpPending = true;
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

  // ─── Semne de activitate ─────────────────────────────────────────────────
  // Un contor local care crește la fiecare gest ce dovedește că cineva chiar
  // a deschis jocul și a făcut ceva: o rotire de roată sau orice mișcare de
  // balanță (monede/gems, în plus sau în minus). Urcă în profilul public la
  // fiecare heartbeat (vezi PlayerProfileService.ensureProfileHeartbeat),
  // fiindcă ștergerea automată a conturilor Guest abandonate se decide pe
  // server, din firestore.rules — iar acolo se poate citi DOAR profilul
  // public, nu și salvarea privată din cloud.
  //
  // Vieţile și hint-urile NU intră aici, deliberat: vieţile se reîncarcă
  // singure în timp (vezi [_rechargeLives]), deci ar marca drept "activ" un
  // cont pe care nu l-a atins nimeni.

  static Future<int> getActivityEvents() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_activityEventsKey) ?? 0;
  }

  /// Primește [prefs] deja deschis, ca apelanții (care tocmai au scris o
  /// balanță) să nu mai ceară încă o instanță.
  static Future<void> _recordActivity(SharedPreferences prefs) async {
    await prefs.setInt(_activityEventsKey, (prefs.getInt(_activityEventsKey) ?? 0) + 1);
  }

  // ─── Monede ──────────────────────────────────────────────────────────────

  static Future<int> getCoins() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_coinsKey) ?? _startingCoins;
  }

  /// Zero e un caz real, nu o greșeală de apelant — o rundă terminată fără
  /// niciun răspuns corect, un pot de multiplayer pierdut. Se iese devreme ca
  /// să nu treacă drept mișcare de balanță (vezi [_recordActivity]) și ca să
  /// nu se scrie degeaba aceeași valoare înapoi.
  static Future<void> addCoins(int amount) async {
    if (amount == 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_coinsKey) ?? _startingCoins;
    await _writeBalance(prefs, _coinsKey, current + amount);
    await _recordActivity(prefs);
  }

  static Future<bool> spendCoins(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_coinsKey) ?? _startingCoins;
    if (current < amount) return false;
    await _writeBalance(prefs, _coinsKey, current - amount);
    await _recordActivity(prefs);
    return true;
  }

  /// Delta cu semn (pozitiv sau negativ), plafonat doar inferior la 0 — spre
  /// deosebire de [addCoins]/[spendCoins], care presupun un sens fix.
  /// Folosit DOAR de CloudSyncService.consumePendingGrant (grant-uri de
  /// admin), unde cantitatea poate fi și o "luare" de monede.
  /// Numără și ca semn de activitate (vezi [_recordActivity]), deși vine de
  /// la admin, nu de la jucător — un cont pe care adminul a pus mâna nu
  /// trebuie măturat automat ca abandonat.
  static Future<void> adjustCoins(int delta) async {
    if (delta == 0) return;
    final prefs = await SharedPreferences.getInstance();
    final updated = (prefs.getInt(_coinsKey) ?? _startingCoins) + delta;
    await _writeBalance(prefs, _coinsKey, updated < 0 ? 0 : updated);
    await _recordActivity(prefs);
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
    await _writeBalance(prefs, _gemsKey, current + amount);
    await _recordActivity(prefs);
  }

  static Future<bool> spendGems(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_gemsKey) ?? starterGemGrant;
    if (current < amount) return false;
    await _writeBalance(prefs, _gemsKey, current - amount);
    await _recordActivity(prefs);
    return true;
  }

  /// Vezi [adjustCoins] — același tipar, pentru gems.
  static Future<void> adjustGems(int delta) async {
    if (delta == 0) return;
    final prefs = await SharedPreferences.getInstance();
    final updated = (prefs.getInt(_gemsKey) ?? starterGemGrant) + delta;
    await _writeBalance(prefs, _gemsKey, updated < 0 ? 0 : updated);
    await _recordActivity(prefs);
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
    await _writeBalance(prefs, _hintsKey, updated);
  }

  /// Fără plafon — folosit DOAR pentru achiziții cu bani reali (vezi Shop).
  /// Plafonul [_hintsCap] există ca hint-urile gratuite "să fie folosite, nu
  /// doar strânse" — regula aia n-ar trebui să trunchieze un pachet plătit.
  static Future<void> addHintsUncapped(int amount) async {
    if (amount <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_hintsKey) ?? _startingHints;
    await _writeBalance(prefs, _hintsKey, current + amount);
  }

  /// Vezi [adjustCoins] — același tipar, pentru hint-uri (fără plafonul
  /// [_hintsCap], la fel ca [addHintsUncapped]).
  static Future<void> adjustHints(int delta) async {
    if (delta == 0) return;
    final prefs = await SharedPreferences.getInstance();
    final updated = (prefs.getInt(_hintsKey) ?? _startingHints) + delta;
    await _writeBalance(prefs, _hintsKey, updated < 0 ? 0 : updated);
  }

  /// Consumă 1 hint din balanța persistată — întoarce false dacă nu mai ai.
  static Future<bool> spendHint() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_hintsKey) ?? _startingHints;
    if (current <= 0) return false;
    await _writeBalance(prefs, _hintsKey, current - 1);
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
    await _writeBalance(prefs, _xpKey, current + amount);
  }

  /// Vezi [adjustCoins] — același tipar, pentru XP (deci poate scădea și
  /// nivelul afișat, spre deosebire de restul jocului unde XP-ul nu scade
  /// niciodată — acceptabil doar aici, un grant de admin poate fi corectat).
  static Future<void> adjustXp(int delta) async {
    if (delta == 0) return;
    final prefs = await SharedPreferences.getInstance();
    await _migrateXpCurveIfNeeded(prefs);
    final updated = (prefs.getInt(_xpKey) ?? 0) + delta;
    await _writeBalance(prefs, _xpKey, updated < 0 ? 0 : updated);
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
        await _writeBalance(prefs, _xpKey, migratedXp);
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
      await _writeBalance(prefs, _xpKey, (xp / _xpRateV3Divisor).round());
    }
    await prefs.setInt(
        _lastClaimedRewardLevelKey, levelForXp(prefs.getInt(_xpKey) ?? 0));
    await prefs.setBool(_xpCurveV3MigratedKey, true);
  }

  /// Redenumire 2026-08-19: modul "Cartoon" (desene animate & filme) avea
  /// id-ul intern 'pixelat', rămas dintr-o vreme când categoria chiar folosea
  /// imagini pixelate — nu se mai potrivea deloc cu conținutul actual (poze
  /// reale de personaje). Noul id e 'cartoon' (vezi gamemodes.dart). Fără
  /// migrarea asta, jucătorii cu progres deja salvat sub cheia veche și-ar
  /// pierde la următorul update nivelul de întrebări deblocate la această
  /// categorie, recordul all-time și punctele de clasament din ciclul curent
  /// — restul contului (monede, gems, alte categorii) nu e atins deloc.
  static Future<void> migratePixelatIdToCartoon() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_pixelatToCartoonMigratedKey) ?? false) return;

    Future<void> moveInt(String oldKey, String newKey) async {
      final value = prefs.getInt(oldKey);
      if (value != null && prefs.getInt(newKey) == null) {
        await prefs.setInt(newKey, value);
      }
    }

    await moveInt('question_unlock_tier_pixelat', 'question_unlock_tier_cartoon');
    await moveInt('high_score_pixelat', 'high_score_cartoon');
    await moveInt('leaderboard_pts_pixelat', 'leaderboard_pts_cartoon');

    final starters = prefs.getStringList(_starterCategoriesKey);
    if (starters != null && starters.contains('pixelat')) {
      await prefs.setStringList(_starterCategoriesKey,
          starters.map((m) => m == 'pixelat' ? 'cartoon' : m).toList());
    }

    final leaderboardModes = prefs.getStringList(_leaderboardModesKey);
    if (leaderboardModes != null && leaderboardModes.contains('pixelat')) {
      final updated = leaderboardModes.toSet()
        ..remove('pixelat')
        ..add('cartoon');
      await prefs.setStringList(_leaderboardModesKey, updated.toList());
    }

    final everPlayed = prefs.getStringList(_modesEverPlayedKey);
    if (everPlayed != null && everPlayed.contains('pixelat')) {
      final updated = everPlayed.toSet()..add('cartoon');
      await prefs.setStringList(_modesEverPlayedKey, updated.toList());
    }

    await prefs.setBool(_pixelatToCartoonMigratedKey, true);
  }

  // ─── Reward-uri de Level Up ─────────────────────────────────────────────
  // Fiecare nivel are un reward dedicat (vezi [levelReward]) — nu se acordă
  // automat, ci se colectează manual (bara de XP din LevelHeader). Nimic nu
  // se pierde dacă treci mai multe niveluri fără să colectezi: se ține minte
  // doar ultimul nivel revendicat, restul se calculează la cerere.

  static Future<int> getPendingLevelRewardsCount() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateXpCurveIfNeeded(prefs);
    final currentLevel = levelForXp(prefs.getInt(_xpKey) ?? 0);
    final lastClaimed = (prefs.getInt(_lastClaimedRewardLevelKey) ?? currentLevel).clamp(0, currentLevel);
    return currentLevel - lastClaimed;
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
    // clamp la [0, currentLevel]: apără de o valoare coruptă/negativă ajunsă
    // aici prin importAll (sincronizare cloud brută, fără validare de domeniu
    // — vezi importAll mai jos), care ar face bucla de mai jos sa itereze un
    // interval enorm.
    final lastClaimed = (prefs.getInt(_lastClaimedRewardLevelKey) ?? currentLevel).clamp(0, currentLevel);
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

  /// Șterge tot progresul salvat (folosit din ecranul de profil).
  static Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    // `prefs.clear()` nu trece prin [_writeBalance] — nu scrie nicio cheie,
    // le șterge. Balanța se schimbă totuși (getterele cad pe valorile de
    // start), deci ecranele trebuie anunțate explicit.
    balanceRevision.value++;
  }

  /// Cheile care SUPRAVIEȚUIESC unui reset pornit de admin (vezi
  /// [resetToStartingBalance]) — nu sunt progres, deci n-au ce căuta la zero:
  /// preferințe (sunet, blur, tutoriale deja văzute), numele afișat (altfel
  /// jucătorul s-ar trezi redenumit în leaderboard, vezi
  /// PlayerProfileService.ensureProfileHeartbeat) și marcajul "fără reclame"
  /// (o dată devenit achiziție cu bani reali — vezi shop.dart — un tap greșit
  /// din admin n-ar mai fi reparabil).
  static const _resetPreservedKeys = <String>[
    _displayNameKey,
    // Fără ea, un reset de admin ar păstra numele ales (e chiar deasupra) dar
    // ar pierde marcajul că a fost ales — iar jucătorul ar cădea înapoi pe
    // numele din contul Google, adică ar fi REDENUMIT în tăcere de o simplă
    // apăsare pe „Reset". Cele două chei trebuie să călătorească împreună.
    _displayNameChosenKey,
    _avatarStyleKey,
    _musicEnabledKey,
    _musicVolumeKey,
    _noBlurKey,
    _adminAnswerRevealKey,
    _multiplayerInfoSeenKey,
    _noAdsForeverKey,
    // Limba e preferință de afișare, nu progres — un reset de cont n-are de ce
    // să repună jocul în română unui jucător străin.
    _languageKey,
    _musicTrackKey,
  ];

  /// Aduce contul de pe TELEFONUL ACESTA în starea unui jucător nou: tot
  /// progresul (XP/nivel, întrebări răspunse, quest-uri, realizări, serii,
  /// highscore-uri, categorii deblocate) dispare, iar balanța revine la
  /// zestrea de start — [_startingCoins] monede, [_startingLives] vieți,
  /// [_startingHints] hint-uri, [starterGemGrant] gems.
  ///
  /// Nu scrie balanțele explicit, ci ȘTERGE cheile: fiecare getter de mai sus
  /// cade oricum pe valoarea de start când cheia lipsește, deci așa nu poate
  /// rămâne un al doilea set de valori "de start" care s-ar desincroniza tăcut
  /// de cel real la următoarea reglare a economiei.
  ///
  /// Apelat de CloudSyncService.consumePendingGrant, când adminul a cerut un
  /// reset din fișa jucătorului (AdminScreen) — la jucător ajunge cel târziu
  /// la următoarea deschidere a jocului, ca orice grant de resurse.
  static Future<void> resetToStartingBalance() async {
    final prefs = await SharedPreferences.getInstance();
    final preserved = <String, dynamic>{};
    for (final key in _resetPreservedKeys) {
      final value = prefs.get(key);
      if (value != null) preserved[key] = value;
    }
    await prefs.clear();
    await importAll(preserved);
    // Vezi nota din [resetAll]: ștergerea de chei nu produce nicio scriere
    // de balanță, dar schimbă tot ce se vede pe ecran.
    balanceRevision.value++;
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
    await _recordActivity(prefs);
    // Consumat cu aplicația în prim-plan: reprogramează notificarea acum, nu
    // abia la trecerea în fundal — altfel alarma veche sună degeaba peste
    // câteva minute pentru ceva deja consumat.
    unawaited(DeviceNotificationService.instance.rescheduleAll());
  }

  // ─── Cadoul de gems „din partea casei" ────────────────────────────────────
  // Era un simplu MESAJ care se stingea singur când scădea soldul. Acum e un
  // buton de revendicat, care revine la [gemGiftCooldownHours] (vezi
  // core/shop_gifts.dart pentru cât și DE CE atât).
  //
  // Acelaşi tipar ca la roată: timestamp, nu dată calendaristică — cine
  // revendică seara nu trebuie să aştepte până a doua zi dimineaţa.
  // Prima revendicare e mereu disponibilă (fără timestamp), deci jucătorul
  // nou primeşte cadoul de pornire chiar de la prima deschidere.

  static Future<bool> canClaimGemGift() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_gemGiftTimestampKey);
    if (last == null) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    return elapsed >= const Duration(hours: gemGiftCooldownHours).inMilliseconds;
  }

  /// Timpul rămas până la următorul cadou (zero dacă e deja disponibil).
  static Future<Duration> gemGiftTimeRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_gemGiftTimestampKey);
    if (last == null) return Duration.zero;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    final remaining = const Duration(hours: gemGiftCooldownHours).inMilliseconds - elapsed;
    return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
  }

  /// ȚINE MINTE că s-a revendicat — gems-ii îi scrie apelantul, aceeași
  /// convenție ca la quest-uri și la categoria zilei.
  static Future<void> recordGemGiftClaim() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_gemGiftTimestampKey, DateTime.now().millisecondsSinceEpoch);
    await _recordActivity(prefs);
  }

  // ─── Notificarea lui Clippy (bonus cu 3 întrebări, la fiecare 5 minute) ────
  // Persistat (nu doar în memoria widget-ului), ca să supraviețuiască
  // navigării între tab-uri (Home se recreează la fiecare schimbare de tab
  // din bottom nav) — altfel notificarea se pierdea/reseta la revenirea pe
  // Home, deși încă era valabilă.
  //
  // Peste cooldown-ul de 5 minute există și un plafon zilnic DUR de
  // [clippyDailyPlayLimit] runde (contorul zilnic `clippy_rounds`, incrementat
  // de ClippyBonusScreen la finalul efectiv al unei runde). Odată consumate
  // toate, Clippy nu mai e disponibil deloc până după miezul nopții — vezi
  // [clippyPlaysLeftToday] / [clippyNextDayRemaining], afișate sub mascotă.

  static const clippyReadyIntervalSeconds = 5 * 60;

  /// Câte runde mai are jucătorul azi (0..[clippyDailyPlayLimit]).
  static Future<int> clippyPlaysLeftToday() async {
    final used = await getDailyCounter('clippy_rounds');
    final left = clippyDailyPlayLimit - used;
    return left > 0 ? left : 0;
  }

  static Future<bool> isClippyReady() async {
    // plafonul zilnic bate cooldown-ul: la 0 runde rămase nu mai contează cât
    // timp a trecut de la ultima rundă.
    if (await clippyPlaysLeftToday() <= 0) return false;
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

  /// Cât mai e până la miezul nopții — cât timp Clippy stă blocat după ce
  /// s-au consumat toate rundele zilei (contoarele zilnice sunt scoped pe
  /// data calendaristică, deci se eliberează exact la 00:00).
  static Duration clippyNextDayRemaining() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    return midnight.difference(now);
  }

  /// Repornește așteptarea pentru următoarea notificare — apelat DOAR când
  /// jucătorul termină efectiv bonusul (nu la simpla intrare), ca notificarea
  /// să rămână activă dacă a intrat și a ieșit fără să termine.
  static Future<void> resetClippyCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_clippyNextReadyKey, DateTime.now().millisecondsSinceEpoch + clippyReadyIntervalSeconds * 1000);
    unawaited(DeviceNotificationService.instance.rescheduleAll());
  }

  // ─── Daily Challenge (mini-quiz special, o dată pe zi) ─────────────────────

  static Future<void> markDailyChallengeDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyChallengeKey, _dateKey(DateTime.now()));
    await prefs.setInt(_dailyChallengesTotalKey, (prefs.getInt(_dailyChallengesTotalKey) ?? 0) + 1);
  }

  static String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  // ─── Provocarea Zilei (set fix de 5, o dată pe zi — vezi
  //     core/daily_challenge.dart) ────────────────────────────────────────────
  // Stocat ca „<dateKey>:<intrebareUrmatoare>:<corecte>:<gata0sau1>".
  //
  // DE CE progresul, nu doar scorul final: fără el, cine răspundea la 3 din 5
  // şi închidea aplicaţia din recente revenea la un start curat şi rejuca tot
  // — o cale de trişat (rerulezi până iese bine). Acum, la PRIMUL răspuns ziua
  // e marcată ca începută, iar la revenire se reia de la întrebarea unde a
  // rămas. Scorul „adevărat" pentru clasament e în Firestore, scris la final.
  //
  // Formatul vechi „<dateKey>:<corecte>" (2 câmpuri) e citit ca „gata".
  static const _dailyChallengeRunKey = 'daily_challenge_run';

  static ({int nextIndex, int correct, bool done})? _parseDailyChallenge(
      String? raw, String todayKey) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.isEmpty || parts.first != todayKey) return null;
    if (parts.length == 2) {
      // format vechi: doar scorul final
      final c = int.tryParse(parts[1]);
      return c == null ? null : (nextIndex: c, correct: c, done: true);
    }
    if (parts.length < 4) return null;
    final nextIndex = int.tryParse(parts[1]) ?? 0;
    final correct = int.tryParse(parts[2]) ?? 0;
    return (nextIndex: nextIndex, correct: correct, done: parts[3] == '1');
  }

  /// Câte răspunsuri corecte a dat azi la Provocarea Zilei DACĂ a terminat-o,
  /// sau `null` dacă n-a terminat-o azi (neîncepută SAU în curs).
  /// [todayKey] e `dailyChallengeDateKey(DateTime.now())`.
  static Future<int?> dailyChallengeResultFor(String todayKey) async {
    final prefs = await SharedPreferences.getInstance();
    final p = _parseDailyChallenge(prefs.getString(_dailyChallengeRunKey), todayKey);
    return (p != null && p.done) ? p.correct : null;
  }

  /// Progresul de azi: de la ce întrebare se reia ([nextIndex]), câte corecte
  /// are până acum, şi dacă a terminat. `null` dacă n-a început-o azi.
  static Future<({int nextIndex, int correct, bool done})?>
      dailyChallengeProgressFor(String todayKey) async {
    final prefs = await SharedPreferences.getInstance();
    return _parseDailyChallenge(prefs.getString(_dailyChallengeRunKey), todayKey);
  }

  /// După fiecare răspuns: salvează unde s-a ajuns, ca o închidere a aplicaţiei
  /// să nu şteargă progresul. NU marchează ziua ca terminată.
  static Future<void> recordDailyChallengeProgress(
      String todayKey, int nextIndex, int correct) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyChallengeRunKey, '$todayKey:$nextIndex:$correct:0');
  }

  /// Notează rularea de azi ca TERMINATĂ. Bumpează şi contorul pentru
  /// `daily_10` (prin [markDailyChallengeDone]).
  static Future<void> recordDailyChallengeRun(String todayKey, int correct) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyChallengeRunKey, '$todayKey:$correct:$correct:1');
    await markDailyChallengeDone();
    await _recordActivity(prefs);
  }

  // ─── Recompensa de sfârşit de sezon (vezi core/season_rewards.dart) ────────
  // `_pendingSeasonRewardKey` = "<seasonKey>:<tierIndex>" cât timp e una
  // nerevendicată; `_seasonRewardHandledKey` = ultimul sezon pe care l-am
  // fotografiat deja (ca să nu-l re-fotografiez la fiecare pornire).
  static const _pendingSeasonRewardKey = 'pending_season_reward';
  static const _seasonRewardHandledKey = 'season_reward_handled';

  static Future<({String season, int tier})?> pendingSeasonReward() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingSeasonRewardKey);
    if (raw == null || raw.isEmpty) return null;
    final i = raw.lastIndexOf(':');
    if (i <= 0) return null;
    final tier = int.tryParse(raw.substring(i + 1));
    if (tier == null) return null;
    return (season: raw.substring(0, i), tier: tier);
  }

  static Future<void> setPendingSeasonReward(String season, int tier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingSeasonRewardKey, '$season:$tier');
  }

  static Future<void> clearPendingSeasonReward() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingSeasonRewardKey);
  }

  static Future<String> seasonRewardHandledKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_seasonRewardHandledKey) ?? '';
  }

  static Future<void> setSeasonRewardHandled(String season) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_seasonRewardHandledKey, season);
  }

  // ─── Jucători recenţi (adversari din meciuri) ─────────────────────────────
  // Listă locală de până la [_recentOpponentsCap], cel mai recent primul,
  // deduplicată pe uid. Pentru secţiunea „Adaugă-i ca prieteni" din ecranul
  // de Prieteni — `completed_matches` NU ţine uid-urile adversarilor, aici e
  // singurul loc unde se ştiu.
  static const _recentOpponentsKey = 'recent_opponents';
  static const _recentOpponentsCap = 15;

  /// O singură cheie, un JSON: listă de `{uid, name, seed, photo?}`.
  static Future<List<Map<String, String>>> getRecentOpponents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentOpponentsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          if (e is Map)
            {
              'uid': '${e['uid'] ?? ''}',
              'name': '${e['name'] ?? '?'}',
              'seed': '${e['seed'] ?? ''}',
              if (e['photo'] != null && '${e['photo']}'.isNotEmpty)
                'photo': '${e['photo']}',
            },
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Adaugă adversarii unui meci în capul listei (dedup pe uid, plafonat la
  /// [_recentOpponentsCap]). [opponents] = intrări cu chei uid/name/seed/photo?.
  static Future<void> addRecentOpponents(List<Map<String, String>> opponents) async {
    if (opponents.isEmpty) return;
    final current = await getRecentOpponents();
    final seen = <String>{};
    final merged = <Map<String, String>>[];
    for (final o in [...opponents, ...current]) {
      final uid = o['uid'] ?? '';
      if (uid.isEmpty || !seen.add(uid)) continue;
      merged.add(o);
      if (merged.length >= _recentOpponentsCap) break;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recentOpponentsKey, jsonEncode(merged));
  }

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

  // ─── Planeta hologramelor: rulări și cooldown ─────────────────────────────
  // Ciclul e: [planetRunsPerCycle] rulări → cooldown de [planetCooldownHours]
  // ore. O reclamă vizionată ridică plafonul ciclului curent la
  // [planetRunsPerCycleWithAd] și anulează cooldown-ul tocmai pornit, deci
  // "2 rulări, sau 3 dacă te uiți la o reclamă" e o singură stare, nu două.
  //
  // Rularea se consumă la PRIMUL RĂSPUNS, nu la colectarea recompensei (vezi
  // PlanetHologramScreen._pick). Înainte se consuma la colectare, iar cine
  // ieșea din rulare înainte de final o primea înapoi — se putea intra,
  // pierde inimile, ieși și reintra la nesfârșit cu 2/2.
  //
  // Primul RĂSPUNS, nu deschiderea ecranului: cine intră din greșeală și iese
  // imediat nu pierde nimic; cine a început efectiv, a consumat. Recompensa
  // rămâne de colectat la final — se pierde doar dacă abandonezi, nu rularea.
  //
  // Spre deosebire de Clippy, ciclul NU e legat de ziua calendaristică: 12
  // ore înseamnă 12 ore, oricând ar fi început.

  static Future<int> _planetLimit(SharedPreferences prefs) async =>
      (prefs.getBool(_planetAdUnlockedKey) ?? false)
          ? planetRunsPerCycleWithAd
          : planetRunsPerCycle;

  /// Cât mai e din cooldown (zero dacă planeta e liberă). Trecerea peste zero
  /// resetează ciclul, deci se poate apela oricând, inclusiv din build.
  static Future<Duration> planetCooldownRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_planetCooldownUntilKey);
    if (until == null) return Duration.zero;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    if (left > 0) return Duration(milliseconds: left);
    // ciclul s-a încheiat — rulările și reclama se resetează împreună.
    await prefs.remove(_planetCooldownUntilKey);
    await prefs.setInt(_planetRunsUsedKey, 0);
    await prefs.setBool(_planetAdUnlockedKey, false);
    return Duration.zero;
  }

  /// Câte rulări are ciclul curent cu totul — 2 normal, 3 dacă s-a văzut
  /// reclama. Public fiindcă insigna de pe planetă arată „1 din 2", deci are
  /// nevoie și de numitor, nu doar de cât a rămas.
  static Future<int> planetRunsLimit() async =>
      _planetLimit(await SharedPreferences.getInstance());

  /// Câte rulări mai are jucătorul în ciclul curent (0 cât timp e cooldown).
  static Future<int> planetRunsLeft() async {
    if ((await planetCooldownRemaining()) > Duration.zero) return 0;
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getInt(_planetRunsUsedKey) ?? 0;
    final left = (await _planetLimit(prefs)) - used;
    return left > 0 ? left : 0;
  }

  /// True dacă mai poate fi oferită reclama pentru o rulare în plus — o
  /// singură dată per ciclu.
  static Future<bool> canWatchAdForPlanetRun() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_planetAdUnlockedKey) ?? false);
  }

  /// Reclama vizionată: ridică plafonul ciclului la
  /// [planetRunsPerCycleWithAd] și șterge cooldown-ul, ca rularea în plus să
  /// fie disponibilă imediat.
  static Future<void> unlockPlanetAdRun() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_planetAdUnlockedKey, true);
    await prefs.remove(_planetCooldownUntilKey);
  }

  /// Marchează o rulare consumată și, dacă era ultima permisă, pornește
  /// cooldown-ul. Se apelează DUPĂ colectarea recompensei.
  /// Consumă o rulare de planetă. Apelat la PRIMUL RĂSPUNS al rulării (vezi
  /// nota de sus), nu la colectarea recompensei. Când s-au consumat toate
  /// rulările ciclului, pornește și cooldown-ul.
  static Future<void> recordPlanetRunStarted() async {
    final prefs = await SharedPreferences.getInstance();
    final used = (prefs.getInt(_planetRunsUsedKey) ?? 0) + 1;
    await prefs.setInt(_planetRunsUsedKey, used);
    if (used >= await _planetLimit(prefs)) {
      await prefs.setInt(
        _planetCooldownUntilKey,
        DateTime.now()
            .add(const Duration(hours: planetCooldownHours))
            .millisecondsSinceEpoch,
      );
    }
    unawaited(DeviceNotificationService.instance.rescheduleAll());
  }

  // ─── Contoare pe VIAȚĂ, derivate din metricile de quest ───────────────────
  // Quest-urile își resetează progresul zilnic (cheie scoped pe dată), dar
  // realizările permanente au nevoie de totaluri care nu se resetează
  // niciodată. În loc să instrumentăm din nou fiecare loc din joc care deja
  // raportează un metric, [bumpQuestMetric] hrănește ȘI contorul de mai jos —
  // o singură cârlig, valabil pentru orice metric existent sau viitor.
  //
  // ATENȚIE: incrementarea se face ÎNAINTE de filtrul "e metricul ăsta activ
  // azi?" din bumpQuestMetric. Altfel, un metric care nu pică în rotația zilei
  // n-ar fi numărat deloc, iar realizările construite pe el ar avansa doar în
  // ~1 zi din 7.

  static String _lifetimeMetricKey(String metric) => 'lifetime_$metric';

  static Future<int> getLifetimeMetric(String metric) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lifetimeMetricKey(metric)) ?? 0;
  }

  static Future<void> addLifetimeMetric(String metric, int amount) async {
    if (amount <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _lifetimeMetricKey(metric);
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + amount);
  }

  static String _dailyCounterKey(String name) => 'daily_${name}_${_dateKey(DateTime.now())}';

  /// Sterge contoarele zilnice din zilele trecute.
  ///
  /// [_dailyCounterKey] scrie o cheie noua in fiecare zi si nimeni nu le
  /// stergea vreodata: dupa cateva luni un cont aduna sute de chei moarte
  /// (`daily_clippy_rounds_2026-8-5`, `..._2026-8-6`, ...), care se urcau si
  /// in `users/{uid}` la fiecare sincronizare, pentru ca [exportAll] trimite
  /// tot ce gaseste. Se pastreaza doar ziua curenta — un contor de ieri nu e
  /// citit niciodata, cheia lui contine data.
  static Future<void> pruneOldDailyCounters() async {
    final prefs = await SharedPreferences.getInstance();
    final azi = '_${_dateKey(DateTime.now())}';
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith('daily_') && !key.endsWith(azi)) {
        // `daily_claim_date`/`daily_challenge_date`/`daily_challenges_total`
        // incep tot cu "daily_" dar nu sunt contoare pe zi — nu au data in
        // nume, deci n-au voie sa cada aici.
        if (RegExp(r'_\d{4}-\d{1,2}-\d{1,2}$').hasMatch(key)) {
          await prefs.remove(key);
        }
      }
    }
  }

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

  // ─── „Vezi răspunsul corect" — DOAR admin (vezi core/admin_reveal.dart) ───
  // Colorează varianta corectă la orice întrebare cu 4 variante, oriunde în
  // joc. Pur vizual. Al doilea gard (emailul de admin) e în admin_reveal.dart:
  // pref-ul singur nu ajunge.

  static Future<bool> getAdminAnswerReveal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_adminAnswerRevealKey) ?? false;
  }

  static Future<void> setAdminAnswerReveal(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adminAnswerRevealKey, value);
  }

  // ─── Cosmeticul echipat (rama + titlu) — vezi core/cosmetics.dart ────────

  static Future<String> getEquippedFrame() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_equippedFrameKey) ?? 'none';
  }

  static Future<void> setEquippedFrame(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_equippedFrameKey, id);
  }

  static Future<String> getEquippedTitle() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_equippedTitleKey) ?? 'novice';
  }

  static Future<void> setEquippedTitle(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_equippedTitleKey, id);
  }

  // ─── Piesa de fundal aleasă (vezi core/music_tracks.dart) ────────────────

  /// Id-ul piesei, nu numele fișierului: fișierul se poate redenumi sau
  /// reîncoda (mp3 → ogg) fără ca preferința fiecărui jucător să se piardă.
  /// Șirul gol = piesa implicită.
  static Future<String> getMusicTrackId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_musicTrackKey) ?? '';
  }

  static Future<void> setMusicTrackId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_musicTrackKey, id);
  }

  // ─── Limba interfeței ─────────────────────────────────────────────────────

  /// Codul limbii alese ('ro' / 'en'), sau șirul gol dacă jucătorul n-a ales
  /// niciodată — caz în care se ia limba telefonului, vezi L10n.load.
  /// Distincția contează: „n-a ales" nu e același lucru cu „a ales română",
  /// altfel un telefon setat pe engleză n-ar porni niciodată în engleză.
  static Future<String> getLanguageCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey) ?? '';
  }

  static Future<void> setLanguageCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, code);
  }

  // ─── Cutia de notificări (vezi NotificationService) ───────────────────────

  /// Notificările ținute pe telefon, ca listă de JSON-uri. Sunt salvate aici,
  /// nu citite de fiecare dată din Firestore, ca panoul să se deschidă instant
  /// și offline; ce trimite adminul se descarcă o singură dată (vezi
  /// NotificationService.pullFromCloud) și rămâne local de atunci.
  static Future<List<String>> getNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_notificationsKey) ?? const [];
  }

  static Future<void> setNotifications(List<String> raw) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_notificationsKey, raw);
  }

  /// Momentul (millisecondsSinceEpoch) în care jucătorul a deschis ultima
  /// oară panoul de notificări. Tot ce a venit după e „necitit" — un singur
  /// număr în loc de un marcaj per notificare, fiindcă panoul se citește
  /// oricum întreg dintr-o privire.
  static Future<int> getNotificationsReadAt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_notificationsReadKey) ?? 0;
  }

  static Future<void> setNotificationsReadAt(int millis) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_notificationsReadKey, millis);
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

  /// Avatarul ales din Profil, ca id de [AvatarStyle] (vezi
  /// widgets/avatar_art.dart). Șirul gol înseamnă „poza implicită" — la fel ca
  /// AvatarStyle.poza, deci un jucător vechi care n-a ales niciodată nimic
  /// rămâne exact cum arăta.
  static Future<String> getAvatarStyleId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_avatarStyleKey) ?? '';
  }

  static Future<void> setAvatarStyleId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_avatarStyleKey, id);
  }

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

  /// Nivelul după care se calculează țintele și plățile quest-urilor de AZI
  /// (vezi [economyGrowth]). Se fixează la prima citire din ziua respectivă și
  /// NU se mai schimbă până la miezul nopții.
  ///
  /// Fără înghețarea asta, un level-up la mijlocul zilei ar mări țintele sub
  /// degetul jucătorului: bara de progres ar da înapoi, iar un quest care era
  /// gata ar redeveni neterminat. Cu ea, ziua se joacă pe regulile cu care a
  /// început, iar nivelul nou se aplică de mâine.
  static Future<int> questScaleLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'quest_level_${_dateKey(DateTime.now())}';
    final stored = prefs.getInt(key);
    if (stored != null) return stored;
    final level = levelForXp(prefs.getInt(_xpKey) ?? 0);
    await prefs.setInt(key, level);
    return level;
  }

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

  /// Varianta CITIRE, fără să scrie nimic — folosită de banner-ul "Categoria
  /// zilei" (vezi CategoriesScreen, PLAN_DE_VIITOR.md punctul 5) ca să știe
  /// dacă butonul de revendicare poate fi apăsat, fără să afecteze contorul
  /// real de "moduri jucate azi" pe care se bazează quest-ul.
  static Future<bool> wasModePlayedToday(String gameModeId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'played_modes_${_dateKey(DateTime.now())}';
    return (prefs.getStringList(key) ?? const []).contains(gameModeId);
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
    final level = await questScaleLevel();
    for (final q in todaysQuests()) {
      final progress = await getQuestProgress(q.metricKey);
      if (progress >= q.targetAt(level) && !await isQuestClaimed(q.id)) {
        return true;
      }
    }
    return false;
  }

  static String _questProgressKey(String id) => 'quest_${id}_${_dateKey(DateTime.now())}';
  static String _questClaimedKey(String id) => 'quest_claimed_${id}_${_dateKey(DateTime.now())}';

  // ─── Categoria zilei ────────────────────────────────────────────────────
  //
  // Conținut rotativ (PLAN_DE_VIITOR.md punctul 5) — cea mai mică variantă
  // reală care se putea face: o categorie evidențiată, aleasă determinist pe
  // zi (vezi core/gamemodes.dart#featuredGameModeToday), cu un bonus mic,
  // revendicabil O SINGURĂ dată pe zi, DUPĂ ce ai jucat-o măcar o dată azi
  // (vezi [wasModePlayedToday]). Exact tiparul quest-urilor
  // (isQuestClaimed/claimQuest de mai sus), dar într-un spațiu de chei
  // separat — nu e un quest din rotația săptămânală, n-are metricKey/tier.

  static String _featuredClaimedKey() => 'featured_claimed_${_dateKey(DateTime.now())}';

  static Future<bool> isFeaturedCategoryClaimed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_featuredClaimedKey()) ?? false;
  }

  /// Doar marchează revendicarea — apelantul (CategoriesScreen) e cel care
  /// scrie efectiv monedele/XP-ul în balanță, aceeași convenție ca
  /// [claimQuest].
  static Future<void> claimFeaturedCategory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_featuredClaimedKey(), true);
  }

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

  static Future<void> incrementHintsUsedTotal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hintsUsedTotalKey, (prefs.getInt(_hintsUsedTotalKey) ?? 0) + 1);
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
  /// citind toate contoarele o singură dată — sursă unică folosită de
  /// [checkNewlyCompletedAchievements], [hasClaimableAchievements] și de
  /// AchievementsScreen. Ecranul avea o copie proprie a acestui switch; când
  /// s-au adăugat realizări noi, cele două ar fi divergat tăcut (bara de
  /// progres ar fi arătat 0 pentru realizări care se deblocau totuși singure),
  /// de-aia acum e publică și una singură.
  ///
  /// Realizările din seria lungă citesc contoarele pe VIAȚĂ
  /// ([getLifetimeMetric]), alimentate automat de bumpQuestMetric — nu au
  /// nevoie de instrumentare separată în ecranele de joc.
  static Future<int Function(Achievement)> achievementProgressResolver() async {
    final prefs = await SharedPreferences.getInstance();
    final answeredCount = (prefs.getStringList(_answeredKey) ?? []).length;
    final level = levelForXp(prefs.getInt(_xpKey) ?? 0);
    final modesPlayed = (prefs.getStringList(_modesEverPlayedKey) ?? []).length;
    final hintsUsed = prefs.getInt(_hintsUsedTotalKey) ?? 0;
    final questsClaimed = prefs.getInt(_questsClaimedTotalKey) ?? 0;
    final dailyChallenges = prefs.getInt(_dailyChallengesTotalKey) ?? 0;
    final starterPackBought = prefs.getBool(_starterPackBoughtKey) ?? false;
    final streak = prefs.getInt(_streakCountKey) ?? 0;
    int lifetime(String metric) => prefs.getInt(_lifetimeMetricKey(metric)) ?? 0;
    return (Achievement a) => switch (a.id) {
          'correct_50' || 'correct_150' || 'correct_400' => answeredCount,
          'level_5' || 'level_15' => level,
          'all_modes' => modesPlayed,
          'hints_50' => hintsUsed,
          'quests_25' || 'quests_180' => questsClaimed,
          'daily_10' => dailyChallenges,
          'starter_pack_bought' => starterPackBought ? 1 : 0,
          'streak_30' => streak,
          'wheel_28' => lifetime('wheel_spin'),
          'mp_wins_23' => lifetime('mp_win'),
          'no_hint_250' => lifetime('no_hint_correct'),
          'culture_600' => lifetime('culture_quiz_correct'),
          'clippy_perfect_47' => lifetime('clippy_perfect'),
          'unlock_batches_3' => lifetime('question_batch_unlocked'),
          'planet_perfect_5' => lifetime('planet_perfect'),
          'coins_earned_37k' => lifetime('coins_earned'),
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
    final progressFor = await achievementProgressResolver();

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
    final progressFor = await achievementProgressResolver();
    for (final a in achievements) {
      if (progressFor(a) >= a.target && !await isAchievementClaimed(a.id)) return true;
    }
    return false;
  }

  /// Id-urile realizărilor cu ținta atinsă (revendicate SAU nu). Folosit de
  /// cosmetice pentru titlurile legate de realizări — vezi
  /// `ownsTitle` din core/cosmetics.dart.
  static Future<Set<String>> completedAchievementIds() async {
    final progressFor = await achievementProgressResolver();
    return {
      for (final a in achievements)
        if (progressFor(a) >= a.target) a.id,
    };
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

    final level = await questScaleLevel();
    final maxTargetByMetric = <String, int>{};
    for (final q in todaysQuests()) {
      final current = maxTargetByMetric[q.metricKey] ?? 0;
      final target = q.targetAt(level);
      if (target > current) maxTargetByMetric[q.metricKey] = target;
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

  /// Numele pe care jucătorul chiar și l-a ales, sau `''` dacă n-a ales
  /// niciodată unul.
  ///
  /// DE CE NU SE FOLOSEȘTE [getDisplayName] pentru asta: acela GENEREAZĂ și
  /// SALVEAZĂ un nume („JucatorNNN") când cheia lipsește. Sub noua ordine a
  /// numelor, întrebarea „și-a ales un nume?" se pune la fiecare rezolvare de
  /// identitate, inclusiv pentru conturi Google — deci [getDisplayName] ar
  /// scrie acel nume generat în contul fiecărui jucător Google care n-avea
  /// unul. Ar intra apoi în cloud-save (exportAll), ar strica amprenta din
  /// CloudSyncService.push și ar produce o scriere Firestore în plus la
  /// fiecare pornire — pe lângă că ar crea exact numele-gunoi pe care noua
  /// ordine încearcă să-l evite.
  static Future<String> getChosenDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_displayNameChosenKey) ?? false)) return '';
    return prefs.getString(_displayNameKey) ?? '';
  }

  /// Jucătorul și-a ales singur numele — de acum al lui bate numele din
  /// contul Google (vezi core/display_name.dart).
  static Future<void> setChosenDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name);
    await prefs.setBool(_displayNameChosenKey, true);
  }

  /// **Numele pus de administrator** din panoul de Admin (vezi
  /// PlayerProfileService.renamePlayerAsAdmin).
  ///
  /// DE CE E O CHEIE SEPARATĂ, ȘI NU O SIMPLĂ SCRIERE PESTE [setDisplayName]:
  /// numele afișat nu vine mereu de aici. La un cont Google el vine din contul
  /// Google (vezi AuthService.multiplayerIdentity), iar la un Guest e cel
  /// local — deci o rescriere a numelui local ar fi fost ștearsă la prima
  /// pornire pentru jumătate din jucători. Ăsta e singurul nume care bate și
  /// contul Google, tocmai pentru că e o decizie de moderare (un nickname
  /// jignitor trebuie să poată fi schimbat inclusiv pe un cont Google).
  ///
  /// Ajunge pe telefonul jucătorului la primul heartbeat de profil de după
  /// redenumire (deschiderea aplicației sau revenirea din fundal), nu instant.
  static Future<String> getForcedName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_forcedNameKey) ?? '';
  }

  /// Tutorialul de la prima pornire — vezi screens/welcome_screen.dart.
  ///
  /// Se citește ÎNAINTE de primul cadru desenat, deci întoarce `true` (adică
  /// „nu-l arăta") dacă ceva nu merge: mai bine sare cineva peste tutorial
  /// decât să-l vadă la fiecare pornire.
  static Future<bool> hasSeenIntro() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_introSeenKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introSeenKey, true);
  }

  static Future<void> setForcedName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name.isEmpty) {
      await prefs.remove(_forcedNameKey);
    } else {
      await prefs.setString(_forcedNameKey, name);
    }
  }

  // ─── Sincronizare cloud (cont Google) ──────────────────────────────────────
  // Generic, nu camp-cu-camp: orice cheie noua adaugata in viitor (achievement
  // nou, quest nou etc.) se sincronizeaza automat, fara alt cod aici.

  static Future<Map<String, dynamic>> exportAll() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (_localOnlyKeys.contains(key)) continue;
      map[key] = prefs.get(key);
    }
    return map;
  }

  /// Amprenta ultimei urcări reușite în cloud — vezi CloudSyncService.push,
  /// singurul care o scrie și o citește. Null înseamnă "nu s-a urcat nimic de
  /// pe telefonul ăsta încă", deci următoarea urcare se face oricum.
  static Future<String?> getCloudPushSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cloudPushSnapshotKey);
  }

  static Future<void> setCloudPushSnapshot(String snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cloudPushSnapshotKey, snapshot);
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
    // Cheia scrisă aici e variabilă la runtime, deci nu se poate ști static
    // dacă a fost una de balanță. Salvarea coborâtă din cloud la logare
    // schimbă aproape sigur balanța, deci se anunță necondiționat.
    balanceRevision.value++;
  }
}
