import 'dart:math';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/betting.dart';
import '../core/repeating_animation.dart';
import '../core/game_helpers.dart';
import '../core/lang.dart';
import '../core/theme.dart';

/// Balonul de vorbă care plutește pe Home, în golul dintre mascota Discord
/// (stânga) și Clippy (dreapta), la nivelul lor — NU mai sus, peste panoul de
/// Cultură Generală, unde acoperea variantele de răspuns și nu se mai putea
/// juca. De-aia e și compact: spațiul dintre cele două mascote e îngust
/// (~100dp), iar textul se micșorează singur ca să încapă.
///
/// La tap deschide [BetaInfoDialog] — locul unde explicăm, într-un singur
/// text, ce înseamnă că jocul e în beta, cum funcționează noul multiplayer cu
/// pariuri și, cel mai important pentru jucătorii noi, PE CE SE APASĂ în
/// fiecare mod de joc.
class BetaInfoBalloon extends StatefulWidget {
  const BetaInfoBalloon({super.key});

  @override
  State<BetaInfoBalloon> createState() => _BetaInfoBalloonState();
}

class _BetaInfoBalloonState extends State<BetaInfoBalloon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float;

  @override
  void initState() {
    super.initState();
    _float = RepeatingAnimationController(
        vsync: this, duration: const Duration(milliseconds: 3200))
      ..repeat();
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _float,
      builder: (context, child) {
        final t = _float.value * 2 * pi;
        return Transform.translate(
          offset: Offset(sin(t) * 3, cos(t) * 4),
          child: Transform.rotate(angle: sin(t) * 0.02, child: child),
        );
      },
      child: GestureDetector(
        onTap: () {
          Sfx.tileSelect();
          BetaInfoDialog.show(context);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.orange.withAlpha(170), width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.orange.withAlpha(60),
                      blurRadius: 18,
                      spreadRadius: -4),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🚧', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 5),
                        Text('BETA',
                            style: TextStyle(
                                color: AppColors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(tr('citește aici', 'read this'),
                        style: const TextStyle(color: Colors.white54, fontSize: 9.5)),
                  ),
                ],
              ),
            ),
            // codița balonului, îndreptată în jos, spre spațiul dintre cele
            // două mascote
            CustomPaint(size: const Size(16, 9), painter: _BalloonTailPainter()),
          ],
        ),
      ),
    );
  }
}

class _BalloonTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.38, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF1A1A2E));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.orange.withAlpha(170),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Textul lung din spatele balonului. Un singur dialog scrollabil, cu un
/// singur buton de închidere — același tipar ca [MultiplayerInfoDialog],
/// deliberat NU paginat (popup-ul vechi de intro era paginat si a fost sters
/// că cerea prea multe apăsări).
class BetaInfoDialog extends StatelessWidget {
  const BetaInfoDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const BetaInfoDialog());

  Widget _section(
      {required IconData icon,
      required Color color,
      required String title,
      required String body}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5)),
                const SizedBox(height: 3),
                Text(body,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12.5, height: 1.4)),
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
            const Text('🚧', style: TextStyle(fontSize: 30)),
            const SizedBox(height: 8),
            Text(
              tr('SodoQuizz e în BETA', 'SodoQuizz is in BETA'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section(
                      icon: Icons.construction_rounded,
                      color: AppColors.orange,
                      title: tr('Ce înseamnă „beta"', 'What "beta" means'),
                      body: tr(
                          'Jocul e încă în testare. Nu toate pozele sunt '
                              'încărcate sau editate — unele întrebări arată încă '
                              'imagini provizorii, altele lipsesc de tot. Îl '
                              'dezvolt singur, așa că update-urile vin mai greu '
                              'decât mi-aș dori. Dacă găsești ceva stricat, spune-mi '
                              'pe Discord (marțianul verde de pe ecranul principal).',
                          'The game is still being tested. Not all the pictures are '
                              'uploaded or edited — some questions still show '
                              'placeholder images, others are missing entirely. I build '
                              'this on my own, so updates come slower than I would like. '
                              'If you find something broken, tell me on Discord (the '
                              'green martian on the main screen).'),
                    ),
                    _section(
                      icon: Icons.quiz_rounded,
                      color: AppColors.purple,
                      title: tr('Modul Clasic — cum se joacă', 'Classic mode — how to play'),
                      body: tr(
                          'PLAY → alegi o categorie → plătești taxa de intrare. '
                          'Vezi o poză neclară și 4 variante dedesubt: APEȘI PE '
                          'VARIANTA pe care o crezi corectă. Butonul „Hint" '
                          'limpezește poza (al 2-lea hint elimină 2 variante '
                          'greșite, al 3-lea îți dă un procent de șansă) — costă '
                          'un hint din stoc plus un mic procent din monedele tale. '
                          'Răspuns greșit = pierzi o viață. La fiecare 10 '
                          'întrebări primești un bonus, iar la ieșire recuperezi '
                          'taxa dacă ai destule răspunsuri corecte.',
                          'PLAY → pick a category → pay the entry fee. '
                              'You see a blurred picture and 4 options underneath: TAP THE '
                              'OPTION you think is right. The "Hint" button sharpens the '
                              'picture (the 2nd hint removes 2 wrong options, the 3rd gives '
                              'you a chance percentage) — it costs coins and hints. '
                              'A wrong answer = you lose a life. Every 10 questions you get '
                              'a bonus, and on the way out you get the fee back if you had '
                              'enough correct answers.'),
                    ),
                    _section(
                      icon: Icons.compare_arrows_rounded,
                      color: AppColors.danger,
                      title: tr('Higher or Lower — cum se joacă', 'Higher or Lower — how to play'),
                      body: tr(
                          'Vezi două lucruri: „campionul", cu numărul lui deja '
                          'la vedere, și „provocatorul", cu numărul ascuns. '
                          'APEȘI PE „MAI MULT" sau „MAI PUȚIN" ca să spui dacă '
                          'provocatorul e căutat mai mult sau mai puțin decât '
                          'campionul. Ai 10 secunde. Corect = seria continuă și '
                          'câștigi tot mai mult la fiecare pas; greșit = gata '
                          'seria. În multiplayer toți votează în secret în '
                          'aceeași rundă, o greșeală îți dă o pâine 🍞, iar la '
                          '$higherLowerMaxBreadsLabel pâini ești eliminat și '
                          'rămâi spectator. Ultimul rămas la masă câștigă.',
                          'You see two things: the "champion", with its number already '
                              'visible, and the "challenger", with its number hidden. '
                              'TAP "HIGHER" or "LOWER" to say whether the challenger is '
                              'searched more or less than the champion. You have 10 '
                              'seconds. Correct = the streak continues and you win more at '
                              'every step; wrong = the streak is over. In multiplayer '
                              'everyone votes secretly in the same round, a mistake earns '
                              'you a bread 🍞, and at $higherLowerMaxBreadsLabel breads you '
                              'are eliminated and become a spectator. The last one left at '
                              'the table wins.'),
                    ),
                    _section(
                      icon: Icons.casino_rounded,
                      color: AppColors.coin,
                      title: tr('Multiplayer — o singură miză, aceeași pentru toți',
                          'Multiplayer — one stake, the same for everyone'),
                      body: tr(
                          'Fiecare cameră are o miză, aleasă o singură dată de '
                          'cel care face camera (💰${matchStakeOptions.join(', 💰')}). '
                          'Toți ceilalți plătesc exact aceeași sumă — cine intră '
                          'nu are ce alege. La Join Online e mereu '
                          '💰$publicMatchStake.\n'
                          'Mizele se strâng într-o grămadă, din care jocul '
                          'oprește ${(matchRake * 100).round()}%. Restul merge la '
                          'jumătatea de sus a clasamentului: locul 1 ia dublu '
                          'față de locul 2, locul 2 dublu față de locul 3, și tot '
                          'așa. Ceilalți pierd miza. Tabelul exact se vede în '
                          'cameră, dinainte.',
                          'Every room has a stake, picked once by whoever creates the '
                              'room (💰${matchStakeOptions.join(', 💰')}). '
                              'Everyone else pays exactly the same — joiners have nothing '
                              'to choose. In Join Online it is always '
                              '💰$publicMatchStake.\n'
                              'All stakes go into one pot, from which the game keeps '
                              '${(matchRake * 100).round()}%. The rest goes to the top '
                              'half of the standings: 1st takes double 2nd, 2nd double '
                              '3rd, and so on. The rest lose their stake. The exact table '
                              'is shown in the room, up front.'),
                    ),
                    _section(
                      icon: Icons.timer_rounded,
                      color: AppColors.play,
                      title: tr('Multiplayer Clasic — un minut, contra tuturor',
                          'Classic Multiplayer — one minute, against everyone'),
                      body: tr(
                          'Meciul ține $multiplayerMatchSeconds de secunde, '
                          'același cronometru pentru toți. Răspuns corect = '
                          'punctele întrebării; răspuns GREȘIT = pierzi puncte, '
                          'deci nu merită să bați la nimereală. Ai '
                          '$multiplayerHintsPerMatch hint-uri pe tot meciul '
                          '(maximum unul pe întrebare): îți lasă doar două '
                          'variante și te costă puncte, dar NU se scad din '
                          'hint-urile tale și nu costă monede — la masă toți au '
                          'exact aceleași unelte.',
                          'The match lasts $multiplayerMatchSeconds seconds, the same '
                              'clock for everyone. A correct answer = the question\'s '
                              'points; a WRONG answer = you lose points, so guessing '
                              'wildly is not worth it. You get '
                              '$multiplayerHintsPerMatch hints for the whole match (at '
                              'most one per question): they leave you only two options and '
                              'cost you points, but they do NOT come out of your own hints '
                              'and cost no coins — at the table everyone has exactly the '
                              'same tools.'),
                    ),
                    _section(
                      icon: Icons.balance_rounded,
                      color: AppColors.teal,
                      title: tr('De ce nu te poate „mânca" un jucător bogat',
                          'Why a rich player cannot eat you alive'),
                      body: tr(
                          'La aceeași masă toți pun exact aceeași miză, deci '
                              'nimeni nu poate cumpăra un loc mai bun. Cine are '
                              'multe monede poate face camere cu mize mari, dar în '
                              'camera lui plătește la fel ca tine, iar premiile se '
                              'dau strict după cum ați jucat.',
                          'At the same table everyone puts in exactly the same stake, so '
                              'nobody can buy a better place. Someone with a lot of coins '
                              'can create high-stake rooms, but in their own room they pay '
                              'the same as you, and prizes are handed out strictly by how '
                              'you played.'),
                    ),
                    _section(
                      icon: Icons.tips_and_updates_rounded,
                      color: AppColors.hint,
                      title: tr('De unde faci rost de resurse', 'Where to get resources'),
                      body: tr(
                          'Roata norocului (o dată la 24h) e cel mai mare '
                              'premiu din joc — nu o rata. Clippy (agrafa) îți dă un '
                              'bonus de 3 întrebări fără risc la fiecare 5 minute. '
                              'Cultură Generală merge în runde, cu pauză între ele. '
                              'Plus quest-urile zilnice, care acum dau gems la '
                              'fiecare prag — gems-ul deblochează categorii noi.',
                          'The lucky wheel (once every 24h) is the biggest prize in the '
                              'game — do not miss it. Clippy (the paperclip) gives you a '
                              'risk-free 3-question bonus every 5 minutes. General '
                              'Knowledge runs in rounds, with a break between them. Plus '
                              'the daily quests, which now give gems at every threshold — '
                              'gems unlock new categories.'),
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
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 13)),
                child: Text(tr('Am înțeles', 'Got it'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pragul de eliminare din Higher or Lower multiplayer, ca text — ținut aici
/// ca să nu importăm multiplayer_service.dart (și, prin el, Firebase) doar
/// pentru un număr afișat într-un dialog informativ.
const String higherLowerMaxBreadsLabel = '5';
