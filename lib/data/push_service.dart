import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'device_notification_service.dart';
import 'multiplayer_service.dart';

/// **Notificări PUSH** — cele care vin din acțiunea ALTUI jucător: mesaj
/// primit, cerere de prietenie, anunț de sistem, invitație într-o cameră.
///
/// Altceva decât notificările LOCALE ([DeviceNotificationService] le
/// programează pe telefon când momentul se știe dinainte). Astea NU se pot
/// programa, iar un client nu poate trimite FCM altui client — trimiterea o
/// fac Cloud Functions (`functions/index.js`).
///
/// ## De ce mesaje DATA-ONLY (fără câmp `notification`)
///
/// Prima versiune primea `notification: {title, body}` de la Functions, iar
/// Android afișa singur notificarea. Două probleme raportate de user:
///  1. TAP-ul nu ducea nicăieri în aplicație;
///  2. întârziere mare — FCM amână/grupează mesajele-notificare către
///     aplicații în fundal, mai ales pe Samsung.
///
/// Acum Functions trimit doar `data`, iar aplicația își desenează singură
/// notificarea prin [DeviceNotificationService.show], cu payload de rutare.
/// Data-only + `priority: high` nu e amânat la fel, iar tap-ul e sub control.
class PushService {
  PushService._();
  static final instance = PushService._();

  /// Chemat când jucătorul apasă o notificare de invitație în cameră.
  void Function(String matchId, String code)? onOpenRoom;

  /// Idem, pentru un mesaj primit.
  void Function(String withUid)? onOpenChat;

  bool _started = false;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  Future<void> start() async {
    if (_started || !_supported) return;
    _started = true;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();

      // Handler pentru mesajele sosite CÂT APLICAȚIA E DESCHISĂ. Fără el, un
      // mesaj FCM primit în timp ce te uiți la ecran nu produce nimic vizibil.
      FirebaseMessaging.onMessage.listen(_showFromMessage);

      // Mesajele sosite CU APLICAȚIA ÎN FUNDAL/ÎNCHISĂ sunt tratate de
      // handler-ul top-level înregistrat mai jos, în `main()`.

      await _saveToken(await fm.getToken());
      fm.onTokenRefresh.listen(_saveToken);

      // TAP pe o notificare push (aici doar cazul rar în care Android chiar
      // livrează un `notification` de sistem — data-only e afișat de noi și
      // rutat de flutter_local_notifications). Inofensiv să fie ambele.
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _route(m.data));
      final initial = await fm.getInitialMessage();
      if (initial != null) _route(initial.data);
    } catch (e) {
      debugPrint('PushService.start a esuat: $e');
    }
  }

  Future<void> _saveToken(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      final uid = MultiplayerService.instance.currentPlayerId;
      if (uid.isEmpty) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcm_tokens')
          .doc(token)
          .set({'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('PushService._saveToken a esuat: $e');
    }
  }

  /// Un mesaj FCM data-only → o notificare desenată de noi, cu payload de
  /// rutare. Aceeași metodă e folosită și din handler-ul de fundal.
  Future<void> _showFromMessage(RemoteMessage msg) async {
    final d = msg.data;
    final type = d['type'] ?? '';
    // Mesajele de la același prieten se înlocuiesc; invitațiile rămân separate.
    final collapse = switch (type) {
      'chat' => 'chat_${d['withUid'] ?? ''}',
      'friend_request' => 'friend_request',
      'system' => 'system',
      _ => null,
    };
    await DeviceNotificationService.instance.show(
      title: d['title'] ?? 'SodoQuizz',
      body: d['body'] ?? '',
      payload: _encodePayload(d),
      collapseId: collapse,
    );
  }

  /// `{type: chat, withUid: abc}` → `"type=chat&withUid=abc"`. Doar câmpurile
  /// de rutare, nu tot payload-ul.
  String _encodePayload(Map<String, dynamic> d) {
    const keys = ['type', 'matchId', 'code', 'withUid', 'fromUid'];
    return keys
        .where((k) => d[k] != null && '${d[k]}'.isNotEmpty)
        .map((k) => '$k=${Uri.encodeComponent('${d[k]}')}')
        .join('&');
  }

  /// Chemat de [DeviceNotificationService] când se apasă o notificare
  /// (locală sau push desenată de noi). Payload-ul e query string-ul de mai sus.
  void routePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final data = <String, dynamic>{};
    for (final pair in payload.split('&')) {
      final i = pair.indexOf('=');
      if (i > 0) {
        data[pair.substring(0, i)] = Uri.decodeComponent(pair.substring(i + 1));
      }
    }
    _route(data);
  }

  void _route(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'room_invite':
        final matchId = data['matchId'] ?? '';
        if (matchId.isNotEmpty) onOpenRoom?.call(matchId, data['code'] ?? '');
      case 'chat':
        final withUid = data['withUid'] ?? '';
        if (withUid.isNotEmpty) onOpenChat?.call(withUid);
      default:
        // „friend_request", „system" și notificările locale (roata etc.) nu
        // au destinație proprie — deschiderea aplicației e tot ce trebuia.
        break;
    }
  }
}

/// Handler TOP-LEVEL pentru mesajele FCM sosite cu aplicația în fundal sau
/// complet închisă. Rulează într-un izolat separat, fără UI — de-aia inițializează
/// singur Firebase și cheamă doar afișarea, nu navigarea (aia se întâmplă la tap,
/// când aplicația chiar pornește). Înregistrat în `main()` cu
/// `FirebaseMessaging.onBackgroundMessage`.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    await PushService.instance._showFromMessage(message);
  } catch (e) {
    debugPrint('firebaseMessagingBackgroundHandler a esuat: $e');
  }
}
