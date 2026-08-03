import 'package:cloud_firestore/cloud_firestore.dart';

/// Cât timp rămâne vizibilă o cameră terminată în `multiplayer_activity`
/// înainte să fie ștearsă. Ținut aici, nu în serviciu, fiindcă valoarea apare
/// și în textul afișat adminului ("se șterge la 10 minute").
const Duration roomActivityRetention = Duration(minutes: 10);

/// Un jucător, așa cum a intrat și cum a ieșit dintr-o cameră terminată.
///
/// [entry] și [exit] sunt cifre de portofel, nu scor: [entry] e tot ce l-a
/// costat participarea (taxa fixă de intrare + miza pusă), iar [exit] e tot ce
/// i s-a creditat înapoi la decontare (câștigul din pool + surplusul returnat
/// de plafonul mesei). Diferența dintre ele e câștigul sau pierderea reală —
/// vezi core/betting.dart.
class RoomActivityPlayer {
  /// Identificatorul unic prin care se leagă totul de baza de date — același
  /// uid ca în `player_profiles` și `users`. Numele e doar pentru citit.
  final String uid;
  final String name;
  final int place;
  final int score;
  final int entry;
  final int exit;

  const RoomActivityPlayer({
    required this.uid,
    required this.name,
    required this.place,
    required this.score,
    required this.entry,
    required this.exit,
  });

  /// Cât a câștigat (pozitiv) sau a pierdut (negativ) în camera asta.
  int get net => exit - entry;

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'place': place,
        'score': score,
        'entry': entry,
        'exit': exit,
      };

  factory RoomActivityPlayer.fromMap(Map<String, dynamic> m) => RoomActivityPlayer(
        uid: m['uid'] as String? ?? '?',
        name: m['name'] as String? ?? '?',
        place: (m['place'] as num?)?.toInt() ?? 0,
        score: (m['score'] as num?)?.toInt() ?? 0,
        entry: (m['entry'] as num?)?.toInt() ?? 0,
        exit: (m['exit'] as num?)?.toInt() ?? 0,
      );
}

/// O cameră de multiplayer încheiată — un doc în `multiplayer_activity`, cu
/// id-ul egal cu matchId-ul camerei.
///
/// Spre deosebire de `matches/{matchId}` (șters imediat ce pleacă ultimul
/// jucător) și de `completed_matches/{matchId}` (rămâne definitiv, dar are
/// doar 3 câmpuri, pentru numărătoarea din Statistici), documentul ăsta ține
/// tabloul complet al mesei și se autodistruge după [roomActivityRetention].
class RoomActivity {
  final String roomId;
  final String gameModeId;
  final Timestamp? finishedAt;
  final Timestamp? expiresAt;
  final int pool;
  final int tableCap;
  final List<RoomActivityPlayer> players;

  const RoomActivity({
    required this.roomId,
    required this.gameModeId,
    required this.players,
    this.finishedAt,
    this.expiresAt,
    this.pool = 0,
    this.tableCap = 0,
  });

  int get playerCount => players.length;

  bool get isExpired {
    final e = expiresAt;
    return e != null && e.toDate().isBefore(DateTime.now());
  }

  /// Cât timp a mai rămas până la ștergere — null dacă a trecut deja.
  Duration? get timeLeft {
    final e = expiresAt;
    if (e == null) return null;
    final left = e.toDate().difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  factory RoomActivity.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final raw = (data['players'] as List?) ?? const [];
    return RoomActivity(
      roomId: doc.id,
      gameModeId: data['gameModeId'] as String? ?? '?',
      finishedAt: data['finishedAt'] as Timestamp?,
      expiresAt: data['expiresAt'] as Timestamp?,
      pool: (data['pool'] as num?)?.toInt() ?? 0,
      tableCap: (data['tableCap'] as num?)?.toInt() ?? 0,
      players: [
        for (final p in raw)
          if (p is Map) RoomActivityPlayer.fromMap(Map<String, dynamic>.from(p)),
      ]..sort((a, b) => a.place.compareTo(b.place)),
    );
  }
}
