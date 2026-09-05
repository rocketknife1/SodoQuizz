import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/cosmetics.dart';
import 'package:guess_it/widgets/avatar.dart';

void main() {
  testWidgets('Avatar cu frame.none nu adauga niciun strat vizibil', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: Avatar(size: 44, label: 'A', frame: Frame.none)),
    ));
    expect(t.takeException(), isNull);
  });

  testWidgets('Avatar cu frame.gold se construieste fara eroare', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: Avatar(size: 44, label: 'A', frame: Frame.gold)),
    ));
    expect(t.takeException(), isNull);
    // inelul e un Container cu decoratie circulara in plus fata de none
    expect(find.byType(Container), findsWidgets);
  });

  testWidgets('frame.lvl50 (gradient) nu arunca', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: Avatar(size: 44, label: 'A', frame: Frame.lvl50)),
    ));
    expect(t.takeException(), isNull);
  });

  testWidgets('MyAvatar se construieste fara eroare', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: MyAvatar(size: 44)),
    ));
    expect(t.takeException(), isNull);
  });
}
