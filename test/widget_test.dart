// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:guess_it/main.dart';
import 'package:guess_it/widgets/mascots/mascot_sync.dart';

void main() {
  testWidgets('SodoQuizz app loads home screen', (WidgetTester tester) async {
    // Marcheaza intro tutorial-ul ca deja vazut - testul verifica doar ca
    // ecranul de Acasa se incarca, nu fluxul separat al popup-ului de
    // introducere (vezi IntroTutorialDialog.maybeShow, aratat automat la
    // prima intrare daca acest flag nu e setat).
    SharedPreferences.setMockInitialValues({'intro_tutorial_seen': true});

    await tester.pumpWidget(const GuessItApp());
    // LoadingScreen initial tine 1400ms inainte sa treaca la HomeScreen
    // (vezi main.dart) - depasim acel prag, apoi mai lasam cateva cadre sa
    // se aseze navigarea si incarcarea datelor din HomeScreen.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('SODO QUIZZ'), findsAtLeastNWidgets(1));
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    // Mascotele de pe Home pornesc dispecerul global MascotSync, care
    // reprogrameaza singur timere la nesfarsit - fara asta, testul pica la
    // final cu "Timer is still pending" (vezi MascotSync.resetForTest).
    MascotSync.resetForTest();
  });
}
