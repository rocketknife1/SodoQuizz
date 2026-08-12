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
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _NotificationBanner(
        title: title,
        message: message,
        icon: icon,
        color: color,
        onTap: () {
          entry.remove();
          onTap();
        },
        onDismiss: () => entry.remove(),
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
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationBanner({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.onDismiss,
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
    Future.delayed(const Duration(milliseconds: 3600), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    await _slide.reverse();
    widget.onDismiss();
  }

  void _handleTap() {
    if (_dismissed) return;
    _dismissed = true;
    widget.onTap();
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
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(140), blurRadius: 18, offset: const Offset(0, 8))],
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
                                for (final delay in [0.0, 0.5])
                                  _buildRing(delay),
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
                            Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(widget.message, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
                    ],
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
