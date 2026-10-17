import 'package:flutter_test/flutter_test.dart';
import 'package:guess_it/core/lang.dart';
import 'package:guess_it/core/progression.dart';

final _ro = RegExp('[ăâîșțĂÂÎȘȚ]');

void main() {
  tearDown(() => L10n.language.value = AppLanguage.ro);

  test('pe engleză, niciun quest și nicio realizare nu rămâne în română', () {
    L10n.language.value = AppLanguage.en;
    for (final q in allQuests) {
      for (final level in [1, 10, 40]) {
        final t = q.titleAt(level);
        expect(t.contains(_ro), isFalse, reason: '${q.id}: $t');
        expect(t.contains('{n}'), isFalse, reason: '${q.id}: $t');
      }
    }
    for (final a in achievements) {
      expect(a.title.contains(_ro), isFalse, reason: '${a.id}: ${a.title}');
      expect(a.description.contains(_ro), isFalse, reason: '${a.id}: ${a.description}');
    }
  });

  test('pe română titlurile rămân ca înainte (cu „de” unde cere gramatica)', () {
    L10n.language.value = AppLanguage.ro;
    final q = allQuests.firstWhere((q) => q.titleAt(40).contains('monede'));
    expect(q.titleAt(40), contains(' de monede'));
  });
}
