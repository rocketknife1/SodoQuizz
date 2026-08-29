import 'package:flutter/material.dart';

import '../data/storage_service.dart';

/// **Temele vizuale ale aplicației.** Fiecare temă e o paletă completă +
/// o textură de fundal. Schimbă DOAR cum arată jocul (culori, gradient,
/// textură) — zero efect pe reguli, economie, progres.
///
/// De ce o singură sursă: [AppColors] (core/theme.dart) NU mai ține culori
/// `const`, ci citește din tema activă de aici. Cele ~700 de locuri care
/// scriu `AppColors.bg` etc. rămân neatinse — devin doar accesări de getter.
///
/// Schimbarea temei reconstruiește tot `MaterialApp` (cheie nouă, ca la
/// limbă — vezi main.dart), deci și ecranele deja pe stivă se recolorează.
enum AppThemeId {
  /// Cerneală în apă: acvamarin adânc, accente splash. Tema implicită —
  /// numele a venit de la user („splasshy").
  splasshy,

  /// Negru + neon crud, scanline-uri retro de arcade.
  neon,

  /// Goth: aproape monocrom, cărbune + os + un roșu-sânge, filigran.
  obsidian,

  /// LUMINOASĂ. Hârtie crem, cerneală, accente mate, grilă de puncte.
  paper,

  /// Rece: verde-brad spre miez de noapte, aurora boreală în fundal.
  aurora,

  /// Cald: prună spre umbră arsă, chihlimbar/coral, scântei.
  ember,
}

/// Ce desenează [ThemeTextureOverlay] peste tot ecranul (foarte discret,
/// `IgnorePointer`, oprit sub Modul Eco).
enum ThemeTexture { blobs, scanlines, filigree, dotGrid, aurora, embers }

/// O paletă completă — toate „sloturile" de culoare pe care le expune
/// [AppColors], plus cele 3 opriri ale gradientului „spațial" și textura.
@immutable
class AppPalette {
  final AppThemeId id;
  final String nameRo;
  final String nameEn;

  /// `true` doar pentru [AppThemeId.paper] — ecranele care aleg o culoare de
  /// text în funcție de fundal (rare, dar există) o pot citi de aici.
  final bool isLight;
  final ThemeTexture texture;

  // Fundal
  final Color bg;
  final Color bgEnd;
  final Color card;
  final Color spaceMid; // oprirea din mijloc a gradientului „spațial"
  final Color spaceEnd; // oprirea de jos

  // Accente
  final Color play;
  final Color blue;
  final Color purple;
  final Color orange;
  final Color teal;
  final Color gray;

  // Semantice (monede/vieți/etc.)
  final Color coin;
  final Color life;
  final Color hint;
  final Color gem;
  final Color success;
  final Color danger;

  const AppPalette({
    required this.id,
    required this.nameRo,
    required this.nameEn,
    required this.texture,
    this.isLight = false,
    required this.bg,
    required this.bgEnd,
    required this.card,
    required this.spaceMid,
    required this.spaceEnd,
    required this.play,
    required this.blue,
    required this.purple,
    required this.orange,
    required this.teal,
    required this.gray,
    required this.coin,
    required this.life,
    required this.hint,
    required this.gem,
    required this.success,
    required this.danger,
  });

  LinearGradient get bgGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bg, bgEnd],
      );

  LinearGradient get spaceGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [bg, spaceMid, spaceEnd],
      );
}

/// Cele 6 palete. Ordinea = ordinea din ecranul de alegere.
const List<AppPalette> kAppPalettes = [
  // ── 1. Splasshy — cerneală în apă ──────────────────────────────────────
  AppPalette(
    id: AppThemeId.splasshy,
    nameRo: 'Splasshy',
    nameEn: 'Splasshy',
    texture: ThemeTexture.blobs,
    bg: Color(0xFF071A2B),
    bgEnd: Color(0xFF0B2E3D),
    card: Color(0xFF0E3244),
    spaceMid: Color(0xFF0A2740),
    spaceEnd: Color(0xFF0B1B33),
    play: Color(0xFF2DD4A7),
    blue: Color(0xFF38BDF8),
    purple: Color(0xFFC026D3),
    orange: Color(0xFFFB7185),
    teal: Color(0xFF22D3EE),
    gray: Color(0xFF3E5566),
    coin: Color(0xFFFDE047),
    life: Color(0xFFFB7185),
    hint: Color(0xFFFDE047),
    gem: Color(0xFF67E8F9),
    success: Color(0xFF2DD4A7),
    danger: Color(0xFFFB6A7A),
  ),

  // ── 2. Neon Arcade ────────────────────────────────────────────────────
  AppPalette(
    id: AppThemeId.neon,
    nameRo: 'Neon Arcade',
    nameEn: 'Neon Arcade',
    texture: ThemeTexture.scanlines,
    bg: Color(0xFF0A0A12),
    bgEnd: Color(0xFF12071E),
    card: Color(0xFF1A0F2E),
    spaceMid: Color(0xFF160A28),
    spaceEnd: Color(0xFF0C0716),
    play: Color(0xFF22E36B),
    blue: Color(0xFF22D3EE),
    purple: Color(0xFFA855F7),
    orange: Color(0xFFFF6B35),
    teal: Color(0xFF2DE1FC),
    gray: Color(0xFF3A3450),
    coin: Color(0xFFFFE600),
    life: Color(0xFFFF3D6E),
    hint: Color(0xFFFFE600),
    gem: Color(0xFF4CC9F0),
    success: Color(0xFF22E36B),
    danger: Color(0xFFFF3D6E),
  ),

  // ── 3. Obsidian — goth ────────────────────────────────────────────────
  AppPalette(
    id: AppThemeId.obsidian,
    nameRo: 'Obsidian',
    nameEn: 'Obsidian',
    texture: ThemeTexture.filigree,
    bg: Color(0xFF0B0B0E),
    bgEnd: Color(0xFF14121A),
    card: Color(0xFF17151D),
    spaceMid: Color(0xFF120F18),
    spaceEnd: Color(0xFF0A090D),
    play: Color(0xFF6B8F71),
    blue: Color(0xFF5B6C8F),
    purple: Color(0xFF7A4E8C),
    orange: Color(0xFF9C5C4B),
    teal: Color(0xFF4E6E6A),
    gray: Color(0xFF44424C),
    coin: Color(0xFFC9A24A),
    life: Color(0xFF8E2C3B),
    hint: Color(0xFFC9A24A),
    gem: Color(0xFF6D7B8F),
    success: Color(0xFF6B8F71),
    danger: Color(0xFFA23545),
  ),

  // ── 4. Paper — luminoasă, simplă ──────────────────────────────────────
  AppPalette(
    id: AppThemeId.paper,
    nameRo: 'Paper',
    nameEn: 'Paper',
    texture: ThemeTexture.dotGrid,
    isLight: true,
    bg: Color(0xFFF4EFE4),
    bgEnd: Color(0xFFECE4D2),
    card: Color(0xFFFBF7EE),
    spaceMid: Color(0xFFEFE8D8),
    spaceEnd: Color(0xFFE7DECB),
    play: Color(0xFF4E7D5B),
    blue: Color(0xFF4B6B8A),
    purple: Color(0xFF6E5B8E),
    orange: Color(0xFFB4703F),
    teal: Color(0xFF3E7C74),
    gray: Color(0xFF8A8272),
    coin: Color(0xFFC99A2E),
    life: Color(0xFFB24A46),
    hint: Color(0xFFC99A2E),
    gem: Color(0xFF5E86A0),
    success: Color(0xFF4E7D5B),
    danger: Color(0xFFB24A46),
  ),

  // ── 5. Aurora Tundra — rece ───────────────────────────────────────────
  AppPalette(
    id: AppThemeId.aurora,
    nameRo: 'Aurora',
    nameEn: 'Aurora',
    texture: ThemeTexture.aurora,
    bg: Color(0xFF06121A),
    bgEnd: Color(0xFF0A2224),
    card: Color(0xFF0E2A2C),
    spaceMid: Color(0xFF0A2130),
    spaceEnd: Color(0xFF07131F),
    play: Color(0xFF5EEAD4),
    blue: Color(0xFF7DD3FC),
    purple: Color(0xFFA5B4FC),
    orange: Color(0xFFFCD34D),
    teal: Color(0xFF34D399),
    gray: Color(0xFF3B5155),
    coin: Color(0xFFFCD34D),
    life: Color(0xFFFB7185),
    hint: Color(0xFFFDE68A),
    gem: Color(0xFF7DD3FC),
    success: Color(0xFF34D399),
    danger: Color(0xFFFB7185),
  ),

  // ── 6. Ember Dusk — cald ──────────────────────────────────────────────
  AppPalette(
    id: AppThemeId.ember,
    nameRo: 'Ember Dusk',
    nameEn: 'Ember Dusk',
    texture: ThemeTexture.embers,
    bg: Color(0xFF1A0E14),
    bgEnd: Color(0xFF2A1420),
    card: Color(0xFF2E1622),
    spaceMid: Color(0xFF241320),
    spaceEnd: Color(0xFF150A11),
    play: Color(0xFF9CCB7A),
    blue: Color(0xFF5FA8C9),
    purple: Color(0xFFC77DA8),
    orange: Color(0xFFF0894E),
    teal: Color(0xFFE8A05B),
    gray: Color(0xFF5A4550),
    coin: Color(0xFFFFC24B),
    life: Color(0xFFE7594C),
    hint: Color(0xFFFFC24B),
    gem: Color(0xFF7BB8C9),
    success: Color(0xFF9CCB7A),
    danger: Color(0xFFE7594C),
  ),
];

AppPalette _paletteFor(AppThemeId id) =>
    kAppPalettes.firstWhere((p) => p.id == id, orElse: () => kAppPalettes.first);

/// Starea globală a temei. La fel ca [EcoMode.enabled] / [L10n.language]:
/// un [ValueNotifier] pe care `main.dart` îl ascultă ca să reconstruiască
/// `MaterialApp`.
class AppTheme {
  AppTheme._();

  static final ValueNotifier<AppThemeId> id =
      ValueNotifier<AppThemeId>(AppThemeId.splasshy);

  /// Paleta activă — [AppColors] citește totul de aici.
  static AppPalette get palette => _paletteFor(id.value);

  /// O singură citire din SharedPreferences, înainte de `runApp`.
  static Future<void> load() async {
    final saved = await StorageService.getAppThemeId();
    if (saved != null) {
      id.value = AppThemeId.values.firstWhere(
        (t) => t.name == saved,
        orElse: () => AppThemeId.splasshy,
      );
    }
  }

  static Future<void> set(AppThemeId next) async {
    if (id.value == next) return;
    id.value = next;
    await StorageService.setAppThemeId(next.name);
  }
}
