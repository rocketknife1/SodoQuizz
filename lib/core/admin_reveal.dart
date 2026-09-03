import 'package:flutter/material.dart';

import '../data/auth_service.dart';
import '../data/storage_service.dart';
import 'admin.dart';

/// „Vezi răspunsul corect" — un toggle din tabul Debug, DOAR pentru admin.
///
/// Când e pornit, varianta corectă (dintre A/B/C/D) e conturată cu chihlimbar
/// la ORICE întrebare cu 4 variante: singleplayer, multiplayer, Cultură
/// Generală, Planeta hologramelor. E pur vizual — nu atinge scorul, nu atinge
/// nicio decizie de joc.
///
/// ## Dublu gard
///
/// [adminAnswerRevealOn] cere DOUĂ lucruri simultan: pref-ul pornit ȘI emailul
/// de admin în tokenul de autentificare. Chiar dacă pref-ul ar ajunge cumva
/// `true` pe alt telefon (un backup de cont copiat, o sincronizare), un
/// jucător obișnuit tot nu vede nimic — nu are emailul. De-aia verificarea
/// NU se face doar pe `_flag.value`.
///
/// ## De ce chihlimbar, nu verde
///
/// Verdele e deja „ai răspuns corect" peste tot în joc, roșul e „ai greșit".
/// Chihlimbarul nu se folosește nicăieri la feedback-ul de răspuns, deci
/// marcajul de admin nu se poate confunda cu starea reală a rundei.
final ValueNotifier<bool> adminAnswerReveal = ValueNotifier<bool>(false);

/// Culoarea conturului pus pe varianta corectă cât toggle-ul e pornit.
const Color adminRevealColor = Color(0xFFFFC107);

/// Citește pref-ul la pornirea aplicației. Chemată din `main()`.
Future<void> loadAdminAnswerReveal() async {
  try {
    adminAnswerReveal.value = await StorageService.getAdminAnswerReveal();
  } catch (_) {
    adminAnswerReveal.value = false;
  }
}

/// Pornește/oprește toggle-ul (din tabul Debug). Scrie și pref-ul, și
/// notifier-ul, ca ecranele deschise să reacționeze pe loc.
Future<void> setAdminAnswerReveal(bool value) async {
  adminAnswerReveal.value = value;
  await StorageService.setAdminAnswerReveal(value);
}

/// True doar dacă toggle-ul e pornit ȘI contul curent e cel de admin.
/// Sincron — se poate chema direct în `build`.
bool get adminAnswerRevealOn =>
    adminAnswerReveal.value &&
    AuthService.instance.currentUser?.email == kAdminEmail;
