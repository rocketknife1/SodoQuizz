import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/lang.dart';
import 'package:guess_it/data/questions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => L10n.language.value = AppLanguage.ro);

  test('pe engleză, fiecare întrebare are răspunsul printre variante și indiciile traduse', () async {
    L10n.language.value = AppLanguage.en;
    final all = await loadAllQuestions();
    expect(all, isNotEmpty);
    for (final q in all) {
      if (q.choices.isEmpty) continue;
      expect(q.choices, contains(q.answer), reason: q.id);
      expect(q.choices.toSet().length, q.choices.length, reason: 'variante duplicate: ${q.id}');
    }
    final lion = all.firstWhere((q) => q.id == 'ani_001');
    expect(lion.answer, 'LION');
    expect(lion.hint1, contains('King of the Jungle'));
    expect(lion.category, 'Animals from around the world');
  });

  test('schimbarea limbii reface întrebările (nu rămân din cache pe limba veche)', () async {
    L10n.language.value = AppLanguage.ro;
    final ro = await loadAllQuestions();
    expect(ro.firstWhere((q) => q.id == 'ani_001').answer, 'LEUL');
    L10n.language.value = AppLanguage.en;
    final en = await loadAllQuestions();
    expect(en.firstWhere((q) => q.id == 'ani_001').answer, 'LION');
    expect(en.length, ro.length, reason: 'aceleași întrebări, în aceeași ordine — Clasicul multiplayer depinde de asta');
    for (var i = 0; i < ro.length; i++) {
      expect(en[i].id, ro[i].id);
    }
  });

  test('formulele cu text în română au varianta în engleză', () async {
    L10n.language.value = AppLanguage.en;
    final all = await loadAllQuestions();
    final notebooks = all.firstWhere((q) => q.id == 'mat_069');
    expect(notebooks.formula, contains('notebooks'));
    expect(notebooks.answer, r'$20');
    expect(notebooks.prompt, 'How much do 5 notebooks cost?');
  });
}
