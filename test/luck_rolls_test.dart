import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/electric_chair.dart';
import 'package:guess_it/core/game_helpers.dart';
import 'package:guess_it/data/storage_service.dart';

void main() {
  test('penalizarea din Clasic: media rămâne cea veche, dar variază', () {
    final rnd = Random(7);
    const n = 20000;
    final counts = {for (final r in WrongPenaltyRoll.values) r: 0};
    var total = 0;
    for (var i = 0; i < n; i++) {
      final r = rollWrongPenalty(rnd);
      counts[r] = counts[r]! + 1;
      total += wrongPenaltyMultiplier(r);
    }
    expect(total / n, closeTo(1.0, 0.03));
    expect(counts[WrongPenaltyRoll.lucky]! / n, closeTo(0.25, 0.02));
    expect(counts[WrongPenaltyRoll.doubled]! / n, closeTo(0.25, 0.02));
  });

  test('scurtcircuitul: determinist și ~25%', () {
    expect(
      chairShortCircuit(matchId: 'm1', roundIndex: 3, victimId: 'p1'),
      chairShortCircuit(matchId: 'm1', roundIndex: 3, victimId: 'p1'),
    );
    var lucky = 0;
    const n = 4000;
    for (var i = 0; i < n; i++) {
      if (chairShortCircuit(matchId: 'm$i', roundIndex: i % 12, victimId: 'p${i % 5}')) lucky++;
    }
    expect(lucky / n, closeTo(electricChairShortCircuitChance, 0.03));
  });

  test('scurtcircuitul nu bate răspunsul, scutul sau reflexia', () {
    ChairVerdict v({bool correct = false, bool shield = false, bool reflect = false}) => chairVerdict(
          answeredCorrectly: correct,
          hasShield: shield,
          allyShielded: false,
          anyAttackerPiercing: false,
          hasReflect: reflect,
          luckyShortCircuit: true,
        );
    expect(v(correct: true), ChairVerdict.survived);
    expect(v(shield: true), ChairVerdict.survived);
    expect(v(reflect: true), ChairVerdict.reflected);
    expect(v(), ChairVerdict.shortCircuit);
  });

  test('viața în single: aruncare de zar ~50%, nu un tipar fix', () {
    var lost = 0;
    const n = 4000;
    for (var i = 0; i < n; i++) {
      if (StorageService.rollWrongAnswerLifeLoss()) lost++;
    }
    expect(lost / n, closeTo(StorageService.wrongAnswerLifeLossChance, 0.04));
  });
}
