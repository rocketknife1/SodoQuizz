import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/admin.dart';
import '../core/breadcrumbs.dart';
import '../core/game_pause.dart';
import '../core/theme.dart';
import '../data/auth_service.dart';
import '../data/bug_report_service.dart';

/// Iconița de owner, mereu vizibilă în colțul din dreapta sus — cerința
/// 2026-09-18: în loc de „scutur telefonul" (senzor nou, se declanșează din
/// greșeală la jocuri ca Tancuri), un buton fix pe care apeși când vezi ceva
/// pe loc, în mijlocul jocului, și vrei să-l notezi înainte să uiți.
///
/// Vizibilă DOAR pe contul de admin (kAdminEmail), la fel ca AdminScreen —
/// restul jucătorilor nu știu că există. Nota ajunge în `bug_reports`,
/// marcată `notaOwner: true`, și apare în tab-ul Bug-uri din Admin alături
/// de rapoartele automate, cu ecranul curent prins din Breadcrumbs (nu e
/// nevoie de un observator de rute separat).
class OwnerNoteOverlay extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  const OwnerNoteOverlay({super.key, required this.child, required this.navigatorKey});

  @override
  State<OwnerNoteOverlay> createState() => _OwnerNoteOverlayState();
}

class _OwnerNoteOverlayState extends State<OwnerNoteOverlay> {
  bool _justSent = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    final dialogContext = widget.navigatorKey.currentContext;
    if (dialogContext == null) return;
    final controller = TextEditingController();
    // Îngheață cronometrele de întrebare din ecranele singleplayer cât scrii
    // — vezi core/game_pause.dart. finally garantează reluarea și la
    // anulare, și la trimitere, și dacă ceva neașteptat aruncă mai jos.
    GamePause.instance.pause();
    final String? text;
    try {
      text = await showDialog<String>(
        context: dialogContext,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Notă rapidă', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Ce ai văzut / ce vrei să schimbi...',
              hintStyle: TextStyle(color: Colors.white38),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anulează')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Trimite', style: TextStyle(color: AppColors.teal)),
            ),
          ],
        ),
      );
    } finally {
      GamePause.instance.resume();
    }
    if (text == null || text.isEmpty) return;
    final ok = await BugReportService.instance.sendOwnerNote(text, screen: Breadcrumbs.currentScreen());
    if (!ok || !mounted) return;
    HapticFeedback.mediumImpact();
    _resetTimer?.cancel();
    setState(() => _justSent = true);
    _resetTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _justSent = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges(),
      initialData: AuthService.instance.currentUser,
      builder: (context, snap) {
        final visible = snap.data?.email == kAdminEmail;
        return Stack(
          children: [
            widget.child,
            if (visible)
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    // la stânga clopoțelului de notificări de pe Acasă, nu
                    // peste el — colțul din dreapta e al lui
                    padding: const EdgeInsets.only(right: 64, top: 4),
                    child: GestureDetector(
                      onTap: _open,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        alignment: Alignment.center,
                        child: _justSent
                            ? const Icon(Icons.check_rounded, color: AppColors.teal, size: 18)
                            : const Text('☣', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
