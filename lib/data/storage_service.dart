import 'package:shared_preferences/shared_preferences.dart';
import '../core/progression.dart';

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
  static const _musicEnabledKey = 'music_enabled';
  static const _musicVolumeKey = 'music_volume';
  static const _hintsKey = 'hints_balance';
  static const _startingHints = 3;
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
  static const _maxLives = 5;
  static const ringSpinCooldownHours = 24;

  /// Praguri (în zile consecutive) la care se acordă un bonus automat.
  static const List<int> streakMilestones = [3, 7, 14, 30, 60, 100];
  static const _livesRechargeMinutes = 30; // o viată la 30 min

  // ─── Vieți ───────────────────────────────────────────────────────────────

  static Future<int> getLives() async {
    final prefs = await SharedPreferences.getInstance();
    await _rechargeLives(prefs);
    return prefs.getInt(_livesKey) ?? _maxLives;
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

  /// Adaugă vieți peste plafonul standard de 5 — folosit doar de recompensa
  /// de colectare din Cultură Generală, unde inimile câștigate se pot
  /// acumula peste maximul obișnuit (regenerarea pasivă tot se oprește la 5).
  static Future<void> addLivesUncapped(int amount) async {
    if (amount <= 0) return;
    final current = await getLives();
    await setLives(current + amount);
  }

  /// Reîncarcă vieți automat în funcție de timp trecut
  static Future<void> _rechargeLives(SharedPreferences prefs) async {
    final current = prefs.getInt(_livesKey) ?? _maxLives;
    if (current >= _maxLives) return;

    final ts = prefs.getInt(_livesTimestampKey);
    if (ts == null) return;

    final elapsed = DateTime.now().millisecondsSinceEpoch - ts;
    final minutesPassed = elapsed ~/ 60000;
    final livesToAdd = minutesPassed ~/ _livesRechargeMinutes;

    if (livesToAdd > 0) {
      final newLives = (current + livesToAdd).clamp(0, _maxLives);
      await prefs.setInt(_livesKey, newLives);
      if (newLives < _maxLives) {
        // actualizează timestamp-ul cu restul de timp
        final remainder = minutesPassed % _livesRechargeMinutes;
        final newTs = DateTime.now().millisecondsSinceEpoch - (remainder * 60000);
        await prefs.setInt(_livesTimestampKey, newTs);
      }
    }
  }

  // ─── Monede ──────────────────────────────────────────────────────────────

  static Future<int> getCoins() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_coinsKey) ?? 0;
  }

  static Future<void> addCoins(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_coinsKey) ?? 0;
    await prefs.setInt(_coinsKey, current + amount);
  }

  static Future<bool> spendCoins(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_coinsKey) ?? 0;
    if (current < amount) return false;
    await prefs.setInt(_coinsKey, current - amount);
    return true;
  }

  // ─── Hints (resursă separată, ca vieți/monede — vezi Home + shop) ─────────
  // Jucătorii noi pornesc cu [_startingHints] gratuit, ca hint-ul din prima
  // întrebare să nu coste nimic din prima sesiune.

  static Future<int> getHints() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_hintsKey) ?? _startingHints;
  }

  static Future<void> addHints(int amount) async {
    if (amount <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_hintsKey) ?? _startingHints;
    await prefs.setInt(_hintsKey, current + amount);
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
    return prefs.getInt(_xpKey) ?? 0;
  }

  static Future<void> addXp(int amount) async {
    if (amount <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_xpKey) ?? 0;
    await prefs.setInt(_xpKey, current + amount);
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

  /// Adaugă [_maxLives] vieți, o dată pe zi calendaristică — aditiv, nu
  /// resetează la plafon, ca să se însumeze corect cu orice bonus deja
  /// acumulat (ex: din Cultură Generală, vezi [addLivesUncapped]).
  static Future<void> claimDailyReward() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dailyClaimKey, _dateKey(DateTime.now()));
    await addLivesUncapped(_maxLives);
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

  // ─── Notificarea lui Clippy (bonus cu 3 întrebări, la fiecare ~15s) ────────
  // Persistat (nu doar în memoria widget-ului), ca să supraviețuiască
  // navigării între tab-uri (Home se recreează la fiecare schimbare de tab
  // din bottom nav) — altfel notificarea se pierdea/reseta la revenirea pe
  // Home, deși încă era valabilă.

  static const clippyReadyIntervalSeconds = 15;

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

  // ─── Modul "fără blur" (accesibilitate / preview) ─────────────────────────

  static Future<bool> getNoBlurMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_noBlurKey) ?? false;
  }

  static Future<void> setNoBlurMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_noBlurKey, value);
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
        await addCoins(milestone * 5);
        await addXp(milestone * 10);
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

  /// Marchează quest-ul ca revendicat și acordă recompensa în monede + XP.
  static Future<void> claimQuest(Quest quest) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_questClaimedKey(quest.id), true);
    await addCoins(quest.coinReward);
    await addXp(quest.xpReward);
    await prefs.setInt(_questsClaimedTotalKey, (prefs.getInt(_questsClaimedTotalKey) ?? 0) + 1);
  }

  /// True dacă vreun quest zilnic are ținta atinsă și încă nerevendicată —
  /// folosit pentru punctul roșu de notificare de pe tab-ul Quests.
  static Future<bool> hasClaimableQuests() async {
    for (final q in dailyQuests) {
      final progress = await getQuestProgress(q.id);
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

  /// Recordul personal pentru un gamemod anume (folosit în Clasament).
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

  static Future<void> claimAchievement(Achievement achievement) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('achievement_claimed_${achievement.id}', true);
    await addCoins(achievement.coinReward);
    await addXp(achievement.xpReward);
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
    return (Achievement a) => switch (a.id) {
          'correct_50' || 'correct_150' || 'correct_400' => answeredCount,
          'level_5' || 'level_15' => level,
          'all_modes' => modesPlayed,
          'hints_50' => hintsUsed,
          'quests_25' => questsClaimed,
          'daily_10' => dailyChallenges,
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
