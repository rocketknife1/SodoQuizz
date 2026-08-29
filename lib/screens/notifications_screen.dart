import 'package:flutter/material.dart';
import '../core/lang.dart';
import '../core/theme.dart';
import '../data/notification_service.dart';
import '../data/player_profile_service.dart';
import '../models/app_notification.dart';
import 'friend_chat_screen.dart';
import 'friends_screen.dart';
import 'multiplayer/leaderboard_screen.dart';

/// Panoul deschis de clopoțelul de lângă avatarul din meniul principal:
/// anunțuri de la administrator, cadourile primite și mesajele/cererile
/// venite de la ceilalți jucători, toate într-o singură listă, cele mai noi
/// sus.
///
/// Cele salvate pe telefon se marchează ca văzute la deschidere. Mesajele și
/// cererile de prietenie NU — vezi NotificationService.markStoredRead pentru
/// de ce o simplă privire prin panou n-are voie să le stingă.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<AppNotification>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AppNotification>> _load() async {
    // Întâi se descarcă ce a lăsat adminul, ca anunțurile noi să apară chiar
    // în lista pe care o deschide acum, nu abia la următoarea intrare.
    await NotificationService.instance.pullFromCloud();
    final all = await NotificationService.instance.fetchAll();
    await NotificationService.instance.markStoredRead();
    return all;
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _openNotification(AppNotification n) async {
    switch (n.type) {
      case AppNotificationType.message:
        final friend = await PlayerProfileService.instance.getProfile(n.peerUid);
        if (!mounted || friend == null) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => FriendChatScreen(friend: friend)),
        );
        if (mounted) _reload();
      case AppNotificationType.friendRequest:
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const FriendsScreen()),
        );
        if (mounted) _reload();
      case AppNotificationType.overtake:
        // Duce direct la clasament, ca depășirea să se vadă pe loc — nu
        // neapărat pe tabul Prieteni (fără un mecanism de "deschide pe tabul
        // X" din afară), dar tot clasamentul e la un tap distanță de-acolo.
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
        );
        if (mounted) _reload();
      case AppNotificationType.system:
      case AppNotificationType.gift:
        // Nu duc nicăieri — textul e tot conținutul lor, deja vizibil în listă.
        break;
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Golești notificările?', 'Clear notifications?'),
            style: const TextStyle(color: Colors.white)),
        content: Text(
          tr(
            'Se șterg anunțurile și cadourile din listă. Mesajele de la prieteni și cererile de prietenie rămân — alea nu sunt salvate aici.',
            'This clears announcements and gifts from the list. Friend messages and friend requests stay — those are not stored here.',
          ),
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Renunță', 'Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Golește', 'Clear'), style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await NotificationService.instance.clearStored();
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white70),
                  ),
                  const SizedBox(width: 4),
                  Text(tr('Notificări', 'Notifications'),
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    onPressed: _confirmClear,
                    tooltip: tr('Golește lista', 'Clear list'),
                    icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white38),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<AppNotification>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Center(child: CircularProgressIndicator(color: AppColors.purple));
                  }
                  final items = snapshot.data ?? const <AppNotification>[];
                  if (items.isEmpty) return _empty();
                  return RefreshIndicator(
                    color: AppColors.purple,
                    backgroundColor: AppColors.card,
                    onRefresh: () async => _reload(),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _NotificationCard(
                        notification: items[i],
                        onTap: () => _openNotification(items[i]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded, color: Colors.white.withAlpha(40), size: 64),
            const SizedBox(height: 14),
            Text(
              tr('Nicio notificare', 'No notifications'),
              style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                'Aici apar anunțurile din joc, cadourile primite și mesajele de la prieteni.',
                'Announcements, gifts you receive and messages from friends show up here.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationCard({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final actionable = notification.type == AppNotificationType.message ||
        notification.type == AppNotificationType.friendRequest;
    return GestureDetector(
      onTap: actionable ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: notification.color.withAlpha(70)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: notification.color.withAlpha(40),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(notification.icon, color: notification.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatNotificationTime(notification.createdAt),
                        style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                      ),
                    ],
                  ),
                  if (notification.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35),
                    ),
                  ],
                ],
              ),
            ),
            if (actionable) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}
