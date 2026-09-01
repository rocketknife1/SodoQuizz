import 'package:flutter/material.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/question_report_service.dart';
import '../models/question_report.dart';

/// Buton de raportare a întrebării curente — pus în bara de sus a fiecărui
/// ecran de joc SINGLE-PLAYER (nu și în multiplayer: acolo o întrebare
/// greșită afectează un meci în desfășurare, cu alți jucători, nu doar
/// raportorul, deci nu are rost butonul).
///
/// Era un steguleț gri de 20px cu `padding: zero`, adică sub pragul de 44px
/// de atingere și practic invizibil lângă text alb pe fundal închis —
/// nimeni nu raporta nimic. Acum e o pastilă ROȘIE plină, cu text: aceeași
/// regulă ca la butoanele de meniu (butoanele reale se văd ca butoane).
///
/// Motivul se alege dintr-o listă fixă, ca la [showModerationSheet] — un
/// câmp liber ar fi ajuns un al doilea chat, nemoderat, direct în colecția
/// de raportări.
class ReportQuestionButton extends StatelessWidget {
  final String questionId;
  final String questionText;
  final String category;

  /// Fără etichetă, doar steagul într-un cerc roșu — pentru rândurile foarte
  /// strâmte. Rămâne roșu și rămâne țintă de 44px; se schimbă doar lățimea.
  final bool iconOnly;

  const ReportQuestionButton({
    super.key,
    required this.questionId,
    required this.questionText,
    required this.category,
    this.iconOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = tr('Raportează', 'Report');
    return Semantics(
      button: true,
      label: tr('Raportează întrebarea', 'Report question'),
      child: Material(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _askReasonAndReport(context),
          child: Container(
            // 44px inaltime = pragul minim de tinta de atingere.
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            padding: iconOnly
                ? const EdgeInsets.all(10)
                : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.flag_rounded, color: Colors.white, size: 20),
                if (!iconOnly) ...[
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _askReasonAndReport(BuildContext context) async {
    final reason = await showDialog<QuestionReportReason>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.flag_rounded, color: AppColors.danger, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('Ce e în neregulă?', "What's wrong?"),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in QuestionReportReason.values) ...[
              // Fiecare motiv e o cutie apăsabilă cu contur roșu, nu un rând
              // de listă: cele trei motive sunt tot ce trebuie ales aici,
              // deci merită să arate a butoane.
              Material(
                color: AppColors.danger.withAlpha(28),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(dialogContext, r),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.danger.withAlpha(120)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(r.label,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: AppColors.danger),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('Renunță', 'Cancel'))),
        ],
      ),
    );
    if (reason == null) return;
    final sent = await QuestionReportService.instance.submitReport(
      questionId: questionId,
      questionText: questionText,
      category: category,
      reason: reason,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        sent
            ? tr('Raportare trimisă. Mulțumim!', 'Report sent. Thank you!')
            : tr('Nu am putut trimite raportarea. Încearcă din nou.', 'Could not send the report. Please try again.'),
      ),
      backgroundColor: sent ? AppColors.teal : AppColors.danger,
    ));
  }
}
