import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/tanks.dart';
import 'package:guess_it/widgets/tank_pov.dart';

ResolvedTankShot shot(String by, String at, {bool hit = true, int dmg = 10}) =>
    ResolvedTankShot(byId: by, atId: at, hit: hit, damage: hit ? dmg : 0);

/// Programul fazei de foc se calculează separat pe fiecare telefon, din
/// aceleași trageri. Dacă ar depinde de ordinea în care sosesc datele sau de
/// ceva local, doi jucători ar vedea scene diferite în același meci.
void main() {
  test('fără trageri: faza scurtă, fără scene', () {
    final p = buildTankAttackPlan(shots: const []);
    expect(p.units, isEmpty);
    expect(p.revealSeconds, tanksEmptyRevealSeconds);
  });

  test('3 tancuri pe aceeași țintă = un bombardament, toți 4 văd aceeași scenă', () {
    final shots = [shot('b', 'a'), shot('c', 'a', hit: false), shot('d', 'a')];
    final p = buildTankAttackPlan(shots: shots);
    expect(p.units, hasLength(1));
    final u = p.units.single;
    expect(u.kind, TankUnitKind.salvo);
    expect(u.targetId, 'a');
    expect(u.participants, {'a', 'b', 'c', 'd'});
    // obuzele pleacă decalat, ca să se vadă fiecare
    final launches = [for (var i = 0; i < 3; i++) p.timings[i]!.launchAt];
    expect(launches[0] < launches[1] && launches[1] < launches[2], isTrue);
    for (final id in ['a', 'b', 'c', 'd']) {
      expect(p.activeUnitFor(id, u.startAt + 0.1), same(u));
    }
  });

  test('bombardament + un 1 la 1 separat rulează în paralel', () {
    // b,c,d → a ; e → f  (nimeni comun)
    final shots = [shot('b', 'a'), shot('c', 'a'), shot('d', 'a'), shot('e', 'f')];
    final p = buildTankAttackPlan(shots: shots);
    expect(p.units, hasLength(2));
    expect(p.units.map((u) => u.slot).toSet(), {0});
    final single = p.units.firstWhere((u) => u.kind == TankUnitKind.single);
    expect(single.participants, {'e', 'f'});
  });

  test('rol dublu: ținta unui bombardament care trage și ea — scene pe rând', () {
    // c,d → a (bombardament) ; a → b (1 la 1). `a` e în amândouă.
    final shots = [shot('a', 'b'), shot('c', 'a'), shot('d', 'a')];
    final p = buildTankAttackPlan(shots: shots);
    final salvo = p.units.firstWhere((u) => u.kind == TankUnitKind.salvo);
    final single = p.units.firstWhere((u) => u.kind == TankUnitKind.single);
    expect(salvo.slot, 0, reason: 'bombardamentul întâi');
    expect(single.slot, 1);
    expect(single.startAt, greaterThanOrEqualTo(salvo.endAt));
    expect(p.activeUnitFor('a', salvo.startAt + 0.1), same(salvo));
    expect(p.activeUnitFor('a', single.startAt + 0.1), same(single));
  });

  test('duel: A în B și B în A devin o singură scenă', () {
    final p = buildTankAttackPlan(shots: [shot('a', 'b', hit: false), shot('b', 'a', hit: false)]);
    expect(p.units, hasLength(1));
    expect(p.units.single.kind, TankUnitKind.duel);
    expect(p.timings[0]!.launchAt, p.timings[1]!.launchAt, reason: 'pleacă în aceeași clipă');
  });

  test('reflexia rămâne o singură scenă, cu zbor mai lung', () {
    // a trage în r (Reflexie): scris ca r→a lovește + a→r ratată
    final shots = [shot('r', 'a'), shot('a', 'r', hit: false)];
    final p = buildTankAttackPlan(shots: shots, reflectorIds: {'r'});
    expect(p.units, hasLength(1));
    expect(p.reflectBackOf, {1: 0});
    final t = p.timings[1]!;
    expect(t.impactAt - t.launchAt, closeTo(tanksFlightSeconds * tanksReflectFlightFactor, 1e-9));
    expect(p.timings[0], same(t));
  });

  test('lovitură dublă pe două ținte neatacate de alții = obuz care se desparte', () {
    final p = buildTankAttackPlan(shots: [shot('a', 'b'), shot('a', 'c')], doubleShotIds: {'a'});
    expect(p.units, hasLength(1));
    expect(p.units.single.kind, TankUnitKind.split);
    expect(p.units.single.participants, {'a', 'b', 'c'});
  });

  test('niciun jucător nu e în două scene care rulează deodată', () {
    // masă de 8 cu focusuri încrucișate
    final shots = [
      shot('a', 'h'), shot('b', 'h'), shot('c', 'a'), shot('d', 'a'),
      shot('e', 'c'), shot('f', 'g'), shot('g', 'f'), shot('h', 'b'),
    ];
    final p = buildTankAttackPlan(shots: shots);
    for (final x in p.units) {
      for (final y in p.units) {
        if (identical(x, y) || x.slot != y.slot) continue;
        expect(x.participants.intersection(y.participants), isEmpty);
      }
    }
    // fiecare tragere are un moment, în interiorul scenei ei
    for (var i = 0; i < shots.length; i++) {
      final t = p.timings[i]!;
      final u = p.units[t.unitIndex];
      expect(t.launchAt, greaterThanOrEqualTo(u.startAt));
      expect(t.impactAt, lessThan(u.endAt));
    }
  });

  test('determinist: aceeași rundă dă exact același program', () {
    final shots = [shot('b', 'a'), shot('c', 'a'), shot('a', 'd'), shot('e', 'd')];
    final p1 = buildTankAttackPlan(shots: shots);
    final p2 = buildTankAttackPlan(shots: List.of(shots));
    expect(p1.revealSeconds, p2.revealSeconds);
    for (var i = 0; i < shots.length; i++) {
      expect(p1.timings[i]!.launchAt, p2.timings[i]!.launchAt);
    }
  });

  test('durata: o scenă e mai scurtă decât vechile 9 secunde, două rămân rezonabile', () {
    final one = buildTankAttackPlan(shots: [shot('b', 'a'), shot('c', 'a')]);
    expect(one.revealSeconds, lessThan(9));
    final two = buildTankAttackPlan(shots: [shot('a', 'b'), shot('c', 'a'), shot('d', 'a')]);
    expect(two.revealSeconds, inInclusiveRange(9, 13));
  });

  test('bara scade după scena în care ai fost lovit', () {
    final shots = [shot('a', 'b'), shot('c', 'a'), shot('d', 'a', hit: false)];
    final p = buildTankAttackPlan(shots: shots);
    final salvo = p.units.firstWhere((u) => u.kind == TankUnitKind.salvo);
    expect(p.drainStartFor('a', shots), salvo.endAt);
    expect(p.drainStartFor('c', shots), isNull, reason: 'c n-a fost ținta nimănui');
  });

  test('ritmul camerelor 1 la 1 e același în plan și în widget', () {
    expect(tanksCamAftermathSeconds, tankPovAftermath);
  });
}
