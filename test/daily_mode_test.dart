import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/daily_mode.dart';
import 'package:guess_it/models/multiplayer_models.dart';

void main() {
  test('modeOfDay e determinist pe zi', () {
    final a = modeOfDay(DateTime(2026, 9, 8, 3));
    final b = modeOfDay(DateTime(2026, 9, 8, 21));
    expect(a, b);
  });

  test('modeOfDay se schimbă între zile (peste o fereastră)', () {
    final picks = {
      for (var d = 0; d < 30; d++)
        modeOfDay(DateTime(2026, 1, 1).add(Duration(days: d)))
    };
    expect(picks.length, greaterThan(1));
  });

  test('modeOfDay alege doar din pool-ul 1-la-1', () {
    for (var d = 0; d < 60; d++) {
      final m = modeOfDay(DateTime(2026, 3, 1).add(Duration(days: d)));
      expect(dailyModePool.contains(m), isTrue);
    }
  });

  test('pool-ul nu conține moduri care cer 4+ jucători', () {
    for (final bad in [
      MatchGameMode.quizzTanks,
      MatchGameMode.obby,
      MatchGameMode.electricChair,
    ]) {
      expect(dailyModePool.contains(bad), isFalse);
    }
  });

  test('label-ul acoperă toate valorile enum', () {
    for (final m in MatchGameMode.values) {
      expect(matchGameModeLabel(m), isNotEmpty);
    }
  });
}
