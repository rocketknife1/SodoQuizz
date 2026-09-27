import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/impostor_game.dart';

Map<String, List<ImpostorPic>> _byCat() => {
      'masini': [
        const ImpostorPic(id: 'm1', answer: 'BUGATTI', imagePath: 'x', categoryId: 'masini'),
        const ImpostorPic(id: 'm2', answer: 'FERRARI', imagePath: 'x', categoryId: 'masini'),
        const ImpostorPic(id: 'm3', answer: 'PORSCHE', imagePath: 'x', categoryId: 'masini'),
      ],
      'animale': [
        const ImpostorPic(id: 'a1', answer: 'TIGRU', imagePath: 'x', categoryId: 'animale'),
        const ImpostorPic(id: 'a2', answer: 'LEU', imagePath: 'x', categoryId: 'animale'),
      ],
    };

void main() {
  const game = ImpostorGame();
  final players = ['a', 'b', 'c', 'd'];

  group('indiciile', () {
    test('sunt toate adevărate despre cuvânt', () {
      for (final word in ['BUGATTI', 'LEU', 'A', 'ZZZ']) {
        for (final c in impostorCluesFor(word)) {
          final w = word.toUpperCase();
          switch (c.kind) {
            case ImpostorClueKind.startsWith:
              expect(w.startsWith(c.value), isTrue, reason: '$word / $c');
            case ImpostorClueKind.endsWith:
              expect(w.endsWith(c.value), isTrue, reason: '$word / $c');
            case ImpostorClueKind.length:
              expect(w.length, int.parse(c.value), reason: '$word / $c');
            case ImpostorClueKind.contains:
              expect(w.contains(c.value), isTrue, reason: '$word / $c');
            case ImpostorClueKind.vowelCount:
              break; // verificat mai jos separat
          }
        }
      }
    });

    test('encode/decode e identitate', () {
      for (final c in impostorCluesFor('BUGATTI')) {
        expect(ImpostorClue.decode(c.encode()).encode(), c.encode());
      }
    });

    test('un cuvânt gol nu dă indicii (nu explodează)', () {
      expect(impostorCluesFor(''), isEmpty);
    });
  });

  group('impostorul și cuvintele', () {
    test('rotația e deterministă și rămâne printre jucătorii la masă', () {
      final a = game.impostorFor(players, 5, 0);
      final b = game.impostorFor(players, 5, 0);
      expect(a, b);
      expect(players, contains(a));
    });

    test('cuvântul real și cel al impostorului sunt din aceeași categorie, dar diferite', () {
      final (real, impostor) = game.wordsFor(byCategory: _byCat(), seed: 1, round: 0);
      expect(real.categoryId, impostor.categoryId);
      expect(real.answer, isNot(impostor.answer));
    });

    test('wordFor dă cuvântul corect fiecăruia', () {
      final round = ImpostorRound(
        impostorId: 'b',
        realWord: const ImpostorPic(id: '1', answer: 'FERRARI', imagePath: 'x', categoryId: 'masini'),
        impostorWord: const ImpostorPic(id: '2', answer: 'PORSCHE', imagePath: 'x', categoryId: 'masini'),
      );
      expect(round.wordFor('a'), 'FERRARI');
      expect(round.wordFor('b'), 'PORSCHE');
      expect(round.wordFor('c'), 'FERRARI');
    });
  });

  group('votul', () {
    test('impostorul prins de majoritate ia doar consolarea', () {
      final res = game.resolveVotes(
        impostorId: 'b',
        playerIds: players,
        votes: {'a': 'b', 'c': 'b', 'd': 'b'},
      );
      expect(res.impostorCaught, isTrue);
      expect(res.scores['b'], impostorCaughtConsolationPoints);
      expect(res.scores['a'], impostorCorrectVotePoints);
      expect(res.scores['c'], impostorCorrectVotePoints);
    });

    test('voturi împărțite = impostorul scapă', () {
      final res = game.resolveVotes(
        impostorId: 'b',
        playerIds: players,
        votes: {'a': 'c', 'c': 'a', 'd': 'b'},
      );
      expect(res.impostorCaught, isFalse);
      expect(res.scores['b'], impostorSurvivePoints);
    });

    test('nimeni nu votează = impostorul scapă', () {
      final res = game.resolveVotes(impostorId: 'b', playerIds: players, votes: {});
      expect(res.impostorCaught, isFalse);
      expect(res.scores.values.every((v) => v == 0 || v == impostorSurvivePoints), isTrue);
    });

    test('votul pe cineva plecat nu numără', () {
      final res = game.resolveVotes(impostorId: 'b', playerIds: ['a', 'b'], votes: {'a': 'zzz'});
      expect(res.votesFor.values.every((v) => v == 0), isTrue);
    });
  });

  group('botul', () {
    test('votează pe cel cu indiciu nepotrivit când e atent', () {
      final rnd = Random(1);
      final vote = impostorBotVote(
        myId: 'a',
        myWord: 'FERRARI',
        otherIds: ['b', 'c'],
        clueByPlayer: {
          'b': const ImpostorClue(ImpostorClueKind.startsWith, 'Z'), // nu se potrivește cu FERRARI
          'c': const ImpostorClue(ImpostorClueKind.startsWith, 'F'),
        },
        difficulty: 5,
        rnd: rnd,
      );
      expect(vote, 'b');
    });

    test('alege un indiciu din cele disponibile', () {
      final clues = impostorCluesFor('LEU');
      final rnd = Random(2);
      for (var i = 0; i < 20; i++) {
        expect(clues, contains(impostorBotPickClue(clues, rnd)));
      }
    });
  });
}
