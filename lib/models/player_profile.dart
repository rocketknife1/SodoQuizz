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
  final int matchesPlayed;
  final int wins;
  final int losses;
  final int currentStreak;
  final int longestStreak;
  final int leaguePoints;

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

  const PlayerProfile({
    required this.uid,
    required this.name,
    required this.avatarSeed,
    this.photoUrl,
    this.matchesPlayed = 0,
    this.wins = 0,
    this.losses = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.leaguePoints = 0,
    this.modeBreakdown = const {},
    this.lastActive,
    this.friendCode,
    this.createdAt,
    this.hasGoogleAccount = false,
    this.activityEvents = 0,
  });

  double get winrate => matchesPlayed == 0 ? 0 : wins / matchesPlayed;

  factory PlayerProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return PlayerProfile(
      uid: doc.id,
      name: data['name'] as String? ?? '?',
      avatarSeed: data['avatarSeed'] as String? ?? doc.id,
      photoUrl: data['photoUrl'] as String?,
      matchesPlayed: data['matchesPlayed'] as int? ?? 0,
      wins: data['wins'] as int? ?? 0,
      losses: data['losses'] as int? ?? 0,
      currentStreak: data['currentStreak'] as int? ?? 0,
      longestStreak: data['longestStreak'] as int? ?? 0,
      leaguePoints: data['leaguePoints'] as int? ?? 0,
      modeBreakdown: Map<String, int>.from(data['modeBreakdown'] as Map? ?? const {}),
      lastActive: data['lastActive'] as Timestamp?,
      friendCode: data['friendCode'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
      hasGoogleAccount: data['hasGoogleAccount'] as bool? ?? false,
      activityEvents: data['activityEvents'] as int? ?? 0,
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
  final Timestamp? createdAt;

  const FriendRequest({
    required this.fromUid,
    required this.fromName,
    required this.fromAvatarSeed,
    this.fromPhotoUrl,
    this.createdAt,
  });

  factory FriendRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return FriendRequest(
      fromUid: doc.id,
      fromName: data['fromName'] as String? ?? '?',
      fromAvatarSeed: data['fromAvatarSeed'] as String? ?? doc.id,
      fromPhotoUrl: data['fromPhotoUrl'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
    );
  }
}
