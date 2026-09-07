import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/async_challenge.dart';

void main() {
  group('asyncChallengeSeed', () {
    test('e determinist pe id', () {
      expect(asyncChallengeSeed('ABC123'), asyncChallengeSeed('ABC123'));
    });
    test('id-uri diferite dau seed-uri diferite', () {
      expect(asyncChallengeSeed('ABC123'), isNot(asyncChallengeSeed('ABC124')));
    });
  });

  group('challengeOutcome', () {
    test('scor mai mare = won', () {
      expect(challengeOutcome(myScore: 5000, theirScore: 4000), ChallengeOutcome.won);
    });
    test('scor mai mic = lost', () {
      expect(challengeOutcome(myScore: 3000, theirScore: 4000), ChallengeOutcome.lost);
    });
    test('scor egal = draw', () {
      expect(challengeOutcome(myScore: 4000, theirScore: 4000), ChallengeOutcome.draw);
    });
  });

  group('challengeCoinReward', () {
    test('câștigătorul ia challengeWinCoins', () {
      expect(challengeCoinReward(ChallengeOutcome.won), challengeWinCoins);
    });
    test('remiza ia challengeDrawCoins', () {
      expect(challengeCoinReward(ChallengeOutcome.draw), challengeDrawCoins);
    });
    test('perdantul nu ia monede', () {
      expect(challengeCoinReward(ChallengeOutcome.lost), 0);
    });
  });

  test('alfabetul codului exclude 0/O/1/I', () {
    for (final c in ['0', 'O', '1', 'I']) {
      expect(asyncChallengeAlphabet.contains(c), isFalse, reason: '$c e ambiguu');
    }
  });
}
