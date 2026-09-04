import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/breadcrumbs.dart';
import 'multiplayer_service.dart';

// ─── „Trimite raport": raportul îl scrie SISTEMUL, nu jucătorul ───────────
//
// Cerință explicită a userului (2026-09-04): „sistemul va spune reportul, nu
// userul. User nu are cum să știe ce problemă este, doar să îi pice jocul și
// să trimită."
//
// Deci jucătorul apasă UN buton. Tot ce urmează se compune singur:
//   ÎNAINTE — firimiturile (vezi core/breadcrumbs.dart): ce ecrane, ce
//             acțiuni, ce cereri au picat, cu timpi relativi la pornire;
//   ÎN TIMPUL — eroarea și stiva de apeluri;
//   DUPĂ — firimiturile continuă să curgă până la apăsarea butonului, deci
//          raportul conține și ce a încercat omul ca să scape. De acolo se
//          vede diferența dintre o eroare izolată și o fundătură.
//
// DE CE EXISTĂ, pe lângă Crashlytics: Crashlytics nu are web, iar azi
// jucătorii sunt în browser. În plus, el prinde doar ce crapă — nu și
// „butonul nu face nimic", care e la fel de rupt pentru cel care joacă.
//
// CE NU SE TRIMITE: nimic scris de jucător, niciun nume, niciun mesaj. Doar
// uid-ul (pe care adminul îl are oricum), versiunea, platforma și urma
// tehnică.

class BugReportService {
  BugReportService._();
  static final BugReportService instance = BugReportService._();

  final _db = FirebaseFirestore.instance;

  /// Rapoartele care n-au putut pleca (fără net) așteaptă aici și se trimit
  /// la următoarea pornire. Nu e un moft: erorile apar cel mai des exact
  /// când conexiunea e proastă, deci fără coadă am pierde tocmai rapoartele
  /// care contează.
  static const _codaKey = 'bug_reports_pending';

  /// Câte rapoarte ținem în coadă. Peste atât, cele vechi se aruncă —
  /// altfel un telefon fără net luni de zile ar umple stocarea locală.
  static const _maxQueue = 10;

  /// Compune raportul din starea curentă. [eroare] și [stiva] lipsesc când
  /// omul raportează manual ceva care nu a crăpat.
  Future<Map<String, dynamic>> build({
    Object? error,
    StackTrace? stack,
    String? screen,
  }) async {
    String version = '?';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Fără versiune raportul e mai sărac, dar tot util — nu renunțăm la el.
    }
    return {
      'uid': MultiplayerService.instance.currentPlayerId,
      'versiune': version,
      'platforma': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'ecran': screen ?? '?',
      'eroare': error?.toString() ?? '',
      // Stiva e taiată: documentele Firestore au limită de 1 MB, iar primele
      // linii sunt oricum cele care spun ceva.
      'stiva': stack?.toString().split('\n').take(30).join('\n') ?? '',
      'firimituri': Breadcrumbs.snapshot(),
      'trimisLa': FieldValue.serverTimestamp(),
      'rezolvat': false,
    };
  }

  /// Trimite raportul. Dacă nu reușește, îl pune în coadă și întoarce `true`
  /// oricum — pentru jucător treaba e făcută, iar minciuna ar fi să-i arătăm
  /// o eroare peste eroarea pe care tocmai o raporta.
  Future<bool> send(Map<String, dynamic> report) async {
    try {
      await _db.collection('bug_reports').add(report);
      return true;
    } catch (e) {
      debugPrint('BugReportService.send a esuat, pun in coada: $e');
      await _enqueue(report);
      return true;
    }
  }

  Future<void> _enqueue(Map<String, dynamic> report) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_codaKey) ?? <String>[];
      // `trimisLa` e un FieldValue, care nu se poate serializa — la trimiterea
      // din coadă se pune oricum unul nou, deci îl scoatem aici.
      final copy = Map<String, dynamic>.from(report)..remove('trimisLa');
      queue.add(jsonEncode(copy));
      while (queue.length > _maxQueue) {
        queue.removeAt(0);
      }
      await prefs.setStringList(_codaKey, queue);
    } catch (e) {
      debugPrint('BugReportService._enqueue a esuat: $e');
    }
  }

  /// Se apelează la pornire. Golește coada, câte unul; ce nu reușește rămâne
  /// pentru data viitoare.
  Future<void> flushQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_codaKey) ?? <String>[];
      if (queue.isEmpty) return;
      final left = <String>[];
      for (final line in queue) {
        try {
          final report = Map<String, dynamic>.from(
              jsonDecode(line) as Map<String, dynamic>);
          report['trimisLa'] = FieldValue.serverTimestamp();
          report['dinCoada'] = true;
          await _db.collection('bug_reports').add(report);
        } catch (_) {
          left.add(line);
        }
      }
      await prefs.setStringList(_codaKey, left);
      if (left.length < queue.length) {
        debugPrint('Trimise ${queue.length - left.length} rapoarte din coada.');
      }
    } catch (e) {
      debugPrint('BugReportService.flushQueue a esuat: $e');
    }
  }
}
