import 'package:flutter/material.dart';
import '../core/betting.dart';
import '../core/game_helpers.dart';
import '../core/progression.dart';
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
            const Text(
              'Cum funcționează Multiplayer',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section(
                      icon: Icons.meeting_room_rounded,
                      color: AppColors.blue,
                      title: 'Cameră privată',
                      body: 'Create Room sau Join with Code te bagă într-un lobby cu chat, unde '
                          'aștepți alți jucători reali. Hostul apasă START când sunteți gata.',
                    ),
                    _section(
                      icon: Icons.public_rounded,
                      color: AppColors.play,
                      title: 'Join Online',
                      body: 'Te bagă automat la coadă și te cuplează cu un adversar real — fără '
                          'cod, fără lobby, direct în meci. Poți alege și o cameră deschisă din '
                          'listă, fără să plătești a doua oară.',
                    ),
                    _section(
                      icon: Icons.monetization_on_rounded,
                      color: AppColors.coin,
                      title: 'Taxă + pariu la intrare',
                      body: 'Orice intrare în meci (inclusiv Join Online, care înainte era '
                          'gratuit) costă $multiplayerEntryFee monede taxă fixă, plus un pariu '
                          'ales de tine între ${(minBetPercent * 100).round()}% și '
                          '${(maxBetPercent * 100).round()}% din câte monede ai. Ai nevoie de cel '
                          'puțin $multiplayerMinimumBankroll de monede ca să poți intra. Dacă '
                          'meciul nu apucă să înceapă, primești totul înapoi.',
                    ),
                    _section(
                      icon: Icons.timer_rounded,
                      color: AppColors.play,
                      title: 'Meciul Clasic ține $multiplayerMatchSeconds de secunde',
                      body: 'Același cronometru pentru toată lumea, pornit când hostul apasă '
                          'START. Câte întrebări apuci în minutul ăla ține numai de tine — '
                          'meciul se încheie singur când se termină timpul.',
                    ),
                    _section(
                      icon: Icons.lightbulb_rounded,
                      color: AppColors.orange,
                      title: 'Puncte, hint și greșeli',
                      body: 'Răspuns corect = punctele întrebării. Răspuns greșit = le pierzi pe '
                          'o parte din ele, deci bătutul la nimereală te bagă pe minus.\n'
                          'Ai $multiplayerHintsPerMatch hint-uri pe meci (maximum unul pe '
                          'întrebare): ascund două variante greșite și te costă puncte. NU se '
                          'scad din hint-urile tale și nu costă monede — toți intră în meci cu '
                          'exact aceleași unelte, ca nimeni să nu-și poată cumpăra avantaj.',
                    ),
                    _section(
                      icon: Icons.pie_chart_rounded,
                      color: AppColors.purple,
                      title: 'Cum se împarte pool-ul',
                      body: 'Toate pariurile de la masă formează un pool, din care se ia un '
                          'comision mic. Cea mai mare parte se împarte după cât ai pariat × cât '
                          'de bine ai jucat × cât risc ți-ai asumat, iar restul STRICT după locul '
                          'din clasament, indiferent de mărimea pariului.\n'
                          'La mesele mari, partea împărțită după loc scade — altfel, cu cât '
                          'sunteți mai mulți, cu atât jumătatea de jos ar plăti mai mult vârful. '
                          'Pool-ul crește oricum cu numărul de jucători: locul 1 ia peste 2× miza '
                          'la o masă plină.',
                    ),
                    _section(
                      icon: Icons.balance_rounded,
                      color: AppColors.teal,
                      title: 'De ce nu poate domina un jucător bogat',
                      body: 'Nimeni nu poate paria mai mult de '
                          '${tableCapMedianMultiple.toStringAsFixed(1).replaceAll('.', ',')}× '
                          'mediana mesei — surplusul se returnează, nu intră în pool. Iar partea '
                          'împărțită după clasament nu ține deloc cont de cât ai pariat: dacă '
                          'cineva mizează mult și pierde, banii lui ajung la cei care au rezistat '
                          'până la final, oricât de puțin ar fi pus ei. Cine iese din meci după '
                          'START e tratat ca ultimul clasat.',
                    ),
                    _section(
                      icon: Icons.emoji_events_rounded,
                      color: AppColors.orange,
                      title: 'XP și bonusul zilei',
                      body: 'XP-ul vine din joc, nu din pool: scor × 0,012, plus '
                          '$multiplayerWinXpBonus dacă termini pe locul 1 (sau '
                          '$multiplayerParticipationXpBonus altfel).\n'
                          'Prima victorie multiplayer a zilei aduce în plus '
                          '+$multiplayerFirstWinBonusCoins monede și +$multiplayerFirstWinBonusXp XP.',
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
                child: const Text('Am înțeles', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
