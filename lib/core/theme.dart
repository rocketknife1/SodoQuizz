import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Poza de profil a jucătorului, folosită în hero-ul de pe home screen
/// și în avatarele din header/Profile.
const String userAvatarAsset = 'assets/branding/avatar.png';

/// Paleta comună a aplicației. **Nu mai ține culori `const`** — fiecare slot
/// citește din tema activă (core/app_theme.dart `AppTheme.palette`), aleasă
/// de jucător din Setări → Temă. Cele ~700 de locuri care scriu
/// `AppColors.bg` etc. au rămas neatinse: sunt acum accesări de getter.
///
/// Consecința: `AppColors.x` nu se mai poate folosi în context `const`
/// (`const Icon(color: AppColors.play)` → fără `const`). E prețul unei
/// singure surse de culori care chiar se poate schimba la runtime.
class AppColors {
  const AppColors._();

  static AppPalette get _p => AppTheme.palette;

  /// `true` pe tema luminoasă (Paper) — pentru puținele ecrane care aleg o
  /// nuanță de text în funcție de cât de deschis e fundalul.
  static bool get isLight => _p.isLight;

  static Color get bg => _p.bg;
  static Color get bgEnd => _p.bgEnd;
  static Color get card => _p.card;

  static Color get play => _p.play;
  static Color get blue => _p.blue;
  static Color get purple => _p.purple;
  static Color get orange => _p.orange;
  static Color get teal => _p.teal;
  static Color get gray => _p.gray;

  static Color get coin => _p.coin;
  static Color get life => _p.life;
  static Color get hint => _p.hint;
  static Color get gem => _p.gem;
  static Color get success => _p.success;
  static Color get danger => _p.danger;

  static LinearGradient get bgGradient => _p.bgGradient;

  /// Fundal "spațial" — folosit în spatele meniului principal și al
  /// ecranului de categorii (tema de "planete").
  static LinearGradient get spaceGradient => _p.spaceGradient;
}
