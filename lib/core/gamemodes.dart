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
    id: 'pixelat',
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
