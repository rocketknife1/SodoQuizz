import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/abandon_policy.dart';

void main() {
  final now = DateTime(2026, 9, 8, 12, 0, 0);
  int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;

  test('fără abandonuri -> fără cooldown', () {
    expect(abandonCooldownRemaining([], now), Duration.zero);
  });

  test('sub prag -> fără cooldown', () {
    expect(
      abandonCooldownRemaining(
          [ago(const Duration(minutes: 5)), ago(const Duration(minutes: 2))], now),
      Duration.zero,
    );
  });

  test('3 abandonuri într-o oră -> cooldown activ', () {
    final ts = [
      ago(const Duration(minutes: 20)),
      ago(const Duration(minutes: 10)),
      ago(const Duration(minutes: 1)),
    ];
    final left = abandonCooldownRemaining(ts, now);
    expect(left, greaterThan(Duration.zero));
    expect(left, lessThanOrEqualTo(abandonCooldown));
  });

  test('abandonuri vechi de peste o oră nu contează', () {
    final ts = [
      ago(const Duration(hours: 2)),
      ago(const Duration(hours: 3)),
      ago(const Duration(minutes: 90)),
    ];
    expect(abandonCooldownRemaining(ts, now), Duration.zero);
  });

  test('cooldown-ul expiră după abandonCooldown de la al 3-lea', () {
    final ts = [
      ago(const Duration(minutes: 40)),
      ago(const Duration(minutes: 35)),
      ago(abandonCooldown + const Duration(minutes: 1)),
    ];
    expect(abandonCooldownRemaining(ts, now), Duration.zero);
  });
}
