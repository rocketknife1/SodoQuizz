import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/category_mastery.dart';

void main() {
  test('nesuficiente întrebări -> nestăpânită oricât de bună acuratețea', () {
    expect(isCategoryMastered(seen: 30, correct: 30), isFalse);
  });

  test('destule întrebări dar acuratețe slabă -> nestăpânită', () {
    expect(isCategoryMastered(seen: 80, correct: 30), isFalse); // 37%
  });

  test('prag atins + acuratețe ok -> stăpânită', () {
    expect(isCategoryMastered(seen: 60, correct: 40), isTrue); // 66%
    expect(isCategoryMastered(seen: 200, correct: 130), isTrue);
  });

  test('masteryProgress: 0 la zero, 1 la stăpânire deplină', () {
    expect(masteryProgress(seen: 0, correct: 0), 0);
    expect(masteryProgress(seen: 60, correct: 60), 1.0);
    final mid = masteryProgress(seen: 30, correct: 20);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));
  });

  test('masteryProgress monoton în volum la acuratețe fixă', () {
    final a = masteryProgress(seen: 20, correct: 16);
    final b = masteryProgress(seen: 40, correct: 32);
    expect(b, greaterThan(a));
  });

  test('tier între 0 și 5', () {
    for (final (s, c) in [(0, 0), (10, 5), (30, 25), (60, 45), (300, 250)]) {
      final t = masteryTier(seen: s, correct: c);
      expect(t, inInclusiveRange(0, 5));
    }
    expect(masteryTier(seen: 60, correct: 45), 5);
  });
}
