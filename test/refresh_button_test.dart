import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/widgets/refresh_button.dart';

void main() {
  Widget host(Future<void> Function() onRefresh) =>
      MaterialApp(home: Scaffold(body: Center(child: RefreshButton(onRefresh: onRefresh))));

  testWidgets('reușita confirmă scurt', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(() async => calls++));
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();
    expect(calls, 1);
    expect(find.textContaining('✓'), findsOneWidget);
  });

  testWidgets('refuzul serverului arată motivul real, nu „verifică internetul"', (tester) async {
    await tester.pumpWidget(host(() async =>
        throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')));
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();
    expect(find.textContaining('App Check'), findsOneWidget);
  });
}
