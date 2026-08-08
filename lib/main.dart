import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'core/ads_service.dart';
import 'core/audio.dart';
import 'data/cloud_sync_service.dart';
import 'data/multiplayer_activity_service.dart';
import 'data/multiplayer_service.dart';
import 'data/player_profile_service.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/loading_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Sfx.preload();
  Music.start();
  // O singura initializare, la pornire - restul (login Google) ramane lazy,
  // declansat doar cand userul chiar foloseste acele functii. Esec aici
  // (ex. platforma neconfigurata inca in Firebase Console) nu trebuie sa
  // blocheze restul aplicatiei - single-player merge oricum 100% local.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // identitate (anonima daca nimeni nu e logat cu Google) chiar la pornire,
    // nu doar lazy cand userul deschide multiplayer - altfel un jucator
    // 100% solo n-ar avea niciodata un uid si n-ar putea aparea in
    // leaderboard-ul global (vezi PlayerProfileService).
    await MultiplayerService.instance.ensureInitialized();
    unawaited(PlayerProfileService.instance.ensureProfileHeartbeat());
    unawaited(CloudSyncService.instance.consumePendingGrant());
    // Sterge camerele de multiplayer scrise de telefonul asta carora le-a
    // expirat termenul de 10 minute. Aici, la pornire, si nu doar la finalul
    // meciului, fiindca ultima camera jucata ar ramane altfel pana la
    // urmatorul meci - vezi MultiplayerActivityService.
    unawaited(MultiplayerActivityService.instance.sweepMine());
  } catch (e) {
    debugPrint('Firebase.initializeApp/identitate a esuat: $e');
  }
  // init() cere intai consimtamantul GDPR (UMP) si abia apoi initializeaza
  // SDK-ul de reclame reale (vezi ads_service.dart) - nu blocheaza pornirea.
  AdsService.instance.init();
  runApp(const GuessItApp());
}

class GuessItApp extends StatefulWidget {
  const GuessItApp({super.key});

  @override
  State<GuessItApp> createState() => _GuessItAppState();
}

/// Observă ciclul de viață al aplicației doar ca să sincronizeze progresul
/// cu cloud-ul (dacă userul e logat cu Google - vezi CloudSyncService.push,
/// no-op sigur pentru Guest) când aplicația trece în fundal - prinde
/// momentul normal în care userul închide jocul.
class _GuessItAppState extends State<GuessItApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      CloudSyncService.instance.push();
      Music.pauseForBackground();
    } else if (state == AppLifecycleState.resumed) {
      Music.resumeFromBackground();
      PlayerProfileService.instance.ensureProfileHeartbeat();
      CloudSyncService.instance.consumePendingGrant();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SodoQuizz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF534AB7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white),
        ),
      ),
      home: const LoadingScreen(nextBuilder: _homeBuilder, duration: Duration(milliseconds: 1400)),
    );
  }

  static Widget _homeBuilder(BuildContext _) => const HomeScreen();
}
