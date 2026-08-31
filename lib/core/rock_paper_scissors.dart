/// Modul Piatră-Hârtie-Foarfecă — logica pură a rundei.
///
/// Spre deosebire de celelalte moduri multiplayer (Higher & Lower, Tanks,
/// Obby, Scaunul Electric) ăsta NU are întrebări sau poze: fiecare rundă e
/// doar o alegere secretă între trei, dezvăluită simultan. Runda se rezolvă
/// printr-o tranzacție Firestore pe care o poate încerca orice client (vezi
/// [MultiplayerService.resolveRockPaperScissorsRound]) — la fel ca la
/// Higher & Lower — deci funcția de scor de aici TREBUIE să fie pură și
/// deterministă: toți clienții calculează același rezultat din aceleași
/// alegeri.
library;

import 'multiplayer_round.dart';

const String rpsRock = 'rock';
const String rpsPaper = 'paper';
const String rpsScissors = 'scissors';

/// Cele trei alegeri valide, în ordinea de afișare pe ecran.
const List<String> rpsChoices = [rpsRock, rpsPaper, rpsScissors];

/// Timpul de alegere per rundă — aceeași sursă unică ca toate modurile
/// sincrone (vezi core/multiplayer_round.dart). O alegere e mai rapidă de
/// făcut decât un răspuns la o întrebare, dar userul a cerut explicit ca
/// toate modurile să aibă același timp per rundă.
const int rpsRoundSeconds = sharedRoundAnswerSeconds;

/// Câte secunde stă pe ecran dezvăluirea (cine a ales ce) înainte de runda
/// următoare — la fel ca [higherLowerRevealSeconds].
const int rpsRevealSeconds = 3;

/// Primul jucător care ajunge la scorul ăsta câștigă meciul.
const int rpsTargetScore = 10;

/// Plafon de runde: dacă nimeni n-a atins [rpsTargetScore] până aici, meciul
/// se încheie și câștigă cine are scorul cel mai mare (departajare în
/// [MultiplayerResultsScreen], ca la Tanks/Obby). Fără plafon, o masă în care
/// toți aleg mereu la fel ar rula la nesfârșit — RPS n-are eliminare care să
/// forțeze un final ca la Higher & Lower.
const int rpsMaxRounds = 30;

/// `true` dacă [a] bate [b] la piatră-hârtie-foarfecă. Alegerea goală (`''`,
/// jucătorul n-a apăsat la timp) nu bate nimic și e bătută de orice alegere
/// validă.
bool _beats(String a, String b) {
  if (a.isEmpty) return false;
  if (b.isEmpty) return true;
  return (a == rpsRock && b == rpsScissors) ||
      (a == rpsScissors && b == rpsPaper) ||
      (a == rpsPaper && b == rpsRock);
}

/// Punctele câștigate în runda asta de fiecare jucător: `+1` pentru fiecare
/// adversar pe care îl bate cu alegerea lui. Aceeași alegere între doi
/// jucători = 0 puncte între ei (egalitate). Alegerea lipsă e bătută de toți.
///
/// Pură, deterministă, fără efecte secundare — ordinea cheilor din [choices]
/// nu contează pentru rezultat.
Map<String, int> rpsRoundScores(Map<String, String> choices) {
  final ids = choices.keys.toList();
  final out = {for (final id in ids) id: 0};
  for (var i = 0; i < ids.length; i++) {
    for (var j = 0; j < ids.length; j++) {
      if (i == j) continue;
      if (_beats(choices[ids[i]] ?? '', choices[ids[j]] ?? '')) {
        out[ids[i]] = out[ids[i]]! + 1;
      }
    }
  }
  return out;
}

/// `true` dacă vreun jucător a atins pragul de victorie.
bool rpsWinnerReached(Map<String, int> scores) =>
    scores.values.any((s) => s >= rpsTargetScore);
