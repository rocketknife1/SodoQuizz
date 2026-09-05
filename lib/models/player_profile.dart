import 'package:cloud_firestore/cloud_firestore.dart';

/// Profilul public al unui jucător — un doc per uid în `player_profiles`,
/// citibil de orice user autentificat (Google sau anonim), scriibil doar
/// de propriul owner (vezi firestore.rules). Separat de `users/{uid}`
/// (acela e privat, doar cloud-save-ul progresului local — vezi
/// CloudSyncService) — acesta e vitrina publică pentru leaderboard/profil,
/// existentă și pentru useri Guest (care n-au niciodată un doc în `users`).
class PlayerProfile {
  final String uid;
  final String name;
  final String? photoUrl;
  final String avatarSeed;

  /// Id-ul avatarului desenat ales din Profil (vezi widgets/avatar_art.dart).
  /// Gol = poza obișnuită. E aici, în profilul PUBLIC, tocmai ca ceilalți
  /// jucători să-l vadă în clasament și în lista de prieteni.
  final String avatarStyle;

  /// Cosmeticele echipate — vezi core/cosmetics.dart. Doar id-uri (numele
  /// enum); randarea recalculează ce e chiar deblocat din `level`/`leaguePoints`.
  final String equippedFrame;
  final String equippedTitle;

  /// Nivelul (levelForXp) — nou în profilul public. Se afișează lângă nume în
  /// clasament și validează ramele/titlurile pe nivel ale acestui jucător.
  final int level;
  final int matchesPlayed;
  final int wins;
  final int losses;
  final int currentStreak;
  final int longestStreak;

  /// Puncte de ligă cumulate PE VIAȚĂ — nu se resetează niciodată. De la
  /// sezoanele adăugate 2026-08-23 (vezi core/leagues.dart), clasamentul și
  /// badge-ul de cosmetică NU mai citesc ăsta direct, ci [seasonPoints] prin
  /// `effectiveSeasonPoints` — acesta rămâne pentru "cel mai bun rezultat
  /// vreodată" și pentru retrocompatibilitate cu ce s-a scris înainte de
  /// sezoane.
  final int leaguePoints;

  /// Puncte de ligă în sezonul CURENT — se resetează lazy la începutul
  /// fiecărei luni calendaristice, vezi [seasonKey] și
  /// `core/leagues.dart#effectiveSeasonPoints` pentru cum se citește corect
  /// (NU direct, fără să verifici [seasonKey] mai întâi).
  final int seasonPoints;

  /// Cheia lunii ("2026-08") în care a fost scris ultima dată
  /// [seasonPoints] — vezi PlayerProfileService.recordMatchResult pentru
  /// cine o schimbă și `core/leagues.dart#currentSeasonKey`.
  final String seasonKey;

  /// Cel mai înalt [LeagueTier.index] atins ÎN SEZONUL CURENT (peak, nu
  /// valoarea de-acum) — badge-ul cosmetic din listă (vezi
  /// widgets/league_badge.dart) îl folosește pe ăsta, nu tier-ul calculat
  /// direct din [seasonPoints], ca o înfrângere de la finalul sezonului să
  /// nu retrogradeze vizual pe cineva care chiar a atins Gold luna asta.
  final int seasonBestTierIndex;

  /// Puncte de ligă acumulate pe fiecare mod de joc (gameModeId → puncte) —
  /// folosit doar pentru "unde și-a făcut punctajul" la tap pe un rând din
  /// leaderboard, nu pentru sortare (sortarea e după [leaguePoints] total).
  final Map<String, int> modeBreakdown;
  final Timestamp? lastActive;

  /// Cod scurt (6 caractere, ex. "7X3K9A"), generat lazy la prima vizită pe
  /// ecranul de Prieteni (vezi PlayerProfileService.getOrCreateFriendCode) —
  /// spre deosebire de [uid], e făcut să fie dictat/tastat manual între doi
  /// jucători. Null dacă acest profil încă nu l-a generat.
  final String? friendCode;

  /// Momentul creării documentului — scris o singură dată, la primul
  /// heartbeat (vezi PlayerProfileService.ensureProfileHeartbeat). Null
  /// pentru profiluri create înainte de acest câmp (fără migrare
  /// retroactivă) — folosit doar de AdminScreen, tab "Noi azi".
  final Timestamp? createdAt;

  /// True dacă profilul e legat de un cont Google (vezi AuthService.isSignedIn,
  /// rescris la fiecare heartbeat) — azi doar informativ (eticheta din
  /// AdminScreen) plus criteriu de ștergere automată: numai un Guest poate fi
  /// măturat ca abandonat. Resursele de la admin ajung la ambele feluri de
  /// cont (vezi CloudSyncService.consumePendingGrant).
  final bool hasGoogleAccount;

  /// Câte gesturi care dovedesc folosirea reală a jocului s-au înregistrat pe
  /// telefonul acestui cont — roți învârtite + mișcări de balanță (vezi
  /// StorageService.getActivityEvents, de unde e urcat la fiecare heartbeat).
  /// Orice valoare peste 0 scutește definitiv un Guest de ștergerea automată
  /// (vezi PlayerProfileService.guestSweepInactivity).
  final int activityEvents;

  /// Numele pus de administrator (vezi
  /// PlayerProfileService.renamePlayerAsAdmin). Gol = jucătorul își alege
  /// singur numele, ca de obicei. Cât timp e setat, telefonul lui îl adoptă la
  /// fiecare pornire și îi blochează editarea numelui — de-aia ADMINUL trebuie
  /// să-l poată și șterge, altfel jucătorul rămâne pe veci cu numele primit,
  /// chiar și după ce motivul redenumirii a dispărut.
  final String forcedName;

  const PlayerProfile({
    required this.uid,
    required this.name,
    required this.avatarSeed,
    this.photoUrl,
    this.avatarStyle = '',
    this.equippedFrame = 'none',
    this.equippedTitle = 'novice',
    this.level = 0,
    this.matchesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.leaguePoints = 0,
    this.seasonPoints = 0,
    this.seasonKey = '',
    this.seasonBestTierIndex = 0,
    this.modeBreakdown = const {},
    this.lastActive,
    this.friendCode,
    this.createdAt,
    this.hasGoogleAccount = false,
    this.activityEvents = 0,
    this.forcedName = '',
  });

  double get winrate => matchesPlayed == 0 ? 0 : wins / matchesPlayed;

  factory PlayerProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return PlayerProfile(
      uid: doc.id,
      name: data['name'] as String? ?? '?',
      avatarSeed: data['avatarSeed'] as String? ?? doc.id,
      photoUrl: data['photoUrl'] as String?,
      avatarStyle: data['avatarStyle'] as String? ?? '',
      equippedFrame: data['equippedFrame'] as String? ?? 'none',
      equippedTitle: data['equippedTitle'] as String? ?? 'novice',
      level: data['level'] as int? ?? 0,
      matchesPlayed: data['matchesPlayed'] as int? ?? 0,
      wins: data['wins'] as int? ?? 0,
      losses: data['losses'] as int? ?? 0,
      currentStreak: data['currentStreak'] as int? ?? 0,
      longestStreak: data['longestStreak'] as int? ?? 0,
      leaguePoints: data['leaguePoints'] as int? ?? 0,
      seasonPoints: data['seasonPoints'] as int? ?? 0,
      seasonKey: data['seasonKey'] as String? ?? '',
      seasonBestTierIndex: data['seasonBestTierIndex'] as int? ?? 0,
      modeBreakdown: Map<String, int>.from(data['modeBreakdown'] as Map? ?? const {}),
      lastActive: data['lastActive'] as Timestamp?,
      friendCode: data['friendCode'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
      hasGoogleAccount: data['hasGoogleAccount'] as bool? ?? false,
      activityEvents: data['activityEvents'] as int? ?? 0,
      forcedName: data['forcedName'] as String? ?? '',
    );
  }
}

/// Un cont care așteaptă ștergerea din Firebase **Authentication** — un doc în
/// `pending_auth_deletions`, scris de [PlayerProfileService.purgePlayer].
///
/// Există fiindcă „Șterge complet" din admin curăță instant tot ce ține de
/// jucător în Firestore, dar NU poate atinge identitatea lui din
/// Authentication: Firebase interzice unui client să șteargă contul altcuiva,
/// operația cere cheia de service account — adică parola de administrator
/// peste tot proiectul, care n-are ce căuta într-un APK public. Coada e citită
/// de `tools/purge_accounts.py`, care rulează pe calculator, unde cheia stă în
/// siguranță.
class PendingAuthDeletion {
  final String uid;
  final String name;
  final Timestamp? requestedAt;

  const PendingAuthDeletion({required this.uid, required this.name, this.requestedAt});

  factory PendingAuthDeletion.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return PendingAuthDeletion(
      uid: doc.id,
      name: data['name'] as String? ?? '?',
      requestedAt: data['requestedAt'] as Timestamp?,
    );
  }
}

/// O cerere de prietenie primită — un doc în subcolecția
/// `player_profiles/{eu}/friend_requests/{fromUid}` (vezi firestore.rules și
/// PlayerProfileService.fetchIncomingRequests).
class FriendRequest {
  final String fromUid;
  final String fromName;
  final String fromAvatarSeed;
  final String? fromPhotoUrl;
  final String fromAvatarStyle;
  final Timestamp? createdAt;

  const FriendRequest({
    required this.fromUid,
    required this.fromName,
    required this.fromAvatarSeed,
    this.fromPhotoUrl,
    this.fromAvatarStyle = '',
    this.createdAt,
  });

  factory FriendRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return FriendRequest(
      fromUid: doc.id,
      fromName: data['fromName'] as String? ?? '?',
      fromAvatarSeed: data['fromAvatarSeed'] as String? ?? doc.id,
      fromPhotoUrl: data['fromPhotoUrl'] as String?,
      fromAvatarStyle: data['fromAvatarStyle'] as String? ?? '',
      createdAt: data['createdAt'] as Timestamp?,
    );
  }
}
