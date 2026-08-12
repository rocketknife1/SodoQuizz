import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';

enum MatchMode { private, public }

enum MatchStatus { lobby, playing, finished }

/// Modul de joc ales de host la creare — [classic] e fluxul original (fiecare
/// răspunde în ritmul lui, fără sincronizare), [higherLower] e varianta
/// multiplayer a mini-jocului solo Higher or Lower (higher_lower_data.dart):
/// toți din cameră văd aceeași pereche campion/provocator pe rundă și
/// votează în secret, vezi MultiplayerHigherLowerScreen.
enum MatchGameMode { classic, higherLower }

/// Faza rundei curente în modul [MatchGameMode.higherLower] — [answering]
/// cât se așteaptă voturile, [revealed] după ce răspunsul corect și
/// câștigătorii rundei au fost calculați.
enum HigherLowerRoundPhase { answering, revealed }

/// Un meci multiplayer (cameră privată SAU matchmaking public) — un singur
/// model deservește ambele fluxuri, vezi planul de arhitectură: o cameră
/// privată e doar un meci creat cu un [code] vizibil, unul public e creat
/// de matchmaking, fără cod.
class MatchInfo {
  final String id;
  final MatchMode mode;
  final String? code;
  final MatchStatus status;
  final String hostId;
  final String? hostName;
  final String? hostPhotoUrl;
  final String hostAvatarStyle;
  final Timestamp? createdAt;

  /// Miza camerei — aleasă o singură dată, de cel care a creat-o (vezi
  /// core/betting.dart). Toți jucătorii plătesc exact atât; cine intră nu mai
  /// alege nimic. 0 doar la camerele rămase de la versiuni mai vechi.
  final int stake;

  /// Dacă documentul chiar mai EXISTĂ în Firestore. Contează pentru că ștergerea
  /// camerei e felul în care gazda îi anunță pe ceilalți că a plecat: fără
  /// steagul ăsta, un `fromDoc` pe un document șters întorcea un MatchInfo gol,
  /// care arăta exact ca o cameră normală goală — iar cei rămași înăuntru
  /// stăteau blocați într-un lobby fantomă. Vezi RoomLobbyScreen.
  final bool exists;

  /// Momentul (de server) în care hostul a apăsat START — ancora
  /// cronometrului de 60 de secunde din modul Clasic. `null` cât timp meciul
  /// e încă în lobby.
  final Timestamp? startedAt;
  final MatchGameMode gameMode;

  /// Câmpuri de sincronizare a rundei — folosite doar în [MatchGameMode.higherLower],
  /// dar scrise (cu valori implicite, neutre) și pentru [MatchGameMode.classic],
  /// ca [toMap] să nu aibă nevoie de ramificații pe mod.
  final int roundIndex;
  final HigherLowerRoundPhase roundPhase;
  final Map<String, String> roundAnswers;
  final List<String> roundWinnerIds;
  final Timestamp? roundStartedAt;

  const MatchInfo({
    required this.id,
    required this.mode,
    required this.status,
    required this.hostId,
    this.code,
    this.hostName,
    this.hostPhotoUrl,
    this.hostAvatarStyle = '',
    this.createdAt,
    this.stake = 0,
    this.exists = true,
    this.startedAt,
    this.gameMode = MatchGameMode.classic,
    this.roundIndex = 0,
    this.roundPhase = HigherLowerRoundPhase.answering,
    this.roundAnswers = const {},
    this.roundWinnerIds = const [],
    this.roundStartedAt,
  });

  factory MatchInfo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return MatchInfo(
      id: doc.id,
      mode: (data['mode'] as String?) == 'private' ? MatchMode.private : MatchMode.public,
      code: data['code'] as String?,
      status: MatchStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => MatchStatus.lobby,
      ),
      hostId: data['hostId'] as String? ?? '',
      hostName: data['hostName'] as String?,
      hostPhotoUrl: data['hostPhotoUrl'] as String?,
      hostAvatarStyle: data['hostAvatarStyle'] as String? ?? '',
      createdAt: data['createdAt'] as Timestamp?,
      stake: data['stake'] as int? ?? 0,
      exists: doc.exists,
      startedAt: data['startedAt'] as Timestamp?,
      gameMode: (data['gameMode'] as String?) == 'higherLower' ? MatchGameMode.higherLower : MatchGameMode.classic,
      roundIndex: data['roundIndex'] as int? ?? 0,
      roundPhase: HigherLowerRoundPhase.values.firstWhere(
        (p) => p.name == data['roundPhase'],
        orElse: () => HigherLowerRoundPhase.answering,
      ),
      roundAnswers: Map<String, String>.from(data['roundAnswers'] as Map? ?? const {}),
      roundWinnerIds: List<String>.from(data['roundWinnerIds'] as List? ?? const []),
      roundStartedAt: data['roundStartedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
        'mode': mode.name,
        'code': code,
        'status': status.name,
        'hostId': hostId,
        'hostName': hostName,
        'hostPhotoUrl': hostPhotoUrl,
        'hostAvatarStyle': hostAvatarStyle,
        'stake': stake,
        'createdAt': FieldValue.serverTimestamp(),
        'gameMode': gameMode.name,
        'roundIndex': 0,
        'roundPhase': HigherLowerRoundPhase.answering.name,
        'roundAnswers': <String, String>{},
        'roundWinnerIds': <String>[],
      };
}

/// Un jucător dintr-un meci — întotdeauna real, identificat prin auth
/// Firebase (Google sau anonim/Guest). [photoUrl] vine din contul Google
/// (vezi AuthService.multiplayerIdentity) — null pentru Guest, caz în care
/// se arată cercul colorat cu inițiala (vezi [pickAvatarColor]).
class MatchPlayer {
  final String id;
  final String name;
  final String avatarSeed;
  final String? photoUrl;
  final int score;
  final bool isHost;

  /// Folosite doar în [MatchGameMode.higherLower] — număr de răspunsuri
  /// greșite ("pâini", vezi widget-ul dedicat) și dacă a atins pragul de
  /// eliminare (devine spectator, vezi MultiplayerHigherLowerScreen).
  final int breads;
  final bool eliminated;

  /// Miza plătită la intrare — aceeași pentru toți, e miza camerei (vezi
  /// [MatchInfo.stake]). Scrisă o singură dată, la intrare, și citită de TOȚI
  /// clienții la final, ca fiecare să calculeze exact aceeași împărțire.
  ///
  /// Se ține și aici, nu doar pe documentul camerei, ca ecranul de rezultate
  /// să nu mai aibă nevoie de o citire în plus și ca un meci să se poată
  /// deconta corect chiar dacă documentul camerei a fost între timp curățat.
  final int bet;

  /// Id-ul avatarului desenat ales de jucător (vezi widgets/avatar_art.dart).
  /// Gol = poza obișnuită. Călătorește cu jucătorul ca ceilalți de la masă
  /// să-l vadă exact cum și-a ales, nu ca inițială.
  final String avatarStyle;

  /// Marcat o singură dată, când jucătorului i s-a scurs minutul și și-a
  /// scris scorul FINAL. Ecranul de rezultate așteaptă ca toată lumea de la
  /// masă să-l aibă înainte să calculeze plățile — altfel, cine termină cu o
  /// secundă mai devreme ar împărți pool-ul după scoruri încă nescrise ale
  /// celorlalți și ar ajunge la alte cifre decât ei.
  final bool finished;

  const MatchPlayer({
    required this.id,
    required this.name,
    required this.avatarSeed,
    required this.score,
    this.photoUrl,
    this.isHost = false,
    this.breads = 0,
    this.eliminated = false,
    this.bet = 0,
    this.finished = false,
    this.avatarStyle = '',
  });

  factory MatchPlayer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return MatchPlayer(
      id: doc.id,
      name: data['name'] as String? ?? '?',
      avatarSeed: data['avatarSeed'] as String? ?? doc.id,
      photoUrl: data['photoUrl'] as String?,
      score: data['score'] as int? ?? 0,
      isHost: data['isHost'] as bool? ?? false,
      breads: data['breads'] as int? ?? 0,
      eliminated: data['eliminated'] as bool? ?? false,
      bet: data['bet'] as int? ?? 0,
      finished: data['finished'] as bool? ?? false,
      avatarStyle: data['avatarStyle'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'avatarSeed': avatarSeed,
        'photoUrl': photoUrl,
        'score': score,
        'isHost': isHost,
        'bet': bet,
        'finished': finished,
        'avatarStyle': avatarStyle,
        'joinedAt': FieldValue.serverTimestamp(),
      };
}

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
  });

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String? ?? '?',
      text: data['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'sentAt': FieldValue.serverTimestamp(),
      };
}

/// Culoare deterministă (din paleta existentă a aplicației, nu inventată)
/// pentru avatarul unui jucător fără poză reală — același [seed] dă mereu
/// aceeași culoare, ca un jucător să se poată recunoaște vizual pe durata
/// unui meci.
Color pickAvatarColor(String seed) {
  const palette = [
    AppColors.purple,
    AppColors.blue,
    AppColors.orange,
    AppColors.teal,
    AppColors.danger,
    AppColors.coin,
  ];
  return palette[seed.hashCode.abs() % palette.length];
}
