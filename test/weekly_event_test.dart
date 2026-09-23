import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/daily_challenge.dart';
import 'package:guess_it/core/gamemodes.dart';
import 'package:guess_it/core/weekly_event.dart';

/// Săptămâna tematică: aceleași rezultate pe orice telefon, și premii care
/// țin economia în bandă — adrenalină pentru cei buni, ceva pentru cei care
/// încearcă, nimeni îmbogățit peste noapte.
void main() {
  group('calendarul', () {
    test('săptămâna începe luni la miezul nopții, oricare ar fi ziua', () {
      final wed = DateTime(2026, 9, 23, 18, 40);
      expect(weekStart(wed), DateTime(2026, 9, 21));
      expect(weekStart(DateTime(2026, 9, 21)), DateTime(2026, 9, 21));
      expect(weekStart(DateTime(2026, 9, 27, 23, 59)), DateTime(2026, 9, 21));
      expect(weeklyEventId(wed), 'saptamana-2026-09-21');
    });

    test('toată săptămâna are aceeași temă, săptămâna următoare alta', () {
      final a = weeklyThemeFor(DateTime(2026, 9, 21));
      for (var d = 0; d < 7; d++) {
        expect(weeklyThemeFor(DateTime(2026, 9, 21 + d, 12)), a);
      }
      expect(weeklyThemeFor(DateTime(2026, 9, 28)), isNot(a));
    });

    test('fiecare categorie din rotație există și revine abia după ciclu', () {
      final ids = gameModes.map((g) => g.id).toSet();
      for (final t in weeklyThemeRotation) {
        expect(ids, contains(t));
      }
      final seen = <String>{};
      for (var w = 0; w < weeklyThemeRotation.length; w++) {
        // pe calendar: peste ora de iarnă, un `Duration` de 7 zile cade duminică seara
        seen.add(weeklyThemeFor(DateTime(2026, 9, 21 + 7 * w, 12)));
      }
      expect(seen.length, weeklyThemeRotation.length);
    });

    test('evenimentul săptămânii ține fix 7 zile și nu dă bonus la jocul liber', () {
      final e = weeklyEventFor(DateTime(2026, 9, 23));
      expect(e.end.difference(e.start).inDays, 7);
      expect(e.dailyRunOnly, isTrue);
      expect(e.coinBonus, 1.0);
      expect(e.isLiveAt(DateTime(2026, 9, 27, 23, 59)), isTrue);
      expect(e.isLiveAt(DateTime(2026, 9, 28)), isFalse);
      expect(dailyChallengeDateKey(e.start), '2026-09-21');
    });
  });

  group('punctele cursei', () {
    test('greșit = 0, corect rapid cu serie = plafonul regulii', () {
      expect(weeklyAnswerPoints(correct: false, answerMs: 500, streakBefore: 9), 0);
      expect(weeklyAnswerPoints(correct: true, answerMs: 1000, streakBefore: 10), weeklyRunMaxPointsPerAnswer);
      expect(weeklyRunMaxPointsPerAnswer, lessThanOrEqualTo(50), reason: 'regula Firestore: +50 pe scriere');
    });

    test('viteza contează: repede > încet > foarte încet', () {
      final fast = weeklyAnswerPoints(correct: true, answerMs: 2000, streakBefore: 0);
      final mid = weeklyAnswerPoints(correct: true, answerMs: 9000, streakBefore: 0);
      final slow = weeklyAnswerPoints(correct: true, answerMs: 30000, streakBefore: 0);
      expect(fast, greaterThan(mid));
      expect(mid, greaterThan(slow));
      expect(slow, 20, reason: 'corectitudinea singură tot valorează');
    });
  });

  group('premiile', () {
    test('treptele pe loc cer cel puțin 3 zile jucate', () {
      expect(weeklyTierFor(rank: 1, participants: 5, daysPlayed: 1), WeeklyTier.tried);
      expect(weeklyTierFor(rank: 1, participants: 5, daysPlayed: 3), WeeklyTier.champion);
      expect(weeklyTierFor(rank: 3, participants: 100, daysPlayed: 7), WeeklyTier.third);
      expect(weeklyTierFor(rank: 9, participants: 100, daysPlayed: 7), WeeklyTier.top10);
      expect(weeklyTierFor(rank: 20, participants: 100, daysPlayed: 7), WeeklyTier.top25);
      expect(weeklyTierFor(rank: 60, participants: 100, daysPlayed: 7), WeeklyTier.participant);
    });

    test('titlul e doar pentru podium', () {
      expect(weeklyRewardFor(rank: 1, participants: 50, daysPlayed: 7, level: 5).honor, weeklyChampionHonor);
      expect(weeklyRewardFor(rank: 2, participants: 50, daysPlayed: 7, level: 5).honor, weeklyPodiumHonor);
      expect(weeklyRewardFor(rank: 5, participants: 50, daysPlayed: 7, level: 5).honor, isNull);
    });
  });

  group('echilibrul', () {
    const levels = [1, 5, 10, 20, 40];

    test('locul 1 nu îmbogățește: sub 3 zile de venit din quest-uri', () {
      for (final l in levels) {
        final r = weeklyRewardFor(rank: 1, participants: 50, daysPlayed: 7, level: l);
        expect(r.coins, lessThan(dailyQuestIncome(l) * 3), reason: 'nivel $l');
        expect(r.gems, lessThanOrEqualTo(5));
      }
    });

    test('cine încearcă nu pleacă cu mâna goală, dar nici nu-l ajunge pe campion', () {
      for (final l in levels) {
        final tried = weeklyRewardFor(rank: 90, participants: 100, daysPlayed: 1, level: l);
        final champ = weeklyRewardFor(rank: 1, participants: 100, daysPlayed: 7, level: l);
        expect(tried.coins, greaterThan(0), reason: 'nivel $l');
        expect(champ.coins / tried.coins, inInclusiveRange(10, 30),
            reason: 'diferența trebuie simțită, nu să fie prăpastie');
      }
    });

    test('premiul zilnic rămâne sub Provocarea Zilei — nu devine salariu', () {
      final best = weeklyDailyCoins(correct: weeklyRunQuestionCount, consecutiveDays: 7);
      expect(best, lessThan(dailyChallengeReward(dailyChallengeQuestionCount)));
      expect(weeklyDailyCoins(correct: 0, consecutiveDays: 1), 0);
    });

    test('valoarea premiilor se ține în aceeași bandă la orice nivel', () {
      final ratios = [
        for (final l in levels)
          weeklyRewardFor(rank: 1, participants: 50, daysPlayed: 7, level: l).coins / dailyQuestIncome(l),
      ];
      for (final r in ratios) {
        expect(r, closeTo(2.5, 0.05));
      }
    });

    test('cifrele, de văzut la ochi', () {
      for (final l in levels) {
        final income = dailyQuestIncome(l).round();
        final line = [
          for (final rank in [1, 2, 3, 8, 20, 60])
            weeklyRewardFor(rank: rank, participants: 100, daysPlayed: 7, level: l).coins,
        ].join(' / ');
        // ignore: avoid_print
        print('nivel $l: venit zilnic quest-uri $income | premii 1/2/3/top10/top25/particip: $line');
      }
    });
  });
}
