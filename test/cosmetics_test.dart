import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/cosmetics.dart';
import 'package:guess_it/data/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ownsFrame', () {
    test('none e mereu detinut', () {
      expect(ownsFrame(Frame.none, level: 0, leaguePoints: 0), isTrue);
    });

    test('ramele de liga cer tierul respectiv', () {
      // 0 puncte = bronze (tier 0). Vezi leagueTierIndexForPoints.
      expect(ownsFrame(Frame.bronze, level: 1, leaguePoints: 0), isTrue);
      expect(ownsFrame(Frame.gold, level: 1, leaguePoints: 0), isFalse);
      // un punctaj de Gold sau mai mare deblocheaza bronze+silver+gold
      // 300..699 = Gold (vezi leagueForPoints). Deblocheaza bronze+silver+gold,
      // dar nu platinum/diamond.
      const goldPoints = 400;
      expect(ownsFrame(Frame.bronze, level: 1, leaguePoints: goldPoints), isTrue);
      expect(ownsFrame(Frame.silver, level: 1, leaguePoints: goldPoints), isTrue);
      expect(ownsFrame(Frame.gold, level: 1, leaguePoints: goldPoints), isTrue);
      expect(ownsFrame(Frame.platinum, level: 1, leaguePoints: goldPoints), isFalse);
      expect(ownsFrame(Frame.diamond, level: 1, leaguePoints: goldPoints), isFalse);
    });

    test('ramele de nivel cer nivelul', () {
      expect(ownsFrame(Frame.lvl10, level: 9, leaguePoints: 0), isFalse);
      expect(ownsFrame(Frame.lvl10, level: 10, leaguePoints: 0), isTrue);
      expect(ownsFrame(Frame.lvl50, level: 49, leaguePoints: 999999), isFalse);
      expect(ownsFrame(Frame.lvl50, level: 50, leaguePoints: 0), isTrue);
    });
  });

  group('ownsTitle', () {
    test('novice e mereu detinut', () {
      expect(ownsTitle(PlayerTitle.novice, level: 0, achievements: {}), isTrue);
    });

    test('titlurile pe nivel cer nivelul', () {
      expect(ownsTitle(PlayerTitle.curios, level: 4, achievements: {}), isFalse);
      expect(ownsTitle(PlayerTitle.curios, level: 5, achievements: {}), isTrue);
      expect(ownsTitle(PlayerTitle.legenda, level: 25, achievements: {}), isTrue);
    });

    test('titlurile pe realizare cer id-ul realizarii', () {
      expect(ownsTitle(PlayerTitle.expert, level: 1, achievements: {}), isFalse);
      expect(ownsTitle(PlayerTitle.expert, level: 1, achievements: {'correct_150'}), isTrue);
      expect(ownsTitle(PlayerTitle.veteran, level: 1, achievements: {'level_15'}), isTrue);
      expect(ownsTitle(PlayerTitle.campion, level: 99, achievements: {}), isFalse);
      expect(ownsTitle(PlayerTitle.campion, level: 1, achievements: {'mp_wins_23'}), isTrue);
      expect(ownsTitle(PlayerTitle.omDeCultura, level: 1, achievements: {'culture_600'}), isTrue);
    });

    test('inAscensiune e pe nivel 10, nu pe realizare', () {
      expect(ownsTitle(PlayerTitle.inAscensiune, level: 9, achievements: {}), isFalse);
      expect(ownsTitle(PlayerTitle.inAscensiune, level: 10, achievements: {}), isTrue);
    });
  });

  group('frameFromId / titleFromId', () {
    test('id necunoscut cade pe default', () {
      expect(frameFromId('inventat'), Frame.none);
      expect(frameFromId(null), Frame.none);
      expect(titleFromId('inventat'), PlayerTitle.novice);
    });

    test('drum dus-intors', () {
      for (final f in Frame.values) {
        expect(frameFromId(f.name), f);
      }
      for (final t in PlayerTitle.values) {
        expect(titleFromId(t.name), t);
      }
    });
  });

  test('frameStyle returneaza culori pentru fiecare rama', () {
    for (final f in Frame.values) {
      expect(frameStyle(f).colors, isNotEmpty);
    }
  });

  test('frameLabel are un text pentru fiecare rama', () {
    for (final f in Frame.values) {
      expect(frameLabel(f), isNotEmpty);
    }
  });

  test('titleLabel are RO si EN pentru fiecare titlu', () {
    for (final t in PlayerTitle.values) {
      final (ro, en) = titleLabel(t);
      expect(ro, isNotEmpty);
      expect(en, isNotEmpty);
    }
  });

  group('echipare — persistenta si globali', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('valorile implicite fara nimic salvat', () async {
      expect(await StorageService.getEquippedFrame(), 'none');
      expect(await StorageService.getEquippedTitle(), 'novice');
    });

    test('setMyFrame scrie prefs SI notifier', () async {
      SharedPreferences.setMockInitialValues({});
      await loadCosmetics();
      expect(myFrame.value, Frame.none);
      await setMyFrame(Frame.gold);
      expect(myFrame.value, Frame.gold);
      expect(await StorageService.getEquippedFrame(), 'gold');
    });

    test('loadCosmetics citeste ce s-a salvat', () async {
      SharedPreferences.setMockInitialValues({
        'equipped_frame': 'diamond',
        'equipped_title': 'veteran',
      });
      await loadCosmetics();
      expect(myFrame.value, Frame.diamond);
      expect(myTitle.value, PlayerTitle.veteran);
    });

    test('loadCosmetics cade pe default la valoare corupta', () async {
      SharedPreferences.setMockInitialValues({'equipped_frame': 'zzz'});
      await loadCosmetics();
      expect(myFrame.value, Frame.none);
    });
  });

  group('validatedFrame', () {
    test('cade pe none daca nu e detinuta', () {
      expect(validatedFrame('diamond', level: 1, leaguePoints: 0), Frame.none);
      expect(validatedFrame('lvl10', level: 15, leaguePoints: 0), Frame.lvl10);
    });

    test('trece o rama de liga daca punctele o acopera', () {
      expect(validatedFrame('gold', level: 1, leaguePoints: 400), Frame.gold);
    });

    test('id necunoscut -> none', () {
      expect(validatedFrame('zzz', level: 99, leaguePoints: 999999), Frame.none);
    });
  });
}
