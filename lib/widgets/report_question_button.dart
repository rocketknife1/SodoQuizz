import 'package:flutter/material.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/question_report_service.dart';
import '../models/question_report.dart';

/// Buton mic (steguleț) pentru raportarea întrebării curente — pus în bara de
/// sus a fiecărui ecran de joc SINGLE-PLAYER (nu și în multiplayer: acolo o
/// întrebare greșită afectează un meci în desfășurare, cu alți jucători, nu
/// doar raportorul, deci nu are rost butonul).
///
/// Motivul se alege dintr-o listă fixă, ca la [showModerationSheet] — un
/// câmp liber ar fi ajuns un al doilea chat, nemoderat, direct în colecția
/// de raportări.
class ReportQuestionButton extends StatelessWidget {
  final String questionId;
  final String questionText;
  final String category;

  const ReportQuestionButton({
    super.key,
    required this.questionId,
    required this.questionText,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: const Icon(Icons.flag_outlined, color: Colors.white54, size: 20),
      tooltip: tr('Raportează întrebarea', 'Report question'),
      onPressed: () => _askReasonAndReport(context),
    );
  }

  Future<void> _askReasonAndReport(BuildContext context) async {
    final reason = await showDialog<QuestionReportReason>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Ce e în neregulă?', "What's wrong?"), style: const TextStyle(color: Colors.white)),
        contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in QuestionReportReason.values)
              ListTile(
                onTap: () => Navigator.pop(dialogContext, r),
                title: Text(r.label, style: const TextStyle(color: Colors.white, fontSize: 14)),
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
              ),
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
