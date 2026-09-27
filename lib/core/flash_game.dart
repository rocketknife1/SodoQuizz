/// **Fulgerul** — memorie, nu cunoștințe. O grilă de poze apare pentru o
/// clipă, apoi dispare; întrebarea e „Unde era X?" și răspunzi atingând
/// căsuța unde ai văzut-o. Grila crește și timpul de afișare scade rundă de
/// rundă, deci runda 1 e ușoară pentru oricine și runda 6 cere memorie reală.
///
/// Toți jucătorii văd EXACT aceeași grilă (aceleași poze, în aceeași ordine),
/// aleasă determinist din `matchId` + rundă — vezi [FlashGame.gridFor]. Nimic
/// aleator nu depinde de răspunsuri, deci un client rezolvă runda
/// (MultiplayerService.closeFlashRound) și restul doar animă.
///
/// Fără eliminare: [flashRounds] runde fixe, scorul se adună (mai multe
/// puncte la o grilă mai grea) — la fel ca Piatră-Hârtie-Foarfecă. Simplu
/// și corect: nu atinge `lives`/`eliminated`, câmpuri deja folosite cu alt
/// sens (număr fix de vieți) la Scaunul Electric.
library;

import 'dart:math';

import 'lang.dart';
import 'stable_hash.dart';

const int flashRounds = 10;
const int flashAnswerSeconds = 8;

/// Câte poze are grila la fiecare rundă (0-indexată) — crește, apoi rămâne
/// la maximul de 9 (3×3), destul cât să rămână greu fără să nu mai încapă
/// pe ecranul unui telefon.
int flashGridSize(int round) => [4, 4, 6, 6, 9, 9, 9, 9, 9, 9][round.clamp(0, flashRounds - 1)];

/// Cât stă grila vizibilă înainte să se acopere — scade rundă de rundă.
int flashRevealMsFor(int round) => [3000, 2400, 2000, 1700, 1400, 1200, 1200, 1200, 1200, 1200][round.clamp(0, flashRounds - 1)];

/// Punctele unui răspuns corect — o grilă mai grea dă mai mult, ca runda 9
/// (9 poze, 1,2 s) să conteze cât 3 runde din prima.
int flashPointsFor(int round) => flashGridSize(round) * 3;

/// O poză din pool: doar ce trebuie ca s-o arăți și s-o verifici — motorul
/// nu ține imaginea în sine, doar calea și numele (răspunsul).
class FlashPic {
  const FlashPic({required this.id, required this.answer, required this.imagePath});

  final String id;
  final String answer;
  final String imagePath;
}

class FlashRound {
  const FlashRound({required this.pics, required this.targetIndex});

  final List<FlashPic> pics;
  final int targetIndex;

  FlashPic get target => pics[targetIndex];
}

class FlashGame {
  const FlashGame();

  /// Grila rundei [round], aleasă determinist din [pool] (toate pozele
  /// disponibile) cu sămânța [seed] — același rezultat pe orice telefon.
  /// [pool] trebuie să aibă cel puțin [flashGridSize] elemente distincte;
  /// altfel se reciclează (un joc cu foarte puține poze tot funcționează).
  FlashRound gridFor({required List<FlashPic> pool, required int seed, required int round}) {
    final rng = StableRandom(seed ^ (round * 0x9E3779B1));
    final size = min(flashGridSize(round), pool.length);
    final shuffled = List.of(pool);
    // Fisher–Yates cu StableRandom, ca stableShuffle, dar cu acest `rng`
    // exact — sămânța trebuie să rămână legată de matchId + rundă.
    for (var i = shuffled.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = tmp;
    }
    final pics = shuffled.take(size).toList();
    final target = rng.nextInt(pics.length);
    return FlashRound(pics: pics, targetIndex: target);
  }
}

/// Botul răspunde corect cu o probabilitate care scade cu mărimea grilei
/// (mai multe căsuțe = mai greu de ținut minte) — nu e „a citit poza", e
/// „și-a amintit unde era".
double flashBotAccuracy(int gridSize) => switch (gridSize) {
      <= 4 => 0.75,
      <= 6 => 0.55,
      _ => 0.4,
    };

int flashBotGuess(FlashRound round, Random rnd) {
  if (rnd.nextDouble() < flashBotAccuracy(round.pics.length)) return round.targetIndex;
  final wrong = [for (var i = 0; i < round.pics.length; i++) if (i != round.targetIndex) i];
  return wrong[rnd.nextInt(wrong.length)];
}

String flashRoundTitle(int round) => tr('Memorează grila…', 'Memorize the grid…');
String flashQuestionFor(String answer) => tr('Unde era $answer?', 'Where was $answer?');
