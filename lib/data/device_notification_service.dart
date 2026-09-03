import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/lang.dart';
import 'storage_service.dart';

/// **Notificări în bara telefonului** — altceva decât [NotificationService],
/// care e clopoțelul DIN aplicație. Astea apar când aplicația e închisă.
///
/// ## Ce trimite, și de ce doar astea
///
/// Doar lucruri care devin disponibile la un moment CUNOSCUT DINAINTE:
/// roata, planeta, questurile, Clippy. Toate se pot programa pe telefon în
/// clipa în care începe așteptarea, deci nu e nevoie de niciun server.
///
/// Ce NU intră aici: mesajele primite, cererile de prietenie, invitațiile în
/// cameră. Alea depind de acțiunea ALTUI jucător, iar un client nu poate
/// trimite o notificare altui client — cere FCM plus ceva server-side care
/// s-o trimită. Vezi TODO.md, „Piesa 3".
///
/// ## Sunetul stă pe CANAL, nu pe mesaj
///
/// Android leagă sunetul de canalul de notificare, iar un canal e imuabil
/// după creare: dacă schimbi sunetul mai târziu, cei care au deja aplicația
/// rămân cu cel vechi până la reinstalare. De-aia [_channelId] are un sufix
/// de versiune — la o schimbare de sunet se creează un canal NOU, cu id nou,
/// și se șterge cel vechi.
///
/// Fișierul (`android/app/src/main/res/raw/sodo_notify.wav`, generat de
/// tools/generate_notification_sound.py) trebuie să stea în `res/raw`, nu în
/// `assets/`: îl redă sistemul, nu aplicația.
class DeviceNotificationService {
  DeviceNotificationService._();
  static final instance = DeviceNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Sufixul `_v1` există ca să se poată schimba sunetul mai târziu — vezi
  /// nota din capul clasei. Dacă îl schimbi, adaugă vechiul id în
  /// [_retiredChannelIds] ca să fie curățat.
  static const _channelId = 'sodo_events_v1';
  static const _channelName = 'Evenimente din joc';
  static const List<String> _retiredChannelIds = [];

  /// Id-uri STABILE, unul per tip. O notificare nouă de același fel o
  /// înlocuiește pe cea veche în loc să adune un teanc în bară — userul a
  /// cerut ca notificarea să RĂMÂNĂ acolo, nu să se strângă zece.
  static const int idWheel = 1001;
  static const int idPlanet = 1002;
  static const int idQuests = 1003;
  static const int idClippy = 1004;

  /// Doar Android are canale/sunet propriu aici; pe web nu există bară de
  /// notificări, iar iOS n-a fost niciodată build-uit pentru proiectul ăsta.
  bool get _supported => !kIsWeb && Platform.isAndroid;

  Future<void> ensureInitialized() async {
    if (_ready || !_supported) return;
    try {
      tzdata.initializeTimeZones();
      // Fusul local: `zonedSchedule` cere un TZDateTime, iar fără fusul
      // corect notificarea ar cădea la altă oră decât cea de pe ceasul
      // telefonului.
      tz.setLocalLocation(tz.getLocation(await _localTimeZone()));

      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      for (final old in _retiredChannelIds) {
        await android?.deleteNotificationChannel(old);
      }
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Când roata, planeta, questurile sau Clippy sunt din nou gata.',
        importance: Importance.high, // banner peste ecran, nu doar în bară
        sound: RawResourceAndroidNotificationSound('sodo_notify'),
        playSound: true,
        enableVibration: true,
      ));
      _ready = true;
    } catch (e) {
      debugPrint('DeviceNotificationService.ensureInitialized a esuat: $e');
    }
  }

  /// Numele fusului orar al sistemului. `DateTime.now().timeZoneName` dă un
  /// nume scurt („EEST"), pe care baza de fusuri nu-l cunoaște — de-aia
  /// încercăm întâi numele lung și cădem pe UTC dacă nu merge.
  Future<String> _localTimeZone() async {
    try {
      final offset = DateTime.now().timeZoneOffset;
      // Nu putem citi IANA fără un plugin în plus. Bucureștiul acoperă
      // publicul de acum; orice altceva cade pe un fus cu același decalaj.
      if (offset == const Duration(hours: 2) || offset == const Duration(hours: 3)) {
        return 'Europe/Bucharest';
      }
    } catch (_) {}
    return 'UTC';
  }

  /// Cere permisiunea de notificări (Android 13+). Se cheamă o singură dată,
  /// din ecranul principal; dacă userul refuză, restul metodelor devin
  /// no-op-uri tăcute — nimic nu crapă.
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    await ensureInitialized();
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? false;
      // Alarmele exacte sunt o permisiune SEPARATĂ pe Android 14+. Fără ea,
      // programarea exactă e refuzata si cadem pe una inexacta (vezi [_schedule]).
      await android?.requestExactAlarmsPermission();
      return granted;
    } catch (e) {
      debugPrint('DeviceNotificationService.requestPermission a esuat: $e');
      return false;
    }
  }

  AndroidNotificationDetails get _details => const AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
        sound: RawResourceAndroidNotificationSound('sodo_notify'),
        playSound: true,
        // Cerința userului: notificarea RĂMÂNE în bară, nu dispare la tap.
        // O șterge doar el, cu degetul, sau [cancel] când lucrul e consumat.
        autoCancel: false,
        icon: '@mipmap/ic_launcher',
      );

  Future<void> _schedule({
    required int id,
    required Duration after,
    required String title,
    required String body,
  }) async {
    if (!_supported) return;
    await ensureInitialized();
    if (!_ready) return;
    // Trecut sau chiar acum: nu programăm nimic. Lucrul e deja disponibil, iar
    // o notificare care spune „e gata" pentru ceva gata de mult e zgomot.
    if (after <= Duration.zero) return;
    final when = tz.TZDateTime.now(tz.local).add(after);
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        NotificationDetails(android: _details),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        // Ceruta de API chiar si cand nu construim pentru iOS.
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      // Cel mai probabil motiv: userul n-a dat permisiunea de alarme exacte.
      // Reîncercăm inexact — mai bine cu câteva minute întârziere decât deloc.
      debugPrint('DeviceNotificationService._schedule exact a esuat ($id): $e');
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          NotificationDetails(android: _details),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e2) {
        debugPrint('DeviceNotificationService._schedule inexact a esuat ($id): $e2');
      }
    }
  }

  Future<void> cancel(int id) async {
    if (!_supported) return;
    try {
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('DeviceNotificationService.cancel a esuat ($id): $e');
    }
  }

  // ─── Cele patru evenimente ────────────────────────────────────────────────

  Future<void> scheduleWheelReady(Duration after) => _schedule(
        id: idWheel,
        after: after,
        title: tr('🎡 Roata te așteaptă', '🎡 The wheel is ready'),
        body: tr('Ai din nou o învârtire gratuită.', 'You have a free spin again.'),
      );

  Future<void> schedulePlanetReady(Duration after) => _schedule(
        id: idPlanet,
        after: after,
        title: tr('🪐 Planeta e gata', '🪐 The planet is ready'),
        body: tr('Te poți întoarce la hologramă.', 'The hologram is waiting for you.'),
      );

  Future<void> scheduleQuestsRenewed(Duration after) => _schedule(
        id: idQuests,
        after: after,
        title: tr('📋 Questuri noi', '📋 New quests'),
        body: tr('Ți s-au reînnoit misiunile zilei.', 'Your daily missions have reset.'),
      );

  Future<void> scheduleClippyReady(Duration after) => _schedule(
        id: idClippy,
        after: after,
        title: tr('📎 Clippy are ceva pentru tine', '📎 Clippy has something for you'),
        body: tr('Poți vorbi din nou cu el.', 'You can talk to him again.'),
      );

  /// Reprogramează TOT, din starea curentă de pe telefon. Se cheamă la
  /// pornire și ori de câte ori aplicația trece în fundal: e mai simplu și mai
  /// sigur decât să ținem minte ce-am programat, iar id-urile fiind stabile,
  /// o reprogramare o înlocuiește pe cea veche.
  ///
  /// Fiecare bucată e independentă: dacă una aruncă, celelalte se programează
  /// oricum.
  Future<void> rescheduleAll() async {
    if (!_supported) return;
    await ensureInitialized();
    if (!_ready) return;

    try {
      await scheduleWheelReady(await StorageService.ringSpinTimeRemaining());
    } catch (e) {
      debugPrint('reschedule roata: $e');
    }
    try {
      await schedulePlanetReady(await StorageService.planetCooldownRemaining());
    } catch (e) {
      debugPrint('reschedule planeta: $e');
    }
    try {
      // Questurile se resetează la schimbarea zilei (vezi StorageService —
      // cheia lor conține data), deci momentul e miezul nopții local.
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
      await scheduleQuestsRenewed(midnight.difference(now));
    } catch (e) {
      debugPrint('reschedule questuri: $e');
    }
    try {
      // Clippy are DOUĂ ceasuri: unul de 5 minute între discuții și unul
      // zilnic, de câte ori poate vorbi pe zi. Notificăm doar pe cel ZILNIC —
      // o notificare la fiecare 5 minute ar fi spam, nu un serviciu.
      if (await StorageService.clippyPlaysLeftToday() <= 0) {
        await scheduleClippyReady(StorageService.clippyNextDayRemaining());
      } else {
        await cancel(idClippy);
      }
    } catch (e) {
      debugPrint('reschedule clippy: $e');
    }
  }
}
