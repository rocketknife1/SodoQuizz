import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'breadcrumbs.dart';

// ─── Cererea de recenzie în Play ──────────────────────────────────────────
//
// DE CE CONTEAZĂ: nota și numărul de recenzii intră direct în cât de sus apari
// în magazin și în cât de mulți instalează după ce te găsesc. Un joc bun fără
// recenzii pierde în fața unuia mediocru cu 200.
//
// REGULA DE AUR: se cere O SINGURĂ DATĂ, într-un moment bun, și niciodată
// dacă omul tocmai a avut o experiență proastă. O cerere prost plasată nu
// aduce doar zero — aduce o stea.
//
// Momentul ales: după ce a terminat cel puțin [_minGames] sesiuni ȘI ultima
// i-a ieșit bine. Cine a jucat de zece ori și tocmai a avut o rundă reușită e
// singurul care are ce spune de bine.
//
// Fereastra de dialog e desenată de Google, nu de noi, iar Google decide dacă
// o arată efectiv — are propriile lui plafoane. De-aia NU se poate promite
// nimic („dă-mi 5 stele și primești X" e și interzis de regulile Play). Se
// cere, atât.

class ReviewPrompt {
  ReviewPrompt._();

  static const _kGames = 'review_games_finished';
  static const _kAsked = 'review_asked';

  /// Câte sesiuni terminate înainte de a cere. Suficient cât omul să-și fi
  /// făcut o părere, nu atât cât să fi uitat de joc.
  static const int _minGames = 10;

  /// Cât de bine trebuie să fi mers ultima sesiune. Sub atât, tăcem: cine
  /// tocmai a greșit jumătate din întrebări n-are chef de recenzii.
  static const double _minCorrectRatio = 0.6;

  /// Se apelează la finalul fiecărei sesiuni de joc. Nu așteaptă nimic și nu
  /// aruncă niciodată — o recenzie nu are voie să încurce sfârșitul unei
  /// partide.
  static Future<void> maybeAsk({
    required int correct,
    required int total,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kAsked) ?? false) return;

      final games = (prefs.getInt(_kGames) ?? 0) + 1;
      await prefs.setInt(_kGames, games);

      if (games < _minGames) return;
      if (total <= 0 || correct / total < _minCorrectRatio) return;

      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;

      // Marcat ÎNAINTE de a cere: dacă cererea pică sau Google alege să nu
      // arate nimic, tot nu vrem să reîncercăm la fiecare partidă. Mai bine
      // pierdem o recenzie decât să devenim aplicația care insistă.
      await prefs.setBool(_kAsked, true);
      Breadcrumbs.drop('cerere de recenzie in Play');
      await review.requestReview();
    } catch (e) {
      debugPrint('ReviewPrompt.maybeAsk a esuat: $e');
    }
  }
}
