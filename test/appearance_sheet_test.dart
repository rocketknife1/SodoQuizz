import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:guess_it/core/cosmetics.dart';
import 'package:guess_it/widgets/appearance_sheet.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sheet-ul are 3 file: Avatar, Rama, Titlu', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => ElevatedButton(
          onPressed: () => showAppearanceSheet(ctx,
              level: 30, leaguePoints: 0, achievements: {}),
          child: const Text('deschide'),
        )),
      ),
    ));
    await t.tap(find.text('deschide'));
    await t.pumpAndSettle();
    expect(find.text('Avatar'), findsOneWidget);
    expect(find.text('Ramă'), findsOneWidget);
    expect(find.text('Titlu'), findsOneWidget);
  });

  testWidgets('un item blocat arata cerinta si nu se echipeaza la tap', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (ctx) => ElevatedButton(
          onPressed: () => showAppearanceSheet(ctx,
              level: 1, leaguePoints: 0, achievements: {}),
          child: const Text('deschide'),
        )),
      ),
    ));
    await t.tap(find.text('deschide'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ramă'));
    await t.pumpAndSettle();
    // rama lvl50 e blocata la nivel 1 → cerinta vizibila
    expect(find.text('Nivel 50'), findsOneWidget);
    // tap pe ea nu schimba myFrame
    await loadCosmetics();
    final before = myFrame.value;
    await t.tap(find.text('Nivel 50'));
    await t.pumpAndSettle();
    expect(myFrame.value, before);
  });
}
