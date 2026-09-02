import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/widgets/tank_art.dart';
import 'package:guess_it/widgets/tank_defence.dart';
import 'package:guess_it/widgets/tank_pov.dart';

/// Cele două camere cinematice din Quizz Tanks (camera de pe obuz și camera
/// din spatele propriului tanc) sunt desenate integral din cod, cadru cu
/// cadru, dintr-un singur ceas. Genul de greșeală care apare aici NU e o
/// eroare de compilare, ci un dreptunghi cu înălțime negativă, o rază NaN sau
/// un `reduce` pe o listă goală — adică o excepție care sare abia la o
/// anumită fracțiune de secundă din animație, pe telefon, în mijlocul unei
/// runde.
///
/// De-aia testul de aici nu verifică frumusețea, ci ceva ce ochiul nu poate:
/// că TOATE clipele din interval se desenează fără excepție, în toate
/// variantele de deznodământ (lovitură, fereală, ciocnire de obuze, două
/// obuze deodată).
void main() {
  Future<void> pumpAcross(WidgetTester tester, double end, Widget Function(double t) build) async {
    for (var t = 0.0; t <= end + 0.2; t += 0.05) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: build(t))));
      expect(tester.takeException(), isNull, reason: 'a crăpat la t=$t');
    }
  }

  TankPovView pov(double t, {required bool hit, bool duel = false, bool intercepted = false}) => TankPovView(
        time: t,
        launchAt: 0.6,
        impactAt: intercepted ? 1.25 : 1.9,
        hit: hit,
        damage: hit ? 24 : 0,
        targetColor: Colors.orange,
        targetName: 'Ana',
        targetHp: 68,
        targetDamageRatio: 0.32,
        shooterColor: Colors.cyan,
        duelIncoming: duel,
        duelIntercepted: intercepted,
        damageTaken: duel ? 21 : 0,
      );

  testWidgets('camera de pe obuz: lovitură, fereală și ciocnire în aer', (tester) async {
    for (final variant in [
      (hit: true, duel: false, intercepted: false),
      (hit: false, duel: false, intercepted: false),
      (hit: true, duel: true, intercepted: false),
      (hit: false, duel: true, intercepted: true),
    ]) {
      await pumpAcross(
        tester,
        TankPovView.endAtFor(variant.intercepted ? 1.25 : 1.9),
        (t) => pov(t, hit: variant.hit, duel: variant.duel, intercepted: variant.intercepted),
      );
    }
  });

  testWidgets('camera de apărare: încasare, fereală și două obuze deodată', (tester) async {
    const hitShell = IncomingShell(
      launchAt: 0.6,
      impactAt: 1.9,
      hit: true,
      damage: 27,
      color: Colors.redAccent,
      shooterName: 'Vlad',
      lane: -0.6,
    );
    const missShell = IncomingShell(
      launchAt: 0.82,
      impactAt: 2.12,
      hit: false,
      damage: 0,
      color: Colors.lightGreen,
      shooterName: 'Ana',
      lane: 0.5,
    );
    for (final shells in [
      [hitShell],
      [missShell],
      [missShell, hitShell],
    ]) {
      await pumpAcross(
        tester,
        TankDefenceView.endAtFor(shells),
        (t) => TankDefenceView(time: t, shells: shells, myColor: Colors.cyan, myName: 'Dragoș', myHp: 54),
      );
    }
  });

  testWidgets('arena: obuzele unui duel se opresc la mijloc, nu pe tanc', (tester) async {
    // Cele două trageri ale unui duel pleacă în aceeași clipă și au aceeași
    // durată de zbor — de-aia „la jumătatea drumului" e chiar aceeași clipă
    // pentru amândouă, iar punctul de întâlnire e același punct.
    const a = Offset(60, 100);
    const b = Offset(260, 300);
    const one = ShotFlight(
        from: a, to: b, hit: false, damage: 0, startAt: 0.6, color: Colors.cyan, intercepted: true, meetLead: true);
    const two = ShotFlight(from: b, to: a, hit: false, damage: 0, startAt: 0.6, color: Colors.orange, intercepted: true);

    expect((one.landing - two.landing).distance, lessThan(0.001));
    expect(one.impactAt, two.impactAt);
    // se opresc la jumătatea zborului obișnuit, deci mai devreme decât o
    // lovitură care chiar ajunge la tanc
    expect(one.travelDuration, one.flightDuration * 0.5);

    await pumpAcross(tester, 2.4, (t) {
      return CustomPaint(
        size: const Size(340, 400),
        painter: TankShotsPainter(flights: const [one, two], time: t),
      );
    });
  });

  testWidgets('reflexie: obuzul cotește din reflector și explodează în trăgător', (tester) async {
    const shooter = Offset(60, 300);
    const reflector = Offset(260, 100);
    const f = ShotFlight(
      from: shooter,
      to: reflector,
      hit: true,
      damage: 9,
      startAt: 0.6,
      color: Colors.cyan,
      flightDuration: 2.34,
      reflectBackTo: shooter,
    );

    expect(f.isReflected, isTrue);
    // la jumătatea zborului obuzul e la reflector...
    expect((f.pointAt(ShotFlight.reflectPivot) - reflector).distance, lessThan(0.001));
    // ...iar la capăt s-a întors fix în trăgător
    expect((f.pointAt(1) - shooter).distance, lessThan(0.001));
    // explozia e în trăgător, nu în reflector
    expect(f.landing, shooter);

    await pumpAcross(tester, 3.5, (t) {
      return CustomPaint(
        size: const Size(340, 400),
        painter: TankShotsPainter(flights: const [f], time: t),
      );
    });
  });

  testWidgets('camera trăgătorului la lovitură dublă: ambele ținte, toate combinațiile', (tester) async {
    // Cele patru deznodăminte posibile pe două ținte — camera trebuie să le
    // deseneze pe toate fără excepție, inclusiv cea în care una încasează și
    // cealaltă evită (aici camera NU se poate rostogoli după una din ele).
    for (final a in [true, false]) {
      for (final b in [true, false]) {
        await pumpAcross(tester, TankPovView.endAtFor(1.9), (t) => TankPovView(
              time: t,
              launchAt: 0.6,
              impactAt: 1.9,
              hit: a,
              damage: a ? 11 : 0,
              targetColor: Colors.orange,
              targetName: 'Ana',
              targetHp: 74,
              targetDamageRatio: 0.26,
              shooterColor: Colors.cyan,
              second: TankPovSecondTarget(
                color: Colors.purple,
                name: 'Bogdan',
                damageRatio: 0.4,
                hit: b,
                damage: b ? 9 : 0,
              ),
            ));
      }
    }
  });

  testWidgets('lovitură dublă: obuzul comun se desparte la splitAt spre două ținte', (tester) async {
    const shooter = Offset(50, 350);
    const targetA = Offset(280, 60);
    const targetB = Offset(300, 320);
    const sp = Offset(150, 250); // punctul de despărțire, dat de ecran
    const a = ShotFlight(
        from: shooter, to: targetA, hit: true, damage: 8, startAt: 0.6,
        color: Colors.cyan, splitPoint: sp, splitLead: true);
    const b = ShotFlight(
        from: shooter, to: targetB, hit: true, damage: 9, startAt: 0.6,
        color: Colors.cyan, splitPoint: sp, splitLead: false);

    // înainte de despărțire, amândouă obuzele sunt în același punct (pe drumul
    // comun tun→splitPoint)
    expect((a.pointAt(0.2) - b.pointAt(0.2)).distance, lessThan(0.001));
    // la despărțire sunt fix în splitPoint
    expect((a.pointAt(ShotFlight.splitAt) - sp).distance, lessThan(0.001));
    // după, fiecare ajunge la ținta lui
    expect((a.pointAt(1) - targetA).distance, lessThan(0.001));
    expect((b.pointAt(1) - targetB).distance, lessThan(0.001));

    await pumpAcross(tester, 2.4, (t) {
      return CustomPaint(
        size: const Size(340, 400),
        painter: TankShotsPainter(flights: const [a, b], time: t),
      );
    });
  });
}
