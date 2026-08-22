import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/data/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regresie pentru bug-ul real semnalat: un jucător cu balanța de hint-uri
/// deja peste plafon (grant admin, UNLIMITED de test, achiziție — toate
/// necapate) vedea balanța TĂIATĂ înapoi la plafon la următorul quest capat
/// (994 -> 20). Vezi comentariul de la StorageService.addHints pentru
/// explicația completă a celor două moduri în care un `clamp` orb greșea.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageService.addHints', () {
    test('nu taie balanța înapoi la plafon când e deja peste el', () async {
      SharedPreferences.setMockInitialValues({'hints_balance': 994});

      await StorageService.addHints(20);

      expect(await StorageService.getHints(), 1014);
    });

    test('rămâne plafonată cât timp balanța e sub plafon', () async {
      SharedPreferences.setMockInitialValues({'hints_balance': 5});

      await StorageService.addHints(1000);

      final hints = await StorageService.getHints();
      expect(hints, greaterThan(5));
      expect(hints, lessThan(994));
    });
  });
}
