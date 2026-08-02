import 'dart:math';
import 'package:flutter/material.dart';
import '../core/audio.dart';
import '../core/betting.dart';
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
    _float = AnimationController(
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
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('citește aici',
                        style: TextStyle(color: Colors.white54, fontSize: 9.5)),
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
/// deliberat NU paginat (vezi IntroTutorialDialog, dezactivat tocmai pentru
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
            const Text(
              'SodoQuizz e în BETA',
              textAlign: TextAlign.center,
              style: TextStyle(
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
                      title: 'Ce înseamnă „beta"',
                      body: 'Jocul e încă în testare. Nu toate pozele sunt '
                          'încărcate sau editate — unele întrebări arată încă '
                          'imagini provizorii, altele lipsesc de tot. Îl '
                          'dezvolt singur, așa că update-urile vin mai greu '
                          'decât mi-aș dori. Dacă găsești ceva stricat, spune-mi '
                          'pe Discord (marțianul verde de pe ecranul principal).',
                    ),
                    _section(
                      icon: Icons.quiz_rounded,
                      color: AppColors.purple,
                      title: 'Modul Clasic — cum se joacă',
                      body: 'PLAY → alegi o categorie → plătești taxa de intrare. '
                          'Vezi o poză neclară și 4 variante dedesubt: APEȘI PE '
                          'VARIANTA pe care o crezi corectă. Butonul „Hint" '
                          'limpezește poza (al 2-lea hint elimină 2 variante '
                          'greșite, al 3-lea îți dă un procent de șansă) — costă '
                          'un hint din stoc plus un mic procent din monedele tale. '
                          'Răspuns greșit = pierzi o viață. La fiecare 10 '
                          'întrebări primești un bonus, iar la ieșire recuperezi '
                          'taxa dacă ai destule răspunsuri corecte.',
                    ),
                    _section(
                      icon: Icons.compare_arrows_rounded,
                      color: AppColors.danger,
                      title: 'Higher or Lower — cum se joacă',
                      body: 'Vezi două lucruri: „campionul", cu numărul lui deja '
                          'la vedere, și „provocatorul", cu numărul ascuns. '
                          'APEȘI PE „MAI MULT" sau „MAI PUȚIN" ca să spui dacă '
                          'provocatorul e căutat mai mult sau mai puțin decât '
                          'campionul. Ai 10 secunde. Corect = seria continuă și '
                          'câștigi tot mai mult la fiecare pas; greșit = gata '
                          'seria. În multiplayer toți votează în secret în '
                          'aceeași rundă, o greșeală îți dă o pâine 🍞, iar la '
                          '$higherLowerMaxBreadsLabel pâini ești eliminat și '
                          'rămâi spectator. Ultimul rămas la masă câștigă.',
                    ),
                    _section(
                      icon: Icons.casino_rounded,
                      color: AppColors.coin,
                      title: 'Multiplayer — noul sistem de pariuri',
                      body: 'Intrarea în orice meci costă $multiplayerEntryFee '
                          'monede taxă fixă PLUS un pariu ales de tine, între '
                          '${(minBetPercent * 100).round()}% și ${(maxBetPercent * 100).round()}% '
                          'din câte monede ai. Toate pariurile formează un pool '
                          'care se împarte la final: '
                          '${(stakePotShare * 100).round()}% după cât ai pariat, '
                          'cât de bine ai jucat și cât risc ți-ai asumat, iar '
                          '${(placementPotShare * 100).round()}% strict după locul '
                          'în clasament, indiferent de mărimea pariului.',
                    ),
                    _section(
                      icon: Icons.balance_rounded,
                      color: AppColors.teal,
                      title: 'De ce nu te poate „mânca" un jucător bogat',
                      body: 'Masa are un plafon: nimeni nu poate pune mai mult '
                          'de ${tableCapMedianMultiple.toStringAsFixed(1).replaceAll('.', ',')}× '
                          'mediana pariurilor de la masă — surplusul i se '
                          'returnează, nu intră în joc. Iar partea de pool '
                          'împărțită după clasament nu ține deloc cont de cât ai '
                          'pariat. Concret: dacă cineva pariază mult și pierde, '
                          'banii lui ajung în mare parte la cei care au rezistat '
                          'până la final — chiar dacă ei au pus foarte puțin. '
                          'A paria enorm la o masă mică e, matematic, o idee '
                          'proastă.',
                    ),
                    _section(
                      icon: Icons.tips_and_updates_rounded,
                      color: AppColors.hint,
                      title: 'De unde faci rost de resurse',
                      body: 'Roata norocului (o dată la 24h) e cel mai mare '
                          'premiu din joc — nu o rata. Clippy (agrafa) îți dă un '
                          'bonus de 3 întrebări fără risc la fiecare 5 minute. '
                          'Cultură Generală merge în runde, cu pauză între ele. '
                          'Plus quest-urile zilnice, care acum dau gems la '
                          'fiecare prag — gems-ul deblochează categorii noi.',
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
                child: const Text('Am înțeles',
                    style: TextStyle(
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
