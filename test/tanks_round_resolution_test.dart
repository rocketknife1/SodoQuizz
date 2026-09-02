import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/powerups.dart';
import 'package:guess_it/core/tanks.dart';

/// Rezolvarea rundei de Quizz Tanks e pură (core/tanks.dart
/// `resolveTanksVolleys`) tocmai ca sa poata fi verificata aici, fara
/// Firestore si fara doi jucatori reali. Toti clientii cheama exact functia
/// asta cu aceleasi date + aceeasi samanta, deci ce se testeaza aici e chiar
/// ce se intampla in meci.

TanksRoundOutcome run({
  required List<String> alive,
  required Set<String> shooters,
  Map<String, int>? hp,
  Map<String, String> targets = const {},
  Map<String, String> powerUps = const {},
  Set<String> allyShielded = const {},
  RoundEvent event = RoundEvent.none,
  int seed = 1,
}) {
  return resolveTanksVolleys(
    alive: alive,
    shooters: shooters,
    hpAtStart: hp ?? {for (final id in alive) id: tanksMaxHp},
    rawTargets: targets,
    rawPowerUps: powerUps,
    allyShieldedIds: allyShielded,
    event: event,
    rng: Random(seed),
  );
}

/// Cauta o samanta care da un rezultat anume la prima aruncare (hit sau
/// dodge), ca testele care depind de asta sa nu fie fragile.
int seedFor({required bool wantHit, required bool targetInGuard}) {
  for (var s = 0; s < 5000; s++) {
    final roll = rollTankShot(targetAnsweredCorrectly: targetInGuard, rnd: Random(s));
    if (roll.hit == wantHit) return s;
  }
  fail('nicio samanta gasita pentru wantHit=$wantHit guard=$targetInGuard');
}

void main() {
  group('lovitura simpla', () {
    test('un tintas, o tinta: un singur proiectil, daunele se contorizeaza pe ambii', () {
      final seed = seedFor(wantHit: true, targetInGuard: false);
      final o = run(alive: ['a', 'b'], shooters: {'a'}, targets: {'a': 'b'}, seed: seed);
      expect(o.shots.length, 1);
      expect(o.shots.first.byId, 'a');
      expect(o.shots.first.atId, 'b');
      expect(o.shots.first.hit, isTrue);
      expect(o.damageTaken['b'], o.shots.first.damage);
      expect(o.damageDealt['a'], o.shots.first.damage);
      expect(o.damageTaken['a'], 0);
    });

    test('tinta care a raspuns si ea corect (in garda) poate evita', () {
      final seed = seedFor(wantHit: false, targetInGuard: true);
      // ambii sunt tintasi -> b e "in garda" si evita mai des
      final o = run(alive: ['a', 'b'], shooters: {'a', 'b'}, targets: {'a': 'b', 'b': 'a'}, seed: seed);
      final atB = o.shots.firstWhere((s) => s.atId == 'b');
      expect(atB.hit, isFalse);
      expect(atB.damage, 0);
      expect(o.damageTaken['b'], 0);
    });

    test('tintas fara alegere valida trage automat in cel mai slabit', () {
      final o = run(
        alive: ['a', 'b', 'c'],
        shooters: {'a'},
        hp: {'a': 100, 'b': 90, 'c': 30},
        targets: const {}, // a n-a ales
        powerUps: {'a': PowerUp.megaRocket.name}, // fortam lovitura ca sa vedem tinta
      );
      expect(o.shots.single.atId, 'c'); // c e cel mai slabit
    });

    test('tinta moarta cand HP-ul ajunge la zero', () {
      final o = run(
        alive: ['a', 'b'],
        shooters: {'a'},
        hp: {'a': 100, 'b': 5},
        targets: {'a': 'b'},
        powerUps: {'a': PowerUp.megaRocket.name},
      );
      expect(o.destroyed, ['b']);
    });
  });

  group('determinism (proprietatea critica intre clienti)', () {
    test('aceleasi date + aceeasi samanta => rezultat identic', () {
      Map<String, dynamic> shape(TanksRoundOutcome o) => {
            'shots': [for (final s in o.shots) '${s.byId}>${s.atId}:${s.hit}:${s.damage}'],
            'taken': o.damageTaken,
            'dealt': o.damageDealt,
            'destroyed': o.destroyed,
          };
      for (var seed = 0; seed < 40; seed++) {
        final a = run(alive: ['x', 'y', 'z'], shooters: {'x', 'z'}, targets: {'x': 'y', 'z': 'y'}, seed: seed);
        final b = run(alive: ['x', 'y', 'z'], shooters: {'x', 'z'}, targets: {'x': 'y', 'z': 'y'}, seed: seed);
        expect(shape(a), shape(b));
      }
    });
  });

  group('mega racheta', () {
    test('loveste intotdeauna si mult mai tare decat o lovitura normala', () {
      var sawBig = false;
      for (var seed = 0; seed < 30; seed++) {
        final o = run(alive: ['a', 'b'], shooters: {'a'}, targets: {'a': 'b'}, powerUps: {'a': PowerUp.megaRocket.name}, seed: seed);
        expect(o.shots.single.hit, isTrue, reason: 'mega racheta nu poate fi evitata');
        if (o.shots.single.damage > tanksDamageMax) sawBig = true;
      }
      expect(sawBig, isTrue, reason: 'daunele ar trebui sa depaseasca maximul normal ($tanksDamageMax)');
    });
  });

  group('scut', () {
    test('scutul propriu blocheaza TOATE loviturile din runda, nu doar prima', () {
      // doi tintasi pe aceeasi tinta, ambele lovituri fortate (mega racheta) —
      // decizie user 2026-09-02: scutul te apara toata runda.
      final o = run(
        alive: ['a', 'b', 'v'],
        shooters: {'a', 'b'},
        targets: {'a': 'v', 'b': 'v'},
        powerUps: {'a': PowerUp.megaRocket.name, 'b': PowerUp.megaRocket.name, 'v': PowerUp.shield.name},
      );
      final atV = o.shots.where((s) => s.atId == 'v').toList();
      expect(atV.length, 2);
      expect(atV.where((s) => s.hit).length, 0, reason: 'niciuna nu trece');
      expect(o.damageTaken['v'], 0);
    });

    test('scutul opreste si ambele proiectile ale unei lovituri duble', () {
      final o = run(
        alive: ['s', 'v', 'x'],
        shooters: {'s'},
        targets: {'s': 'v${tanksTargetSeparator}v'}, // aceeasi tinta de doua ori
        powerUps: {'s': PowerUp.doubleShot.name, 'v': PowerUp.shield.name},
      );
      expect(o.damageTaken['v'], 0);
    });

    test('scutul de aliat se comporta la fel ca scutul propriu', () {
      final o = run(
        alive: ['a', 'v'],
        shooters: {'a'},
        targets: {'a': 'v'},
        powerUps: {'a': PowerUp.megaRocket.name},
        allyShielded: {'v'},
      );
      expect(o.shots.single.hit, isFalse);
      expect(o.damageTaken['v'], 0);
    });
  });

  group('reflexie', () {
    test('lovitura care ar fi lovit reflectorul se intoarce spre atacator', () {
      final o = run(
        alive: ['atac', 'refl'],
        shooters: {'atac'},
        targets: {'atac': 'refl'},
        powerUps: {'atac': PowerUp.megaRocket.name, 'refl': PowerUp.reflect.name},
      );
      // proiectilul original: nu atinge reflectorul
      final original = o.shots.firstWhere((s) => s.byId == 'atac' && s.atId == 'refl');
      expect(original.hit, isFalse);
      // proiectilul intors: refl -> atac, loveste
      final bounced = o.shots.firstWhere((s) => s.byId == 'refl' && s.atId == 'atac');
      expect(bounced.hit, isTrue);
      expect(o.damageTaken['atac'], bounced.damage);
      expect(o.damageTaken['refl'], 0);
      expect(o.damageDealt['refl'], bounced.damage, reason: 'reflectorul ia creditul');
      expect(o.damageDealt['atac'], 0);
    });
  });

  group('lovitura dubla', () {
    test('doua tinte diferite: doua proiectile normale', () {
      final o = run(
        alive: ['s', 'a', 'b'],
        shooters: {'s'},
        targets: {'s': 'a${tanksTargetSeparator}b'},
        powerUps: {'s': PowerUp.doubleShot.name},
      );
      expect(o.shots.length, 2);
      expect(o.shots.map((e) => e.atId).toSet(), {'a', 'b'});
      for (final s in o.shots.where((e) => e.hit)) {
        expect(s.damage, lessThanOrEqualTo(tanksDamageMax));
      }
    });

    test('aceeasi tinta de doua ori: un singur proiectil, daune marite', () {
      var sawFocused = false;
      for (var seed = 0; seed < 40; seed++) {
        final o = run(
          alive: ['s', 'a'],
          shooters: {'s'},
          targets: {'s': 'a${tanksTargetSeparator}a'},
          powerUps: {'s': PowerUp.doubleShot.name},
          seed: seed,
        );
        expect(o.shots.length, 1, reason: 'concentrat = un proiectil');
        expect(o.shots.single.atId, 'a');
        if (o.shots.single.hit && o.shots.single.damage > tanksDamageMax) sawFocused = true;
      }
      expect(sawFocused, isTrue, reason: 'macar o data daunele depasesc maximul normal');
    });

    test('fara a doua alegere: al doilea proiectil merge pe urmatorul cel mai slabit', () {
      final o = run(
        alive: ['s', 'a', 'b'],
        shooters: {'s'},
        hp: {'s': 100, 'a': 100, 'b': 20},
        targets: {'s': 'a'}, // doar prima aleasa
        powerUps: {'s': PowerUp.doubleShot.name, 's2': ''},
      );
      expect(o.shots.length, 2);
      expect(o.shots.map((e) => e.atId).toSet(), {'a', 'b'});
    });
  });

  group('evenimente de runda', () {
    test('Munitie Grea inmulteste daunele tuturor loviturilor', () {
      // acelasi seed, cu si fara eveniment; lovitura fortata
      final normal = run(alive: ['a', 'b'], shooters: {'a'}, targets: {'a': 'b'}, powerUps: {'a': PowerUp.megaRocket.name}, seed: 3);
      final heavy = run(alive: ['a', 'b'], shooters: {'a'}, targets: {'a': 'b'}, powerUps: {'a': PowerUp.megaRocket.name}, event: RoundEvent.heavyShells, seed: 3);
      expect(heavy.shots.single.damage, greaterThan(normal.shots.single.damage));
    });

    test('Ceata de Lupta: toata lumea evita mai usor', () {
      var normalHits = 0;
      var fogHits = 0;
      for (var seed = 0; seed < 200; seed++) {
        if (run(alive: ['a', 'b'], shooters: {'a'}, targets: {'a': 'b'}, seed: seed).shots.single.hit) normalHits++;
        if (run(alive: ['a', 'b'], shooters: {'a'}, targets: {'a': 'b'}, event: RoundEvent.battleFog, seed: seed).shots.single.hit) fogHits++;
      }
      expect(fogHits, lessThan(normalHits), reason: 'cu ceata se loveste mai rar');
    });
  });

  group('cazuri la limita', () {
    test('niciun tintas: nicio lovitura, nimeni ranit', () {
      final o = run(alive: ['a', 'b', 'c'], shooters: {}, targets: const {});
      expect(o.shots, isEmpty);
      expect(o.destroyed, isEmpty);
      expect(o.damageTaken.values.every((v) => v == 0), isTrue);
    });

    test('tintasul ramas singur nu are pe cine trage', () {
      final o = run(alive: ['a'], shooters: {'a'}, targets: {'a': 'a'});
      expect(o.shots, isEmpty);
    });

    test('tinta aleasa deja moarta (nu e in alive) => cade pe cel mai slabit viu', () {
      final o = run(
        alive: ['a', 'b'],
        shooters: {'a'},
        targets: {'a': 'mort'},
        powerUps: {'a': PowerUp.megaRocket.name},
      );
      expect(o.shots.single.atId, 'b');
    });
  });
}
