import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/theme.dart';
import 'package:guess_it/widgets/solid_menu_button.dart';

/// `badge` era desenat DOAR pe varianta fără subtitlu. Orice apelant care
/// trece `subtitle` (fie și gol, cum face butonul SETĂRI din meniul principal)
/// cădea pe varianta card, unde insigna era ignorată TĂCUT: parametrul se
/// accepta, dar pe ecran nu apărea nimic.
///
/// Nu se vedea nici la `flutter analyze`, nici în restul testelor — doar cu
/// ochii, pe dispozitiv. De-aia există testul ăsta: un parametru acceptat
/// trebuie să aibă efect în ORICE variantă a widget-ului.
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          backgroundColor: AppColors.bg,
          body: SizedBox(width: 200, child: child),
        ),
      );

  testWidgets('insigna apare pe varianta CARD (cu subtitlu, fie el si gol)', (tester) async {
    await tester.pumpWidget(host(SolidMenuButton(
      icon: Icons.settings_rounded,
      label: 'SETARI',
      subtitle: '',
      color: AppColors.gray,
      badge: '1 nou',
      onTap: () {},
    )));
    expect(find.text('1 nou'), findsOneWidget);
  });

  testWidgets('insigna apare si pe varianta cu subtitlu nevid', (tester) async {
    await tester.pumpWidget(host(SolidMenuButton(
      icon: Icons.settings_rounded,
      label: 'SETARI',
      subtitle: 'ceva',
      color: AppColors.gray,
      badge: '3',
      onTap: () {},
    )));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('ceva'), findsOneWidget);
  });

  testWidgets('insigna apare pe varianta FARA subtitlu (cazul care mergea deja)', (tester) async {
    await tester.pumpWidget(host(SolidMenuButton(
      icon: Icons.settings_rounded,
      label: 'SETARI',
      color: AppColors.gray,
      badge: '2',
      onTap: () {},
    )));
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('fara badge nu apare nimic in plus', (tester) async {
    await tester.pumpWidget(host(SolidMenuButton(
      icon: Icons.settings_rounded,
      label: 'SETARI',
      subtitle: '',
      color: AppColors.gray,
      onTap: () {},
    )));
    expect(find.text('SETARI'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
  });
}
