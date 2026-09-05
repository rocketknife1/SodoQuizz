import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/widgets/cosmetic_title.dart';

void main() {
  testWidgets('titlul novice nu afiseaza nimic', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: CosmeticTitle(titleId: 'novice')),
    ));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('un titlu real se afiseaza', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: CosmeticTitle(titleId: 'veteran')),
    ));
    expect(find.text('Veteran'), findsOneWidget);
  });

  testWidgets('id necunoscut -> nimic (cade pe novice)', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: CosmeticTitle(titleId: 'inventat')),
    ));
    expect(find.byType(Text), findsNothing);
  });
}
