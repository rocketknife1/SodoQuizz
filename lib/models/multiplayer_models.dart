import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';

enum MatchMode { private, public }

enum MatchStatus { lobby, playing, finished }

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

  const MatchInfo({
    required this.id,
    required this.mode,
    required this.status,
    required this.hostId,
    this.code,
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
    );
  }

  Map<String, dynamic> toMap() => {
        'mode': mode.name,
        'code': code,
        'status': status.name,
        'hostId': hostId,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

/// Un jucător dintr-un meci — real (identificat prin auth anonim Firebase)
/// sau ficțiv (`isBot`), completat local când matchmaking-ul nu adună 5
/// oameni reali la timp.
class MatchPlayer {
  final String id;
  final String name;
  final String avatarSeed;
  final int score;
  final bool isBot;
  final bool isHost;

  const MatchPlayer({
    required this.id,
    required this.name,
    required this.avatarSeed,
    required this.score,
    this.isBot = false,
    this.isHost = false,
  });

  factory MatchPlayer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return MatchPlayer(
      id: doc.id,
      name: data['name'] as String? ?? '?',
      avatarSeed: data['avatarSeed'] as String? ?? doc.id,
      score: data['score'] as int? ?? 0,
      isBot: data['isBot'] as bool? ?? false,
      isHost: data['isHost'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'avatarSeed': avatarSeed,
        'score': score,
        'isBot': isBot,
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

/// Nume ficțive pentru jucătorii-bot care completează matchmaking-ul public
/// când nu se adună 5 oameni reali la timp.
const List<String> botNamePool = [
  'Alex', 'Maria', 'Andrei', 'Ioana', 'Cristi', 'Elena', 'Bogdan', 'Diana',
  'Radu', 'Ana', 'Vlad', 'Larisa', 'Mihai', 'Sorana', 'George',
];
