import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/category_mastery.dart';
import 'package:guess_it/core/cosmetics.dart';
import 'package:guess_it/core/daily_mode.dart';
import 'package:guess_it/core/gamemodes.dart';
import 'package:guess_it/core/impostor_game.dart';
import 'package:guess_it/core/lang.dart';
import 'package:guess_it/core/music_tracks.dart';
import 'package:guess_it/core/powerups.dart';
import 'package:guess_it/core/question_difficulty.dart';
import 'package:guess_it/core/unknown_game.dart';
import 'package:guess_it/data/culture_questions.dart';
import 'package:guess_it/data/higher_lower_data.dart';
import 'package:guess_it/data/shop.dart';
import 'package:guess_it/models/moderation.dart';
import 'package:guess_it/models/multiplayer_models.dart';
import 'package:guess_it/models/question_report.dart';
import 'package:guess_it/widgets/avatar_art.dart';

/// Diacritice sau cuvinte românești uzuale — inclusiv cele fără diacritice,
/// pe care o căutare doar după ă/î/ș/ț le rata („Fulgerul”, „pct”).
final _romanian = RegExp(
  r'[ăâîșțşţĂÂÎȘȚ]|\b(si|sau|nu|cu|pe|din|pentru|este|joaca|jucator|intrebare|raspuns|monede|vieti|runda|'
  r'castig|pierzi|alege|inapoi|acum|camera|meci|nimic|toti|pct|Claritate|Fulgerul|Impostorul|Clasic|Scaunul|'
  r'Piatra|Hartie|Foarfeca|Fara|Nivel|Argint|Aur|Lui|Lumii|Tara|Tari)\b',
  caseSensitive: false,
);

void _expectEnglish(String text, String where) {
  expect(_romanian.hasMatch(text), isFalse, reason: '$where: „$text”');
}

void main() {
  setUp(() => L10n.language.value = AppLanguage.en);
  tearDown(() => L10n.language.value = AppLanguage.ro);

  test('modurile de joc', () {
    for (final m in MatchGameMode.values) {
      _expectEnglish(matchGameModeLabel(m), 'mod ${m.name}');
    }
    for (final g in gameModes) {
      _expectEnglish(g.title, 'categorie ${g.id}');
      _expectEnglish(g.subtitle, 'categorie ${g.id}');
    }
  });

  test('power-up-uri și evenimente de rundă', () {
    for (final p in PowerUp.values) {
      final t = powerUpTitles[p];
      final d = powerUpDescriptions[p];
      if (t != null) _expectEnglish(tr(t.$1, t.$2), 'power-up ${p.name}');
      if (d != null) _expectEnglish(tr(d.$1, d.$2), 'power-up ${p.name}');
    }
    for (final e in RoundEvent.values) {
      final t = roundEventTitles[e];
      final d = roundEventDescriptions[e];
      if (t != null) _expectEnglish(tr(t.$1, t.$2), 'eveniment ${e.name}');
      if (d != null) _expectEnglish(tr(d.$1, d.$2), 'eveniment ${e.name}');
    }
  });

  test('Unknown: artefacte, obiecte, evenimente, poțiuni, note', () {
    for (final r in UnknownRelic.values) {
      _expectEnglish(unknownRelicName(r), 'artefact ${r.name}');
      _expectEnglish(unknownRelicDesc(r), 'artefact ${r.name}');
    }
    for (final i in UnknownItem.values) {
      _expectEnglish(unknownItemName(i), 'obiect ${i.name}');
      _expectEnglish(unknownItemDesc(i), 'obiect ${i.name}');
    }
    for (final e in UnknownEvent.values) {
      _expectEnglish(unknownEventTitle(e), 'eveniment ${e.name}');
      _expectEnglish(unknownEventDesc(e), 'eveniment ${e.name}');
    }
    for (final p in UnknownPotionEffect.values) {
      _expectEnglish(unknownPotionName(p), 'poțiune ${p.name}');
      _expectEnglish(unknownPotionDesc(p), 'poțiune ${p.name}');
    }
    for (final n in UnknownNote.values) {
      _expectEnglish(unknownNoteText(n, 3, 11), 'notă ${n.name}');
    }
  });

  test('Impostorul: indiciile', () {
    for (final k in ImpostorClueKind.values) {
      _expectEnglish(impostorClueText(ImpostorClue(k, 'A')), 'indiciu ${k.name}');
    }
  });

  test('cosmetice, dificultate, stăpânire, avatare, rapoarte', () {
    for (final f in Frame.values) {
      _expectEnglish(frameLabel(f), 'ramă ${f.name}');
    }
    for (final t in PlayerTitle.values) {
      final l = titleLabel(t);
      _expectEnglish(tr(l.$1, l.$2), 'titlu ${t.name}');
    }
    for (final d in QuestionDifficulty.values) {
      _expectEnglish(difficultyLabelTr(d), 'dificultate ${d.name}');
    }
    for (final l in masteryTierLabelsEn) {
      _expectEnglish(l, 'stăpânire');
    }
    for (final a in AvatarStyle.values) {
      _expectEnglish(a.label, 'avatar ${a.name}');
    }
    for (final r in ReportReason.values) {
      _expectEnglish(r.label, 'raport ${r.name}');
    }
    for (final r in QuestionReportReason.values) {
      _expectEnglish(r.label, 'raport întrebare ${r.name}');
    }
  });

  test('magazin și muzică', () {
    for (final b in [...bundles, noAdsBundle]) {
      _expectEnglish(b.title, 'pachet');
      _expectEnglish(b.subtitle, 'pachet');
    }
    for (final m in musicTracks) {
      _expectEnglish(m.description, 'muzică ${m.id}');
    }
  });

  test('Higher & Lower și cultura generală', () {
    for (final h in higherLowerItems) {
      _expectEnglish(h.label, 'Higher & Lower');
    }
    _expectEnglish(formatSearchVolume(1500), 'volum');
    _expectEnglish(formatSearchVolume(12), 'volum');
    _expectEnglish(formatSearchVolume(0.3), 'volum');
    for (final q in cultureQuestions) {
      _expectEnglish(q.text, 'cultură: ${q.question}');
      for (final c in q.choices) {
        _expectEnglish(q.label(c), 'cultură (variantă): ${q.question}');
      }
    }
  });
}
