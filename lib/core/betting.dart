/// Mizele meciurilor multiplayer — varianta SIMPLĂ (v3.5).
///
/// Sistemul vechi cerea jucătorului să înțeleagă cinci lucruri deodată: o taxă
/// fixă de intrare, un procent din avere ales pe slider, un bonus de risc, un
/// plafon de masă calculat din mediana pariurilor și un pot rupt în două
/// bucăți, cu cote care scădeau cu numărul de jucători. Nimeni — și mai ales
/// nu un copil de 13 ani — nu putea spune, uitându-se la ecran, cât pierde și
/// cât ia dacă termină pe locul 2.
///
/// Acum sunt trei propoziții, atât:
///   1. Camera are o **miză**, aleasă o singură dată de cel care o creează.
///      Toți plătesc exact aceeași miză — cine intră nu mai alege nimic.
///   2. Mizele se strâng într-o grămadă, din care jocul ia [matchRake]
///      comision (singurul loc pe unde ies monede din economie la multiplayer).
///   3. Grămada se împarte doar în JUMĂTATEA DE SUS a clasamentului: locul 1
///      ia dublu față de locul 2, locul 2 dublu față de locul 3 ș.a.m.d.
///      Ceilalți pierd miza.
///
/// Consecința care contează: premiile depind DOAR de miză și de câți jucători
/// sunt la masă, deci pot fi afișate exact, dinainte, ca un tabel — vezi
/// `widgets/match_stake_dialog.dart`. Nu mai există nicio cifră pe care
/// jucătorul s-o afle abia la final.
library;

import 'dart:math';
import 'lang.dart';

/// Mizele dintre care alege cel care creează camera. Valori absolute, nu
/// procente din avere: un număr fix se poate citi pe ecran și se poate compara
/// cu portofelul dintr-o privire. Cea mai mică e sub zestrea de start
/// (StorageService.startingCoinsDefault = 173), ca un jucător nou să poată
/// intra din prima zi.
const List<int> matchStakeOptions = [50, 150, 500];

/// Numele mizelor, în ordinea din [matchStakeOptions].
// Getter, nu constantă: textul se traduce, iar o `const` nu poate chema tr().
List<String> get matchStakeLabels => [tr('Mică', 'Small'), tr('Medie', 'Medium'), tr('Mare', 'Large')];

/// Miza preselectată în dialogul de creare a camerei.
const int defaultMatchStake = 150;

/// Miza la Join Online. Acolo nu există „cel care creează camera", deci nu are
/// cine să aleagă: e fixă, și e cea mai MICĂ dintre opțiuni tocmai pentru că e
/// singurul drum pe care jucătorul nu are ce decide — nimeni nu trebuie să
/// rămână pe dinafară de la matchmaking-ul public din lipsă de monede.
const int publicMatchStake = 50;

/// Pragul absolut de intrare în orice fel de meci.
const int minMatchStake = 50;

/// Comisionul jocului din grămadă. Rotund și ușor de spus cu voce tare („din
/// tot ce se strânge, jocul ia o zecime"). Înlocuiește AMBELE sink-uri vechi
/// (taxa fixă de 37 + rake-ul variabil de 1,3-3,5%), care împreună însemnau o
/// ardere mai mare, dar imposibil de explicat.
const double matchRake = 0.10;

/// Câte locuri primesc premiu: jumătatea de sus a clasamentului, rotunjită în
/// sus. La 2 jucători înseamnă că învingătorul ia tot — exact ce trebuie
/// pentru Join Online, care e mereu 1 vs 1: altfel, cu premii împărțite și
/// comision luat, victoria într-un duel ar fi adus un plus derizoriu.
int paidPlaceCount(int players) => players <= 0 ? 0 : (players + 1) ~/ 2;

/// Tot ce s-a strâns pe masă, înainte de comision.
int matchPot({required int stake, required int players}) =>
    players <= 0 || stake <= 0 ? 0 : stake * players;

/// Ce rămâne de împărțit după comision.
int matchPrizePool({required int stake, required int players}) =>
    (matchPot(stake: stake, players: players) * (1 - matchRake)).round();

/// Premiul fiecărui loc, în ordine (indexul 0 = locul 1). Locurile neplătite
/// primesc 0.
///
/// Un meci rămas cu un singur jucător nu e un pariu: își ia miza înapoi
/// întreagă, fără comision.
List<int> matchPrizes({required int stake, required int players}) {
  if (players <= 0) return const [];
  if (stake <= 0) return List.filled(players, 0);
  if (players == 1) return [stake];

  final pool = matchPrizePool(stake: stake, players: players);
  final paid = paidPlaceCount(players);
  // 1, 1/2, 1/4, ... — „fiecare loc ia jumătate din cât ia cel de deasupra".
  var weightTotal = 0.0;
  for (var i = 0; i < paid; i++) {
    weightTotal += pow(0.5, i);
  }

  final prizes = List<int>.filled(players, 0);
  // Locurile se calculează de jos în sus, iar locul 1 primește ce a mai rămas:
  // așa suma premiilor e EXACT pool-ul, fără monede inventate sau pierdute din
  // rotunjiri (locul 1 ia oricum cea mai mare felie, deci o abatere de 1-2
  // monede se pierde în ea).
  var given = 0;
  for (var i = paid - 1; i >= 1; i--) {
    final prize = (pool * (pow(0.5, i) / weightTotal)).round();
    prizes[i] = prize;
    given += prize;
  }
  prizes[0] = pool - given;
  return prizes;
}

/// Premiile efective pentru un clasament concret, cu EGALITĂȚILE împărțite.
///
/// [sortedScores] sunt scorurile finale, deja ordonate descrescător (poziția
/// din listă = locul). Fără regula asta, doi jucători cu exact același scor ar
/// lua sume complet diferite după cum s-a nimerit sortarea — iar la 1 vs 1,
/// unde învingătorul ia tot, o remiză l-ar fi lăsat pe unul cu toată grămada
/// și pe celălalt cu zero.
List<int> matchPrizesForRanking({required int stake, required List<int> sortedScores}) {
  final n = sortedScores.length;
  final base = matchPrizes(stake: stake, players: n);
  final out = List<int>.filled(n, 0);
  var i = 0;
  while (i < n) {
    var last = i;
    while (last + 1 < n && sortedScores[last + 1] == sortedScores[i]) {
      last++;
    }
    var sum = 0;
    for (var k = i; k <= last; k++) {
      sum += base[k];
    }
    final count = last - i + 1;
    final each = sum ~/ count;
    var remainder = sum - each * count;
    for (var k = i; k <= last; k++) {
      out[k] = each + (remainder > 0 ? 1 : 0);
      if (remainder > 0) remainder--;
    }
    i = last + 1;
  }
  return out;
}

/// Numele mizei ('Mică'/'Medie'/'Mare'), sau șir gol pentru o valoare care nu
/// e printre opțiuni (camere create de versiuni mai vechi ale aplicației).
String matchStakeLabel(int stake) {
  final i = matchStakeOptions.indexOf(stake);
  return i == -1 ? '' : matchStakeLabels[i];
}
