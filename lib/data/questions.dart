import 'dart:convert';
import 'package:flutter/services.dart';
import '../core/flash_game.dart';
import '../core/gamemodes.dart';
import '../core/impostor_game.dart';
import '../core/lang.dart';
import '../models/question.dart';

Color _parseColor(String hexColor) {
  final clean = hexColor.replaceAll('#', '');
  final value = int.parse(clean, radix: 16);
  return Color(value | 0xFF000000);
}

Future<List<Question>>? _questionCache;
AppLanguage? _questionCacheLang;

/// Întrebările vin deja în limba jucătorului (vezi [_loadEnglish]); la
/// schimbarea limbii, cache-urile se refac.
void _dropCacheIfLanguageChanged() {
  if (_questionCacheLang == L10n.current) return;
  _questionCacheLang = L10n.current;
  _questionCache = null;
  _imagePoolCache = null;
}

Future<List<Question>> loadAllQuestions() async {
  _dropCacheIfLanguageChanged();
  _questionCache ??= _loadAllQuestions();
  return _questionCache!;
}

Future<List<Question>> _loadAllQuestions() async {
  final batches = await Future.wait(gameModes.where((m) => !m.locked).map(_loadQuestionsForMode));
  return batches.expand((questions) => questions).toList();
}

/// Traducerea în engleză a unei categorii, din `intrebari_en.json` de lângă
/// `intrebari.json`: doar textele, pe id. Lipsește fișierul sau o întrebare
/// → rămâne textul în română, nu se strică nimic.
Future<Map<String, dynamic>?> _loadEnglish(GameMode mode) async {
  if (!L10n.isEn) return null;
  try {
    final raw = await rootBundle.loadString(mode.questionsAssetPath.replaceFirst('intrebari.json', 'intrebari_en.json'));
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Future<List<Question>> _loadQuestionsForMode(GameMode mode) async {
  final jsonString = await rootBundle.loadString(mode.questionsAssetPath);
  final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
  final categories = jsonData['categorii'] as Map<String, dynamic>;
  final en = await _loadEnglish(mode);
  final enNames = (en?['descrieri'] as Map?)?.cast<String, dynamic>() ?? const {};
  final enItems = (en?['q'] as Map?)?.cast<String, dynamic>() ?? const {};
  final questions = <Question>[];

  for (final entry in categories.entries) {
    final category = entry.value as Map<String, dynamic>;
    final categoryName = enNames[entry.key] as String? ?? category['descriere'] as String? ?? mode.title;
    final color = _parseColor(category['culoare_tema'] as String? ?? '#FFFFFF');
    final items = category['intrebari'] as List<dynamic>? ?? [];

    for (final itemData in items) {
      final item = itemData as Map<String, dynamic>;
      final id = item['id'] as String;
      var formula = item['formula'] as String?;
      var answer = item['raspuns'] as String;
      var choices = item['variante'] != null
          ? List<String>.from(item['variante'] as List<dynamic>)
          : const <String>[];
      var hints = [item['hint_1'] as String? ?? '', item['hint_2'] as String? ?? '', item['hint_3'] as String? ?? ''];
      var prompt = item['enunt'] as String? ?? '';
      final t = enItems[id] as Map<String, dynamic>?;
      if (t != null) {
        final v = (t['v'] as List?)?.cast<String>();
        final at = choices.indexOf(answer);
        if (v != null && v.length == choices.length && at >= 0) {
          choices = v;
          answer = v[at];
        }
        final h = (t['h'] as List?)?.cast<String>();
        if (h != null && h.length == 3) hints = h;
        prompt = t['e'] as String? ?? prompt;
        if (formula != null) formula = t['f'] as String? ?? formula;
      }
      questions.add(Question(
        id: id,
        answer: answer,
        hint1: hints[0],
        hint2: hints[1],
        hint3: hints[2],
        categoryId: mode.id,
        category: categoryName,
        choices: choices,
        color: color,
        maxPoints: item['puncte_max'] as int? ?? 200,
        prompt: prompt,
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
  _dropCacheIfLanguageChanged();
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
