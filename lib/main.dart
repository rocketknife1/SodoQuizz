import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'core/ads_service.dart';
import 'core/audio.dart';
import 'core/eco_mode.dart';
import 'core/lang.dart';
import 'data/cloud_sync_service.dart';
import 'data/moderation_service.dart';
import 'data/multiplayer_activity_service.dart';
import 'data/multiplayer_service.dart';
import 'data/notification_service.dart';
import 'data/player_profile_service.dart';
import 'data/storage_service.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/loading_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Sfx.preload();
  Music.start();
  // Inainte de orice sincronizare, ca sa nu se mai urce in cloud contoarele
  // zilnice ale zilelor trecute — vezi StorageService.pruneOldDailyCounters.
  await StorageService.pruneOldDailyCounters();
  // Amandoua INAINTE de runApp, ca primul cadru desenat sa fie deja in limba
  // corecta si cu ecranul deja stins daca Modul Eco e pornit — cerinta era
  // explicit ca modul sa fie activ din clipa intrarii in joc, nu sa se aprinda
  // vizibil dupa o secunda. Sunt doua citiri din SharedPreferences, deci nu
  // intarzie pornirea in vreun fel simtit.
  await L10n.load();
  await EcoMode.load();
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
    // Lista de jucatori blocati, adusa in memorie o data pe sesiune, ca
    // filtrarea chatului sa fie sincrona - vezi ModerationService.blockedIds.
    unawaited(ModerationService.instance.loadBlocked());
    unawaited(CloudSyncService.instance.consumePendingGrant());
    // Anunturile lasate de admin, descarcate o data si tinute apoi local —
    // vezi NotificationService. Bulina de pe clopotel se aprinde imediat ce
    // ajung, chiar daca jucatorul e deja in meniu.
    unawaited(NotificationService.instance.pullFromCloud().then((_) {
      return NotificationService.instance.refreshUnread();
    }));
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
      // Gratis daca uid-ul n-a schimbat; reincarca doar dupa o logare care a
      // schimbat contul - vezi ModerationService.loadBlocked.
      ModerationService.instance.loadBlocked();
      // Android reseteaza atributele ferestrei cand Activity-ul e recreat,
      // deci luminozitatea redusa trebuie ceruta din nou la fiecare revenire
      // — altfel modul ramanea "pornit" in setari, dar fara efect. Exact
      // cazul cerut: se reintra in joc, ecranul e deja mai stins.
      EcoMode.reapply();
      NotificationService.instance.pullFromCloud().then((_) {
        return NotificationService.instance.refreshUnread();
      });
    }
  }

  /// CHEIA DE PE MaterialApp DEPINDE DOAR DE LIMBA, nu si de Modul Eco — si
  /// diferenta conteaza.
  ///
  /// La limba e obligatorie: textele traduse se citesc prin `tr()` chiar in
  /// `build`-ul fiecarui widget, iar rutele deja impinse pe stiva isi tin
  /// pagina construita in cache, deci fara o cheie noua ecranele de sub cel
  /// curent ar fi ramas in limba veche. Cheia le reconstruieste pe toate, cu
  /// pretul intoarcerii in meniul principal — comportamentul asteptat oricum
  /// dupa "am schimbat limba jocului".
  ///
  /// La Eco ar fi fost stricator: un simplu comutator din Setari ar fi
  /// aruncat jucatorul afara din Setari, inapoi in meniu. Nici nu e nevoie —
  /// animatiile se opresc singure (asculta EcoMode.enabled, vezi
  /// EcoAnimationController), luminozitatea e nativa, iar tranzitiile si
  /// umbra software se recitesc oricum la reconstructia asta de MaterialApp.
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: L10n.language,
      builder: (context, language, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: EcoMode.enabled,
          builder: (context, eco, __) {
            return MaterialApp(
              key: ValueKey(language.code),
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
                // null cat timp Eco e oprit = tranzitiile obisnuite ale
                // platformei, neatinse.
                pageTransitionsTheme: EcoMode.pageTransitionsTheme(),
              ),
              builder: _withEcoDim,
              home: const LoadingScreen(nextBuilder: _homeBuilder, duration: Duration(milliseconds: 1400)),
            );
          },
        );
      },
    );
  }

  /// Umbra software a Modului Eco — folosita DOAR unde nu exista canalul
  /// nativ de luminozitate (web, desktop; vezi EcoMode). Pe Android
  /// `dimOverlayOpacity` e 0, fiindca acolo se stinge backlight-ul real, iar
  /// un strat suplimentar de compus la fiecare cadru ar fi lucrat exact
  /// impotriva scopului.
  static Widget _withEcoDim(BuildContext context, Widget? child) {
    final dim = EcoMode.dimOverlayOpacity;
    if (child == null) return const SizedBox.shrink();
    if (dim <= 0) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(color: Colors.black.withAlpha((255 * dim).round())),
          ),
        ),
      ],
    );
  }

  static Widget _homeBuilder(BuildContext _) => const HomeScreen();
}
