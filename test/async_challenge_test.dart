import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/async_challenge.dart';
import 'package:guess_it/models/question.dart';

Question _q(String id) => Question(
      id: id,
      answer: 'a',
      hint1: '',
      hint2: '',
      hint3: '',
      categoryId: 'c',
      category: 'C',
      color: const Color(0xFF000000),
      maxPoints: 100,
      imageAssetPath: 'assets/x.jpg',
    );

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

  group('pickAsyncChallenge', () {
    final pool = List.generate(200, (i) => _q('q$i'));

    test('acelasi id -> exact aceleasi 10 intrebari (creator == adversar)', () {
      final creator = pickAsyncChallenge(pool, 'SYHZCR').map((q) => q.id).toList();
      final opponent = pickAsyncChallenge(pool, 'SYHZCR').map((q) => q.id).toList();
      expect(creator.length, asyncChallengeQuestionCount);
      expect(creator, opponent);
    });

    test('id-uri diferite -> selectii diferite', () {
      final a = pickAsyncChallenge(pool, 'AAAAAA').map((q) => q.id).toList();
      final b = pickAsyncChallenge(pool, 'BBBBBB').map((q) => q.id).toList();
      expect(a, isNot(b));
    });

    test('newAsyncChallengeId da 6 caractere din alfabet', () {
      final id = newAsyncChallengeId();
      expect(id.length, 6);
      for (final c in id.split('')) {
        expect(asyncChallengeAlphabet.contains(c), isTrue);
      }
    });
  });

  test('alfabetul codului exclude 0/O/1/I', () {
    for (final c in ['0', 'O', '1', 'I']) {
      expect(asyncChallengeAlphabet.contains(c), isFalse, reason: '$c e ambiguu');
    }
  });
}
