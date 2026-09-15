import 'package:firebase_core/firebase_core.dart';

import 'lang.dart';

/// Motivul REAL al unei erori de citire, pe înțelesul omului. Înainte orice
/// eșec afișa „Verifică internetul", inclusiv când internetul mergea și
/// serverul refuza accesul — deci nu se putea afla ce era de fapt stricat.
String firestoreErrorText(Object? error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return tr('Serverul a refuzat accesul (cont fără drept sau App Check blochează build-ul instalat de pe PC).',
            'The server denied access (account without permission, or App Check blocking a sideloaded build).');
      case 'unavailable':
      case 'deadline-exceeded':
        return tr('Nu ajung la server. Verifică internetul.', "Can't reach the server. Check your internet.");
      case 'failed-precondition':
        return tr('Lipsește un index în Firestore pentru interogarea asta.', 'A Firestore index is missing for this query.');
    }
    return '${error.code}: ${error.message ?? ''}';
  }
  return error.toString();
}
