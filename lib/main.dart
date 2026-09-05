import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/admin_reveal.dart';
import 'core/ads_service.dart';
import 'core/analytics.dart';
import 'widgets/remote_gate.dart';
import 'core/remote_flags.dart';
import 'data/bug_report_service.dart';
import 'widgets/error_boundary.dart';
import 'core/app_check_service.dart';
import 'core/audio.dart';
import 'core/lang.dart';
import 'core/theme.dart';
import 'data/cloud_sync_service.dart';
import 'data/device_notification_service.dart';
import 'data/push_service.dart';
import 'data/auth_service.dart';
import 'screens/multiplayer/room_lobby_screen.dart';
import 'screens/admin_chat_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/friend_chat_screen.dart';
import 'data/live_sync.dart';
import 'data/moderation_service.dart';
import 'data/multiplayer_activity_service.dart';
import 'data/multiplayer_presence_service.dart';
import 'data/multiplayer_service.dart';
import 'data/notification_service.dart';
import 'data/player_profile_service.dart';
import 'models/player_profile.dart';
import 'data/storage_service.dart';
import 'firebase_options.dart';
import 'models/multiplayer_models.dart';
import 'screens/home_screen.dart';
import 'screens/loading_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/multiplayer/multiplayer_electric_chair_screen.dart';
import 'screens/multiplayer/multiplayer_rock_paper_scissors_screen.dart';
import 'screens/multiplayer/multiplayer_higher_lower_screen.dart';
import 'screens/multiplayer/multiplayer_match_screen.dart';
import 'screens/multiplayer/multiplayer_obby_screen.dart';
import 'screens/multiplayer/multiplayer_tanks_screen.dart';
import 'widgets/in_app_notification.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inlocuieste dreptunghiul gri implicit al Flutter cu un ecran care ii spune
  // omului ca nu e vina lui si ii da un buton de trimis raportul (vezi
  // widgets/error_boundary.dart).
  //
  // AICI, in main, NU in `MaterialApp.builder`: e o variabila globala, iar
  // atribuirea ei la fiecare reconstructie de widget e o scapare — testele de
  // widget chiar pica pe asta („The value of ErrorWidget.builder was changed
  // by the test"), fiindca ramanea schimbata intre teste.
  ErrorWidget.builder = (details) => ErrorBoundary(details: details);
  Sfx.preload();
  Music.start();
  // Inainte de orice sincronizare, ca sa nu se mai urce in cloud contoarele
  // zilnice ale zilelor trecute — vezi StorageService.pruneOldDailyCounters.
  await StorageService.pruneOldDailyCounters();
  await StorageService.migratePixelatIdToCartoon();
  // Toggle-ul de admin „vezi raspunsul corect" (core/admin_reveal.dart).
  unawaited(loadAdminAnswerReveal());
  // INAINTE de runApp, ca primul cadru desenat sa fie deja in limba corecta.
  await L10n.load();
  // O singura initializare, la pornire - restul (login Google) ramane lazy,
  // declansat doar cand userul chiar foloseste acele functii. Esec aici
  // (ex. platforma neconfigurata inca in Firebase Console) nu trebuie sa
  // blocheze restul aplicatiei - single-player merge oricum 100% local.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // IMEDIAT dupa Firebase, inainte de orice altceva care poate crapa: de
    // aici incolo, o eroare nu se mai pierde. Vezi core/error_reporting.dart
    // pentru de ce conteaza intr-un proiect cu ~168 de `catch` tacute.
    //
    // Doar Android/iOS — Crashlytics nu exista pe web. Jucatorii din browser
    // sunt acoperiti de raportul trimis din aplicatie, nu de aici.
    if (!kIsWeb) {
      // Erorile de framework (build/layout/paint) si cele asincrone care
      // scapa pana la radacina. Fara astea doua linii, Crashlytics ar vedea
      // doar crash-urile native, adica aproape nimic dintr-o aplicatie Dart.
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }
    // Merge si pe web, spre deosebire de Crashlytics. Vezi core/analytics.dart
    // pentru de ce sunt putine evenimente si care anume.
    Analytics.instance.init();
    // NU se asteapta dupa el (`unawaited`): pornirea nu are voie sa depinda de
    // retea, iar valorile implicite din cod sunt bune pana sosesc cele reale.
    // Vezi core/remote_flags.dart.
    unawaited(RemoteFlags.instance.init());
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
    // `consumePendingGrant` NU se mai cheamă aici: `LiveSync.attachToIdentity()`
    // (din initState) atașează ascultătorul pe `admin_grants/{uid}`, iar primul
    // lui snapshot face exact același consum câteva milisecunde mai târziu.
    // Tranzacția de revendicare + `_consumingGrant` fac dublarea imposibilă.
    // Anunturile lasate de admin, descarcate o data si tinute apoi local —
    // vezi NotificationService. Bulina de pe clopotel se aprinde imediat ce
    // ajung, chiar daca jucatorul e deja in meniu.
    // `pullFromCloud` rămâne (aduce anunțurile lăsate de admin în cloud), dar
    // recalcularea bulinei e LOCAL-ONLY, ca pe calea de `resumed`:
    // `LiveSync.attachToIdentity()` (din initState, câteva ms mai târziu)
    // atașează abonamentele care aduc EXACT aceleași cifre prin snapshot-uri.
    // `refreshUnread` ar fi însemnat `2 + 2N` citiri Firestore la fiecare
    // pornire la rece, pentru date care sosesc oricum gratis. NU pune
    // `refreshUnread` înapoi aici.
    unawaited(NotificationService.instance.pullFromCloud().then((_) {
      return NotificationService.instance.refreshUnreadLocalOnly();
    }));
    // Sterge camerele de multiplayer scrise de telefonul asta carora le-a
    // expirat termenul de 10 minute. Aici, la pornire, si nu doar la finalul
    // meciului, fiindca ultima camera jucata ar ramane altfel pana la
    // urmatorul meci - vezi MultiplayerActivityService.
    unawaited(MultiplayerActivityService.instance.sweepMine());
    // Rapoartele de eroare care n-au putut pleca (fara net) pleaca acum.
    // Erorile apar cel mai des cand conexiunea e proasta, deci fara pasul
    // asta am pierde exact rapoartele care conteaza.
    unawaited(BugReportService.instance.flushQueue());
  } catch (e) {
    debugPrint('Firebase.initializeApp/identitate a esuat: $e');
  }
  // init() cere intai consimtamantul GDPR (UMP) si abia apoi initializeaza
  // SDK-ul de reclame reale (vezi ads_service.dart) - nu blocheaza pornirea.
  AdsService.instance.init();
  // Handler-ul de fundal FCM trebuie inregistrat INAINTE de runApp si e o
  // functie top-level (ruleaza in izolat separat) — vezi push_service.dart.
  if (!kIsWeb && !Platform.isIOS) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
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
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenForMultiplayerPresence();
    LiveSync.instance.attachToIdentity();
    MultiplayerService.instance.lastFinishedMatchId.addListener(_watchRematchOffer);
    _listenForDeepLinks();
    _setUpNotifications();
    // La pornire: am fost intr-un meci care inca ruleaza? (aplicatia a murit
    // in mijlocul lui). Banner-ul de reconectare il monteaza [_ReconnectHost].
    MultiplayerService.instance.checkReconnect();
  }

  /// Ordine: întâi notificările locale (care inițializează pluginul și citesc
  /// payload-ul de pornire), apoi push-ul (token FCM + rutarea tap-ului),
  /// apoi consumarea payload-ului de pornire — abia după ce navigatorul e gata.
  Future<void> _setUpNotifications() async {
    await _setUpDeviceNotifications();
    _setUpPush();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushService.instance.routePayload(
        DeviceNotificationService.instance.takePendingLaunchPayload(),
      );
    });
  }

  /// Notificarile PUSH (mesaj, cerere de prietenie, anunt de sistem,
  /// invitatie in camera). Serviciul nu stie nimic despre widget-uri — aici i
  /// se spune UNDE sa duca fiecare tap.
  void _setUpPush() {
    if (Firebase.apps.isEmpty) return;
    PushService.instance
      ..onOpenRoom = _openInvitedRoom
      ..onOpenChat = _openChatWith
      ..onOpenAdminChat = _openAdminChat
      ..start();
  }

  /// Tap pe o invitatie in camera: intram DIRECT in ea, nu doar deschidem
  /// aplicatia. Daca intre timp camera a disparut (gazda a inchis-o, meciul
  /// s-a terminat), spunem asta pe fata in loc sa lasam un ecran gol.
  Future<void> _openInvitedRoom(String matchId, String code) async {
    try {
      await MultiplayerService.instance.ensureInitialized();
      final identity = await AuthService.instance.multiplayerIdentity();
      final info = await MultiplayerService.instance.joinRoomById(
        matchId: matchId,
        displayName: identity.name,
        photoUrl: identity.photoUrl,
        avatarStyle: identity.avatarStyle,
      );
      _navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => RoomLobbyScreen(matchId: info.id, isHost: false, stakePaid: info.stake),
      ));
    } catch (e) {
      debugPrint('Deschiderea camerei din invitatie a esuat: $e');
      _showRootBanner(
        title: tr('Invitație', 'Invite'),
        message: tr('Camera nu mai e disponibilă.', 'That room is no longer available.'),
        icon: Icons.meeting_room_outlined,
      );
    }
  }

  /// Tap pe notificarea firului cu administratorul. [playerUid] gol = firul
  /// meu (mi-a raspuns adminul); nevid = sunt adminul, iar acela e jucatorul.
  Future<void> _openAdminChat(String playerUid) async {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    final asAdmin = playerUid.isNotEmpty;
    final uid = asAdmin ? playerUid : MultiplayerService.instance.currentPlayerId;
    if (uid.isEmpty) return;
    var title = tr('Administrator', 'Administrator');
    if (asAdmin) {
      // Numele jucatorului, ca sa nu deschid un fir intitulat cu un uid.
      // Daca profilul nu se poate citi, uid-ul e tot mai bun decat nimic.
      try {
        final profile = await PlayerProfileService.instance.getProfile(playerUid);
        title = profile?.name ?? playerUid;
      } catch (e) {
        debugPrint('_openAdminChat: profilul $playerUid nu s-a putut citi: $e');
        title = playerUid;
      }
    }
    nav.push(MaterialPageRoute(
      builder: (_) => AdminChatScreen(playerUid: uid, title: title, asAdmin: asAdmin),
    ));
  }

  Future<void> _openChatWith(String withUid) async {
    // Tap pe notificarea de mesaj: deschidem DIRECT firul cu omul respectiv,
    // nu lista de prieteni. Daca profilul nu se poate incarca (offline, cont
    // sters), cadem pe lista de prieteni ca sa nu ramana tap-ul fara efect.
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    PlayerProfile? friend;
    try {
      friend = await PlayerProfileService.instance.getProfile(withUid);
    } catch (e) {
      debugPrint('_openChatWith: incarcarea profilului $withUid a esuat: $e');
    }
    nav.push(MaterialPageRoute(
      builder: (_) => friend != null
          ? FriendChatScreen(friend: friend)
          : const FriendsScreen(),
    ));
  }

  /// Permisiunea de notificari + prima programare. Nu blocheaza pornirea:
  /// daca userul refuza, tot serviciul devine un no-op tacut si jocul merge
  /// mai departe neschimbat.
  ///
  /// Cererea vine la PRIMA pornire, nu ingropata intr-un ecran de setari:
  /// notificarile astea sunt singurul lucru care aduce jucatorul inapoi cand
  /// i s-a reincarcat roata, si nimeni nu cauta un comutator pentru ceva ce
  /// n-a vazut niciodata.
  Future<void> _setUpDeviceNotifications() async {
    await DeviceNotificationService.instance.requestPermission();
    await DeviceNotificationService.instance.rescheduleAll();
  }

  @override
  void dispose() {
    _presenceSub?.cancel();
    MultiplayerService.instance.lastFinishedMatchId.removeListener(_watchRematchOffer);
    _rematchSub?.cancel();
    _linkSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ─── Link de invitație prieteni (guessit://addfriend/<cod>) ────────────

  /// Prinde link-ul ATÂT la pornire rece (aplicația era închisă, s-a
  /// deschis direct din link — [AppLinks.getInitialLink]) CÂT ȘI cu
  /// aplicația deja pornită în fundal ([AppLinks.uriLinkStream]). Fără
  /// primul, cineva care apasă link-ul fără să aibă aplicația deja
  /// deschisă n-ar vedea niciodată cererea de prietenie trimisă.
  ///
  /// Aceeași gardă pe `Firebase.apps` ca la [_listenForMultiplayerPresence]:
  /// testul de widget montează aplicația fără `Firebase.initializeApp`.
  void _listenForDeepLinks() {
    if (Firebase.apps.isEmpty) return;
    final appLinks = AppLinks();
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleFriendInviteUri(uri);
    });
    _linkSub = appLinks.uriLinkStream.listen(
      _handleFriendInviteUri,
      onError: (e) => debugPrint('Ascultarea link-urilor de invitatie a esuat: $e'),
    );
  }

  /// [uri] arată `guessit://addfriend/<cod>` — codul e primul segment de
  /// cale. Orice altă schemă/gazdă (n-ar trebui să apară, dar un link scris
  /// de mână poate greși) e ignorată tăcut.
  ///
  /// [MultiplayerService.ensureInitialized] înainte de cerere: cine deschide
  /// link-ul fără să fi intrat NICIODATĂ în Multiplayer încă n-are cont
  /// anonim în Firebase Auth, iar [PlayerProfileService.sendFriendRequest]
  /// citește `currentPlayerId` — fără pasul ăsta, cererea ar eșua tăcut cu
  /// `notFound` pentru cel dintâi link deschis vreodată.
  Future<void> _handleFriendInviteUri(Uri uri) async {
    if (uri.scheme != 'guessit' || uri.host != 'addfriend') return;
    final code = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (code.isEmpty) return;
    try {
      await MultiplayerService.instance.ensureInitialized();
      final outcome = await PlayerProfileService.instance.sendFriendRequest(code);
      final message = switch (outcome) {
        FriendRequestOutcome.sent => tr('Cerere de prietenie trimisă!', 'Friend request sent!'),
        FriendRequestOutcome.autoAccepted => tr('V-ați adăugat reciproc!', 'You added each other!'),
        FriendRequestOutcome.alreadyFriends => tr('Sunteți deja prieteni.', 'You are already friends.'),
        FriendRequestOutcome.notFound =>
          tr('Linkul de invitație nu mai e valabil.', "This invite link isn't valid anymore."),
        FriendRequestOutcome.isSelf => tr('Ăsta e chiar linkul tău de invitație.', "That's your own invite link."),
      };
      _showRootBanner(
        title: tr('Invitație de prieten', 'Friend invite'),
        message: message,
        icon: Icons.person_add_alt_1_rounded,
      );
    } catch (e) {
      debugPrint('Deep link addfriend a esuat: $e');
    }
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
    // Cont banat: nu-i arătăm deloc dialogul. Poarta din
    // MultiplayerService.acceptRematchOffer i-ar refuza oricum acceptul (întoarce
    // false), dar atunci ar rămâne cu bannerul fals „Ai acceptat revanșa" la
    // nesfârșit. Fără acțiune oferită, fără banner fals — decizia „banatul AFLĂ"
    // e servită de porțile din ecranele de Multiplayer și Clasament.
    if (PlayerProfileService.instance.amIBanned.value) return;
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
          MatchGameMode.obby => MultiplayerObbyScreen(matchId: matchId),
          MatchGameMode.electricChair => MultiplayerElectricChairScreen(matchId: matchId),
          MatchGameMode.classic => MultiplayerMatchScreen(matchId: matchId),
          MatchGameMode.rockPaperScissors => MultiplayerRockPaperScissorsScreen(matchId: matchId),
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        // Pe web `paused` poate să nu vină niciodată — se primește `hidden`.
        // Verificarea cu doi jucători rulează în Chrome, deci fără ramura
        // asta abonamentele n-ar fi oprite niciodată chiar acolo unde se
        // măsoară costul lor.
        state == AppLifecycleState.hidden) {
      LiveSync.instance.stop();
      CloudSyncService.instance.push();
      Music.pauseForBackground();
      // Reprogramam alarmele TOCMAI cand plecam din aplicatie: aia e clipa in
      // care starea de pe telefon (cat mai are roata, planeta, Clippy) e cea
      // mai proaspata, si tot atunci notificarile chiar incep sa conteze.
      DeviceNotificationService.instance.rescheduleAll();
    } else if (state == AppLifecycleState.resumed) {
      LiveSync.instance.start();
      Music.resumeFromBackground();
      PlayerProfileService.instance.ensureProfileHeartbeat();
      // `consumePendingGrant` NU se mai cheamă aici: abonamentul din LiveSync
      // îl declanșează singur, iar reatașarea aduce oricum un snapshot
      // proaspăt cu tot ce s-a schimbat cât aplicația era în fundal.
      // `loadBlocked` NU se mai cheamă aici: `LiveSync.start()` de mai sus
      // reatașează `ModerationService.startLive()`, al cărui prim snapshot
      // rescrie oricum `blockedIds` cu lista de pe server. Apelul rămăsese un
      // `.get()` în plus pe exact aceleași documente, la fiecare revenire din
      // fundal.
      // `pullFromCloud` rămâne (aduce anunțurile lăsate de admin). Recalcularea
      // bulinei folosește varianta LOCAL-ONLY, nu `refreshUnread`: partea live
      // (mesaje necitite, cereri) vine acum din abonamentele reatașate de
      // `LiveSync.start()` de mai sus, prin snapshot-uri. `refreshUnread` ar
      // reface `fetchLive()` = încă `2 + N` citiri Firestore pentru exact
      // aceleași date. NU pune `refreshUnread` înapoi aici.
      NotificationService.instance.pullFromCloud().then((_) {
        return NotificationService.instance.refreshUnreadLocalOnly();
      });
      // Am revenit in prim-plan — daca eram intr-un meci si l-am pierdut
      // (net cazut, aplicatia omorata), aici se aprinde butonul de reconectare.
      MultiplayerService.instance.checkReconnect();
    }
  }

  /// CHEIA DE PE MaterialApp DEPINDE DOAR DE LIMBA.
  ///
  /// Textele traduse se citesc prin `tr()` chiar in `build`-ul fiecarui
  /// widget, iar rutele deja impinse pe stiva isi tin pagina construita in
  /// cache, deci fara o cheie noua ecranele de sub cel curent ar ramane in
  /// limba veche. Cheia le reconstruieste pe toate, cu pretul intoarcerii in
  /// meniul principal — comportamentul asteptat dupa "am schimbat limba".
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: L10n.language,
      builder: (context, language, _) {
        return MaterialApp(
          key: ValueKey(language.code),
          navigatorKey: _navigatorKey,
          // Numara singur ecranele vizitate. O linie aici tine locul unei
          // linii in fiecare din cele 33 de ecrane — si nu se poate uita la
          // adaugarea unuia nou.
          navigatorObservers: [
            if (Analytics.instance.observer != null) Analytics.instance.observer!,
          ],
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
          // Banner-ul de reconectare sta DEASUPRA oricarui ecran (peste
          // navigator), ca sa apara si daca jucatorul a ajuns inapoi in meniu.
          builder: (context, child) => RemoteGate(
            child: _ReconnectHost(
              navigatorKey: _navigatorKey,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }

  /// Ce se vede dupa ecranul de incarcare: la PRIMA pornire tutorialul, pe
  /// urma mereu meniul. Vezi screens/welcome_screen.dart.
  ///
  /// Cat timp raspunsul nu a sosit din SharedPreferences (cateva
  /// milisecunde), se arata meniul — nu un ecran gol si nici un spinner:
  /// jucatorul care a mai jucat nu are de ce sa astepte, iar cel nou vede
  /// tutorialul o clipa mai tarziu, fara sa piarda nimic.
  static Widget _homeBuilder(BuildContext _) => FutureBuilder<bool>(
        future: StorageService.hasSeenIntro(),
        builder: (_, snap) => snap.data == false
            ? const WelcomeScreen()
            : const HomeScreen(),
      );
}

/// Bara subtire de sus „Ai un meci in desfasurare — Reconecteaza". Asculta
/// [MultiplayerService.reconnectTarget]; la tap deschide ecranul modului
/// respectiv cu acelasi matchId.
class _ReconnectHost extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  const _ReconnectHost({required this.child, required this.navigatorKey});

  @override
  State<_ReconnectHost> createState() => _ReconnectHostState();
}

class _ReconnectHostState extends State<_ReconnectHost> {
  bool _opening = false;

  Future<void> _reconnect(String matchId, MatchGameMode mode) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      // Verificam inca o data live — meciul putea sa se termine intre timp.
      await MultiplayerService.instance.checkReconnect();
      if (MultiplayerService.instance.reconnectTarget.value == null) return;
      widget.navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => switch (mode) {
          MatchGameMode.higherLower => MultiplayerHigherLowerScreen(matchId: matchId),
          MatchGameMode.quizzTanks => MultiplayerTanksScreen(matchId: matchId),
          MatchGameMode.obby => MultiplayerObbyScreen(matchId: matchId),
          MatchGameMode.electricChair => MultiplayerElectricChairScreen(matchId: matchId),
          MatchGameMode.rockPaperScissors => MultiplayerRockPaperScissorsScreen(matchId: matchId),
          MatchGameMode.classic => MultiplayerMatchScreen(matchId: matchId),
        },
      ));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<({String matchId, MatchGameMode gameMode})?>(
      valueListenable: MultiplayerService.instance.reconnectTarget,
      builder: (context, target, _) {
        return Stack(
          children: [
            widget.child,
            if (target != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Material(
                  color: Colors.transparent,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B2540),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.play.withAlpha(180), width: 1.4),
                          boxShadow: [BoxShadow(color: AppColors.play.withAlpha(90), blurRadius: 14)],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.sports_esports_rounded, color: AppColors.play, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                tr('Ai un meci în desfășurare.', 'You have a match in progress.'),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _opening
                                  ? null
                                  : () => _reconnect(target.matchId, target.gameMode),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.play,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: _opening
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : Text(tr('RECONECTEAZĂ', 'RECONNECT'),
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
