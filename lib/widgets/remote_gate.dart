import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/lang.dart';
import '../core/remote_flags.dart';
import '../core/theme.dart';

// ─── Poarta pe care o poți închide de la distanță ─────────────────────────
//
// Două lucruri, amândouă imposibile fără un comutator de la distanță:
//
//   1. VERSIUNE PREA VECHE — dacă scapă un bug urât, clienții vechi rămân pe
//      el pentru totdeauna: nimeni nu e obligat să actualizeze. De aici îi
//      poți opri, fără să publici nimic.
//   2. ÎNTREȚINERE — un anunț peste joc, pentru toată lumea, imediat.
//
// Poarta e ÎNCHISĂ DOAR când Remote Config o cere explicit. Fără net, la
// prima pornire, sau dacă Remote Config nu răspunde, jocul merge normal —
// un joc care se blochează singur fiindcă n-a putut întreba serverul ar fi
// mai rău decât problema pe care o rezolvă.

class RemoteGate extends StatefulWidget {
  final Widget child;
  const RemoteGate({super.key, required this.child});

  @override
  State<RemoteGate> createState() => _RemoteGateState();
}

class _RemoteGateState extends State<RemoteGate> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    // Fără versiune nu putem compara, iar poarta rămâne deschisă — vezi
    // `isTooOld`, care întoarce false la orice nu înțelege.
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    }).onError((_, __) {});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: RemoteFlags.instance.revision,
      builder: (context, _, child) {
        final flags = RemoteFlags.instance;
        if (RemoteFlags.isTooOld(
            current: _version, minimum: flags.minVersion)) {
          return _BlockingScreen(
            emoji: '⬆️',
            title: tr('E nevoie de o versiune nouă', 'A new version is required'),
            body: tr(
              'Versiunea asta nu mai merge cum trebuie. Actualizează și te întorci imediat în joc.',
              'This version no longer works properly. Update and you will be right back in the game.',
            ),
            actionLabel: tr('Actualizează', 'Update'),
            onAction: () => launchUrl(
              Uri.parse(
                  'https://play.google.com/store/apps/details?id=com.dragosssx.guessit'),
              mode: LaunchMode.externalApplication,
            ),
          );
        }
        final maintenance = flags.maintenanceMessage.trim();
        if (maintenance.isNotEmpty) {
          return _BlockingScreen(
            emoji: '🛠️',
            title: tr('Revenim imediat', 'Back shortly'),
            body: maintenance,
          );
        }
        return child!;
      },
      child: widget.child,
    );
  }
}

class _BlockingScreen extends StatelessWidget {
  final String emoji;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _BlockingScreen({
    required this.emoji,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 60)),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 15, height: 1.5),
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(actionLabel!,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
