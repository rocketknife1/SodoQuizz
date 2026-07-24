import 'package:flutter/material.dart';

/// Poza de profil a jucătorului, folosită în hero-ul de pe home screen
/// și în avatarele din header/Profile.
const String userAvatarAsset = 'assets/branding/avatar.png';

/// Paleta comună a aplicației — carduri solide, saturate, cu umbră,
/// pe fundal navy închis. O singură sursă de culori, ca să nu se
/// împrăștie hexuri hardcodate prin toate ecranele.
class AppColors {
  static const bg = Color(0xFF0B1229);
  static const bgEnd = Color(0xFF141B36);
  static const card = Color(0xFF141B36);

  static const play = Color(0xFF22C55E);
  static const blue = Color(0xFF3B82F6);
  static const purple = Color(0xFF8B5CF6);
  static const orange = Color(0xFFFF7A1A);
  static const teal = Color(0xFF2EC4B6);
  static const gray = Color(0xFF4B5563);

  static const coin = Color(0xFFFFD700);
  static const life = Color(0xFFE24B4A);
  static const success = Color(0xFF1D9E75);
  static const danger = Color(0xFFE24B4A);

  static const bgGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bg, bgEnd],
  );

  /// Fundal "spațial" — navy închis spre violet adânc — folosit în spatele
  /// meniului principal și al ecranului de categorii (tema de "planete").
  static const spaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bg, Color(0xFF1B1140), Color(0xFF120B2E)],
  );
}
