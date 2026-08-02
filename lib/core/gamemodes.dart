import 'package:flutter/material.dart';

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
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;

  /// Categorii blocate: apar în grilă dar nu au încă întrebări/poze —
  /// tap-ul arată un mesaj "va urma în update" în loc să deschidă jocul.
  final bool locked;

  const GameMode({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.locked = false,
  });

  String get contentPath => 'assets/continut/$id';
  String get questionsAssetPath => '$contentPath/intrebari.json';
  String imagePath(String questionId) => '$contentPath/poze/$questionId.webp';
}

const List<GameMode> gameModes = [
  GameMode(
    id: 'pixelat',
    title: 'Cartoon',
    subtitle: 'Desene & filme',
    icon: Icons.blur_on_rounded,
    accentColor: Color(0xFF534AB7),
  ),
  GameMode(
    id: 'logouri',
    title: 'Logo-uri',
    subtitle: 'Branduri cunoscute',
    icon: Icons.grid_view_rounded,
    accentColor: Color(0xFF1D9E75),
  ),
  GameMode(
    id: 'jocuri',
    title: 'Gamers Cave',
    subtitle: 'Steam trivia',
    icon: Icons.videogame_asset_rounded,
    accentColor: Color(0xFFFF4500),
  ),
  GameMode(
    id: 'medical',
    title: 'Medical',
    subtitle: 'Obiecte medicale',
    icon: Icons.medical_services_rounded,
    accentColor: Color(0xFF2EC4B6),
  ),
  GameMode(
    id: 'mecanica',
    title: 'Mecanica',
    subtitle: 'Piese & scule auto',
    icon: Icons.build_rounded,
    accentColor: Color(0xFFE0A62B),
  ),
  GameMode(
    id: 'aplicatii',
    title: 'Aplicatii',
    subtitle: 'Apps de telefon',
    icon: Icons.apps_rounded,
    accentColor: Color(0xFF4C6FFF),
  ),
  GameMode(
    id: 'masini',
    title: 'Mașini de Lux',
    subtitle: 'Bolizi & branduri auto',
    icon: Icons.directions_car_filled_rounded,
    accentColor: Color(0xFFC0392B),
  ),
  GameMode(
    id: 'celebritati',
    title: 'Celebrități',
    subtitle: 'Vedete & staruri',
    icon: Icons.star_rounded,
    accentColor: Color(0xFF8E44AD),
  ),
  GameMode(
    id: 'sport',
    title: 'Fotbal & Sport',
    subtitle: 'Sportivi & echipe celebre',
    icon: Icons.sports_soccer_rounded,
    accentColor: Color(0xFF16A085),
  ),
  GameMode(
    id: 'romania',
    title: 'România',
    subtitle: 'Cultură & simboluri',
    icon: Icons.flag_rounded,
    accentColor: Color(0xFF2C3E90),
  ),
  GameMode(
    id: 'steaguri',
    title: 'Steaguri',
    subtitle: 'Țări din toată lumea',
    icon: Icons.language_rounded,
    accentColor: Color(0xFF1FA2B8),
  ),
  GameMode(
    id: 'animale',
    title: 'Animale',
    subtitle: 'Fauna din toată lumea',
    icon: Icons.pets_rounded,
    accentColor: Color(0xFF27AE60),
  ),
  GameMode(
    id: 'monumente',
    title: 'Monumente',
    subtitle: 'Minuni ale lumii',
    icon: Icons.account_balance_rounded,
    accentColor: Color(0xFFB8860B),
  ),
  GameMode(
    id: 'instrumente',
    title: 'Instrumente',
    subtitle: 'Muzică din toată lumea',
    icon: Icons.music_note_rounded,
    accentColor: Color(0xFFD63384),
  ),
];

GameMode gameModeById(String id) => gameModes.firstWhere((m) => m.id == id);
