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

  /// Deschide ecranul de întreținere pentru probă (buton din Admin → Debug).
  /// Ca să se vadă exact ce vede jucătorul, fără să atingi Remote Config.
  static void previewMaintenance(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Stack(
        children: [
          const _BlockingScreen(
            emoji: '🛠️',
            title: 'Revenim imediat',
            body: 'Facem niște treburi la joc. Nu dura mult — încearcă din nou '
                'peste câteva minute.',
            showProgress: true,
          ),
          // DOAR în preview: o cale de ieșire. Jucătorul real n-are.
          Positioned(
            top: 44,
            right: 12,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    ));
  }
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
            // Bara care se mișcă = semnalul „lucrăm, nu s-a blocat". Un ecran
            // de întreținere complet static se citește prea ușor ca „aplicația
            // e stricată" — exact impresia greșită.
            showProgress: true,
          );
        }
        return child!;
      },
      child: widget.child,
    );
  }
}

class _BlockingScreen extends StatefulWidget {
  final String emoji;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showProgress;

  const _BlockingScreen({
    required this.emoji,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.showProgress = false,
  });

  @override
  State<_BlockingScreen> createState() => _BlockingScreenState();
}

class _BlockingScreenState extends State<_BlockingScreen>
    with TickerProviderStateMixin {
  // Icoana se leagănă încet (o cheie care se învârte), nu sare — trebuie să
  // calmeze, nu să agite.
  late final AnimationController _wiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  // Sweep-ul continuu al barei de progres — indeterminat, ca la un download.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _wiggle.dispose();
    _sweep.dispose();
    super.dispose();
  }

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
              AnimatedBuilder(
                animation: _wiggle,
                builder: (_, child) => Transform.rotate(
                  // -0.14 .. +0.14 rad ≈ ±8°, cu easing la capete.
                  angle: (Curves.easeInOut.transform(_wiggle.value) - 0.5) * 0.28,
                  child: child,
                ),
                child: Text(widget.emoji, style: const TextStyle(fontSize: 60)),
              ),
              const SizedBox(height: 20),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                widget.body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 15, height: 1.5),
              ),
              if (widget.showProgress) ...[
                const SizedBox(height: 26),
                _SweepBar(_sweep),
              ],
              if (widget.actionLabel != null) ...[
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: widget.onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.purple,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(widget.actionLabel!,
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

/// Bară subțire cu un segment luminos care alunecă la nesfârșit stânga→dreapta.
class _SweepBar extends StatelessWidget {
  final Animation<double> t;
  const _SweepBar(this.t);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 4,
        width: 180,
        child: Stack(
          children: [
            Container(color: Colors.white.withValues(alpha: 0.10)),
            // Segmentul luminos = 40% din bară. Pleacă ascuns complet în
            // stânga (translație -1 din propria lățime) și iese complet prin
            // dreapta (translație 2.5 = 1/0.4), apoi reia — un „indeterminate".
            FractionallySizedBox(
              widthFactor: 0.4,
              child: AnimatedBuilder(
                animation: t,
                builder: (_, child) => FractionalTranslation(
                  translation: Offset(t.value * 3.5 - 1.0, 0),
                  child: child,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppColors.purple.withValues(alpha: 0.0),
                      AppColors.purple,
                      AppColors.purple.withValues(alpha: 0.0),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
