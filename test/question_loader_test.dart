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

  test('every answer is among its own 4 choices', () async {
    // Fara asta, o intrebare cu raspunsul scris altfel decat in lista de
    // variante (o diacritica in plus, un spatiu) trece nedetectata: ecranul
    // de joc coloreaza varianta corecta comparand `opt == q.answer`, deci
    // nu s-ar colora NICIUNA si intrebarea ar fi imposibil de castigat.
    final questions = await loadAllQuestions();
    for (final q in questions) {
      expect(q.choices, contains(q.answer),
          reason: '${q.id}: raspunsul nu e printre variante');
      expect(q.choices.toSet().length, q.choices.length,
          reason: '${q.id}: variante duplicate');
    }
  });

  test('question ids are unique', () async {
    final questions = await loadAllQuestions();
    final ids = questions.map((q) => q.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('formula questions carry their own prompt and no image', () async {
    // Categoria Matematica e singura care arata o formula in locul pozei.
    // Cele doua conditii merg impreuna: daca ar ramane si cu imageAssetPath,
    // BlurImage ar cauta un fisier inexistent; daca ar ramane fara enunt,
    // jucatorul ar vedea o formula fara sa stie ce se cere de la el.
    final questions = await loadAllQuestions();
    final cuFormula = questions.where((q) => q.formula != null).toList();
    expect(cuFormula, isNotEmpty);
    for (final q in cuFormula) {
      expect(q.imageAssetPath, isNull, reason: '${q.id} nu trebuie sa aiba poza');
      expect(q.prompt.trim(), isNotEmpty, reason: '${q.id} nu are enunt');
      expect(q.formula!.trim(), isNotEmpty, reason: '${q.id} are formula goala');
    }
  });

  test('no duplicate answers across gamemodes', () async {
    final questions = await loadAllQuestions();
    final answers = questions.map((q) => q.answer.trim().toUpperCase()).toList();
    expect(answers.toSet().length, answers.length);
  });
}
