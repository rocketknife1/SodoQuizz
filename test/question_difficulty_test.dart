import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/question_difficulty.dart';

void main() {
  test('sub prag -> necalibrat', () {
    expect(
      difficultyFromStats(shown: difficultyMinSample - 1, correct: 0, avgMs: 0),
      QuestionDifficulty.necalibrat,
    );
  });

  test('acuratețe mare -> ușoară', () {
    expect(
      difficultyFromStats(shown: 100, correct: 95, avgMs: 5000),
      QuestionDifficulty.usoara,
    );
  });

  test('acuratețe mijlocie -> medie', () {
    expect(
      difficultyFromStats(shown: 100, correct: 68, avgMs: 6000),
      QuestionDifficulty.medie,
    );
  });

  test('acuratețe mică -> grea', () {
    expect(
      difficultyFromStats(shown: 100, correct: 38, avgMs: 6000),
      QuestionDifficulty.grea,
    );
  });

  test('acuratețe foarte mică -> extremă', () {
    expect(
      difficultyFromStats(shown: 100, correct: 12, avgMs: 6000),
      QuestionDifficulty.extrema,
    );
  });

  test('timp mare împinge o treaptă în sus', () {
    final normal = difficultyFromStats(shown: 100, correct: 68, avgMs: 5000);
    final slow = difficultyFromStats(shown: 100, correct: 68, avgMs: 13000);
    expect(normal, QuestionDifficulty.medie);
    expect(slow, QuestionDifficulty.grea);
  });

  test('timp mic împinge o treaptă în jos', () {
    final fast = difficultyFromStats(shown: 100, correct: 68, avgMs: 2500);
    expect(fast, QuestionDifficulty.usoara);
  });

  test('nudge-ul nu iese din enum', () {
    // extremă + lent nu urcă peste extremă
    expect(
      difficultyFromStats(shown: 100, correct: 5, avgMs: 20000),
      QuestionDifficulty.extrema,
    );
    // ușoară + rapid nu coboară sub ușoară
    expect(
      difficultyFromStats(shown: 100, correct: 99, avgMs: 500),
      QuestionDifficulty.usoara,
    );
  });

  test('avgMs 0 (nemăsurat) nu aplică niciun nudge', () {
    expect(
      difficultyFromStats(shown: 100, correct: 68, avgMs: 0),
      QuestionDifficulty.medie,
    );
  });

  test('label RO+EN pentru fiecare treaptă', () {
    for (final d in QuestionDifficulty.values) {
      final (ro, en) = difficultyLabel(d);
      expect(ro, isNotEmpty);
      expect(en, isNotEmpty);
    }
  });
}
