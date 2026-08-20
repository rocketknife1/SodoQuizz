import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'core/ads_service.dart';
import 'core/app_check_service.dart';
import 'core/audio.dart';
import 'core/eco_mode.dart';
import 'core/lang.dart';
import 'core/theme.dart';
import 'data/cloud_sync_service.dart';
import 'data/moderation_service.dart';
import 'data/multiplayer_activity_service.dart';
import 'data/multiplayer_presence_service.dart';
import 'data/multiplayer_service.dart';
import 'data/notification_service.dart';
import 'data/player_profile_service.dart';
import 'data/storage_service.dart';
import 'firebase_options.dart';
import 'models/multiplayer_models.dart';
import 'screens/home_screen.dart';
import 'screens/loading_screen.dart';
import 'screens/multiplayer/multiplayer_astrosodo_screen.dart';
import 'screens/multiplayer/multiplayer_higher_lower_screen.dart';
import 'screens/multiplayer/multiplayer_match_screen.dart';
import 'screens/multiplayer/multiplayer_obby_screen.dart';
import 'screens/multiplayer/multiplayer_tanks_screen.dart';
import 'widgets/in_app_notification.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Sfx.preload();
  Music.start();
  // Inainte de orice sincronizare, ca sa nu se mai urce in cloud contoarele
  // zilnice ale zilelor trecute — vezi StorageService.pruneOldDailyCounters.
  await StorageService.pruneOldDailyCounters();
  await StorageService.migratePixelatIdToCartoon();
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
    // Inainte de prima cerere catre Auth/Firestore, ca tokenul care dovedeste
    // ca binarul e cel autentic sa plece odata cu ea - vezi
    // app_check_service.dart, inclusiv de ce activarea singura nu schimba
    // inca nimic pe server. Nu arunca niciodata, deci nu poate rupe pornirea.
    await activateAppCheck();
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
  /// Necesară anunțului „cineva a intrat în Multiplayer": banner-ul se
  /// inserează într-un Overlay, iar Overlay-ul aplicației trăiește SUB
  /// Navigator. Contextul din `build`-ul ăsta e deasupra lui, deci
  /// `Overlay.of(context)` de aici n-ar găsi nimic — cheia dă acces la
  /// contextul corect, oricare ar fi ecranul deschis în acel moment.
  final _navigatorKey = GlobalKey<NavigatorState>();

  StreamSubscription<MultiplayerPresencePing>? _presenceSub;
  StreamSubscription<RematchOffer?>? _rematchSub;
  bool _rematchDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenForMultiplayerPresence();
    MultiplayerService.instance.lastFinishedMatchId.addListener(_watchRematchOffer);
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    MultiplayerService.instance.lastFinishedMatchId.removeListener(_watchRematchOffer);
    _rematchSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ─── Revanșă cerută după ce ai ieșit deja din meci ──────────────────────

  /// Oferta de revanșă era ascultată DOAR în ecranul de rezultate, deci cine
  /// apuca să iasă în meniu înainte ca gazda să apese „Cere revanșă" nu mai
  /// primea nimic — iar gazda aștepta un accept imposibil. Aici o ascultăm de
  /// la rădăcină, unde suntem oricare ar fi ecranul deschis.
  ///
  /// Se urmărește un singur meci: ultimul părăsit (vezi
  /// [MultiplayerService.lastFinishedMatchId], pus de MultiplayerResultsScreen
  /// când se închide). Nu e nevoie de nicio interogare pe colecție — id-ul
  /// documentului de ofertă E chiar matchId-ul, pe care toți foștii
  /// participanți îl știu deja.
  void _watchRematchOffer() {
    _rematchSub?.cancel();
    _rematchSub = null;
    final matchId = MultiplayerService.instance.lastFinishedMatchId.value;
    if (matchId == null || Firebase.apps.isEmpty) return;
    _rematchSub = MultiplayerService.instance.watchRematchOffer(matchId).listen(
          _onRematchOffer,
          onError: (e) => debugPrint('Ascultarea revansei a esuat: $e'),
        );
  }

  void _onRematchOffer(RematchOffer? offer) {
    if (offer == null) return;
    final me = MultiplayerService.instance.currentPlayerId;
    if (!offer.participants.any((p) => p.id == me)) return;

    // Gazda a pornit deja camera nouă: intrăm direct, fără să mai întrebăm —
    // am apăsat „Accept" mai devreme, asta e urmarea lui.
    if (offer.status == 'started' && offer.newMatchId != null) {
      MultiplayerService.instance.lastFinishedMatchId.value = null;
      _enterRematch(offer.newMatchId!, offer.gameMode);
      return;
    }
    if (offer.status != 'pending') return;
    // Gazda vede oferta în propriul ecran de rezultate; cine a răspuns deja nu
    // mai e întrebat a doua oară la fiecare eveniment din stream.
    if (offer.hostId == me || offer.acceptedIds.contains(me)) return;
    if (_rematchDialogOpen) return;
    _askRematch(offer);
  }

  Future<void> _askRematch(RematchOffer offer) async {
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final host = offer.participants.firstWhere(
      (p) => p.id == offer.hostId,
      orElse: () => const RematchParticipant(id: '', name: '?', avatarSeed: ''),
    );
    _rematchDialogOpen = true;
    // Fără închidere prin tap în afara ferestrei: gazda chiar așteaptă un
    // răspuns, iar o fereastră închisă din greșeală ar lăsa-o blocată.
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.replay_rounded, color: AppColors.play, size: 34),
        title: Text(tr('${host.name} vrea revanșă', '${host.name} wants a rematch')),
        content: Text(
          offer.stake > 0
              ? tr('Aceiași jucători, aceeași miză: 💰${offer.stake}.',
                  'Same players, same stake: 💰${offer.stake}.')
              : tr('Aceiași jucători, fără miză.', 'Same players, no stake.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Refuz', 'Decline')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Accept', 'Accept')),
          ),
        ],
      ),
    );
    _rematchDialogOpen = false;
    try {
      if (accepted == true) {
        // Nu navigăm noi: gazda pornește camera când s-au strâns toate
        // accepturile, iar noi intrăm pe ramura 'started' de mai sus.
        await MultiplayerService.instance.acceptRematchOffer(offer.matchId);
        // Între accept și pornirea camerei pot trece secunde bune (se așteaptă
        // și ceilalți). Fără rândul ăsta, ecranul rămâne exact cum era și pare
        // că apăsarea n-a făcut nimic.
        _showRootBanner(
          title: tr('Ai acceptat revanșa', 'Rematch accepted'),
          message: tr('Aștepți gazda să pornească meciul.', 'Waiting for the host to start.'),
          icon: Icons.hourglass_top_rounded,
        );
      } else {
        await MultiplayerService.instance.declineRematchOffer(offer.matchId);
        MultiplayerService.instance.lastFinishedMatchId.value = null;
      }
    } catch (e) {
      debugPrint('Raspunsul la revansa a esuat: $e');
    }
  }

  void _enterRematch(String matchId, MatchGameMode gameMode) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => switch (gameMode) {
          MatchGameMode.higherLower => MultiplayerHigherLowerScreen(matchId: matchId),
          MatchGameMode.quizzTanks => MultiplayerTanksScreen(matchId: matchId),
          MatchGameMode.astroSodo => MultiplayerAstroSodoScreen(matchId: matchId),
          MatchGameMode.obby => MultiplayerObbyScreen(matchId: matchId),
          MatchGameMode.classic => MultiplayerMatchScreen(matchId: matchId),
        },
      ),
    );
  }

  /// Ascultarea pornește o singură dată, la lansare, și ține cât ține
  /// aplicația: anunțul are sens tocmai pentru că ajunge ORIUNDE ai fi în
  /// joc, nu doar în ecranul de Multiplayer.
  ///
  /// Nu are nevoie de login explicit: dacă utilizatorul n-a ajuns niciodată
  /// în multiplayer, nu există încă un cont anonim, iar interogarea ar fi
  /// respinsă de reguli. De-aia se abonează abia după ce Firebase Auth chiar
  /// are pe cineva — și se reabonează dacă contul se schimbă (Guest → Google).
  ///
  /// Garda pe `Firebase.apps`: în testul de widget aplicația se construiește
  /// DIRECT, fără `main()`, deci fără `Firebase.initializeApp` — iar simpla
  /// atingere a lui `FirebaseAuth.instance` ar arunca și ar face aplicația
  /// imposibil de montat fără Firebase. Anunțul e o îmbunătățire, nu o
  /// condiție de pornire: dacă nu există Firebase, pur și simplu nu apare.
  void _listenForMultiplayerPresence() {
    if (Firebase.apps.isEmpty) return;
    try {
      FirebaseAuth.instance.authStateChanges().listen((user) {
        _presenceSub?.cancel();
        if (user == null) return;
        _presenceSub = MultiplayerPresenceService.instance.watchOthers().listen(_showPresenceBanner);
      });
    } catch (e) {
      debugPrint('Anunturile de Multiplayer nu au putut porni: $e');
    }
  }

  /// Banner afișat de la RĂDĂCINA aplicației, deci peste orice ecran ar fi
  /// deschis în acel moment.
  ///
  /// Overlay-ul se ia DIRECT din starea Navigator-ului, nu prin
  /// `Overlay.of(context)` — vezi InAppNotification.showInfo pentru de ce
  /// căutarea obișnuită n-are ce găsi de aici.
  void _showRootBanner({
    required String title,
    required String message,
    required IconData icon,
    Color color = AppColors.play,
  }) {
    final overlay = _navigatorKey.currentState?.overlay;
    final context = _navigatorKey.currentContext;
    if (overlay == null || context == null || !context.mounted) return;
    InAppNotification.showInfo(
      context,
      overlay: overlay,
      title: title,
      message: message,
      icon: icon,
      color: color,
    );
  }

  void _showPresenceBanner(MultiplayerPresencePing ping) => _showRootBanner(
        title: tr('${ping.name} a intrat în Multiplayer', '${ping.name} just entered Multiplayer'),
        message: tr('Intră și tu acum dacă vrei să prinzi un meci.', 'Jump in now if you want to catch a match.'),
        icon: Icons.groups_rounded,
      );

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
              navigatorKey: _navigatorKey,
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
