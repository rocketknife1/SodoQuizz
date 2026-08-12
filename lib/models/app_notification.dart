import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/lang.dart';
import '../core/theme.dart';

/// De unde vine o notificare — determină iconița, culoarea și ce se întâmplă
/// la tap (vezi NotificationsScreen).
enum AppNotificationType {
  /// Anunț scris de admin, pentru un jucător anume sau pentru toți.
  system,

  /// „Felicitări, ai primit..." — compusă automat din ce a trimis adminul,
  /// chiar în momentul în care resursele intră în cont (vezi
  /// CloudSyncService.consumePendingGrant). Jucătorul nu mai trebuie să
  /// ghicească de ce i-au crescut monedele.
  gift,

  /// Mesaj necitit de la un prieten. NU se salvează pe telefon ca celelalte:
  /// se citește live din firele de chat la fiecare deschidere a panoului
  /// (vezi NotificationService.fetchLive), fiindcă „necitit" e o stare care
  /// se schimbă și de pe alt telefon, iar o copie locală ar rămâne în urmă.
  message,

  /// Cerere de prietenie primită — la fel, stare live.
  friendRequest,
}

/// O intrare din panoul de notificări (clopoțelul de lângă avatarul din
/// meniul principal). Vezi [AppNotificationType] pentru care dintre ele se
/// salvează pe telefon și care se citesc live.
class AppNotification {
  final String id;
  final AppNotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;

  /// Cu cine are legătură notificarea (uid-ul prietenului), pentru cele care
  /// duc undeva la tap. Gol pentru anunțuri și cadouri.
  final String peerUid;
  final String peerName;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.peerUid = '',
    this.peerName = '',
  });

  IconData get icon => switch (type) {
        AppNotificationType.system => Icons.campaign_rounded,
        AppNotificationType.gift => Icons.card_giftcard_rounded,
        AppNotificationType.message => Icons.chat_bubble_rounded,
        AppNotificationType.friendRequest => Icons.person_add_rounded,
      };

  Color get color => switch (type) {
        AppNotificationType.system => AppColors.blue,
        AppNotificationType.gift => AppColors.coin,
        AppNotificationType.message => AppColors.teal,
        AppNotificationType.friendRequest => AppColors.purple,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (peerUid.isNotEmpty) 'peerUid': peerUid,
        if (peerName.isNotEmpty) 'peerName': peerName,
      };

  String encode() => jsonEncode(toJson());

  /// Întoarce null pentru o intrare stricată, în loc să arunce — o singură
  /// linie coruptă în SharedPreferences n-are voie să golească tot panoul.
  static AppNotification? decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AppNotification(
        id: map['id'] as String? ?? '',
        type: AppNotificationType.values.firstWhere(
          (t) => t.name == map['type'],
          orElse: () => AppNotificationType.system,
        ),
        title: map['title'] as String? ?? '',
        body: map['body'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int? ?? 0),
        peerUid: map['peerUid'] as String? ?? '',
        peerName: map['peerName'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// „acum" / „acum 5 min" / „azi 14:03" / „09.08" — cât se poate de scurt,
/// fiindcă stă pe același rând cu titlul notificării.
String formatNotificationTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return tr('acum', 'now');
  if (diff.inMinutes < 60) return tr('acum ${diff.inMinutes} min', '${diff.inMinutes} min ago');
  final local = time.toLocal();
  final hhmm = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  final now = DateTime.now();
  if (local.year == now.year && local.month == now.month && local.day == now.day) {
    return tr('azi $hhmm', 'today $hhmm');
  }
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')} $hhmm';
}
