import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/game_event.dart';

const _valid = '''
{
  "id": "halloween-2026",
  "titlu": "Halloween",
  "titlu_en": "Halloween",
  "descriere": "Categorie horror.",
  "categorie": "istorie",
  "start": "2026-10-28",
  "sfarsit": "2026-11-02",
  "bonus": 1.5
}
''';

void main() {
  test('gol / JSON stricat / campuri lipsa -> null, nu arunca', () {
    expect(parseGameEvent(''), isNull);
    expect(parseGameEvent('   '), isNull);
    expect(parseGameEvent('{nu e json'), isNull);
    expect(parseGameEvent('{"id":"x"}'), isNull); // fara titlu/date
    expect(parseGameEvent('[1,2,3]'), isNull);
    expect(parseGameEvent('{"id":"x","titlu":"T","start":"2026-10-28","sfarsit":"2026-10-27"}'),
        isNull); // sfarsit inainte de start
  });

  test('parsare corecta', () {
    final e = parseGameEvent(_valid)!;
    expect(e.id, 'halloween-2026');
    expect(e.titleRo, 'Halloween');
    expect(e.categoryId, 'istorie');
    expect(e.coinBonus, 1.5);
    expect(e.start, DateTime.parse('2026-10-28'));
    expect(e.end, DateTime.parse('2026-11-02'));
  });

  test('bonus plafonat 1.0..3.0', () {
    expect(parseGameEvent(_valid.replaceAll('1.5', '99'))!.coinBonus, 3.0);
    expect(parseGameEvent(_valid.replaceAll('1.5', '0.1'))!.coinBonus, 1.0);
    final noBonus = parseGameEvent(_valid.replaceAll('"bonus": 1.5', '"x": 0'))!;
    expect(noBonus.coinBonus, 1.0);
  });

  test('isLiveAt / daysLeftAt', () {
    final e = parseGameEvent(_valid)!;
    expect(e.isLiveAt(DateTime.parse('2026-10-27')), isFalse);
    expect(e.isLiveAt(DateTime.parse('2026-10-29')), isTrue);
    expect(e.isLiveAt(DateTime.parse('2026-11-02')), isFalse); // end exclusiv
    expect(e.daysLeftAt(DateTime.parse('2026-10-30')), 3);
    expect(e.daysLeftAt(DateTime.parse('2026-11-05')), 0);
  });

  test('countsMode: categoria fixata sau orice cand e gol', () {
    final e = parseGameEvent(_valid)!;
    expect(e.countsMode('istorie'), isTrue);
    expect(e.countsMode('geografie'), isFalse);
    final anyCat = parseGameEvent(_valid.replaceAll('"categorie": "istorie"', '"categorie": ""'))!;
    expect(anyCat.countsMode('orice'), isTrue);
  });
}
