import 'package:flutter/material.dart';
import '../core/eco_mode.dart';
import '../core/theme.dart';
import '../data/notification_service.dart';
import '../screens/notifications_screen.dart';

/// Clopoțelul de notificări, așezat DEASUPRA avatarului din meniul principal
/// (vezi LevelHeader) — de acolo se deschide panoul cu anunțuri de sistem,
/// cadouri și mesaje de la prieteni.
///
/// Numărul de necitite vine din [NotificationService.unreadCount], deci se
/// actualizează singur din orice ecran, fără ca meniul să fie reconstruit:
/// un mesaj primit cât stai pe Home aprinde bulina pe loc.
///
/// Cât timp există ceva necitit, clopoțelul pulsează discret — dar prin
/// [EcoAnimationController], adică se oprește singur în Modul Eco și rămâne
/// doar bulina roșie, care oricum e semnalul care contează.
class NotificationBell extends StatefulWidget {
  /// Chemat după închiderea panoului — meniul își reîncarcă balanța, fiindcă
  /// un cadou revendicat între timp îi schimbă cifrele.
  final VoidCallback? onClosed;

  const NotificationBell({super.key, this.onClosed});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> with SingleTickerProviderStateMixin {
  late final EcoAnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = EcoAnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
      restValue: 0.5,
    )..repeat(reverse: true);
    // Bulina trebuie să fie corectă din primul cadru (partea locală, fără
    // rețea), apoi completată cu ce se află abia întrebând Firestore.
    NotificationService.instance.refreshUnreadLocalOnly();
    NotificationService.instance.refreshUnread();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (!mounted) return;
    await NotificationService.instance.refreshUnread();
    widget.onClosed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationService.instance.unreadCount,
      builder: (context, unread, _) {
        return GestureDetector(
          onTap: _open,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final glow = unread > 0 ? 0.35 + _pulse.value * 0.65 : 0.0;
              return Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(unread > 0 ? 26 : 15),
                  shape: BoxShape.circle,
                  border: Border.all(color: unread > 0 ? AppColors.coin.withAlpha(160) : Colors.white24),
                  boxShadow: unread > 0
                      ? [BoxShadow(color: AppColors.coin.withAlpha((90 * glow).round()), blurRadius: 10 * glow, spreadRadius: glow)]
                      : null,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                      color: unread > 0 ? AppColors.coin : Colors.white54,
                      size: 19,
                    ),
                    if (unread > 0)
                      Positioned(
                        top: -3,
                        right: -5,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 17),
                          height: 17,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: AppColors.bg, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
