import 'package:cloud_firestore/cloud_firestore.dart';

/// Un mesaj dintr-un fir de chat privat între doi prieteni — un doc în
/// `friend_chats/{threadId}/messages/{id}`. Vezi FriendChatService pentru cum
/// se construiește `threadId` și de ce firul e separat de chatul din camera
/// multiplayer.
class FriendMessage {
  final String id;
  final String senderId;
  final String text;
  final Timestamp? sentAt;

  const FriendMessage({required this.id, required this.senderId, required this.text, this.sentAt});

  factory FriendMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return FriendMessage(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      sentAt: data['sentAt'] as Timestamp?,
    );
  }
}

/// Capul firului — documentul `friend_chats/{threadId}` însuși, cu ultimul
/// mesaj copiat în el.
///
/// Există ca ecranul de Prieteni să poată arăta bulina de „mesaj nou" și
/// începutul ultimului mesaj cu O SINGURĂ citire per prieten. Alternativa —
/// să întrebe fiecare fir care e ultimul lui mesaj — ar fi cerut un query
/// ordonat pentru fiecare rând din listă, la fiecare deschidere a ecranului.
class FriendChatSummary {
  final Timestamp? lastMessageAt;
  final String lastSenderId;
  final String lastText;

  /// uid → momentul în care acel participant a deschis ultima oară firul.
  final Map<String, Timestamp> readAt;

  const FriendChatSummary({
    this.lastMessageAt,
    this.lastSenderId = '',
    this.lastText = '',
    this.readAt = const {},
  });

  factory FriendChatSummary.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final rawRead = data['readAt'] as Map? ?? const {};
    return FriendChatSummary(
      lastMessageAt: data['lastMessageAt'] as Timestamp?,
      lastSenderId: data['lastSenderId'] as String? ?? '',
      lastText: data['lastText'] as String? ?? '',
      readAt: {
        for (final entry in rawRead.entries)
          if (entry.value is Timestamp) entry.key as String: entry.value as Timestamp,
      },
    );
  }

  /// True dacă ultimul mesaj e de la celălalt și a venit după ultima mea
  /// deschidere a firului. Un fir niciodată deschis, în care celălalt a scris,
  /// numără ca necitit — de-aia lipsa lui `readAt[me]` nu înseamnă „citit".
  bool hasUnreadFor(String uid) {
    if (lastMessageAt == null || lastSenderId.isEmpty || lastSenderId == uid) return false;
    final mine = readAt[uid];
    return mine == null || lastMessageAt!.compareTo(mine) > 0;
  }
}
