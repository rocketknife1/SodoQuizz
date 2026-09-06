import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/data/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('gol la inceput', () async {
    expect(await StorageService.getRecentOpponents(), isEmpty);
  });

  test('adauga, dedup pe uid, cel mai recent primul', () async {
    await StorageService.addRecentOpponents([
      {'uid': 'a', 'name': 'Ana', 'seed': 'a'},
      {'uid': 'b', 'name': 'Bob', 'seed': 'b'},
    ]);
    await StorageService.addRecentOpponents([
      {'uid': 'b', 'name': 'Bob2', 'seed': 'b'},
      {'uid': 'c', 'name': 'Cip', 'seed': 'c'},
    ]);
    final r = await StorageService.getRecentOpponents();
    expect(r.map((o) => o['uid']).toList(), ['b', 'c', 'a']);
    expect(r.first['name'], 'Bob2'); // ultima valoare castiga
  });

  test('plafonat la 15', () async {
    for (var i = 0; i < 25; i++) {
      await StorageService.addRecentOpponents([
        {'uid': 'u$i', 'name': 'P$i', 'seed': 's'}
      ]);
    }
    expect((await StorageService.getRecentOpponents()).length, 15);
  });

  test('photo optional, JSON stricat -> gol', () async {
    await StorageService.addRecentOpponents([
      {'uid': 'x', 'name': 'X', 'seed': 'x', 'photo': 'http://p.jpg'}
    ]);
    expect((await StorageService.getRecentOpponents()).first['photo'], 'http://p.jpg');
    SharedPreferences.setMockInitialValues({'recent_opponents': 'nu e json'});
    expect(await StorageService.getRecentOpponents(), isEmpty);
  });
}
