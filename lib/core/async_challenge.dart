import 'dart:math';

import '../models/question.dart';
import 'stable_hash.dart';

/// Async Challenge — „Provoacă un prieten". Un duel de quiz care NU cere doi
/// oameni online în același moment: A joacă 10 întrebări, trimite un cod,
/// B joacă EXACT aceleași 10 întrebări când poate, se compară scorurile.
///
/// Singura formă de PvP care merge la 0 jucători online simultan (vezi
/// docs/superpowers/specs/2026-09-07-async-challenge.md).
///
/// Determinismul (aceleași întrebări pe web și pe telefon) vine din
/// [stableHash] + [stableShuffle], la fel ca Provocarea Zilei — `Random(seed)`
/// din `dart:math` NU e stabil între platforme.

const int asyncChallengeQuestionCount = 10;

/// Alfabetul codului de provocare — fără caractere ambigue (0/O, 1/I/L),
/// același ca la codul de prieten.
const String asyncChallengeAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

/// Un id nou de provocare (6 caractere). Generat pe client ÎNAINTE ca
/// creatorul să joace — trebuie să fie același id din care se derivă
/// întrebările lui ȘI ale adversarului, altfel joacă seturi diferite.
String newAsyncChallengeId([Random? rnd]) {
  final r = rnd ?? Random();
  return List.generate(
      6, (_) => asyncChallengeAlphabet[r.nextInt(asyncChallengeAlphabet.length)]).join();
}

/// Sămânța deterministă a unei provocări, derivată din id-ul ei.
int asyncChallengeSeed(String challengeId) =>
    stableHash('provocare-async-$challengeId');

/// Cele [asyncChallengeQuestionCount] întrebări ale provocării [challengeId],
/// deterministe. Nu modifică [pool]. Doar întrebări cu POZĂ reală (fără
/// formule / categorii fără imagine — vezi `pickDailyChallenge`).
List<Question> pickAsyncChallenge(List<Question> pool, String challengeId) {
  final eligible = pool
      .where((q) => q.imageAssetPath != null && q.formula == null)
      .toList();
  if (eligible.isEmpty) return const [];
  stableShuffle(eligible, asyncChallengeSeed(challengeId));
  return eligible.take(asyncChallengeQuestionCount).toList();
}

/// Rezultatul unui duel din perspectiva unui jucător.
enum ChallengeOutcome { won, lost, draw }

ChallengeOutcome challengeOutcome({required int myScore, required int theirScore}) {
  if (myScore > theirScore) return ChallengeOutcome.won;
  if (myScore < theirScore) return ChallengeOutcome.lost;
  return ChallengeOutcome.draw;
}

/// Recompensa în monede. Câștigătorul ia [challengeWinCoins] (+ XP scalat pe
/// nivel, calculat separat), perdantul doar XP de consolare, remiza ambii
/// [challengeDrawCoins]. Fără miză — nimeni nu pierde monede.
///
/// Plafon: doar primele [challengeRewardedPerDay] provocări câștigate pe zi
/// aduc monede (contor zilnic în StorageService) — a 6-a tot se joacă, ca
/// experiență, dar nefarmabilă cu conturi-alt.
const int challengeWinCoins = 120;
const int challengeDrawCoins = 60;
const int challengeLoseXp = 20;
const int challengeRewardedPerDay = 5;

int challengeCoinReward(ChallengeOutcome o) => switch (o) {
      ChallengeOutcome.won => challengeWinCoins,
      ChallengeOutcome.draw => challengeDrawCoins,
      ChallengeOutcome.lost => 0,
    };

/// Câte provocări trebuie câștigate pentru titlul „Provocatoru'" — metric
/// `challenge_win`, la fel ca `mp_wins_23` (vezi core/cosmetics.dart).
const int challengeTitleWins = 15;
