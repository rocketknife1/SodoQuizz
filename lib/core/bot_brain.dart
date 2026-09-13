/// Deciziile unui bot din meciurile solo (data/bot_match.dart) — pur, fără
/// rețea, ca să poată fi testat și echilibrat separat de ecrane.
///
/// Dificultatea 1..5 schimbă TREI lucruri: cât de des nimerește răspunsul,
/// cât de repede răspunde și cât de „deștept" își alege ținta/placa. Un bot
/// de nivel 5 nu e perfect — altfel un meci pierdut pare trucat, nu greu.
library;

import 'dart:math';

import 'rock_paper_scissors.dart';

const int botMinDifficulty = 1;
const int botMaxDifficulty = 5;
const int botMinCount = 1;
const int botMaxCount = 6;

const List<double> _accuracy = [0.35, 0.50, 0.64, 0.77, 0.88];

int _clampDifficulty(int d) => d.clamp(botMinDifficulty, botMaxDifficulty);

double botAccuracy(int difficulty) => _accuracy[_clampDifficulty(difficulty) - 1];

/// Timpul de gândire înainte de răspuns. Mereu sub [roundSeconds], ca botul să
/// nu fie tratat ca AFK, dar destul de variat încât să nu răspundă toți deodată.
Duration botThinkTime({required int difficulty, required int roundSeconds, required Random rnd}) {
  final d = _clampDifficulty(difficulty);
  // nivel 1: 35%..80% din rundă; nivel 5: 10%..35%
  final minFrac = 0.35 - (d - 1) * 0.0625;
  final maxFrac = 0.80 - (d - 1) * 0.1125;
  final frac = minFrac + rnd.nextDouble() * (maxFrac - minFrac);
  final ms = (roundSeconds * 1000 * frac).round().clamp(600, roundSeconds * 1000 - 1500);
  return Duration(milliseconds: ms);
}

/// Răspunsul corect cu probabilitatea [botAccuracy], altfel o variantă greșită.
String botPickAnswer({
  required String correct,
  required List<String> choices,
  required int difficulty,
  required Random rnd,
}) {
  final wrong = choices.where((c) => c != correct).toList();
  if (wrong.isEmpty || rnd.nextDouble() < botAccuracy(difficulty)) return correct;
  return wrong[rnd.nextInt(wrong.length)];
}

/// Ținta unui bot care are drept de tragere. Nivelurile mari vânează tancul
/// cel mai slăbit (lovitura care poate ucide); cele mici trag la întâmplare.
/// [hpById] conține doar țintele valide (vii, altele decât botul).
String? botPickTarget({required Map<String, int> hpById, required int difficulty, required Random rnd}) {
  if (hpById.isEmpty) return null;
  final ids = hpById.keys.toList()..sort();
  final focusChance = (_clampDifficulty(difficulty) - 1) * 0.2; // 0 .. 0.8
  if (rnd.nextDouble() < focusChance) {
    ids.sort((a, b) => hpById[a]!.compareTo(hpById[b]!));
    return ids.first;
  }
  return ids[rnd.nextInt(ids.length)];
}

/// Placa aleasă la Obby. Botul „simte" plăcile sigure cu atât mai des cu cât
/// e mai bun; altfel alege orbește, ca un om.
int botPickPlatform({
  required int platformCount,
  required Set<int> safeIndices,
  required int difficulty,
  required Random rnd,
}) {
  final senseFake = (_clampDifficulty(difficulty) - 1) * 0.18; // 0 .. 0.72
  if (safeIndices.isNotEmpty && rnd.nextDouble() < senseFake) {
    final safe = safeIndices.toList()..sort();
    return safe[rnd.nextInt(safe.length)];
  }
  return rnd.nextInt(platformCount);
}

/// Piatră-Hârtie-Foarfecă: aleator, dar un bot bun contrează uneori mâna pe
/// care jucătorul a jucat-o cel mai des până acum.
String botPickRps({required Map<String, int> humanHistory, required int difficulty, required Random rnd}) {
  const all = [rpsRock, rpsPaper, rpsScissors];
  final counterChance = (_clampDifficulty(difficulty) - 1) * 0.1; // 0 .. 0.4
  if (humanHistory.isNotEmpty && rnd.nextDouble() < counterChance) {
    final favourite = humanHistory.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    return switch (favourite) {
      rpsRock => rpsPaper,
      rpsPaper => rpsScissors,
      _ => rpsRock,
    };
  }
  return all[rnd.nextInt(all.length)];
}

const List<String> _botNames = [
  'Ionel', 'Maricica', 'Gigel', 'Viorica', 'Costel', 'Lenuța',
  'Dorel', 'Aurica', 'Fănel', 'Tanti Geta', 'Nea Mitică', 'Săndel',
];

/// Nume vizibil de bot — 🤖 e obligatoriu: jucătorul trebuie să știe mereu că
/// adversarul nu e om. La SFÂRȘIT, nu la început: ecranele iau inițiala
/// avatarului din `name[0]`, iar un emoji dă acolo o jumătate de caracter.
List<String> botNames(int count, Random rnd) {
  final pool = List.of(_botNames)..shuffle(rnd);
  return [for (var i = 0; i < count; i++) '${pool[i % pool.length]} 🤖'];
}

/// Câte meciuri cu boți pe zi dau recompensă. Peste plafon se joacă în
/// continuare, doar fără monede/XP — altfel boții de nivel 1 ar deveni o
/// fermă de monede.
const int botRewardedMatchesPerDay = 5;

/// Recompensa unui meci cu boți, după locul ocupat (0 = primul). Mult sub un
/// meci real: nu există miză, deci nici risc. Nimic pentru ultimul loc.
({int coins, int xp}) botMatchReward({
  required int place,
  required int totalPlayers,
  required int difficulty,
  required int botCount,
}) {
  final d = _clampDifficulty(difficulty);
  final bots = botCount.clamp(botMinCount, botMaxCount);
  if (totalPlayers > 1 && place >= totalPlayers - 1) return (coins: 0, xp: 4);
  final full = (coins: 3 * d + 2 * bots, xp: 6 + 3 * d + bots);
  if (place == 0) return full;
  return (coins: full.coins ~/ 2, xp: full.xp ~/ 2);
}
