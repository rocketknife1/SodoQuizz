import 'package:flutter/material.dart';
import 'lang.dart';

/// Sursa unică de adevăr pentru cele 4 gamemoduri — un singur loc de
/// editat ca să adaugi/schimbi un mod, în loc să umbli prin mai multe
/// fișiere (home screen, loader de întrebări etc).
///
/// Fiecare gamemod își are conținutul într-un singur folder:
/// `assets/continut/{id}/intrebari.json` și `assets/continut/{id}/poze/{id_intrebare}.webp`.
///
/// Pozele au fost PNG până în 2026-08-02 — format fără pierderi, deci cel mai
/// prost caz posibil pentru fotografii: 1297 de imagini de 800x600 ocupau
/// 589MB. Convertite în WebP q90 (diferență invizibilă chiar și la zoom 100%)
/// ocupă 89MB, ceea ce aduce bundle-ul sub limita de 200MB a Google Play
/// pentru descărcarea de bază — singurul lucru care bloca publicarea.
class GameMode {
  final String id;
  final String _titleRo;
  final String _subtitleRo;
  final String _titleEn;
  final String _subtitleEn;
  final IconData icon;
  final Color accentColor;

  /// Numele categoriei, în limba curentă. Gettere, nu câmpuri: [gameModes] e
  /// o listă `const`, iar o constantă nu poate chema tr() — se țin ambele
  /// variante ca date și se alege abia la afișare.
  String get title => tr(_titleRo, _titleEn);
  String get subtitle => tr(_subtitleRo, _subtitleEn);

  /// Categorii blocate: apar în grilă dar nu au încă întrebări/poze —
  /// tap-ul arată un mesaj "va urma în update" în loc să deschidă jocul.
  final bool locked;

  const GameMode({
    required this.id,
    required String title,
    required String subtitle,
    required String titleEn,
    required String subtitleEn,
    required this.icon,
    required this.accentColor,
    this.locked = false,
  })  : _titleRo = title,
        _subtitleRo = subtitle,
        _titleEn = titleEn,
        _subtitleEn = subtitleEn;

  String get contentPath => 'assets/continut/$id';
  String get questionsAssetPath => '$contentPath/intrebari.json';
  String imagePath(String questionId) => '$contentPath/poze/$questionId.webp';
}

const List<GameMode> gameModes = [
  GameMode(
    id: 'cartoon',
    title: 'Cartoon',
    titleEn: 'Cartoon',
    subtitle: 'Desene & filme',
    subtitleEn: 'Cartoons & movies',
    icon: Icons.blur_on_rounded,
    accentColor: Color(0xFF534AB7),
  ),
  GameMode(
    id: 'logouri',
    title: 'Logo-uri',
    titleEn: 'Logos',
    subtitle: 'Branduri cunoscute',
    subtitleEn: 'Well-known brands',
    icon: Icons.grid_view_rounded,
    accentColor: Color(0xFF1D9E75),
  ),
  GameMode(
    id: 'jocuri',
    title: 'Gamers Cave',
    titleEn: 'Gamers Cave',
    subtitle: 'Steam trivia',
    subtitleEn: 'Steam trivia',
    icon: Icons.videogame_asset_rounded,
    accentColor: Color(0xFFFF4500),
  ),
  GameMode(
    id: 'medical',
    title: 'Medical',
    titleEn: 'Medical',
    subtitle: 'Obiecte medicale',
    subtitleEn: 'Medical objects',
    icon: Icons.medical_services_rounded,
    accentColor: Color(0xFF2EC4B6),
  ),
  GameMode(
    id: 'mecanica',
    title: 'Mecanica',
    titleEn: 'Mechanics',
    subtitle: 'Piese & scule auto',
    subtitleEn: 'Car parts & tools',
    icon: Icons.build_rounded,
    accentColor: Color(0xFFE0A62B),
  ),
  GameMode(
    id: 'aplicatii',
    title: 'Aplicatii',
    titleEn: 'Apps',
    subtitle: 'Apps de telefon',
    subtitleEn: 'Phone apps',
    icon: Icons.apps_rounded,
    accentColor: Color(0xFF4C6FFF),
  ),
  GameMode(
    id: 'masini',
    title: 'Mașini de Lux',
    titleEn: 'Luxury Cars',
    subtitle: 'Bolizi & branduri auto',
    subtitleEn: 'Supercars & car brands',
    icon: Icons.directions_car_filled_rounded,
    accentColor: Color(0xFFC0392B),
  ),
  GameMode(
    id: 'celebritati',
    title: 'Celebrități',
    titleEn: 'Celebrities',
    subtitle: 'Vedete & staruri',
    subtitleEn: 'Stars & famous faces',
    icon: Icons.star_rounded,
    accentColor: Color(0xFF8E44AD),
  ),
  GameMode(
    id: 'sport',
    title: 'Fotbal & Sport',
    titleEn: 'Football & Sport',
    subtitle: 'Sportivi & echipe celebre',
    subtitleEn: 'Famous athletes & teams',
    icon: Icons.sports_soccer_rounded,
    accentColor: Color(0xFF16A085),
  ),
  GameMode(
    id: 'romania',
    title: 'România',
    titleEn: 'Romania',
    subtitle: 'Cultură & simboluri',
    subtitleEn: 'Culture & symbols',
    icon: Icons.flag_rounded,
    accentColor: Color(0xFF2C3E90),
  ),
  GameMode(
    id: 'steaguri',
    title: 'Steaguri',
    titleEn: 'Flags',
    subtitle: 'Țări din toată lumea',
    subtitleEn: 'Countries from all over the world',
    icon: Icons.language_rounded,
    accentColor: Color(0xFF1FA2B8),
  ),
  GameMode(
    id: 'animale',
    title: 'Animale',
    titleEn: 'Animals',
    subtitle: 'Fauna din toată lumea',
    subtitleEn: 'Wildlife from all over the world',
    icon: Icons.pets_rounded,
    accentColor: Color(0xFF27AE60),
  ),
  GameMode(
    id: 'monumente',
    title: 'Monumente',
    titleEn: 'Monuments',
    subtitle: 'Minuni ale lumii',
    subtitleEn: 'Wonders of the world',
    icon: Icons.account_balance_rounded,
    accentColor: Color(0xFFB8860B),
  ),
  // Singura categorie care NU merge pe poze: intrebarile arata o formula
  // scrisa mare (vezi FormulaCard si campul `formula` din intrebari.json).
  // Poate contine si intrebari cu poza — un matematician de ghicit se comporta
  // exact ca orice alta poza din joc, fara cod special.
  GameMode(
    id: 'matematica',
    title: 'Matematică',
    titleEn: 'Mathematics',
    subtitle: 'Formule, simboluri & matematicieni',
    subtitleEn: 'Formulas, symbols & mathematicians',
    icon: Icons.functions_rounded,
    accentColor: Color(0xFF7C4DFF),
  ),
  GameMode(
    id: 'instrumente',
    title: 'Instrumente',
    titleEn: 'Instruments',
    subtitle: 'Muzică din toată lumea',
    subtitleEn: 'Music from all over the world',
    icon: Icons.music_note_rounded,
    accentColor: Color(0xFFD63384),
  ),
];

GameMode gameModeById(String id) => gameModes.firstWhere((m) => m.id == id);

// ─── Categoria zilei ────────────────────────────────────────────────────
//
// Conținut rotativ (PLAN_DE_VIITOR.md punctul 5) — pilotul cel mai simplu
// care rămâne totuși REAL: o categorie evidențiată, aleasă determinist pe
// zi (aceeași pentru toți jucătorii, ca o "temă a zilei"), cu un mic bonus
// de revendicat DUPĂ ce ai jucat-o (vezi CategoriesScreen și
// StorageService.claimFeaturedCategory). Recompensa e FLAT, nu crește cu
// nivelul ca la quest-uri (Quest.coinRewardAt) — n-are voie să intre în
// niciuna din curbele testate de test/economy_balance_test.dart, e doar un
// motiv în plus să deschizi jocul azi, nu o sursă de venit calculată.

/// Monede/XP acordate la revendicarea categoriei zilei — pe scara unui
/// quest ușor de bază (vezi progression.dart, QuestTier.easy: ~11-17
/// monede), dar FIX, nu scalat cu nivelul.
const int featuredCategoryCoinReward = 15;
const int featuredCategoryXpReward = 5;

/// Categoria evidențiată azi — aceeași pentru toată lumea, calculată din
/// ziua din an (nu din dată completă, ca să nu depindă de fus orar în
/// moduri ciudate; suficient de stabil pentru o rotație vizuală, nu literă
/// de lege). Sare peste categoriile [GameMode.locked] — n-are sens să
/// evidențiezi ceva ce nu se poate încă juca.
GameMode featuredGameModeToday([DateTime? now]) {
  final unlocked = gameModes.where((m) => !m.locked).toList();
  final n = now ?? DateTime.now();
  final dayOfYear = n.difference(DateTime(n.year, 1, 1)).inDays;
  return unlocked[dayOfYear % unlocked.length];
}
