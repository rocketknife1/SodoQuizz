import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/gamemodes.dart';

/// "Categoria zilei" (PLAN_DE_VIITOR.md punctul 5) — funcția e pură
/// intenționat (nu citește Firestore/SharedPreferences), exact ca placa
/// falsă din Obby, ca să poată fi testată fără mock-uri.
void main() {
  group('featuredGameModeToday', () {
    test('e determinist: aceeași zi dă mereu aceeași categorie', () {
      final day = DateTime(2026, 8, 23);
      final first = featuredGameModeToday(day);
      final second = featuredGameModeToday(day);
      expect(second.id, first.id);
    });

    test('nu alege niciodată o categorie blocată', () {
      for (var d = 0; d < 366; d++) {
        final day = DateTime(2026, 1, 1).add(Duration(days: d));
        expect(featuredGameModeToday(day).locked, isFalse);
      }
    });

    test('se schimbă de-a lungul anului, nu rămâne fixă', () {
      final seen = <String>{};
      for (var d = 0; d < 30; d++) {
        final day = DateTime(2026, 1, 1).add(Duration(days: d));
        seen.add(featuredGameModeToday(day).id);
      }
      expect(seen.length, greaterThan(1));
    });

    test('aceeași pentru TOȚI jucătorii într-o zi dată — nu depinde de altceva', () {
      final day = DateTime(2026, 3, 15, 9, 30);
      final sameDayLater = DateTime(2026, 3, 15, 22, 10);
      expect(featuredGameModeToday(sameDayLater).id, featuredGameModeToday(day).id);
    });
  });
}
