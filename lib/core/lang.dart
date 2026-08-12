import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import '../data/storage_service.dart';

enum AppLanguage {
  ro('ro', 'Română', '🇷🇴'),
  en('en', 'English', '🇬🇧');

  const AppLanguage(this.code, this.label, this.flag);
  final String code;
  final String label;
  final String flag;

  static AppLanguage fromCode(String code) =>
      AppLanguage.values.firstWhere((l) => l.code == code, orElse: () => AppLanguage.ro);
}

/// Limba interfeței. Jocul a fost scris integral în română; engleza a fost
/// adăugată ca să poată fi jucat și de cineva din afara țării.
///
/// CUM SE TRADUCE, ȘI DE CE AȘA: nu există fișiere de traduceri cu chei
/// (`t('settings.title')`), ci funcția [tr], care primește direct ambele
/// variante — `tr('Setări', 'Settings')`. Motivul e practic: textul românesc
/// rămâne vizibil exact acolo unde e folosit, deci nimeni nu trebuie să sară
/// într-un fișier separat ca să vadă ce scrie pe un buton, iar o traducere
/// nu poate rămâne „orfană" după ce textul original se schimbă. Cu ~600 de
/// texte într-o singură limbă-sursă, tabelul de chei ar fi adus doar
/// bookkeeping.
///
/// CE NU E TRADUS, deliberat: conținutul de joc — întrebările și răspunsurile
/// din poze, Cultura Generală, Higher or Lower, catalogul de quest-uri. Alea
/// sunt date, nu interfață, și sunt scrise în română. Un jucător străin
/// navighează perfect prin joc, dar întrebările îi apar tot în română — vezi
/// [contentLanguageNotice], avertismentul arătat la alegerea englezei, ca
/// asta să nu fie o surpriză.
///
/// Panoul de Admin rămâne în română: îl vede un singur cont (vezi
/// admin_screen.dart), al proprietarului jocului.
class L10n {
  L10n._();

  static final ValueNotifier<AppLanguage> language = ValueNotifier<AppLanguage>(AppLanguage.ro);

  static AppLanguage get current => language.value;
  static bool get isEn => language.value == AppLanguage.en;

  /// Chemat înainte de `runApp`, ca primul cadru să fie deja în limba bună.
  ///
  /// Dacă jucătorul n-a ales niciodată explicit o limbă, se ia limba
  /// telefonului: cineva care instalează jocul pe un telefon în engleză îl
  /// vrea aproape sigur în engleză, nu într-o limbă pe care n-o citește. Orice
  /// altă limbă decât româna cade tot pe engleză — sunt singurele două
  /// existente, iar engleza e alegerea sigură pentru un necunoscut.
  static Future<void> load() async {
    final saved = await StorageService.getLanguageCode();
    if (saved.isNotEmpty) {
      language.value = AppLanguage.fromCode(saved);
      return;
    }
    final systemCode = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    language.value = systemCode == 'ro' ? AppLanguage.ro : AppLanguage.en;
  }

  static Future<void> setLanguage(AppLanguage value) async {
    language.value = value;
    await StorageService.setLanguageCode(value.code);
  }

  /// Textul arătat la trecerea pe engleză — vezi nota din capul clasei.
  static String get contentLanguageNotice =>
      'The menus, buttons and multiplayer are in English. The quiz questions '
      'themselves (picture answers, General Knowledge, Higher or Lower) are '
      'still written in Romanian.';
}

/// Alege varianta potrivită limbii curente. Vezi [L10n] pentru de ce
/// traducerile stau în linie, nu într-un fișier de chei.
String tr(String ro, String en) => L10n.isEn ? en : ro;
