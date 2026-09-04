import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:guess_it/main.dart';
import 'package:guess_it/widgets/mascots/mascot_sync.dart';

/// Ce vede omul imediat după ecranul de încărcare — depinde de un singur
/// lucru: dacă a mai deschis jocul vreodată.
///
/// Cazul „instalare curată" contează cel puțin la fel de mult ca celălalt:
/// tutorialul e singura șansă de a explica jocul cuiva care nu l-a mai văzut,
/// iar dacă nu apare, nu se plânge nimeni — pur și simplu nu se mai întorc.
void main() {
  /// Trece de ecranul de încărcare (1400 ms, vezi main.dart) și lasă câteva
  /// cadre pentru navigare și citirile din SharedPreferences.
  Future<void> pumpPastLoading(WidgetTester tester) async {
    await tester.pumpWidget(const GuessItApp());
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('la instalare curată apare TUTORIALUL, nu meniul',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await pumpPastLoading(tester);

    expect(find.text('Vezi o poză neclară.'), findsOneWidget);
    expect(find.text('Sari peste'), findsOneWidget);
    // Meniul NU trebuie să fie dedesubt — altfel jucătorul nou l-ar vedea
    // pe jumătate și tutorialul și-ar pierde rostul.
    expect(find.text('PLAY'), findsNothing);

    MascotSync.resetForTest();
  });

  testWidgets('după ce l-a văzut o dată, intră direct în meniu',
      (WidgetTester tester) async {
    // Aceeași cheie ca `StorageService._introSeenKey`. Dacă se schimbă acolo,
    // testul ăsta pică — și e bine: altfel tutorialul ar reapărea la fiecare
    // pornire fără ca nimeni să observe.
    SharedPreferences.setMockInitialValues({'intro_seen': true});

    await pumpPastLoading(tester);

    expect(find.text('SODO QUIZZ'), findsAtLeastNWidgets(1));
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    // Mascotele de pe Home pornesc dispecerul global MascotSync, care
    // reprogrameaza singur timere la nesfarsit - fara asta, testul pica la
    // final cu "Timer is still pending" (vezi MascotSync.resetForTest).
    MascotSync.resetForTest();
  });
}
