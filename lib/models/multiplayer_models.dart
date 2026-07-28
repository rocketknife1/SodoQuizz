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
  final Timestamp? createdAt;
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
    this.createdAt,
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
      createdAt: data['createdAt'] as Timestamp?,
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

  const MatchPlayer({
    required this.id,
    required this.name,
    required this.avatarSeed,
    required this.score,
    this.photoUrl,
    this.isHost = false,
    this.breads = 0,
    this.eliminated = false,
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
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'avatarSeed': avatarSeed,
        'photoUrl': photoUrl,
        'score': score,
        'isHost': isHost,
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
