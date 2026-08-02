import 'package:flutter/material.dart';
import '../core/betting.dart';
import '../core/theme.dart';
import '../data/storage_service.dart';

/// Ce a ales jucătorul la intrarea într-un meci: taxa fixă (mereu
/// [multiplayerEntryFee]) plus pariul propriu-zis.
class MatchStake {
  final int bet;
  final double betPercent;
  const MatchStake({required this.bet, required this.betPercent});

  /// Cât se scade din portofel la intrare — taxa fixă (sink, nu se întoarce
  /// decât dacă meciul nu pornește) plus pariul (intră în pool).
  int get total => multiplayerEntryFee + bet;
}

/// Dialogul de intrare în meci: taxă fixă + un slider de risc 5%-85% din
/// monedele rămase după taxă. Înlocuiește vechea confirmare de taxă fixă —
/// acum intrarea e o decizie, nu un simplu "ok".
///
/// Întoarce `null` dacă jucătorul renunță sau nu are minimul necesar
/// ([multiplayerMinimumBankroll]).
Future<MatchStake?> pickMatchStake(BuildContext context) async {
  final coins = await StorageService.getCoins();
  if (!context.mounted) return null;
  if (coins < multiplayerMinimumBankroll) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Nu poți intra încă', style: TextStyle(color: Colors.white)),
        content: Text(
          'Ca să intri într-un meci ai nevoie de cel puțin '
          '$multiplayerMinimumBankroll de monede: $multiplayerEntryFee taxă de '
          'intrare + minim $minBetAmount pariu.\n\nAi $coins.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.play),
            child: const Text('Am înțeles', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return null;
  }
  return showDialog<MatchStake>(
    context: context,
    builder: (_) => _StakeDialog(coins: coins),
  );
}

class _StakeDialog extends StatefulWidget {
  final int coins;
  const _StakeDialog({required this.coins});

  @override
  State<_StakeDialog> createState() => _StakeDialogState();
}

class _StakeDialogState extends State<_StakeDialog> {
  double _percent = defaultBetPercent;

  int get _bet => betAmountFor(coins: widget.coins, percent: _percent);

  /// Procentul REAL pe care îl reprezintă pariul (poate diferi de slider dacă
  /// s-a lovit de [minBetAmount] la un portofel mic) — el contează în
  /// formulă, deci el se și trimite mai departe.
  double get _effectivePercent {
    final afterFee = widget.coins - multiplayerEntryFee;
    if (afterFee <= 0) return minBetPercent;
    return (_bet / afterFee).clamp(minBetPercent, maxBetPercent);
  }

  @override
  Widget build(BuildContext context) {
    final bet = _bet;
    final estimate2 = estimateTopPayout(bet: bet, betPercent: _effectivePercent, players: 2);
    final estimate5 = estimateTopPayout(bet: bet, betPercent: _effectivePercent, players: 5);
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Cât pariezi?', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Taxă de intrare: $multiplayerEntryFee monede (nu se întoarce decât '
            'dacă meciul nu apucă să înceapă).',
            style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${(_percent * 100).round()}% din ce ai',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              Text('💰 $bet',
                  style: const TextStyle(
                      color: AppColors.coin, fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
          Slider(
            value: _percent,
            min: minBetPercent,
            max: maxBetPercent,
            divisions: 16,
            activeColor: AppColors.coin,
            inactiveColor: Colors.white24,
            label: '${(_percent * 100).round()}%',
            onChanged: (v) => setState(() => _percent = v),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dacă termini primul: ~$estimate2 la o masă de 2 · ~$estimate5 la una de 5.',
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Estimările presupun că toți pariază ca tine. Cu cât riscul și '
                  'numărul de jucători sunt mai mari, cu atât premiul crește — dar '
                  'ultimul clasat pleacă mereu cu mult mai puțin decât a pus.',
                  style: TextStyle(color: Colors.white38, fontSize: 10.5, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Total la intrare: ${multiplayerEntryFee + bet} monede (ai ${widget.coins}).',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Renunță')),
        ElevatedButton(
          onPressed: () => Navigator.pop(
              context, MatchStake(bet: bet, betPercent: _effectivePercent)),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.play),
          child: Text('Intră  •  💰${multiplayerEntryFee + bet}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
