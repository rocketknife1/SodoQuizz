import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/progression.dart';

/// Invariantele rotației săptămânale de quest-uri (vezi [todaysQuests]) —
/// ușor de rupt din greșeală la o schimbare în catalog sau în împărțire.
void main() {
  // 2026-08-03 e o luni; cele 7 zile de mai jos acoperă exact o săptămână.
  final week = List.generate(7, (i) => DateTime(2026, 8, 3 + i));

  test('o săptămână acoperă tot catalogul, fără repetări', () {
    final seen = <String>{};
    for (final day in week) {
      for (final quest in todaysQuests(day)) {
        expect(seen.add(quest.id), isTrue, reason: 'quest repetat: ${quest.id}');
      }
    }
    expect(seen.length, allQuests.length);
  });

  test('fiecare zi are ~10 quest-uri, din toate dificultățile', () {
    for (final day in week) {
      final quests = todaysQuests(day);
      expect(quests.length, inInclusiveRange(9, 11));
      for (final tier in QuestTier.values) {
        expect(quests.where((q) => q.tier == tier), isNotEmpty,
            reason: 'ziua ${day.weekday} nu are niciun quest $tier');
      }
    }
  });

  test('setul unei zile se repetă săptămâna următoare, identic', () {
    for (final day in week) {
      expect(
        todaysQuests(day.add(const Duration(days: 7))).map((q) => q.id),
        todaysQuests(day).map((q) => q.id),
      );
    }
  });

  test('o zi întreagă revendicată nu depășește plafonul zilnic de gems', () {
    for (final day in week) {
      final gems = todaysQuests(day).fold<int>(0, (sum, q) => sum + q.gemReward);
      expect(gems, lessThanOrEqualTo(dailyQuestGemCap));
    }
  });
}
