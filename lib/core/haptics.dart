import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Vibrații scurte, ca la un buton fizic. Android le leagă de setarea de
/// sistem „Vibrație la atingere”, deci cine le-a oprit acolo nu le simte nici
/// aici.
class Haptics {
  static DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  /// Apăsare de buton, monedă care ajunge, placă aleasă. Limitată la una la
  /// ~60 ms: o ploaie de monede se simte ca un tril, nu ca un bâzâit continuu.
  static void tap() {
    if (kIsWeb) return;
    final now = DateTime.now();
    if (now.difference(_lastTap).inMilliseconds < 60) return;
    _lastTap = now;
    HapticFeedback.selectionClick();
  }

  /// Recompensă, final de cursă.
  static void light() {
    if (!kIsWeb) HapticFeedback.lightImpact();
  }

  /// Răspuns corect, lovitură.
  static void medium() {
    if (!kIsWeb) HapticFeedback.mediumImpact();
  }

  /// Greșeală, inimă pierdută, explozie.
  static void heavy() {
    if (!kIsWeb) HapticFeedback.heavyImpact();
  }
}
