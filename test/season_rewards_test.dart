import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/leagues.dart';
import 'package:guess_it/core/season_rewards.dart';

void main() {
  test('recompensa creste cu tier-ul, Bronze primeste ceva', () {
    expect(seasonRewardCoins(0), 100);
    expect(seasonRewardCoins(1), 250);
    expect(seasonRewardCoins(2), 500);
    expect(seasonRewardCoins(3), 1000);
    expect(seasonRewardCoins(4), 2000);
    // monoton
    for (var i = 1; i < 5; i++) {
      expect(seasonRewardCoins(i), greaterThan(seasonRewardCoins(i - 1)));
    }
  });

  test('index in afara limitelor e plafonat, nu arunca', () {
    expect(seasonRewardCoins(-3), 100);
    expect(seasonRewardCoins(99), 2000);
    expect(seasonRewardTier(99), LeagueTier.diamond);
    expect(seasonRewardTier(-1), LeagueTier.bronze);
  });
}
