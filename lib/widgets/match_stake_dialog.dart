import 'package:flutter/material.dart';
import '../core/betting.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';

/// Tot ce ține de MIZA unei camere: alegerea ei (doar la creare), confirmarea
/// la intrare și tabelul de premii — vezi `core/betting.dart` pentru regulă.
///
/// Ideea de bază a acestui fișier: fiindcă premiile depind doar de miză și de
/// câți jucători sunt, nu mai explicăm nimic cu formule — ARĂTĂM tabelul.
/// Același tabel apare în dialogul de creare, în cel de intrare și, live, în
/// lobby, unde se rearanjează pe măsură ce intră lume.

/// Regula scrisă o singură dată, folosită în toate dialogurile și în ecranul
/// de informații, ca să nu existe două formulări care se bat cap în cap.
String get matchPrizeRuleText => tr(
    'Toți pun aceeași miză. Premiile merg doar la jumătatea de sus a '
        'clasamentului: locul 1 ia dublu față de locul 2, locul 2 dublu față de '
        'locul 3, și tot așa. Restul pierd miza. Jocul oprește 10% din grămadă.',
    'Everyone puts in the same stake. Prizes only go to the top half of the '
        'standings: 1st place takes double 2nd, 2nd double 3rd, and so on. The '
        'rest lose their stake. The game keeps 10% of the pot.');

/// Tabelul de premii pentru o miză și un număr de jucători: ce ia fiecare loc
/// și cât iese în plus sau în minus față de miza pusă.
class MatchPrizeTable extends StatelessWidget {
  final int stake;
  final int players;

  /// Locul propriu, dacă e cunoscut — se evidențiază rândul.
  final int? highlightPlace;

  const MatchPrizeTable({
    super.key,
    required this.stake,
    required this.players,
    this.highlightPlace,
  });

  static const _medals = ['🥇', '🥈', '🥉'];

  @override
  Widget build(BuildContext context) {
    if (players < 2) {
      return Text(
        tr('Premiile se văd de îndată ce intră al doilea jucător.',
            'Prizes appear as soon as a second player joins.'),
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      );
    }
    final prizes = matchPrizes(stake: stake, players: players);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < players; i++) _row(i, prizes[i]),
      ],
    );
  }

  Widget _row(int index, int prize) {
    final delta = prize - stake;
    final mine = highlightPlace != null && highlightPlace == index + 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: mine ? AppColors.blue.withAlpha(45) : Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(10),
        border: mine ? Border.all(color: AppColors.blue) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              index < _medals.length ? _medals[index] : '${index + 1}',
              style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Text('Locul ${index + 1}',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ),
          Text('💰$prize',
              style: TextStyle(
                color: prize > 0 ? AppColors.coin : Colors.white38,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              )),
          SizedBox(
            width: 62,
            child: Text(
              delta >= 0 ? '+$delta' : '$delta',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: delta >= 0 ? AppColors.play : AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rezumatul de o linie al mesei: cât e miza, cât s-a strâns, ce ia locul 1.
/// Folosit în lobby, unde nu încape tabelul întreg — un tap îl deschide.
class MatchPrizeStrip extends StatelessWidget {
  final int stake;
  final int players;
  const MatchPrizeStrip({super.key, required this.stake, required this.players});

  @override
  Widget build(BuildContext context) {
    final prizes = matchPrizes(stake: stake, players: players);
    final first = prizes.isEmpty ? 0 : prizes.first;
    final second = prizes.length > 1 ? prizes[1] : 0;
    return GestureDetector(
      onTap: () => showMatchPrizesDialog(context, stake: stake, players: players),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.coin.withAlpha(25),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.coin.withAlpha(110)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${tr('Miza', 'Stake')}: 💰$stake',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                Text('${tr('pe masă', 'on the table')}: 💰${matchPot(stake: stake, players: players)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              players < 2
                  ? tr('Premiile apar când intră al doilea jucător',
                      'Prizes appear when a second player joins')
                  : '🥇 $first   🥈 $second   •   ${tr('apasă pentru tot tabelul', 'tap for the full table')}',
              style: const TextStyle(color: AppColors.coin, fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showMatchPrizesDialog(
  BuildContext context, {
  required int stake,
  required int players,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(tr('Premii la ${players < 2 ? 2 : players} jucători',
              'Prizes with ${players < 2 ? 2 : players} players'),
          style: const TextStyle(color: Colors.white, fontSize: 17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _potLine(stake, players < 2 ? 2 : players),
            const SizedBox(height: 10),
            MatchPrizeTable(stake: stake, players: players < 2 ? 2 : players),
            const SizedBox(height: 10),
            Text(matchPrizeRuleText,
                style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.35)),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.play),
          child: Text(tr('Am înțeles', 'Got it'), style: const TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

Widget _potLine(int stake, int players) {
  return Text(
    tr(
        '$players jucători × 💰$stake = 💰${matchPot(stake: stake, players: players)} pe masă.\n'
            'Se împart 💰${matchPrizePool(stake: stake, players: players)} (restul e comisionul jocului).',
        '$players players × 💰$stake = 💰${matchPot(stake: stake, players: players)} on the table.\n'
            '💰${matchPrizePool(stake: stake, players: players)} gets shared out (the rest is the game\'s cut).'),
    style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
  );
}

/// Alegerea mizei — se întâmplă O SINGURĂ DATĂ pe cameră, la creare. Cine
/// intră după aceea nu mai alege nimic, plătește exact miza camerei.
///
/// Întoarce `null` dacă jucătorul renunță sau nu are nici măcar
/// [minMatchStake] monede.
Future<int?> pickMatchStake(BuildContext context) async {
  final coins = await StorageService.getCoins();
  if (!context.mounted) return null;
  if (coins < minMatchStake) {
    await _notEnoughCoins(context, needed: minMatchStake, coins: coins);
    return null;
  }
  return showDialog<int>(
    context: context,
    builder: (_) => _StakePickerDialog(coins: coins),
  );
}

/// Confirmarea la INTRAREA într-o cameră deja existentă (cod, listă, Join
/// Online): miza nu se alege, doar se arată cât costă și ce se poate câștiga.
/// Întoarce `true` dacă jucătorul a apăsat „Intră".
///
/// [alreadyPaid] e cât a scos deja din buzunar pentru intrarea asta — cazul
/// real e cineva care a plătit miza de Join Online și alege apoi o cameră din
/// listă, cu altă miză. Se scade doar DIFERENȚA, și tot pe diferență se face
/// și verificarea de „ai destule monede": altfel un jucător cu 123 de monede,
/// din care 50 deja plătiți, era refuzat la o cameră de 150 pe care de fapt
/// și-o permitea.
Future<bool> confirmMatchStake(
  BuildContext context, {
  required int stake,
  required String title,
  String? subtitle,
  int players = 2,
  int alreadyPaid = 0,
}) async {
  // O cameră fără miză nu poate veni decât de la un telefon rămas pe o
  // versiune mai veche a jocului (înainte ca miza să fie a camerei, nu a
  // fiecăruia). Nu intrăm: masa aia n-ar avea ce împărți la final, iar
  // jucătorul ar juca degeaba fără să înțeleagă de ce.
  if (stake <= 0) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Cameră veche', 'Outdated room'), style: const TextStyle(color: Colors.white)),
        content: Text(
          tr(
              'Camera asta a fost făcută cu o versiune mai veche a jocului și nu '
                  'are miză. Roagă-l pe cel care a făcut-o să actualizeze aplicația.',
              'This room was created with an older version of the game and has no '
                  'stake. Ask whoever created it to update the app.'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.play),
            child: Text(tr('Am înțeles', 'Got it'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return false;
  }
  final coins = await StorageService.getCoins();
  if (!context.mounted) return false;
  final due = stake - alreadyPaid;
  if (coins < due) {
    await _notEnoughCoins(context, needed: due, coins: coins);
    return false;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Intri cu 💰$stake. Ai 💰$coins.', 'You join with 💰$stake. You have 💰$coins.'),
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            if (alreadyPaid > 0) ...[
              const SizedBox(height: 4),
              Text(
                due > 0
                    ? tr('Ai plătit deja 💰$alreadyPaid, deci mai scădem doar 💰$due.',
                        'You already paid 💰$alreadyPaid, so we only take 💰$due more.')
                    : due == 0
                        ? tr('Ai plătit deja exact atât — nu mai scădem nimic.',
                            'You already paid exactly this — nothing more is taken.')
                        : tr('Ai plătit deja 💰$alreadyPaid, deci îți dăm înapoi 💰${-due}.',
                            'You already paid 💰$alreadyPaid, so we give you 💰${-due} back.'),
                style: const TextStyle(color: AppColors.coin, fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ],
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.35)),
            ],
            const SizedBox(height: 12),
            Text(tr('Dacă jucați $players:', 'If $players of you play:'),
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            MatchPrizeTable(stake: stake, players: players),
            const SizedBox(height: 8),
            Text(
              tr('Dacă meciul nu apucă să înceapă, primești miza înapoi.',
                  'If the match never starts, you get your stake back.'),
              style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('Renunță', 'Cancel'))),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.play),
          child: Text(due > 0 ? '${tr('Intră', 'Join')}  •  💰$due' : tr('Intră', 'Join'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

Future<void> _notEnoughCoins(BuildContext context, {required int needed, required int coins}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(tr('Nu poți intra încă', 'You cannot join yet'), style: const TextStyle(color: Colors.white)),
      content: Text(
        tr('Îți trebuie 💰$needed ca să intri. Ai 💰$coins.',
            'You need 💰$needed to join. You have 💰$coins.'),
        style: const TextStyle(color: Colors.white70),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.play),
          child: Text(tr('Am înțeles', 'Got it'), style: const TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

class _StakePickerDialog extends StatelessWidget {
  final int coins;
  const _StakePickerDialog({required this.coins});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(tr('Cu cât se joacă?', 'How high are the stakes?'), style: const TextStyle(color: Colors.white, fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Alegi o singură dată, pentru toată camera. Ai 💰$coins.',
                    'You pick once, for the whole room. You have 💰$coins.'),
                style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.35)),
            const SizedBox(height: 12),
            for (var i = 0; i < matchStakeOptions.length; i++) ...[
              _StakeOption(
                stake: matchStakeOptions[i],
                label: matchStakeLabels[i],
                affordable: coins >= matchStakeOptions[i],
                recommended: matchStakeOptions[i] == defaultMatchStake,
                onTap: () => Navigator.pop(context, matchStakeOptions[i]),
              ),
              if (i != matchStakeOptions.length - 1) const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
            Text(matchPrizeRuleText,
                style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.35)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Anulează', 'Cancel'))),
      ],
    );
  }
}

/// Un rând din alegerea mizei. Arată exact ce ia învingătorul într-un meci de
/// 2 — cea mai mică masă posibilă, deci cel mai prudent exemplu; cu cât intră
/// mai multă lume, cu atât premiul crește.
class _StakeOption extends StatelessWidget {
  final int stake;
  final String label;
  final bool affordable;
  final bool recommended;
  final VoidCallback onTap;

  const _StakeOption({
    required this.stake,
    required this.label,
    required this.affordable,
    required this.recommended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final winner = matchPrizes(stake: stake, players: 2).first;
    final color = affordable ? AppColors.coin : Colors.white24;
    return Opacity(
      opacity: affordable ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: affordable ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withAlpha(affordable ? 150 : 80)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(tr('Miză $label', '$label stake'),
                              style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
                          if (recommended) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.play.withAlpha(60),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(tr('obișnuită', 'usual'),
                                  style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        affordable
                            ? tr('În doi: câștigătorul ia 💰$winner, celălalt pierde 💰$stake.',
                                'Heads-up: the winner takes 💰$winner, the other loses 💰$stake.')
                            : tr('Nu ai destule monede.', 'Not enough coins.'),
                        style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text('💰$stake',
                    style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
