import 'dart:math';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/betting.dart';
import '../core/repeating_animation.dart';
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
                          'Jocul e în testare și îl fac singur: unele poze sunt '
                              'provizorii sau lipsesc. Găsești ceva stricat? Scrie-mi '
                              'pe Discord (marțianul verde de pe Home) sau din '
                              'Setări → „Mesaj către admin".',
                          'The game is in testing and I build it alone: some pictures are '
                              'placeholders or missing. Found something broken? Tell me on '
                              'Discord (the green martian on Home) or from '
                              'Settings → "Message the admin".'),
                    ),
                    _section(
                      icon: Icons.quiz_rounded,
                      color: AppColors.purple,
                      title: tr('Cum se joacă', 'How to play'),
                      body: tr(
                          'PLAY → categorie → apeși varianta corectă din 4. „Hint" '
                              'limpezește poza; răspuns greșit = o viață mai puțin.\n'
                              'Higher or Lower: ghicești dacă provocatorul e căutat '
                              'MAI MULT sau MAI PUȚIN decât campionul.\n'
                              'Cultură Generală (pe Home) e gratis, în runde scurte.',
                          'PLAY → category → tap the right one out of 4. "Hint" sharpens '
                              'the picture; a wrong answer = one life less.\n'
                              'Higher or Lower: guess whether the challenger is searched '
                              'MORE or LESS than the champion.\n'
                              'General Knowledge (on Home) is free, in short rounds.'),
                    ),
                    _section(
                      icon: Icons.groups_rounded,
                      color: AppColors.teal,
                      title: tr('Multiplayer — 6 moduri', 'Multiplayer — 6 modes'),
                      body: tr(
                          'Clasic, Higher or Lower, Quizz Tanks, Obby, '
                              'Piatră-Hârtie-Foarfecă și Scaunul Electric.\n'
                              'Toți din cameră plătesc EXACT aceeași miză '
                              '(💰${matchStakeOptions.join(', 💰')}; Join Online e mereu '
                              '💰$publicMatchStake, iar Quizz Tanks e gratuit). Din pot '
                              'jocul oprește ${(matchRake * 100).round()}%, restul merge '
                              'la jumătatea de sus a clasamentului. Nimeni nu poate '
                              'cumpăra un loc mai bun.',
                          'Classic, Higher or Lower, Quizz Tanks, Obby, '
                              'Rock-Paper-Scissors and Electric Chair.\n'
                              'Everyone in a room pays EXACTLY the same stake '
                              '(💰${matchStakeOptions.join(', 💰')}; Join Online is always '
                              '💰$publicMatchStake, and Quizz Tanks is free). The game '
                              'keeps ${(matchRake * 100).round()}% of the pot, the rest '
                              'goes to the top half of the standings. Nobody can buy a '
                              'better place.'),
                    ),
                    _section(
                      icon: Icons.tips_and_updates_rounded,
                      color: AppColors.hint,
                      title: tr('De unde iei resurse', 'Where to get resources'),
                      body: tr(
                          'Roata norocului (24h) — cel mai mare premiu, nu o rata. '
                              'Clippy (agrafa) — bonus la 5 minute. Planeta '
                              'hologramelor — recompense pe ture. Quest-urile zilnice '
                              'dau gems, iar gems-ul deblochează categorii. Sezoanele '
                              'și liga premiază unde ajungi în clasament.',
                          'The lucky wheel (24h) — the biggest prize, do not miss it. '
                              'Clippy (the paperclip) — a bonus every 5 minutes. The '
                              'hologram planet — rewards per run. Daily quests give gems, '
                              'and gems unlock categories. Seasons and the league reward '
                              'how high you finish.'),
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
