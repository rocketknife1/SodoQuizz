import 'package:flutter/material.dart';
import '../core/eco_mode.dart';

/// Notificare tip banner (stil Messenger) care alunecă lin de sus în jos,
/// oriunde ai fi în aplicație — folosită când se completează un quest sau
/// o realizare în timp ce joci. Tap pe ea te duce direct la ecranul
/// potrivit (Quests / Realizări); dispare singură după câteva secunde.
class InAppNotification {
  static void show(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    _insert(Overlay.of(context), title: title, message: message, icon: icon, color: color, onTap: onTap);
  }

  /// Varianta STRICT INFORMATIVĂ: aceeași bandă, dar fără nicio acțiune la
  /// tap și fără săgeata din dreapta. Nu prinde atingerile deloc
  /// (IgnorePointer), deci nu poate fura un tap de la ecranul de dedesubt —
  /// exact ce trebuie pentru un anunț care apare peste orice, inclusiv în
  /// mijlocul unei runde cronometrate.
  ///
  /// Folosită de anunțul „cineva a intrat în Multiplayer" (vezi
  /// MultiplayerPresenceService), care e o informație, nu o invitație de
  /// apăsat.
  /// [overlay] se dă explicit când apelul NU vine dintr-un ecran, ci de la
  /// rădăcina aplicației (vezi main.dart, anunțul de Multiplayer).
  ///
  /// DE CE NU MERGE `Overlay.of(context)` ACOLO: Overlay-ul aplicației e un
  /// DESCENDENT al Navigator-ului, iar `Overlay.of` caută în sus, printre
  /// strămoși. Dintr-un ecran obișnuit merge (ecranul e sub Overlay), dar
  /// din contextul Navigator-ului nu există niciun Overlay deasupra — și
  /// apelul cade. Rădăcina trece deci direct `navigatorKey.currentState!.overlay`.
  static void showInfo(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    Duration duration = const Duration(milliseconds: 2800),
    OverlayState? overlay,
  }) {
    _insert(
      overlay ?? Overlay.of(context),
      title: title,
      message: message,
      icon: icon,
      color: color,
      onTap: null,
      duration: duration,
    );
  }

  static void _insert(
    OverlayState overlay, {
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    Duration duration = const Duration(milliseconds: 3600),
  }) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _NotificationBanner(
        title: title,
        message: message,
        icon: icon,
        color: color,
        duration: duration,
        onTap: onTap == null
            ? null
            : () {
                entry.remove();
                onTap();
              },
        // `mounted` — a doua ștergere ar arunca: banner-ul poate fi scos și
        // de tap, și de cronometrul lui.
        onDismiss: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _NotificationBanner extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color color;

  /// null = banner pur informativ, care nu prinde atingeri deloc.
  final VoidCallback? onTap;
  final VoidCallback onDismiss;
  final Duration duration;

  const _NotificationBanner({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.onDismiss,
    required this.duration,
  });

  @override
  State<_NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<_NotificationBanner> with TickerProviderStateMixin {
  late final AnimationController _slide;
  late final AnimationController _pulse;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _pulse = EcoAnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();
    _slide.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    await _slide.reverse();
    widget.onDismiss();
  }

  void _handleTap() {
    if (_dismissed || widget.onTap == null) return;
    _dismissed = true;
    widget.onTap!();
  }

  @override
  void dispose() {
    _slide.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      // Un banner fără acțiune nu prinde atingeri deloc — altfel ar înghiți
      // tap-uri destinate ecranului de dedesubt (o variantă de răspuns, un
      // buton) exact în cele două secunde cât e pe ecran.
      child: IgnorePointer(
        ignoring: widget.onTap == null,
        child: SafeArea(
          bottom: false,
          child: AnimatedBuilder(
            animation: _slide,
            builder: (context, child) {
              final curved = Curves.easeOutBack.transform(_slide.value);
              final offsetY = -130 * (1 - curved);
              return Transform.translate(offset: Offset(0, offsetY), child: child);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12).copyWith(top: 6),
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: _handleTap,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B2340),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white12),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withAlpha(140), blurRadius: 18, offset: const Offset(0, 8))
                      ],
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: AnimatedBuilder(
                            animation: _pulse,
                            builder: (context, _) {
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  for (final delay in [0.0, 0.5]) _buildRing(delay),
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                                    child: Icon(widget.icon, color: Colors.white, size: 20),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(widget.title,
                                  style:
                                      const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(widget.message,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        if (widget.onTap != null)
                          const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRing(double delay) {
    final t = (_pulse.value + delay) % 1.0;
    return Opacity(
      opacity: (1 - t) * 0.5,
      child: Container(
        width: 40 + t * 24,
        height: 40 + t * 24,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: widget.color, width: 2)),
      ),
    );
  }
}
