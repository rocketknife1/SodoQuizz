import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/daily_challenge.dart';
import 'package:guess_it/models/question.dart';

Question _q(String id, {String? image = 'assets/x.jpg', String? formula}) => Question(
      id: id,
      answer: 'a',
      hint1: '',
      hint2: '',
      hint3: '',
      categoryId: 'c',
      category: 'C',
      color: const Color(0xFF000000),
      maxPoints: 100,
      imageAssetPath: image,
      formula: formula,
    );

void main() {
  final pool = List.generate(200, (i) => _q('q$i'));

  test('dateKey e zero-padded', () {
    expect(dailyChallengeDateKey(DateTime(2026, 9, 6)), '2026-09-06');
    expect(dailyChallengeDateKey(DateTime(2026, 12, 31)), '2026-12-31');
  });

  test('acelasi day -> aceleasi 5 intrebari, alt day -> alta selectie', () {
    final a1 = pickDailyChallenge(pool, DateTime(2026, 9, 6)).map((q) => q.id).toList();
    final a2 = pickDailyChallenge(pool, DateTime(2026, 9, 6)).map((q) => q.id).toList();
    final b = pickDailyChallenge(pool, DateTime(2026, 9, 7)).map((q) => q.id).toList();
    expect(a1.length, 5);
    expect(a1, a2);
    expect(a1, isNot(b));
  });

  test('ora din zi nu conteaza — doar data calendaristica', () {
    final morning = pickDailyChallenge(pool, DateTime(2026, 9, 6, 3)).map((q) => q.id).toList();
    final evening = pickDailyChallenge(pool, DateTime(2026, 9, 6, 23, 59)).map((q) => q.id).toList();
    expect(morning, evening);
  });

  test('pool mic -> le intoarce pe toate, fara sa arunce', () {
    final tiny = [_q('x'), _q('y')];
    expect(pickDailyChallenge(tiny, DateTime(2026, 9, 6)).length, 2);
    expect(pickDailyChallenge(const [], DateTime(2026, 9, 6)), isEmpty);
  });

  test('exclude intrebarile fara poza si cele pe formula', () {
    final mixed = [
      _q('foto1'),
      _q('foto2'),
      _q('noimg', image: null),
      _q('formula', formula: 'x^2'),
    ];
    final picked = pickDailyChallenge(mixed, DateTime(2026, 9, 6)).map((q) => q.id).toList();
    expect(picked, containsAll(['foto1', 'foto2']));
    expect(picked, isNot(contains('noimg')));
    expect(picked, isNot(contains('formula')));
  });

  test('recompensa: 40/corect, +150 bonus doar la perfect', () {
    expect(dailyChallengeReward(0), 0);
    expect(dailyChallengeReward(3), 120);
    expect(dailyChallengeReward(4), 160);
    expect(dailyChallengeReward(5), 350);
    expect(dailyChallengeReward(9), 350); // clamp
    expect(dailyChallengeReward(-1), 0);
  });

  test('pickDailyChallenge nu modifica pool-ul dat', () {
    final original = List<Question>.of(pool);
    pickDailyChallenge(pool, DateTime(2026, 9, 6));
    expect(pool.map((q) => q.id), original.map((q) => q.id));
  });
}
