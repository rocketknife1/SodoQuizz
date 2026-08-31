import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/display_name.dart';
import 'package:guess_it/data/shop.dart' show starterGemGrant;
import 'package:guess_it/data/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cele două bucăți de logică pur locală din resetul de cont pornit de admin
/// (AdminScreen → PlayerProfileService.resetPlayer → cutia poștală →
/// CloudSyncService.consumePendingGrant). Se testează aici fiindcă amândouă
/// greșesc tăcut și scump:
///  - o cheie uitată din lista de păstrate la reset ar șterge o achiziție
///    ("fără reclame") sau ar redenumi jucătorul, la un singur tap din admin;
///  - un contor de activitate care nu crește trimite la ștergerea automată
///    conturi Guest ale unor jucători reali (vezi
///    PlayerProfileService.guestSweepInactivity).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resetToStartingBalance', () {
    test('aduce balanța și progresul la zestrea de start', () async {
      SharedPreferences.setMockInitialValues({
        'coins': 9999,
        'gems': 400,
        'lives': 1,
        'hints_balance': 0,
        'xp': 250000,
        'high_score': 88,
        'streak_count': 42,
        'answered_ids': <String>['q1', 'q2'],
      });

      await StorageService.resetToStartingBalance();

      expect(await StorageService.getCoins(), StorageService.startingCoinsDefault);
      expect(await StorageService.getGems(), starterGemGrant);
      expect(await StorageService.getLives(), StorageService.startingLivesDefault);
      expect(await StorageService.getHints(), StorageService.startingHintsDefault);
      expect(await StorageService.getXp(), 0);
      expect(await StorageService.getHighScore(), 0);
      expect(await StorageService.getStreak(), 0);
      expect(await StorageService.getAnsweredIds(), isEmpty);
      expect(await StorageService.getActivityEvents(), 0);
    });

    test('păstrează numele, setările și achiziția "fără reclame"', () async {
      SharedPreferences.setMockInitialValues({
        'display_name': 'Dragos',
        'music_enabled': false,
        'music_volume': 0.3,
        'no_blur_mode': true,
        'intro_tutorial_seen': true,
        'multiplayer_info_seen': true,
        'no_ads_forever': true,
        'coins': 9999,
      });

      await StorageService.resetToStartingBalance();

      expect(await StorageService.getDisplayName(), 'Dragos');
      expect(await StorageService.getMusicEnabled(), false);
      expect(await StorageService.getMusicVolume(), 0.3);
      expect(await StorageService.getNoBlurMode(), true);
      expect(await StorageService.getIntroSeen(), true);
      expect(await StorageService.getMultiplayerInfoSeen(), true);
      expect(await StorageService.getNoAdsForever(), true);
      expect(await StorageService.getCoins(), StorageService.startingCoinsDefault);
    });

    test('resetul de admin nu redenumeste jucatorul', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.setChosenDisplayName('NumeleMeu');
      expect(await StorageService.getChosenDisplayName(), 'NumeleMeu');

      await StorageService.resetToStartingBalance();

      expect(await StorageService.getChosenDisplayName(), 'NumeleMeu',
          reason: 'un reset de balanta nu are voie sa schimbe numele ales');
    });

    test('un jucator Google vechi nu e redenumit de trecerea la noua ordine', () async {
      // Exact starea unui cont Google de dinaintea acestei schimbari: are un nume
      // auto-generat in prefs, care nu s-a folosit niciodata fiindca numele din
      // Google avea prioritate. Marcajul `display_name_chosen` nu exista.
      SharedPreferences.setMockInitialValues({'display_name': 'Jucator123'});

      expect(await StorageService.getChosenDisplayName(), '',
          reason: 'fara marcaj, numele vechi din prefs NU conteaza ca nume ales');

      expect(
        resolveDisplayName(
          forcedName: '',
          chosenName: await StorageService.getChosenDisplayName(),
          googleName: 'Nume Google',
        ),
        'Nume Google',
        reason: 'jucatorul isi pastreaza numele din Google, nu se trezeste cu Jucator123',
      );
    });
  });

  group('semne de activitate', () {
    test('un cont abia instalat e la zero', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await StorageService.getActivityEvents(), 0);
    });

    test('roata și mișcările de balanță contează', () async {
      SharedPreferences.setMockInitialValues({});

      await StorageService.recordRingSpin();
      expect(await StorageService.getActivityEvents(), 1);

      await StorageService.addCoins(10);
      await StorageService.spendCoins(5);
      await StorageService.addGems(1);
      await StorageService.spendGems(1);
      expect(await StorageService.getActivityEvents(), 5);
    });

    test('o cheltuială respinsă nu trece drept activitate', () async {
      SharedPreferences.setMockInitialValues({'coins': 0, 'gems': 0});

      expect(await StorageService.spendCoins(50), false);
      expect(await StorageService.spendGems(3), false);
      expect(await StorageService.getActivityEvents(), 0);
    });

    test('o recompensă de zero monede nu trece drept activitate', () async {
      // Rundă terminată fără niciun răspuns corect — se întâmplă des.
      SharedPreferences.setMockInitialValues({});

      await StorageService.addCoins(0);
      await StorageService.addGems(0);
      expect(await StorageService.getActivityEvents(), 0);
      expect(await StorageService.getCoins(), StorageService.startingCoinsDefault);
    });

    test('amprenta ultimei urcări în cloud nu pleacă ea însăși în cloud', () async {
      // Dacă ar face parte din export, s-ar auto-invalida la fiecare urcare și
      // optimizarea "sari peste urcare dacă nimic nu s-a schimbat" (vezi
      // CloudSyncService.push) n-ar sări niciodată nimic.
      SharedPreferences.setMockInitialValues({'coins': 500});
      await StorageService.setCloudPushSnapshot('amprenta');

      final exported = await StorageService.exportAll();
      expect(exported.containsKey('cloud_push_snapshot'), false);
      expect(exported['coins'], 500);
      expect(await StorageService.getCloudPushSnapshot(), 'amprenta');
    });

    test('resetul șterge amprenta, ca noua stare să se urce sigur', () async {
      SharedPreferences.setMockInitialValues({'coins': 9999});
      await StorageService.setCloudPushSnapshot('amprenta veche');

      await StorageService.resetToStartingBalance();

      expect(await StorageService.getCloudPushSnapshot(), isNull);
    });

    test('doar deschiderea jocului nu contează ca activitate', () async {
      // Vieţile se reîncarcă singure, în timp — dacă ar fi numărate, orice
      // cont pornit și lăsat în pace ar părea activ și n-ar mai fi măturat
      // niciodată. La fel, simpla citire a balanței nu schimbă nimic.
      SharedPreferences.setMockInitialValues({});

      await StorageService.getLives();
      await StorageService.getCoins();
      await StorageService.getHints();
      expect(await StorageService.getActivityEvents(), 0);
    });
  });

  group('pruneOldDailyCounters', () {
    test('sterge contoarele din zilele trecute, le pastreaza pe cele de azi', () async {
      final acum = DateTime.now();
      final azi = '${acum.year}-${acum.month}-${acum.day}';
      SharedPreferences.setMockInitialValues({
        'daily_clippy_rounds_$azi': 3,
        'daily_culture_batches_$azi': 1,
        'daily_clippy_rounds_2026-8-5': 5,
        'daily_hearts_bought_2026-8-5': 4,
        'daily_quest_gems_2025-12-31': 7,
      });

      await StorageService.pruneOldDailyCounters();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('daily_clippy_rounds_$azi'), 3);
      expect(prefs.getInt('daily_culture_batches_$azi'), 1);
      expect(prefs.getKeys().where((k) => k.endsWith('2026-8-5')), isEmpty);
      expect(prefs.getInt('daily_quest_gems_2025-12-31'), isNull);
    });

    test('nu atinge cheile "daily_" care nu sunt contoare pe zi', () async {
      SharedPreferences.setMockInitialValues({
        'daily_claim_date': '2026-8-5',
        'daily_challenge_date': '2026-8-5',
        'daily_challenges_total': 12,
        'daily_lives_claimed': 4,
      });

      await StorageService.pruneOldDailyCounters();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('daily_claim_date'), '2026-8-5');
      expect(prefs.getString('daily_challenge_date'), '2026-8-5');
      expect(prefs.getInt('daily_challenges_total'), 12);
      expect(prefs.getInt('daily_lives_claimed'), 4);
    });
  });
}
