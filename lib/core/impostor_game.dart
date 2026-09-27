/// **Impostorul** — deducție socială, nu cunoștințe. Toți jucătorii, în
/// afară de unul, primesc ACELAȘI cuvânt de ghicit (o poză din aceeași
/// categorie); impostorul primește alt cuvânt din aceeași categorie, fără
/// să știe că e diferit de al celorlalți.
///
/// Fiecare alege pe rând un indiciu ADEVĂRAT despre cuvântul lui, dintr-o
/// listă generată din literele cuvântului (nu text liber — vezi
/// [impostorCluesFor]), ca și boții să poată juca real. Apoi toată masa
/// votează cine crede că e impostorul.
///
/// Determinist: cuvintele și impostorul se aleg din `matchId` + rundă, deci
/// un client rezolvă runda (MultiplayerService.closeImpostorRound) și restul
/// doar animă. Fără eliminare — scorul se adună pe [impostorRounds] runde,
/// ca la Piatră-Hârtie-Foarfecă.
library;

import 'dart:math';

import 'lang.dart';
import 'stable_hash.dart';

/// Ordinea „canonică" a categoriilor și pozelor din ele: sortate după id.
/// Fiecare client construiește [byCategory] separat, din datele oficiale ale
/// jocului — trebuie să iasă IDENTIC pe telefon și în browser, altfel doi
/// jucători ar vedea cuvinte diferite din aceeași rundă. Se folosește doar
/// [StableRandom] mai jos, niciodată `dart:math` cu o sămânță — vezi
/// core/stable_hash.dart pentru bug-ul cross-platform găsit deja o dată.

const int impostorRounds = 8;
const int impostorMinPlayers = 3;
const int impostorMaxPlayers = 8;
const int impostorClueSeconds = 20;
const int impostorVoteSeconds = 20;

/// Puncte: impostorul care scapă ia mai mult decât cineva care doar
/// nimerește votul, ca rolul greu să merite riscul.
const int impostorSurvivePoints = 6;
const int impostorCorrectVotePoints = 3;
const int impostorCaughtConsolationPoints = 1;

/// O poză din pool — la fel ca la Fulgerul, motorul ține doar ce trebuie ca
/// s-o arate și s-o compare.
class ImpostorPic {
  const ImpostorPic({required this.id, required this.answer, required this.imagePath, required this.categoryId});

  final String id;
  final String answer;
  final String imagePath;
  final String categoryId;
}

enum ImpostorClueKind { startsWith, endsWith, length, contains, vowelCount }

class ImpostorClue {
  const ImpostorClue(this.kind, this.value);

  final ImpostorClueKind kind;

  /// Litera, cifra sau numărul din indiciu, ca text — de-atât e nevoie ca
  /// să reconstruim propoziția (`impostorClueText`).
  final String value;

  String encode() => '${kind.name}:$value';

  factory ImpostorClue.decode(String raw) {
    final i = raw.indexOf(':');
    final kind = ImpostorClueKind.values.firstWhere((k) => k.name == raw.substring(0, i));
    return ImpostorClue(kind, raw.substring(i + 1));
  }
}

String impostorClueText(ImpostorClue c) => switch (c.kind) {
      ImpostorClueKind.startsWith => tr('Începe cu litera „${c.value}"', 'Starts with the letter "${c.value}"'),
      ImpostorClueKind.endsWith => tr('Se termină cu litera „${c.value}"', 'Ends with the letter "${c.value}"'),
      ImpostorClueKind.length => tr('Are ${c.value} litere', 'Has ${c.value} letters'),
      ImpostorClueKind.contains => tr('Conține litera „${c.value}"', 'Contains the letter "${c.value}"'),
      ImpostorClueKind.vowelCount => tr('Are ${c.value} vocale', 'Has ${c.value} vowels'),
    };

const _vowels = 'AEIOUĂÂÎ';

/// Toate indiciile ADEVĂRATE despre [word] — jucătorul alege unul, nu-l
/// scrie. Cel puțin 4 mereu (start, sfârșit, lungime, o literă conținută),
/// ca alegerea să fie reală.
List<ImpostorClue> impostorCluesFor(String word) {
  final w = word.toUpperCase().replaceAll(RegExp(r'[^A-ZĂÂÎȘȚ]'), '');
  if (w.isEmpty) return const [];
  final clues = <ImpostorClue>[
    ImpostorClue(ImpostorClueKind.startsWith, w[0]),
    ImpostorClue(ImpostorClueKind.endsWith, w[w.length - 1]),
    ImpostorClue(ImpostorClueKind.length, '${w.length}'),
  ];
  final vowels = w.split('').where((c) => _vowels.contains(c)).length;
  clues.add(ImpostorClue(ImpostorClueKind.vowelCount, '$vowels'));
  final letters = w.split('').toSet().toList()..sort();
  for (final l in letters) {
    if (l != w[0] && l != w[w.length - 1]) clues.add(ImpostorClue(ImpostorClueKind.contains, l));
  }
  return clues;
}

class ImpostorRound {
  const ImpostorRound({required this.impostorId, required this.realWord, required this.impostorWord});

  final String impostorId;
  final ImpostorPic realWord;
  final ImpostorPic impostorWord;

  String wordFor(String playerId) => playerId == impostorId ? impostorWord.answer : realWord.answer;
}

class ImpostorVoteResult {
  const ImpostorVoteResult({required this.votesFor, required this.impostorCaught, required this.scores});

  /// id → câte voturi a primit.
  final Map<String, int> votesFor;
  final bool impostorCaught;

  /// id → punctele câștigate runda asta.
  final Map<String, int> scores;
}

class ImpostorGame {
  const ImpostorGame();

  /// Alege impostorul rundei — rotație deterministă peste ROSTERUL original
  /// al camerei ([playerIds], lista stocată la crearea meciului, aceeași pe
  /// toate telefoanele). Cineva plecat între timp tot poate „ieși" din
  /// rotație runda respectivă — ecranul pur și simplu sare peste el.
  String impostorFor(List<String> playerIds, int seed, int round) {
    final sorted = List.of(playerIds)..sort();
    final rng = StableRandom(seed ^ (round * 0x85EBCA6B));
    return sorted[rng.nextInt(sorted.length)];
  }

  /// Alege cuvântul real și cuvântul impostorului: aceeași categorie, ca
  /// indiciile să nu-l dea de gol din prima („e o mașină" ar fi evident dacă
  /// impostorul are un animal). Doar [StableRandom] — orice altă sursă de
  /// aleator ar putea alege altă pereche pe telefon față de browser.
  (ImpostorPic real, ImpostorPic impostor) wordsFor({
    required Map<String, List<ImpostorPic>> byCategory,
    required int seed,
    required int round,
  }) {
    final rng = StableRandom(seed ^ (round * 0xC2B2AE35));
    final categories = byCategory.keys.where((c) => byCategory[c]!.length >= 2).toList()..sort();
    final cat = categories[rng.nextInt(categories.length)];
    final pool = List.of(byCategory[cat]!)..sort((a, b) => a.id.compareTo(b.id));
    // Fisher–Yates cu StableRandom — vezi core/stable_hash.dart stableShuffle,
    // reimplementat aici ca să reutilizăm același `rng` (o singură sămânță).
    for (var i = pool.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = pool[i];
      pool[i] = pool[j];
      pool[j] = tmp;
    }
    return (pool[0], pool[1]);
  }

  ImpostorVoteResult resolveVotes({
    required String impostorId,
    required List<String> playerIds,
    required Map<String, String> votes,
  }) {
    final tally = <String, int>{for (final id in playerIds) id: 0};
    for (final accused in votes.values) {
      if (tally.containsKey(accused)) tally[accused] = tally[accused]! + 1;
    }
    final maxVotes = tally.values.fold(0, max);
    final topAccused = maxVotes == 0 ? <String>[] : [for (final e in tally.entries) if (e.value == maxVotes) e.key];
    final caught = topAccused.length == 1 && topAccused.first == impostorId;

    final scores = <String, int>{};
    for (final id in playerIds) {
      if (id == impostorId) {
        scores[id] = caught ? impostorCaughtConsolationPoints : impostorSurvivePoints;
      } else {
        scores[id] = votes[id] == impostorId ? impostorCorrectVotePoints : 0;
      }
    }
    return ImpostorVoteResult(votesFor: tally, impostorCaught: caught, scores: scores);
  }
}

/// Botul alege un indiciu la întâmplare dintre cele disponibile — toate
/// sunt adevărate, deci orice alegere e „corectă", doar mai mult sau mai
/// puțin dezvăluitoare.
ImpostorClue impostorBotPickClue(List<ImpostorClue> available, Random rnd) => available[rnd.nextInt(available.length)];

/// Botul votează pe cineva ale cărui indicii nu se potrivesc cu propriul
/// cuvânt (dacă e nevinovat) — o urmă simplă, dar reală, de „citire".
/// Dificultatea crește șansa de a observa nepotrivirea; altfel votează
/// la întâmplare printre ceilalți.
String impostorBotVote({
  required String myId,
  required String myWord,
  required List<String> otherIds,
  required Map<String, ImpostorClue> clueByPlayer,
  required int difficulty,
  required Random rnd,
}) {
  final chance = (difficulty - 1) * 0.2; // 0..0.8
  if (rnd.nextDouble() < chance) {
    for (final id in otherIds) {
      final clue = clueByPlayer[id];
      if (clue == null) continue;
      if (!_clueMatches(clue, myWord)) return id;
    }
  }
  return otherIds[rnd.nextInt(otherIds.length)];
}

bool _clueMatches(ImpostorClue c, String word) {
  final w = word.toUpperCase().replaceAll(RegExp(r'[^A-ZĂÂÎȘȚ]'), '');
  return switch (c.kind) {
    ImpostorClueKind.startsWith => w.startsWith(c.value),
    ImpostorClueKind.endsWith => w.endsWith(c.value),
    ImpostorClueKind.length => w.length == int.parse(c.value),
    ImpostorClueKind.contains => w.contains(c.value),
    ImpostorClueKind.vowelCount => w.split('').where((ch) => _vowels.contains(ch)).length == int.parse(c.value),
  };
}
