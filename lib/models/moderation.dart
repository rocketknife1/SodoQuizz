import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/lang.dart';

/// Motivul unei raportări. Lista e scurtă și fixă deliberat: un câmp liber ar
/// fi ajuns un al doilea chat, nemoderat, direct în panoul de admin.
enum ReportReason {
  limbaj('Limbaj vulgar / injurii', 'Vulgar language / insults'),
  harassment('Hărțuire / amenințări', 'Harassment / threats'),
  spam('Spam sau reclamă', 'Spam or advertising'),
  trisare('Trișare', 'Cheating'),
  altceva('Altceva', 'Something else');

  const ReportReason(this._labelRo, this._labelEn);
  final String _labelRo;
  final String _labelEn;

  /// Getter, nu câmp: constantele de enum nu pot chema tr().
  String get label => tr(_labelRo, _labelEn);

  static ReportReason fromId(String? id) =>
      ReportReason.values.firstWhere((r) => r.name == id, orElse: () => ReportReason.altceva);
}

/// O raportare trimisă de un jucător — un doc în `reports`, citit doar de
/// admin (vezi firestore.rules).
///
/// Ține și o COPIE a mesajului reclamat ([messageText]), nu doar id-ul lui.
/// Motivul e practic: chatul unei camere se șterge complet când pleacă
/// ultimul jucător (vezi MultiplayerService._deleteMatch), deci până să
/// deschidă adminul panoul, mesajul original de obicei nu mai există. Fără
/// copie, raportarea ar fi ajuns „X l-a reclamat pe Y" fără nimic de judecat.
class PlayerReport {
  final String id;
  final String reporterUid;
  final String reporterName;
  final String targetUid;
  final String targetName;
  final ReportReason reason;

  /// Textul reclamat, dacă raportarea a pornit de la un mesaj anume. Gol dacă
  /// s-a raportat jucătorul în general (din lista de jucători a camerei).
  final String messageText;

  /// Unde s-a întâmplat — id-ul meciului sau al firului de chat privat.
  /// Informativ, pentru context; nu se mai poate deschide de nicăieri.
  final String context;

  final Timestamp? createdAt;

  /// Marcat de admin după ce s-a uitat peste ea. Rămâne în listă (nu se
  /// șterge automat) ca să se vadă istoricul unui jucător reclamat des.
  final bool handled;

  const PlayerReport({
    required this.id,
    required this.reporterUid,
    required this.reporterName,
    required this.targetUid,
    required this.targetName,
    required this.reason,
    this.messageText = '',
    this.context = '',
    this.createdAt,
    this.handled = false,
  });

  factory PlayerReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return PlayerReport(
      id: doc.id,
      reporterUid: data['reporterUid'] as String? ?? '',
      reporterName: data['reporterName'] as String? ?? '?',
      targetUid: data['targetUid'] as String? ?? '',
      targetName: data['targetName'] as String? ?? '?',
      reason: ReportReason.fromId(data['reason'] as String?),
      messageText: data['messageText'] as String? ?? '',
      context: data['context'] as String? ?? '',
      createdAt: data['createdAt'] as Timestamp?,
      handled: data['handled'] as bool? ?? false,
    );
  }
}

/// Un jucător blocat de contul curent — un doc în
/// `player_profiles/{eu}/blocked/{uid}`. Numele e copiat la blocare ca lista
/// să rămână citibilă chiar dacă celălalt își schimbă numele sau își șterge
/// contul.
class BlockedPlayer {
  final String uid;
  final String name;
  final Timestamp? blockedAt;

  const BlockedPlayer({required this.uid, required this.name, this.blockedAt});

  factory BlockedPlayer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return BlockedPlayer(
      uid: doc.id,
      name: data['name'] as String? ?? '?',
      blockedAt: data['blockedAt'] as Timestamp?,
    );
  }
}
