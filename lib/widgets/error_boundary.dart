import 'package:flutter/material.dart';

import '../core/breadcrumbs.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/bug_report_service.dart';

// ─── Ce vede jucătorul când se strică ceva ────────────────────────────────
//
// Implicit, Flutter desenează în release un dreptunghi gri (în debug, faimosul
// ecran roșu). Ambele îi spun jucătorului „ceva e stricat și nu te privește".
//
// Aici îi spunem altceva: nu e vina lui, și poate ajuta cu o apăsare. NU i se
// cere să descrie nimic — el n-are cum să știe ce s-a rupt (cerința userului).
// Raportul se compune singur, cu tot ce s-a întâmplat înainte și după.

/// Înlocuiește ecranul de eroare implicit al Flutter. Se pune o singură dată,
/// în `MaterialApp.builder`.
class ErrorBoundary extends StatefulWidget {
  final FlutterErrorDetails details;
  const ErrorBoundary({super.key, required this.details});

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  bool _sending = false;
  bool _sent = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    Breadcrumbs.drop('a apasat Trimite raport');
    final report = await BugReportService.instance.build(
      error: widget.details.exception,
      stack: widget.details.stack,
      screen: widget.details.context?.toString(),
    );
    await BugReportService.instance.send(report);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🛠️', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 18),
              Text(
                tr('Ceva s-a stricat aici', 'Something broke here'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                tr('Nu e vina ta. Dacă îmi trimiți ce s-a întâmplat, repar.',
                    "It's not your fault. Send me what happened and I'll fix it."),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white60, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 26),
              if (_sent)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.teal, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      tr('Trimis. Mulțumesc!', 'Sent. Thank you!'),
                      style: const TextStyle(
                          color: AppColors.teal,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _sending
                          ? tr('Se trimite...', 'Sending...')
                          : tr('Trimite raportul', 'Send the report'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                tr('Se trimit doar date tehnice, nimic personal.',
                    'Only technical data is sent, nothing personal.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white30, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
