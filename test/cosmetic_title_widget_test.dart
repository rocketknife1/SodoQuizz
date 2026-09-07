import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/widgets/cosmetic_title.dart';

void main() {
  testWidgets('titlul novice arata „Boboc" (progresia trebuie sa se vada)', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: CosmeticTitle(titleId: 'novice')),
    ));
    expect(find.text('Boboc'), findsOneWidget);
  });

  testWidgets('un titlu real se afiseaza', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: CosmeticTitle(titleId: 'explorator')),
    ));
    expect(find.text('Le-a Făcut Pe Toate'), findsOneWidget);
  });

  testWidgets('id necunoscut -> cade pe novice („Boboc")', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: CosmeticTitle(titleId: 'inventat')),
    ));
    expect(find.text('Boboc'), findsOneWidget);
  });
}
