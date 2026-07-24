import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/gamemodes.dart';
import 'package:guess_it/data/questions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads questions for every gamemode', () async {
    final questions = await loadAllQuestions();

    expect(questions, isNotEmpty);
    for (final mode in gameModes) {
      expect(
        questions.where((q) => q.categoryId == mode.id).length,
        greaterThan(0),
        reason: '${mode.id} should have at least one question',
      );
      for (final q in questions.where((q) => q.categoryId == mode.id)) {
        expect(q.choices.length, 4, reason: '${q.id} should have 4 choices');
      }
    }
  });

  test('no duplicate answers across gamemodes', () async {
    final questions = await loadAllQuestions();
    final answers = questions.map((q) => q.answer.trim().toUpperCase()).toList();
    expect(answers.toSet().length, answers.length);
  });
}
