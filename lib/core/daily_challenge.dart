import '../models/question.dart';
import 'stable_hash.dart';

/// Provocarea Zilei — un set FIX de întrebări, acelaşi pentru toată lumea într-o
/// zi calendaristică, jucabil o singură dată pe zi, cu recompensă mare şi un
/// clasament „de azi".
///
/// De ce e nevoie: „Daily Challenge" exista doar ca bifă într-un quest (fă
/// Cultură Generală o dată). Fără miză proprie, fără conţinut special, fără
/// competiţie — deci fără motiv real de revenire zilnică. (Secţiunea RETENŢIE
/// din notele de plan, punctul 2.)
///
/// Determinismul (aceleaşi întrebări pe web şi pe telefon) vine din
/// [stableHash] + [stableShuffle] — `Random(seed)` din `dart:math` NU
/// garantează acelaşi şir între platforme (vezi core/stable_hash.dart).

const int dailyChallengeQuestionCount = 5;

/// Cheia zilei — `2026-09-06`, zero-padded. Foloseşte ora LOCALĂ, la fel ca
/// restul „zilnicelor" din joc (contoare, quest-uri, categoria zilei), ca
/// „ziua" să însemne acelaşi lucru peste tot.
String dailyChallengeDateKey(DateTime day) {
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '${day.year}-$m-$d';
}

/// Sămânţa deterministă pentru ziua respectivă.
int dailyChallengeSeed(DateTime day) =>
    stableHash('provocarea-zilei-${dailyChallengeDateKey(day)}');

/// Alege [dailyChallengeQuestionCount] întrebări din [pool], determinist pe
/// [day]. Nu modifică [pool].
///
/// Doar întrebări cu POZĂ reală: cele fără imagine (categorii noi, întrebările
/// pe formulă din Matematică) arată un placeholder „Va urma" în [BlurImage] —
/// n-au ce căuta într-o provocare cu miză. Dacă după filtrare rămân mai puţine
/// de [dailyChallengeQuestionCount], le întoarce pe toate câte sunt.
List<Question> pickDailyChallenge(List<Question> pool, DateTime day) {
  final eligible = pool
      .where((q) => q.imageAssetPath != null && q.formula == null)
      .toList();
  if (eligible.isEmpty) return const [];
  stableShuffle(eligible, dailyChallengeSeed(day));
  return eligible.take(dailyChallengeQuestionCount).toList();
}

/// Recompensa în monede pentru [correct] răspunsuri corecte (din
/// [dailyChallengeQuestionCount]). 40 pe răspuns + 150 bonus doar la scor
/// perfect. O întrebare de gameplay normal plăteşte ~5-15 monede — asta e de
/// câteva ori mai mult, dar e o singură rulare pe zi, nefarmabilă.
int dailyChallengeReward(int correct) {
  final clamped = correct.clamp(0, dailyChallengeQuestionCount);
  final base = clamped * 40;
  return clamped >= dailyChallengeQuestionCount ? base + 150 : base;
}
