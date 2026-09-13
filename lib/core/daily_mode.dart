import '../models/multiplayer_models.dart';
import 'daily_challenge.dart';
import 'lang.dart';
import 'stable_hash.dart';

/// Modul zilei în multiplayer — „🔥 AZI: Clasic". Un mod evidențiat, ales
/// determinist pe zi (același pentru toată lumea), cu un mic bonus de
/// revendicat DUPĂ ce ai jucat o partidă în el.
///
/// De ce: „Join Online" arunca omul într-un mod aleator din două, iar
/// selectorul de cameră are șase moduri pe care un jucător nou nu le învață
/// deodată. O singură coadă recomandată pe zi = un motiv concret de revenire
/// („azi e piatra-hârtie") și un punct de intrare clar, fără să dispară
/// varietatea (se rotește zilnic).
///
/// Același tipar ca „categoria zilei" (core/gamemodes.dart): pick determinist
/// + recompensă FLAT, nu scalată cu nivelul. NU are clasament separat —
/// clasamentul de sezon multiplayer acoperă deja rezultatele; un board
/// pe-zi-pe-mod ar fi o colecție Firestore care crește fără rost.
///
/// Determinismul: [stableHash] pe cheia zilei, nu `Random(seed)` (care nu e
/// stabil între platforme — vezi core/stable_hash.dart).

/// Modurile pe care „Join Online" (mereu 1 la 1) le poate propune. Tancuri /
/// Obby / Scaunul Electric cer 4-5 jucători într-o arenă fixă, deci n-au ce
/// căuta într-o pereche formată din coadă — la fel ca vechiul
/// `_quickMatchModes` din multiplayer_service.dart.
const List<MatchGameMode> dailyModePool = [
  MatchGameMode.classic,
  MatchGameMode.higherLower,
  MatchGameMode.rockPaperScissors,
];

/// Monede/XP la revendicarea modului zilei — pe scara categoriei zilei
/// (`featuredCategoryCoinReward`), FIX, o dată pe zi. Nu intră în curbele din
/// test/economy_balance_test.dart: e un motiv în plus să deschizi azi, nu
/// venit calculat.
const int dailyModeCoinReward = 20;
const int dailyModeXpReward = 8;

/// Modul evidențiat azi — același pentru toată lumea.
MatchGameMode modeOfDay([DateTime? now]) {
  final key = dailyChallengeDateKey(now ?? DateTime.now());
  final idx = stableHash('modul-zilei-$key').abs() % dailyModePool.length;
  return dailyModePool[idx];
}

/// Numele scurt al unui mod, pentru bannere și dialoguri.
String matchGameModeLabel(MatchGameMode m) => switch (m) {
      MatchGameMode.classic => tr('Clasic', 'Classic'),
      MatchGameMode.higherLower => 'Higher & Lower',
      MatchGameMode.quizzTanks => 'Quizz Tanks',
      MatchGameMode.obby => 'Obby',
      MatchGameMode.rockPaperScissors =>
        tr('Piatră-Hârtie-Foarfecă', 'Rock-Paper-Scissors'),
      MatchGameMode.electricChair => tr('Scaunul Electric', 'Electric Chair'),
    };
