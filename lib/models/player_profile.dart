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
    );
  }
}
