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
///
/// Accentele sunt intenționat SATURATE — un joc, nu o aplicație de birou.
/// Fundalurile rămân închise (sau crem, la Paper), dar butoanele/cardurile
/// trebuie să „sară" din ecran. Excepția e Paper, unde accentele sunt mate
/// prin definiție (cerneală pe hârtie).
const List<AppPalette> kAppPalettes = [
  // ── 1. Splasshy — cerneală în apă, acvamarin electric ──────────────────
  AppPalette(
    id: AppThemeId.splasshy,
    nameRo: 'Splasshy',
    nameEn: 'Splasshy',
    texture: ThemeTexture.blobs,
    bg: Color(0xFF04141F),
    bgEnd: Color(0xFF0A3346),
    card: Color(0xFF10394D),
    spaceMid: Color(0xFF072C46),
    spaceEnd: Color(0xFF061A30),
    play: Color(0xFF12E9B0),
    blue: Color(0xFF29B6FF),
    purple: Color(0xFFF02BD8),
    orange: Color(0xFFFF5C7A),
    teal: Color(0xFF1EE6FF),
    gray: Color(0xFF3E5566),
    coin: Color(0xFFFFE23D),
    life: Color(0xFFFF5C7A),
    hint: Color(0xFFFFE23D),
    gem: Color(0xFF5EF0FF),
    success: Color(0xFF12E9B0),
    danger: Color(0xFFFF556A),
  ),

  // ── 2. Neon Arcade — negru + neon crud ────────────────────────────────
  AppPalette(
    id: AppThemeId.neon,
    nameRo: 'Neon Arcade',
    nameEn: 'Neon Arcade',
    texture: ThemeTexture.scanlines,
    bg: Color(0xFF08060F),
    bgEnd: Color(0xFF140528),
    card: Color(0xFF231041),
    spaceMid: Color(0xFF1A0736),
    spaceEnd: Color(0xFF0A0518),
    play: Color(0xFF1FFF7A),
    blue: Color(0xFF12E6FF),
    purple: Color(0xFFC63BFF),
    orange: Color(0xFFFF6A1F),
    teal: Color(0xFF23F0FF),
    gray: Color(0xFF3A3450),
    coin: Color(0xFFFFE800),
    life: Color(0xFFFF2D6E),
    hint: Color(0xFFFFE800),
    gem: Color(0xFF3FD8FF),
    success: Color(0xFF1FFF7A),
    danger: Color(0xFFFF2D6E),
  ),

  // ── 3. Obsidian — goth: void purpuriu, ametist + sânge ────────────────
  AppPalette(
    id: AppThemeId.obsidian,
    nameRo: 'Obsidian',
    nameEn: 'Obsidian',
    texture: ThemeTexture.filigree,
    bg: Color(0xFF0A0810),
    bgEnd: Color(0xFF15111F),
    card: Color(0xFF1C1626),
    spaceMid: Color(0xFF130F1D),
    spaceEnd: Color(0xFF08070C),
    play: Color(0xFF3FBE7E),
    blue: Color(0xFF6E7BE0),
    purple: Color(0xFFB24BE6),
    orange: Color(0xFFCF6A3E),
    teal: Color(0xFF3FA69B),
    gray: Color(0xFF44424C),
    coin: Color(0xFFE0AE3C),
    life: Color(0xFFD22B48),
    hint: Color(0xFFE0AE3C),
    gem: Color(0xFF8E97D6),
    success: Color(0xFF3FBE7E),
    danger: Color(0xFFD22B48),
  ),

  // ── 4. Paper — luminoasă, cerneală mată pe hârtie ─────────────────────
  AppPalette(
    id: AppThemeId.paper,
    nameRo: 'Paper',
    nameEn: 'Paper',
    texture: ThemeTexture.dotGrid,
    isLight: true,
    bg: Color(0xFFF3EDDF),
    bgEnd: Color(0xFFE9E0CC),
    card: Color(0xFFFCF8EF),
    spaceMid: Color(0xFFEEE6D4),
    spaceEnd: Color(0xFFE4DAC4),
    play: Color(0xFF35774A),
    blue: Color(0xFF345C86),
    purple: Color(0xFF614493),
    orange: Color(0xFFC0611F),
    teal: Color(0xFF227168),
    gray: Color(0xFF8A8272),
    coin: Color(0xFFBE8410),
    life: Color(0xFFB1332E),
    hint: Color(0xFFBE8410),
    gem: Color(0xFF3C6E8C),
    success: Color(0xFF35774A),
    danger: Color(0xFFB1332E),
  ),

  // ── 5. Aurora — rece, boreală ────────────────────────────────────────
  AppPalette(
    id: AppThemeId.aurora,
    nameRo: 'Aurora',
    nameEn: 'Aurora',
    texture: ThemeTexture.aurora,
    bg: Color(0xFF04130F),
    bgEnd: Color(0xFF07271F),
    card: Color(0xFF0C302B),
    spaceMid: Color(0xFF07271E),
    spaceEnd: Color(0xFF041712),
    play: Color(0xFF34F0C0),
    blue: Color(0xFF56C6FF),
    purple: Color(0xFF9AA6FF),
    orange: Color(0xFFFFD23D),
    teal: Color(0xFF1FE79A),
    gray: Color(0xFF3B5155),
    coin: Color(0xFFFFD23D),
    life: Color(0xFFFF6A82),
    hint: Color(0xFFFFE07A),
    gem: Color(0xFF56C6FF),
    success: Color(0xFF1FE79A),
    danger: Color(0xFFFF6A82),
  ),

  // ── 6. Ember Dusk — cald, apus ───────────────────────────────────────
  AppPalette(
    id: AppThemeId.ember,
    nameRo: 'Ember Dusk',
    nameEn: 'Ember Dusk',
    texture: ThemeTexture.embers,
    bg: Color(0xFF190A10),
    bgEnd: Color(0xFF321324),
    card: Color(0xFF3A1A28),
    spaceMid: Color(0xFF2A1220),
    spaceEnd: Color(0xFF14080E),
    play: Color(0xFFA6D86A),
    blue: Color(0xFF4FAACE),
    purple: Color(0xFFE07AAE),
    orange: Color(0xFFFF7A3C),
    teal: Color(0xFFF0954A),
    gray: Color(0xFF5A4550),
    coin: Color(0xFFFFB627),
    life: Color(0xFFF04E3C),
    hint: Color(0xFFFFB627),
    gem: Color(0xFF66C6DB),
    success: Color(0xFFA6D86A),
    danger: Color(0xFFF04E3C),
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
