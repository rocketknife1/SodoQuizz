import 'dart:math';

/// Rating vizibil de tip Elo pentru multiplayer — un număr care creşte când
/// baţi jucători buni şi scade când pierzi cu jucători slabi, spre deosebire
/// de `leaguePoints` (±20/±8 fix, indiferent de adversar). Vezi notele de
/// plan, secţiunea RETENŢIE, punctul 5.
///
/// Toate modurile sunt FFA (nu 1v1), deci calculăm PE PERECHI: pentru fiecare
/// adversar, un mini-meci „am terminat peste el / sub el", cu delta scalată de
/// diferenţa de rating. Suma se împarte la numărul de adversari, ca un meci cu
/// 5 jucători să nu mişte ratingul de 4 ori mai mult decât unul cu 2.

const int eloStartRating = 1000;

/// K — cât de repede se mişcă ratingul. 24 e un compromis: destul cât să simţi
/// progresul în câteva meciuri, nu atât cât un singur meci norocos să te urce
/// vizibil peste nivelul real.
const int _eloK = 24;

/// Probabilitatea aşteptată ca [a] să termine peste [b], din diferenţa de
/// rating (formula Elo standard, scală 400).
double _expected(int a, int b) => 1.0 / (1.0 + pow(10, (b - a) / 400.0));

/// Schimbarea de rating pentru un meci în care [myRating] a terminat peste
/// adversarii din [beat] (true) şi sub cei cu false. [opponentRatings] şi
/// [beat] trebuie să aibă aceeaşi lungime. Fără adversari → 0.
///
/// Rezultatul e rotunjit la întreg şi plafonat la ±[_eloK] (un singur meci nu
/// poate mişca mai mult decât K, oricât de dezechilibrat ar fi).
int eloDelta({
  required int myRating,
  required List<int> opponentRatings,
  required List<bool> beat,
}) {
  final n = opponentRatings.length;
  if (n == 0 || beat.length != n) return 0;
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final actual = beat[i] ? 1.0 : 0.0;
    sum += _eloK * (actual - _expected(myRating, opponentRatings[i]));
  }
  final delta = (sum / n).round();
  return delta.clamp(-_eloK, _eloK);
}
