import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../core/repeating_animation.dart';
import '../core/theme.dart';
import '../data/notification_service.dart';
import '../screens/notifications_screen.dart';

/// Clopoțelul de notificări, așezat în bara de sus a meniului principal, la
/// dreapta titlului (vezi HomeScreen._buildTopBar) — de acolo se deschide
/// panoul cu anunțuri de sistem, cadouri și mesaje de la prieteni.
///
/// A stat înainte în rândul de resurse, lipit de pastila de monede, unde era
/// înghesuit între cifre. Locul de acum era oricum gol (titlul e centrat), deci
/// mutarea nu costă nicio înălțime în plus și scapă rândul de resurse de un
/// element care nu e o resursă.
///
/// Numărul de necitite vine din [NotificationService.unreadCount], deci se
/// actualizează singur din orice ecran, fără ca meniul să fie reconstruit:
/// un mesaj primit cât stai pe Home aprinde bulina pe loc.
///
/// Cu ceva necitit, clopoțelul chiar SUNĂ: se leagănă în jurul punctului lui
/// de agățare (de sus, nu din centru — altfel arată ca o rotire, nu ca un
/// clopot), iar în spate pulsează un halou. Fără nimic necitit stă complet
/// nemișcat: o animație permanentă pe meniul principal ar fi doar zgomot.
class NotificationBell extends StatefulWidget {
  /// Chemat după închiderea panoului — meniul își reîncarcă balanța, fiindcă
  /// un cadou revendicat între timp îi schimbă cifrele.
  final VoidCallback? onClosed;

  const NotificationBell({super.key, this.onClosed});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> with SingleTickerProviderStateMixin {
  late final RepeatingAnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = RepeatingAnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
      restValue: 0.5,
    )..repeat(reverse: true);
    // Bulina trebuie să fie corectă din primul cadru — partea locală, fără
    // rețea. Partea LIVE (cereri de prietenie, fire cu mesaj necitit) NU se
    // mai cere aici cu `refreshUnread`: `LiveSync.attachToIdentity()` rulează
    // din `initState`-ul rădăcinii aplicației (main.dart), deci abonamentele
    // sunt atașate înainte ca vreun ecran cu clopoțel să se construiască, iar
    // ele împing cifrele prin `setLiveUnread`, fără nicio citire. Cu
    // `refreshUnread` aici, FIECARE intrare pe un ecran cu clopoțel plătea
    // `fetchLive()` = `2 + 2N` citiri Firestore pentru date deja sosite.
    NotificationService.instance.refreshUnreadLocalOnly();
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
              final active = unread > 0;
              // 0..1 -> 0..1..0, ca haloul să crească și să scadă lin.
              final beat = active ? _pulse.value : 0.0;
              final accent = active ? AppColors.coin : AppColors.blue;
              // Legănarea: două perioade pe ciclu, ca să bată mai repede decât
              // pulsează haloul — un clopot sună, nu respiră.
              final swing = active ? math.sin(_pulse.value * 2 * math.pi * 2) * 0.20 : 0.0;
              return SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Haloul care se umflă în spate — desenat SUB pastilă, deci
                    // nu mișcă nimic din layout când pulsează.
                    if (active)
                      Container(
                        width: 34 + beat * 12,
                        height: 34 + beat * 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withAlpha((46 * (1 - beat)).round()),
                        ),
                      ),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: active
                              ? [accent.withAlpha(105), accent.withAlpha(35)]
                              : [Colors.white.withAlpha(26), Colors.white.withAlpha(10)],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: accent.withAlpha(active ? 215 : 95), width: 1.4),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withAlpha(active ? (60 + 70 * beat).round() : 40),
                            blurRadius: active ? 8 + 10 * beat : 6,
                            spreadRadius: -1,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Transform(
                        alignment: Alignment.topCenter,
                        transform: Matrix4.rotationZ(swing),
                        child: Icon(
                          active
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_none_rounded,
                          color: active ? AppColors.coin : Colors.white70,
                          size: 21,
                        ),
                      ),
                    ),
                    if (active)
                      Positioned(
                        top: -2,
                        right: -4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFFFF6B6B), AppColors.danger],
                            ),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: AppColors.bg, width: 1.6),
                            boxShadow: [
                              BoxShadow(
                                  color: AppColors.danger.withAlpha(120),
                                  blurRadius: 6,
                                  spreadRadius: -1),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                height: 1.0),
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
