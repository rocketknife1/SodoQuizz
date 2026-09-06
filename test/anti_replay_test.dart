import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/data/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Anti-reluare: cine răspunde la câteva întrebări și închide aplicația din
// recente NU trebuie să poată relua de la zero. Testat aici la nivelul
// storage-ului — partea care supraviețuiește închiderii aplicației.
//
// Ecranele consumă încercarea la PRIMUL RĂSPUNS (nu la final, nu la
// deschiderea ecranului); testele de mai jos verifică exact ce rămâne scris.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Provocarea Zilei — progres salvat după fiecare răspuns', () {
    const azi = '2026-09-07';

    test('neîncepută: fără progres, fără rezultat', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await StorageService.dailyChallengeProgressFor(azi), isNull);
      expect(await StorageService.dailyChallengeResultFor(azi), isNull);
    });

    test('3 din 5 apoi închide: progresul rămâne, ziua NU e terminată',
        () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.recordDailyChallengeProgress(azi, 3, 2);

      final p = await StorageService.dailyChallengeProgressFor(azi);
      expect(p, isNotNull);
      expect(p!.nextIndex, 3, reason: 'se reia de la întrebarea 4 (index 3)');
      expect(p.correct, 2);
      expect(p.done, isFalse);
      // Ecranul de rezultate/quest-ul NU trebuie să creadă că a terminat.
      expect(await StorageService.dailyChallengeResultFor(azi), isNull);
    });

    test('terminată: rezultatul devine vizibil, done = true', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.recordDailyChallengeProgress(azi, 4, 3);
      await StorageService.recordDailyChallengeRun(azi, 4);

      expect(await StorageService.dailyChallengeResultFor(azi), 4);
      final p = await StorageService.dailyChallengeProgressFor(azi);
      expect(p!.done, isTrue);
      expect(p.correct, 4);
    });

    test('progresul de IERI nu se aplică azi', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService.recordDailyChallengeProgress('2026-09-06', 3, 2);
      expect(await StorageService.dailyChallengeProgressFor(azi), isNull);
      expect(await StorageService.dailyChallengeResultFor(azi), isNull);
    });

    test('formatul VECHI („dată:scor") se citește ca terminat', () async {
      // Telefoanele care aveau deja o rulare salvată înainte de schimbare.
      SharedPreferences.setMockInitialValues({'daily_challenge_run': '$azi:5'});
      expect(await StorageService.dailyChallengeResultFor(azi), 5);
      final p = await StorageService.dailyChallengeProgressFor(azi);
      expect(p!.done, isTrue);
      expect(p.correct, 5);
    });
  });

  group('Planeta hologramelor — rularea se consumă, nu se dă înapoi', () {
    test('o rulare consumată scade din cele rămase', () async {
      SharedPreferences.setMockInitialValues({});
      final total = await StorageService.planetRunsLimit();
      expect(await StorageService.planetRunsLeft(), total);

      await StorageService.recordPlanetRunStarted();
      expect(await StorageService.planetRunsLeft(), total - 1,
          reason: 'ieșirea din rulare nu o mai dă înapoi');
    });

    test('consumarea ultimei rulări pornește cooldown-ul', () async {
      SharedPreferences.setMockInitialValues({});
      final total = await StorageService.planetRunsLimit();
      for (var i = 0; i < total; i++) {
        await StorageService.recordPlanetRunStarted();
      }
      expect(await StorageService.planetRunsLeft(), 0);
      expect(await StorageService.planetCooldownRemaining(),
          greaterThan(Duration.zero));
    });
  });

  group('Cultură Generală — slotul rundei se consumă la primul răspuns', () {
    test('rundele consumate se numără, chiar fără colectare', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await StorageService.cultureQuizPlaysInWindow(), 0);

      await StorageService.recordCultureQuizPlay();
      expect(await StorageService.cultureQuizPlaysInWindow(), 1,
          reason: 'închiderea aplicației în timpul rundei nu o mai dă înapoi');

      await StorageService.recordCultureQuizPlay();
      expect(await StorageService.cultureQuizPlaysInWindow(), 2);
    });

    test('închiderea ciclului resetează contorul și pornește cooldown-ul',
        () async {
      SharedPreferences.setMockInitialValues({});
      for (var i = 0; i < StorageService.cultureQuizPlayLimit; i++) {
        await StorageService.recordCultureQuizPlay();
      }
      expect(await StorageService.cultureQuizPlaysInWindow(),
          StorageService.cultureQuizPlayLimit);

      await StorageService.startCultureQuizCooldown();
      expect(await StorageService.cultureQuizPlaysInWindow(), 0);
      expect(await StorageService.canPlayCultureQuiz(), isFalse);
    });
  });
}
