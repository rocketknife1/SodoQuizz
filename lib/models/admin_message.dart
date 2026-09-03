import 'package:cloud_firestore/cloud_firestore.dart';

/// Un mesaj din firul dintre un jucător și administrator — un doc în
/// `admin_threads/{playerUid}/messages/{id}`.
///
/// Separat de `friend_chats` (vezi FriendChatService) fiindcă firul ăsta NU
/// cere prietenie: orice jucător trebuie să poată scrie adminului din prima
/// secundă, iar adminul trebuie să poată deschide fir cu oricine, fără să
/// trimită mai întâi cerere de prietenie.
class AdminMessage {
  final String id;
  final String senderId;

  /// Cine a scris. Se citește DIN DOCUMENT, nu se deduce comparând
  /// `senderId` cu emailul de admin: clientul jucătorului nu știe uid-ul
  /// adminului, iar o comparație pe nume ar fi falsificabilă. Regulile
  /// Firestore sunt cele care garantează că un jucător nu poate scrie un
  /// mesaj cu `fromAdmin: true`.
  final bool fromAdmin;

  final String text;
  final Timestamp? sentAt;

  const AdminMessage({
    required this.id,
    required this.senderId,
    required this.fromAdmin,
    required this.text,
    this.sentAt,
  });

  factory AdminMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return AdminMessage(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      fromAdmin: data['fromAdmin'] as bool? ?? false,
      text: data['text'] as String? ?? '',
      sentAt: data['sentAt'] as Timestamp?,
    );
  }
}

/// Capul firului — documentul `admin_threads/{playerUid}` însuși.
///
/// Există din același motiv ca [FriendChatSummary]: lista de fire din panoul
/// de Admin trebuie să arate ultimul mesaj și bulina de necitit cu O SINGURĂ
/// citire per fir, nu cu un query ordonat în fiecare subcolecție.
///
/// Numele jucătorului e copiat aici (denormalizat) tot pentru asta: altfel
/// lista de fire ar fi cerut încă o citire în `player_profiles` pentru
/// fiecare rând, doar ca să afle cum îl cheamă.
class AdminThreadSummary {
  /// uid-ul jucătorului = și id-ul documentului.
  final String playerUid;
  final String playerName;
  final Timestamp? lastMessageAt;
  final String lastText;

  /// True dacă ultimul mesaj din fir e scris de admin.
  final bool lastFromAdmin;

  /// Când a deschis ultima oară firul fiecare parte. Două câmpuri fixe, nu o
  /// hartă uid→timestamp ca la `friend_chats`: firul are mereu exact două
  /// părți, iar „adminul" e un rol, nu un uid anume — dacă emailul de admin
  /// s-ar muta pe alt cont, o hartă pe uid ar fi arătat brusc tot ca necitit.
  final Timestamp? readAtPlayer;
  final Timestamp? readAtAdmin;

  const AdminThreadSummary({
    required this.playerUid,
    this.playerName = '',
    this.lastMessageAt,
    this.lastText = '',
    this.lastFromAdmin = false,
    this.readAtPlayer,
    this.readAtAdmin,
  });

  factory AdminThreadSummary.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return AdminThreadSummary(
      playerUid: doc.id,
      playerName: data['playerName'] as String? ?? '',
      lastMessageAt: data['lastMessageAt'] as Timestamp?,
      lastText: data['lastText'] as String? ?? '',
      lastFromAdmin: data['lastFromAdmin'] as bool? ?? false,
      readAtPlayer: data['readAtPlayer'] as Timestamp?,
      readAtAdmin: data['readAtAdmin'] as Timestamp?,
    );
  }

  /// Are jucătorul un răspuns nevăzut de la admin? (bulina de pe SETĂRI)
  bool get hasUnreadForPlayer => _unread(lastFromAdmin, readAtPlayer);

  /// Are adminul un mesaj nevăzut de la jucător? (bulina din panoul de Admin)
  bool get hasUnreadForAdmin => _unread(!lastFromAdmin, readAtAdmin);

  /// Un fir niciodată deschis în care celălalt a scris numără ca NECITIT —
  /// de-aia lipsa lui `readAt` nu înseamnă „citit". Același raționament ca
  /// [FriendChatSummary.hasUnreadFor].
  bool _unread(bool lastFromOther, Timestamp? mineReadAt) {
    if (lastMessageAt == null || !lastFromOther) return false;
    return mineReadAt == null || lastMessageAt!.compareTo(mineReadAt) > 0;
  }
}
