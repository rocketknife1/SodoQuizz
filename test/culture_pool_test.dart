import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/lang.dart';
import 'package:guess_it/data/culture_questions.dart';

void main() {
  test('pool-ul are 550 de întrebări, toate bine formate', () {
    expect(cultureQuestions.length, 550);
    final seen = <String>{};
    for (final q in cultureQuestions) {
      expect(seen.add(q.question), isTrue, reason: 'duplicat: ${q.question}');
      expect(q.choices.length, 4, reason: q.question);
      expect(q.choices.toSet().length, 4, reason: 'variante duplicate: ${q.question}');
      expect(q.choices, contains(q.answer), reason: q.question);
      expect(q.en, isNotNull, reason: q.question);
      expect(q.en!.trim(), isNotEmpty, reason: q.question);
      final en = q.choicesEn;
      if (en != null) {
        expect(en.length, 4, reason: q.question);
        expect(en.toSet().length, 4, reason: 'variante EN duplicate: ${q.question}');
      }
    }
  });

  test('poziția răspunsului corect e împrăștiată uniform (nu se ghicește fără citit)', () {
    final counts = List.filled(4, 0);
    for (final q in cultureQuestions) {
      counts[q.choices.indexOf(q.answer)]++;
    }
    for (final c in counts) {
      // 550 / 4 = 137,5 — o abatere de ±35 e încă zgomot, nu o tendință.
      expect(c, inInclusiveRange(100, 175), reason: 'distribuție: $counts');
    }
  });

  test('pe engleză se afișează textul și variantele traduse; logica rămâne canonică', () async {
    final q = cultureQuestions.firstWhere((q) => q.question == 'Care este capitala Coreei de Sud?');
    L10n.language.value = AppLanguage.en;
    expect(q.text, 'What is the capital of South Korea?');
    expect(q.label('Seul'), 'Seoul');
    expect(q.answer, 'Seul');
    L10n.language.value = AppLanguage.ro;
    expect(q.text, 'Care este capitala Coreei de Sud?');
    expect(q.label('Seul'), 'Seul');
  });

  test('reordered păstrează traducerea lângă varianta ei', () {
    final q = cultureQuestions.firstWhere((q) => q.choicesEn != null);
    final r = q.reordered([3, 2, 1, 0]);
    L10n.language.value = AppLanguage.en;
    for (final c in q.choices) {
      expect(r.label(c), q.label(c));
    }
    L10n.language.value = AppLanguage.ro;
  });
}
