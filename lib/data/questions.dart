import 'dart:convert';
import 'package:flutter/services.dart';
import '../core/gamemodes.dart';
import '../models/question.dart';

Color _parseColor(String hexColor) {
  final clean = hexColor.replaceAll('#', '');
  final value = int.parse(clean, radix: 16);
  return Color(value | 0xFF000000);
}

Future<List<Question>>? _questionCache;

Future<List<Question>> loadAllQuestions() async {
  _questionCache ??= _loadAllQuestions();
  return _questionCache!;
}

Future<List<Question>> _loadAllQuestions() async {
  final batches = await Future.wait(gameModes.where((m) => !m.locked).map(_loadQuestionsForMode));
  return batches.expand((questions) => questions).toList();
}

Future<List<Question>> _loadQuestionsForMode(GameMode mode) async {
  final jsonString = await rootBundle.loadString(mode.questionsAssetPath);
  final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
  final categories = jsonData['categorii'] as Map<String, dynamic>;
  final questions = <Question>[];

  for (final categoryValue in categories.values) {
    final category = categoryValue as Map<String, dynamic>;
    final categoryName = category['descriere'] as String? ?? mode.title;
    final color = _parseColor(category['culoare_tema'] as String? ?? '#FFFFFF');
    final items = category['intrebari'] as List<dynamic>? ?? [];

    for (final itemData in items) {
      final item = itemData as Map<String, dynamic>;
      final id = item['id'] as String;
      questions.add(Question(
        id: id,
        answer: item['raspuns'] as String,
        hint1: item['hint_1'] as String? ?? '',
        hint2: item['hint_2'] as String? ?? '',
        hint3: item['hint_3'] as String? ?? '',
        categoryId: mode.id,
        category: categoryName,
        choices: item['variante'] != null
            ? List<String>.from(item['variante'] as List<dynamic>)
            : const [],
        color: color,
        maxPoints: item['puncte_max'] as int? ?? 200,
        imageAssetPath: mode.imagePath(id),
      ));
    }
  }

  return questions;
}
