import 'dart:convert';
import 'package:flutter/services.dart';
import '../core/flash_game.dart';
import '../core/gamemodes.dart';
import '../core/impostor_game.dart';
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
      final formula = item['formula'] as String?;
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
        prompt: item['enunt'] as String? ?? '',
        formula: formula,
        // O întrebare cu formulă NU are poză: ecranul de joc desenează cardul
        // de formulă în locul ei. Lăsat pe `mode.imagePath(id)` ar fi însemnat
        // ca BlurImage să caute un fișier inexistent și să cadă pe
        // placeholder-ul „Va urma" în spatele formulei.
        imageAssetPath: formula == null ? mode.imagePath(id) : null,
      ));
    }
  }

  return questions;
}

Future<List<Question>>? _imagePoolCache;

/// Toate întrebările CU poză (adică orice categorie în afară de formulele de
/// la Matematică), într-o ordine CANONICĂ (sortate după id) — aceeași pe
/// telefon și pe web, fiindcă vin din același JSON. Folosită de Fulgerul și
/// Impostorul (core/flash_game.dart, core/impostor_game.dart): fiecare rundă
/// își face propriul amestec determinist plecând de la ordinea asta fixă.
Future<List<Question>> imagePool() async {
  if (_imagePoolCache != null) return _imagePoolCache!;
  final all = await loadAllQuestions();
  final imgs = all.where((q) => q.imageAssetPath != null).toList()..sort((a, b) => a.id.compareTo(b.id));
  _imagePoolCache = Future.value(imgs);
  return imgs;
}

List<FlashPic> flashPicsFrom(List<Question> pool) =>
    [for (final q in pool) FlashPic(id: q.id, answer: q.answer, imagePath: q.imageAssetPath!)];

/// [pool] grupat pe categorie, pentru Impostorul — ordinea din fiecare listă
/// rămâne cea canonică (sortată după id), moștenită din [pool].
Map<String, List<ImpostorPic>> impostorPicsByCategory(List<Question> pool) {
  final map = <String, List<ImpostorPic>>{};
  for (final q in pool) {
    map.putIfAbsent(q.categoryId, () => []).add(
          ImpostorPic(id: q.id, answer: q.answer, imagePath: q.imageAssetPath!, categoryId: q.categoryId),
        );
  }
  return map;
}
