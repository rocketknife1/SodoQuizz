import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'multiplayer_service.dart';

/// **Notificări PUSH** — cele care vin din acțiunea ALTUI jucător: mesaj
/// primit, cerere de prietenie, anunț de sistem, invitație într-o cameră.
///
/// Altceva decât [DeviceNotificationService], care programează pe telefon
/// lucruri al căror moment se știe dinainte (roata, planeta, questurile).
/// Astea NU se pot programa: nu știi când îți scrie cineva. Iar un client nu
/// poate trimite FCM altui client, deci trimiterea o fac Cloud Functions —
/// vezi `functions/index.js`.
///
/// ## Ce face fișierul ăsta, concret
///
/// Doar DOUĂ lucruri, pe partea de telefon:
///  1. ia token-ul FCM și îl scrie în `users/{uid}/fcm_tokens/{token}`, de
///     unde îl citesc Functions. Nu în `player_profiles`, care e citibil
///     public — un token în mâna altcuiva înseamnă notificări false trimise
///     în numele jocului;
///  2. ascultă TAP-ul pe notificare și spune aplicației unde să navigheze
///     ([onOpenRoom] etc.).
///
/// Afișarea notificării când aplicația e închisă o face Android singur, din
/// mesajul trimis de Functions — nu trece prin cod Dart.
class PushService {
  PushService._();
  static final instance = PushService._();

  /// Chemat când jucătorul apasă o notificare de invitație în cameră.
  /// Ecranul-rădăcină îl leagă de navigare — serviciul ăsta nu știe nimic
  /// despre widget-uri.
  void Function(String matchId, String code)? onOpenRoom;

  /// Idem, pentru un mesaj primit: deschide firul cu jucătorul respectiv.
  void Function(String withUid)? onOpenChat;

  bool _started = false;

  /// Web-ul ar cere o cheie VAPID și un service worker separat; iOS n-a fost
  /// niciodată build-uit aici. Deci deocamdată doar Android.
  bool get _supported => !kIsWeb && Platform.isAndroid;

  Future<void> start() async {
    if (_started || !_supported) return;
    _started = true;
    try {
      final fm = FirebaseMessaging.instance;

      // Permisiunea de notificări e aceeași cu cea cerută de notificările
      // locale (POST_NOTIFICATIONS). Dacă a fost deja acordată acolo, asta
      // nu mai întreabă nimic.
      await fm.requestPermission();

      await _saveToken(await fm.getToken());
      // Token-ul se poate schimba singur (reinstalare, curățare de date,
      // rotire periodică). Fără abonamentul ăsta, jucătorul ar înceta tăcut
      // să mai primească notificări după prima rotire.
      fm.onTokenRefresh.listen(_saveToken);

      // Aplicația era în fundal, jucătorul a apăsat notificarea.
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
      // Aplicația era complet închisă: mesajul care a pornit-o.
      final initial = await fm.getInitialMessage();
      if (initial != null) _handleTap(initial);
    } catch (e) {
      debugPrint('PushService.start a esuat: $e');
    }
  }

  Future<void> _saveToken(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      final uid = MultiplayerService.instance.currentPlayerId;
      if (uid.isEmpty) return;
      // Id-ul documentului E token-ul: rescrierea aceluiași token nu adaugă
      // un rând nou, iar Functions pot șterge exact token-ul mort pe care
      // l-a refuzat FCM, fără să caute după câmp.
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

  void _handleTap(RemoteMessage msg) {
    final data = msg.data;
    switch (data['type']) {
      case 'room_invite':
        final matchId = data['matchId'] ?? '';
        if (matchId.isNotEmpty) onOpenRoom?.call(matchId, data['code'] ?? '');
      case 'chat':
        final withUid = data['withUid'] ?? '';
        if (withUid.isNotEmpty) onOpenChat?.call(withUid);
      default:
        // „friend_request" și „system" nu au destinație proprie: deschiderea
        // aplicației e deja tot ce trebuia să se întâmple, iar panoul de
        // notificări le arată oricum.
        break;
    }
  }
}
