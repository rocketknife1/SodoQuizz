import 'package:flutter/material.dart';
import '../core/betting.dart';
import '../core/electric_chair.dart';
import '../core/game_helpers.dart';
import '../core/lang.dart';
import '../core/obby.dart';
import '../core/progression.dart';
import '../core/tanks.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';

/// Popup explicativ pentru ecranul de Multiplayer: cameră privată vs. Join
/// Online, taxa de intrare în lobby și formula de recompensă la finalul
/// meciului. Spre deosebire de IntroTutorialDialog (dezactivat în
/// home_screen.dart pentru că cerea prea multe apăsări paginate la prima
/// intrare), e un singur dialog scrollabil, cu un singur buton de închidere.
/// Arătat automat o singură dată ([maybeShow]), dar redeschidere oricând din
/// iconița ℹ️ din MultiplayerScreen ([show]).
class MultiplayerInfoDialog extends StatelessWidget {
  const MultiplayerInfoDialog({super.key});

  /// Exemplele din text se CALCULEAZĂ din aceleași funcții ca premiile reale
  /// (core/betting.dart) — dacă se schimbă vreodată miza sau comisionul,
  /// explicația nu are cum să rămână în urmă cu cifre false.
  static const int _exampleStake = defaultMatchStake;
  static int get _exampleWinnerOf2 => matchPrizes(stake: _exampleStake, players: 2).first;
  static int get _exampleWinnerOf4 => matchPrizes(stake: _exampleStake, players: 4)[0];
  static int get _exampleSecondOf4 => matchPrizes(stake: _exampleStake, players: 4)[1];

  static Future<void> maybeShow(BuildContext context) async {
    final seen = await StorageService.getMultiplayerInfoSeen();
    if (seen || !context.mounted) return;
    await StorageService.setMultiplayerInfoSeen(true);
    if (!context.mounted) return;
    await show(context);
  }

  static Future<void> show(BuildContext context) {
    return showDialog(context: context, builder: (_) => const MultiplayerInfoDialog());
  }

  Widget _section({required IconData icon, required Color color, required String title, required String body}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
                const SizedBox(height: 3),
                Text(body, style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_rounded, color: AppColors.blue, size: 36),
            const SizedBox(height: 8),
            Text(
              tr('Cum funcționează Multiplayer', 'How Multiplayer works'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section(
                      icon: Icons.monetization_on_rounded,
                      color: AppColors.coin,
                      title: tr('Miza — o singură cifră', 'The stake — one single number'),
                      body: tr(
                          'Fiecare cameră are o miză. O alege o singură dată cel care face '
                              'camera (💰${matchStakeOptions.join(', 💰')}), iar toți ceilalți plătesc '
                              'exact aceeași sumă — cine intră nu are ce alege.\n'
                              'La Join Online miza e mereu 💰$publicMatchStake, fiindcă acolo nu '
                              'există nimeni care s-o aleagă.\n'
                              'Dacă meciul nu apucă să înceapă, primești miza înapoi.',
                          'Every room has a stake. Whoever creates the room picks it once '
                              '(💰${matchStakeOptions.join(', 💰')}), and everyone else pays exactly '
                              'the same — joiners have nothing to choose.\n'
                              'In Join Online the stake is always 💰$publicMatchStake, because there '
                              'is nobody there to pick it.\n'
                              'If the match never starts, you get your stake back.'),
                    ),
                    _section(
                      icon: Icons.pie_chart_rounded,
                      color: AppColors.purple,
                      title: tr('Cine ia și cine pierde', 'Who wins and who loses'),
                      body: tr(
                          'Mizele se strâng într-o grămadă. Premiile merg doar la jumătatea de '
                              'sus a clasamentului: locul 1 ia dublu față de locul 2, locul 2 dublu '
                              'față de locul 3, și tot așa. Ceilalți pierd miza.\n'
                              'De exemplu, în doi cu miza 💰$_exampleStake: câștigătorul ia '
                              '💰$_exampleWinnerOf2, celălalt nu ia nimic. În patru: locul 1 ia '
                              '💰$_exampleWinnerOf4, locul 2 ia 💰$_exampleSecondOf4, locurile 3 și 4 '
                              'nu iau nimic.\n'
                              'Tabelul exact se vede în cameră, dinainte, și se actualizează pe '
                              'măsură ce intră lume — nu trebuie să calculezi nimic.',
                          'All stakes go into one pot. Prizes only reach the top half of the '
                              'standings: 1st place takes double 2nd, 2nd double 3rd, and so on. '
                              'Everyone else loses their stake.\n'
                              'For example, heads-up at 💰$_exampleStake: the winner takes '
                              '💰$_exampleWinnerOf2, the other gets nothing. With four players: 1st takes '
                              '💰$_exampleWinnerOf4, 2nd takes 💰$_exampleSecondOf4, 3rd and 4th get '
                              'nothing.\n'
                              'The exact table is shown in the room, up front, and updates as people '
                              'join — you never have to calculate anything.'),
                    ),
                    _section(
                      icon: Icons.percent_rounded,
                      color: AppColors.teal,
                      title: tr('Comisionul jocului', 'The game\'s cut'),
                      body: tr(
                          'Din grămadă, jocul oprește ${(matchRake * 100).round()}%. Restul se '
                              'împarte între jucători. Nu există alte taxe ascunse.\n'
                              'La egalitate de scor, cei egali împart premiile lor între ei.',
                          'The game keeps ${(matchRake * 100).round()}% of the pot. The rest is '
                              'split between players. There are no other hidden fees.\n'
                              'On a tied score, the tied players split their prizes between them.'),
                    ),
                    _section(
                      icon: Icons.military_tech_rounded,
                      color: AppColors.orange,
                      title: tr('Quizz Tanks — singurul mod fără miză',
                          'Quizz Tanks — the one mode with no stake'),
                      body: tr(
                          'Până la $tanksPlayerCount tancuri, întrebări de cultură generală, '
                              '$tanksRoundSeconds secunde de răspuns. Cine nimerește răspunsul '
                              'primește ecranul de țintire și alege, în $tanksTargetSeconds secunde, '
                              'PE CINE trage; cine a răspuns corect e și mult mai greu de lovit. '
                              'Fiecare pornește cu $tanksMaxHp viață și pierde '
                              '$tanksDamageMin-$tanksDamageMax la o lovitură primită.\n'
                              'Aici NU se pune miză și nu pierzi nimic din balanță. La final se '
                              'împarte pradă — monede, inimi, hints și, rar, gems — după cât ai '
                              'lovit. Cine face cele mai multe daune ia cel mai mult.',
                          'Up to $tanksPlayerCount tanks, general knowledge questions, '
                              '$tanksRoundSeconds seconds to answer. Whoever gets it right goes to '
                              'the targeting screen and picks, in $tanksTargetSeconds seconds, WHO '
                              'they shoot; answering correctly also makes you much harder to hit. '
                              'Everyone starts at $tanksMaxHp health and loses '
                              '$tanksDamageMin-$tanksDamageMax per hit taken.\n'
                              'There is NO stake here and nothing leaves your balance. At the end '
                              'there is salvage — coins, hearts, hints and, rarely, gems — split by '
                              'how much damage you dealt. The biggest gunner takes the most.'),
                    ),
                    _section(
                      icon: Icons.directions_run_rounded,
                      color: AppColors.play,
                      title: 'Obby',
                      body: tr(
                          'De la 2 la $obbyMaxPlayers personaje pe aceeași pistă de obstacole, '
                              'filmate din spate. Răspunzi corect la o întrebare de cultură generală '
                              '($obbyRoundSeconds secunde), apoi alegi, din $obbyPlatformChoiceCount '
                              'plăci, pe care sari — una e falsă. Sari cu bine și treci obstacolul; '
                              'greșești sau nimerești placa falsă și rămâi pe loc, fără eliminare. '
                              'Primul care trece de toate cele $obbyObstacleCount obstacole câștigă '
                              'pe loc.',
                          'From 2 to $obbyMaxPlayers characters on the same obstacle course, filmed '
                              'from behind. Answer a general-knowledge question correctly '
                              '($obbyRoundSeconds seconds), then pick, out of $obbyPlatformChoiceCount '
                              'platforms, which one you jump on — one is fake. Jump safely and you '
                              'clear the obstacle; get it wrong or land on the fake platform and you '
                              'stay put, no elimination. First to clear all $obbyObstacleCount '
                              'obstacles wins instantly.'),
                    ),
                    _section(
                      icon: Icons.electric_bolt_rounded,
                      color: AppColors.danger,
                      title: tr('Scaunul Electric', 'Electric Chair'),
                      body: tr(
                          'Până la $electricChairPlayerCount jucători, $electricChairMaxLives vieți '
                              'fiecare. Cine răspunde corect la propria întrebare '
                              '($electricChairAnswerSeconds secunde) capătă dreptul să aleagă pe '
                              'cineva pentru scaun ȘI una din patru întrebări pentru el. Victima '
                              'răspunde corect și scapă neatinsă, sau greșește și pierde o viață. La '
                              'zero vieți e eliminată, dar rămâne la masă ca spectator. Ultimul rămas '
                              'în viață iese pe primul loc în clasament.',
                          'Up to $electricChairPlayerCount players, $electricChairMaxLives lives '
                              'each. Whoever answers their own question correctly '
                              '($electricChairAnswerSeconds seconds) earns the right to pick someone '
                              'for the chair AND one of four questions for them. The victim answers '
                              'correctly and walks away unharmed, or gets it wrong and loses a life. '
                              'At zero lives they are eliminated but stay at the table as a '
                              'spectator. The last one standing takes first place.'),
                    ),
                    _section(
                      icon: Icons.meeting_room_rounded,
                      color: AppColors.blue,
                      title: tr('Cameră privată', 'Private room'),
                      body: tr(
                          'Create Room sau Join with Code te bagă într-un lobby cu chat, unde '
                              'aștepți alți jucători reali. Gazda apasă START când sunteți gata.\n'
                              'Dacă gazda pleacă din lobby, camera se închide, toată lumea iese '
                              'automat și fiecare își primește miza înapoi.',
                          'Create Room or Join with Code puts you in a lobby with chat, where you '
                              'wait for other real players. The host presses START when you are ready.\n'
                              'If the host leaves the lobby, the room closes, everyone is kicked out '
                              'automatically and each gets their stake back.'),
                    ),
                    _section(
                      icon: Icons.public_rounded,
                      color: AppColors.play,
                      title: 'Join Online',
                      body: tr(
                          'Te bagă automat la coadă și te cuplează cu un adversar real — fără '
                              'cod, fără lobby, direct în meci. Poți alege și o cameră deschisă din '
                              'listă; dacă are altă miză, se reglează automat doar diferența.',
                          'It queues you automatically and matches you with a real opponent — no '
                              'code, no lobby, straight into the match. You can also pick an open room '
                              'from the list; if its stake differs, only the difference is adjusted.'),
                    ),
                    _section(
                      icon: Icons.timer_rounded,
                      color: AppColors.play,
                      title: tr('Meciul Clasic ține $multiplayerMatchSeconds de secunde',
                          'A Classic match lasts $multiplayerMatchSeconds seconds'),
                      body: tr(
                          'Același cronometru pentru toată lumea, pornit când hostul apasă '
                              'START. Câte întrebări apuci în minutul ăla ține numai de tine — '
                              'meciul se încheie singur când se termină timpul.',
                          'The same clock for everyone, started when the host presses START. How '
                              'many questions you get through in that time is entirely up to you — the '
                              'match ends by itself when the time runs out.'),
                    ),
                    _section(
                      icon: Icons.lightbulb_rounded,
                      color: AppColors.orange,
                      title: tr('Puncte, hint și greșeli', 'Points, hints and mistakes'),
                      body: tr(
                          'Răspuns corect = punctele întrebării. Răspuns greșit = le pierzi pe '
                              'o parte din ele, deci bătutul la nimereală te bagă pe minus.\n'
                              'Ai $multiplayerHintsPerMatch hint-uri pe meci (maximum unul pe '
                              'întrebare): ascund două variante greșite și te costă puncte. NU se '
                              'scad din hint-urile tale și nu costă monede — toți intră în meci cu '
                              'exact aceleași unelte, ca nimeni să nu-și poată cumpăra avantaj.',
                          'A correct answer = the question\'s points. A wrong answer = you lose part '
                              'of them, so guessing wildly puts you in the negative.\n'
                              'You get $multiplayerHintsPerMatch hints per match (at most one per '
                              'question): they hide two wrong options and cost you points. They do NOT '
                              'come out of your own hints and cost no coins — everyone enters a match '
                              'with exactly the same tools, so nobody can buy an advantage.'),
                    ),
                    _section(
                      icon: Icons.balance_rounded,
                      color: AppColors.teal,
                      title: tr('De ce nu poate domina un jucător bogat',
                          'Why a rich player cannot dominate'),
                      body: tr(
                          'Nimeni nu poate pune mai mult decât ceilalți: la aceeași masă, toți '
                              'plătesc exact aceeași miză. Banii nu pot cumpăra un loc mai bun — '
                              'contează doar cât de bine joci.\n'
                              'Cine iese din meci după START e tratat ca ultimul clasat.',
                          'Nobody can put in more than the others: at the same table, everyone pays '
                              'exactly the same stake. Money cannot buy a better place — only how well '
                              'you play counts.\n'
                              'Anyone who quits the match after START is treated as last place.'),
                    ),
                    _section(
                      icon: Icons.emoji_events_rounded,
                      color: AppColors.orange,
                      title: tr('XP și bonusul zilei', 'XP and the daily bonus'),
                      body: tr(
                          'XP-ul vine din joc, nu din pool: scor × 0,012, plus '
                              '$multiplayerWinXpBonus dacă termini pe locul 1 (sau '
                              '$multiplayerParticipationXpBonus altfel).\n'
                              'Prima victorie multiplayer a zilei aduce în plus '
                              '+$multiplayerFirstWinBonusCoins monede și +$multiplayerFirstWinBonusXp XP.',
                          'XP comes from playing, not from the pot: score × 0.012, plus '
                              '$multiplayerWinXpBonus if you finish 1st (or '
                              '$multiplayerParticipationXpBonus otherwise).\n'
                              'Your first multiplayer win of the day adds '
                              '+$multiplayerFirstWinBonusCoins coins and +$multiplayerFirstWinBonusXp XP.'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue, padding: const EdgeInsets.symmetric(vertical: 13)),
                child: Text(tr('Am înțeles', 'Got it'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
