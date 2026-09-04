import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

// ─── O singură ușă prin care ies erorile din aplicație ────────────────────
//
// DE CE EXISTĂ: proiectul are ~168 de locuri scrise ca
//   `try { ... } catch (e) { debugPrint('X a esuat: $e'); }`
// Fiecare e un loc unde ceva se poate strica la un jucător real, iar mesajul
// se duce în consola unui telefon pe care nu-l vede nimeni. Tiparul ăsta a
// produs în aceeași zi (2026-09-04) patru bug-uri invizibile: spinner infinit
// la o eroare de stream, o Cloud Function oarbă pe viață, un parametru de UI
// ignorat tăcut și verbul DELETE pierdut din reguli timp de trei săptămâni.
//
// [reportError] NU înlocuiește `debugPrint` — îl completează. Local vezi la
// fel ca înainte; în plus, pe telefoanele reale eroarea ajunge în Crashlytics.
//
// UNDE NU MERGE: Crashlytics suportă doar Android/iOS/macOS, nu web
// (pub.dev/packages/firebase_crashlytics). Pe web apelul iese tăcut, fără să
// arunce — jucătorii din browser sunt acoperiți de raportul trimis din
// aplicație (vezi ecranul de eroare), nu de aici.
//
// NU se pune în toate cele 168 de locuri. Doar acolo unde eșecul chiar
// contează: salvarea în cloud, identitatea, scrierile de profil și de meci.
// Restul sunt zgomot — un `catch` pe redarea unui sunet nu merită o cerere de
// rețea.

/// Trimite o eroare NEFATALĂ (aplicația merge mai departe) către Crashlytics.
///
/// [unde] e eticheta după care o cauți în consolă: pune numele metodei, nu o
/// propoziție — „CloudSyncService.push", nu „nu s-a putut salva".
///
/// Nu aruncă niciodată: un raport de eroare care strică aplicația ar fi o
/// glumă proastă.
void reportError(Object error, StackTrace? stack, {required String unde}) {
  debugPrint('$unde a esuat: $error');
  if (kIsWeb) return;
  try {
    FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: unde,
      fatal: false,
    );
  } catch (_) {
    // Crashlytics neinițializat (teste, pornire fără Firebase) — nu are ce
    // strica, mesajul a ajuns deja în debugPrint mai sus.
  }
}
