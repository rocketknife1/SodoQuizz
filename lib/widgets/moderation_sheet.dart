import 'package:flutter/material.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/moderation_service.dart';
import '../models/moderation.dart';

/// Meniul de siguranță al unui jucător — raportare și blocare — deschis prin
/// apăsare lungă pe o bulă de chat sau prin tap pe un jucător din camera
/// multiplayer.
///
/// E un fișier separat fiindcă îl folosesc două ecrane cu chat, cu aceleași
/// opțiuni: lobby-ul camerei multiplayer și firul privat dintre prieteni. Ce
/// diferă între ele — cine e reclamat, ce mesaj anume, în ce cameră/fir — vine
/// prin parametri.
///
/// [messageText] e mesajul reclamat, dacă meniul s-a deschis de pe unul. Se
/// trimite mai departe în raportare, ca adminul să vadă TEXTUL, nu doar
/// numele reclamatului: chatul camerei se șterge odată cu meciul, deci până
/// să deschidă panoul mesajul de obicei nu mai există nicăieri.
Future<void> showModerationSheet(
  BuildContext context, {
  required String targetUid,
  required String targetName,
  String messageText = '',
  String contextId = '',
}) async {
  final blocked = ModerationService.instance.isBlocked(targetUid);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              targetName,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
            if (messageText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: Colors.white.withAlpha(14), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  messageText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.35),
                ),
              ),
            ],
            const SizedBox(height: 18),
            _SheetAction(
              icon: Icons.flag_rounded,
              color: AppColors.orange,
              label: tr('Raportează', 'Report'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _askReasonAndReport(
                  context,
                  targetUid: targetUid,
                  targetName: targetName,
                  messageText: messageText,
                  contextId: contextId,
                );
              },
            ),
            const SizedBox(height: 10),
            _SheetAction(
              icon: blocked ? Icons.lock_open_rounded : Icons.block_rounded,
              color: blocked ? AppColors.teal : AppColors.danger,
              label: blocked ? tr('Deblochează', 'Unblock') : tr('Blochează', 'Block'),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (blocked) {
                  await ModerationService.instance.unblockPlayer(targetUid);
                  if (context.mounted) _toast(context, '$targetName a fost deblocat.');
                } else {
                  await _confirmBlock(context, targetUid: targetUid, targetName: targetName);
                }
              },
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(tr('Anulează', 'Cancel'), style: const TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Butoanele din meniu — pline, pe toată lățimea, ca restul butoanelor din
/// aplicație (nu rânduri subțiri de listă).
class _SheetAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _SheetAction({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 20),
      label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/// Blocarea cere confirmare, spre deosebire de raportare: are efect imediat
/// asupra a ce vezi și e ușor de apăsat din greșeală pe un telefon.
Future<void> _confirmBlock(BuildContext context, {required String targetUid, required String targetName}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(tr('Blochezi jucătorul?', 'Block this player?'), style: const TextStyle(color: Colors.white)),
      content: Text(
        tr(
            'Nu vei mai vedea mesajele lui $targetName, nici în camerele de '
                'multiplayer, nici în chatul privat.\n\n'
                'El nu află că l-ai blocat. Poți anula oricând din Setări → Jucători blocați.',
            'You will no longer see messages from $targetName, neither in multiplayer '
                'rooms nor in private chat.\n\n'
                'They are not told they were blocked. You can undo this any time from '
                'Settings → Blocked players.'),
        style: const TextStyle(color: Colors.white70, height: 1.35),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('Renunță', 'Cancel'))),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(tr('Blochează', 'Block'), style: TextStyle(color: AppColors.danger)),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ModerationService.instance.blockPlayer(targetUid, name: targetName);
  if (context.mounted) _toast(context, '$targetName a fost blocat.');
}

/// Motivul se alege dintr-o listă fixă — un câmp liber ar fi ajuns un al
/// doilea chat, nemoderat, direct în panoul de admin.
Future<void> _askReasonAndReport(
  BuildContext context, {
  required String targetUid,
  required String targetName,
  required String messageText,
  required String contextId,
}) async {
  final reason = await showDialog<ReportReason>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('De ce raportezi?', style: TextStyle(color: Colors.white)),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in ReportReason.values)
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
  final sent = await ModerationService.instance.submitReport(
    targetUid: targetUid,
    targetName: targetName,
    reason: reason,
    messageText: messageText,
    context: contextId,
  );
  if (!context.mounted) return;
  _toast(
    context,
    sent
        ? tr('Raportare trimisă. Ne uităm peste ea.', 'Report sent. We will look into it.')
        : tr('Nu am putut trimite raportarea. Încearcă din nou.', 'Could not send the report. Please try again.'),
  );
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
