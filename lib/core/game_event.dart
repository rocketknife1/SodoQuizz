import 'dart:convert';

/// Un eveniment limitat în timp — „Săptămâna Gaming", „Weekend fotbal",
/// Halloween. O categorie pusă în față 3-7 zile, cu clasament propriu şi un
/// bonus la monede cât ţine. Controlat 100% din Remote Config (cheia
/// `eveniment_activ`), fără build nou. Vezi RemoteFlags.
///
/// Formatul din Remote Config (JSON, sau gol = niciun eveniment):
/// ```json
/// {
///   "id": "halloween-2026",
///   "titlu": "Halloween",
///   "titlu_en": "Halloween",
///   "descriere": "Categorie horror în față. Clasament propriu.",
///   "descriere_en": "Spooky category up front. Its own leaderboard.",
///   "categorie": "istorie",
///   "start": "2026-10-28",
///   "sfarsit": "2026-11-02",
///   "bonus": 1.5
/// }
/// ```
/// `categorie` = un `gameModeId` (vezi core/gamemodes.dart); gol = orice
/// categorie contează. `bonus` = multiplicatorul de monede pe categoria
/// respectivă cât ţine (1.0 = fără bonus).
class GameEvent {
  final String id;
  final String titleRo;
  final String titleEn;
  final String descRo;
  final String descEn;

  /// `gameModeId` pus în față. Gol = orice categorie contează pentru eveniment.
  final String categoryId;

  final DateTime start;
  final DateTime end;

  /// Multiplicator de monede pe categoria evenimentului cât ţine. Plafonat
  /// 1.0..3.0 la parsare — un typo în consolă nu poate da monede la infinit.
  final double coinBonus;

  const GameEvent({
    required this.id,
    required this.titleRo,
    required this.titleEn,
    required this.descRo,
    required this.descEn,
    required this.categoryId,
    required this.start,
    required this.end,
    required this.coinBonus,
  });

  bool isLiveAt(DateTime now) => !now.isBefore(start) && now.isBefore(end);

  /// Zilele întregi rămase (0 în ultima zi). Pentru textul „încă 3 zile".
  int daysLeftAt(DateTime now) {
    final d = end.difference(now).inDays;
    return d < 0 ? 0 : d;
  }

  /// True dacă modul jucat contează pentru eveniment (categoria lui sau
  /// „orice" când [categoryId] e gol).
  bool countsMode(String gameModeId) =>
      categoryId.isEmpty || categoryId == gameModeId;
}

/// Parsează cheia `eveniment_activ`. Întoarce `null` pentru: gol, JSON
/// stricat, câmpuri lipsă, sau date imposibile. Nu aruncă niciodată — un
/// eveniment prost configurat înseamnă „niciun eveniment", nu un crash.
GameEvent? parseGameEvent(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  try {
    final m = jsonDecode(trimmed);
    if (m is! Map) return null;
    final id = (m['id'] as String? ?? '').trim();
    final titleRo = (m['titlu'] as String? ?? '').trim();
    final start = DateTime.tryParse((m['start'] as String? ?? '').trim());
    final end = DateTime.tryParse((m['sfarsit'] as String? ?? '').trim());
    if (id.isEmpty || titleRo.isEmpty || start == null || end == null) return null;
    if (!end.isAfter(start)) return null;
    final bonusRaw = (m['bonus'] as num?)?.toDouble() ?? 1.0;
    return GameEvent(
      id: id,
      titleRo: titleRo,
      titleEn: (m['titlu_en'] as String? ?? titleRo).trim(),
      descRo: (m['descriere'] as String? ?? '').trim(),
      descEn: (m['descriere_en'] as String? ?? m['descriere'] as String? ?? '').trim(),
      categoryId: (m['categorie'] as String? ?? '').trim(),
      start: start,
      end: end,
      coinBonus: bonusRaw.clamp(1.0, 3.0),
    );
  } catch (_) {
    return null;
  }
}
