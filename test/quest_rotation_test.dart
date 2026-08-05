import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/progression.dart';

/// Invariantele rotației săptămânale de quest-uri (vezi [todaysQuests]) —
/// ușor de rupt din greșeală la o schimbare în catalog sau în împărțire.
void main() {
  // 2026-08-03 e o luni; cele 7 zile de mai jos acoperă exact o săptămână.
  final week = List.generate(7, (i) => DateTime(2026, 8, 3 + i));

  test('catalogul se potrivește exact cu cotele zilnice', () {
    // Dacă adaugi quest-uri fără să ajustezi questsPerWeekday (sau invers),
    // partiția nu mai poate ieși — mai bine pică testul decât să se umple
    // zilele la întâmplare.
    expect(questsPerWeekday.fold<int>(0, (a, b) => a + b), allQuests.length);
    expect(questsPerWeekday.length, questRotationDays);
  });

  test('o săptămână acoperă tot catalogul, fără repetări', () {
    final seen = <String>{};
    for (final day in week) {
      for (final quest in todaysQuests(day)) {
        expect(seen.add(quest.id), isTrue, reason: 'quest repetat: ${quest.id}');
      }
    }
    expect(seen.length, allQuests.length);
  });

  test('12 quest-uri în timpul săptămânii, 14 în weekend, din toate dificultățile', () {
    for (final day in week) {
      final quests = todaysQuests(day);
      expect(quests.length, questsPerWeekday[day.weekday - 1],
          reason: 'ziua ${day.weekday} are ${quests.length} quest-uri');
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

  test('quest-urile unei zile sunt UNICE — niciun contor de progres repetat', () {
    // Variantele aceleiași familii (answer_10 / answer_25 / ...) împart un
    // singur contor: două în aceeași zi ar însemna că una se bifează singură
    // pe drumul spre cealaltă, adică două rânduri pe ecran pentru o acțiune.
    for (final day in week) {
      final metrics = todaysQuests(day).map((q) => q.metricKey).toList();
      expect(metrics.toSet().length, metrics.length,
          reason: 'ziua ${day.weekday} are contoare repetate: $metrics');
    }
  });

  test('nicio familie nu are mai multe variante decât zile în săptămână', () {
    // Condiția care face posibilă unicitatea de mai sus. Dacă adaugi a 8-a
    // variantă pe answer_count, partiția devine imposibilă.
    final families = <String, int>{};
    for (final q in allQuests) {
      families[q.metricKey] = (families[q.metricKey] ?? 0) + 1;
    }
    families.forEach((metric, count) {
      expect(count, lessThanOrEqualTo(questRotationDays),
          reason: '$metric are $count variante, dar săptămâna are $questRotationDays zile');
    });
  });

  group('țintele scalate rămân realizabile într-o zi', () {
    // Cerința a fost ca un quest să se termine "în decursul unei zile", de
    // unde questTargetScale. Pericolul e opusul: o țintă scalată peste ce
    // permite fizic jocul într-o zi ar fi imposibil de terminat, iar
    // jucătorul n-ar avea cum să-și dea seama de ce.
    const dailyCeiling = <String, int>{
      // o rotire la 24h, o revendicare de vieți pe zi, un Daily Challenge
      'wheel_spin': 1,
      'daily_lives_claimed': 1,
      'daily_challenge_done': 1,
      // plafoane dure din game_helpers/storage
      'clippy_done': 5,
      'clippy_perfect': 5,
      'heart_bought': 5,
      'hint_pack_bought': 3,
      // 3 rulări la 12h × 17 întrebări
      'planet_run': planetRunsPerCycleWithAd,
      'planet_correct': planetRunsPerCycleWithAd * planetQuestionCount,
      'planet_good_run': planetRunsPerCycleWithAd,
      'planet_great_run': planetRunsPerCycleWithAd,
      'planet_perfect': planetRunsPerCycleWithAd,
      // câte gamemoduri există
      'modes_played': unlockedGameModeCount,
    };

    test('metricile cu plafon fizic nu sunt scalate', () {
      for (final metric in dailyCeiling.keys) {
        expect(scalableQuestMetrics.contains(metric), isFalse,
            reason: '$metric are plafon zilnic, nu poate fi scalat');
      }
    });

    test('nicio țintă nu depășește plafonul zilnic al metricului ei', () {
      for (final q in allQuests) {
        final ceiling = dailyCeiling[q.metricKey];
        if (ceiling == null) continue;
        expect(q.target, lessThanOrEqualTo(ceiling),
            reason: '${q.id} cere ${q.target} din ${q.metricKey}, dar maximul zilnic e $ceiling');
      }
    });

    test('quest-urile pe numărul de revendicări încap în ziua lor', () {
      // "Revendică alte N quest-uri azi" nu poate cere mai multe decât are
      // ziua în care pică, minus el însuși.
      for (var d = 0; d < questRotationDays; d++) {
        for (final q in todaysQuests(DateTime(2026, 8, 3 + d))) {
          if (q.metricKey != 'quests_claimed_today') continue;
          expect(q.target, lessThan(questsPerWeekday[d]),
              reason: '${q.id} cere ${q.target} revendicări într-o zi cu ${questsPerWeekday[d]} quest-uri');
        }
      }
    });
  });

  test('titlurile cu țintă scalabilă afișează ținta EFECTIVĂ', () {
    // Catalogul scrie {n}; dacă cineva pune iar cifra direct în titlu, textul
    // ar minți față de bara de progres de sub el.
    for (final q in allQuests) {
      if (!scalableQuestMetrics.contains(q.metricKey)) continue;
      expect(q.title, contains('${q.target}'),
          reason: '${q.id}: titlul "${q.title}" nu conține ținta ${q.target}');
      expect(q.title, isNot(contains('{n}')));
    }
  });
}
