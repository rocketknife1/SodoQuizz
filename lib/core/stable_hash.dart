/// Amestecare determinist IDENTICĂ pe toate platformele.
///
/// Multiplayer-ul nu trimite întrebările prin Firestore: fiecare client
/// încarcă local același pool și îl amestecă pornind de la `matchId`,
/// presupunând că toți obțin aceeași ordine. Două lucruri stricau
/// presupunerea între web și Android:
///
///  1. `String.hashCode` NU e garantat același între compilatorul de web și
///     cel de mobil — și chiar nu este.
///  2. Nici `Random(seed)` din `dart:math` nu garantează același șir de
///     numere pe platforme diferite ("the implementation of the random
///     stream can change", zice documentația).
///
/// Efectul: cine juca din browser primea alte întrebări decât cine juca din
/// aplicație, în același meci — scoruri incomparabile, iar la Higher &
/// Lower runda se rezolva după perechea altui client, deci răspunsul corect
/// apărea ca greșit.
///
/// Aici nu ne bazăm pe niciuna din cele două: hash propriu (FNV-1a) și
/// generator propriu (xorshift32), amândouă scrise cu aritmetică pe 32 de
/// biți mascată explicit (`& 0xFFFFFFFF`), ca să dea exact aceleași numere
/// și acolo unde întregii sunt double-uri IEEE (dart2js), și acolo unde
/// sunt întregi pe 64 de biți (mobil, dart2wasm).
library;

import 'dart:math';

/// Hash de șir pe 32 de biți, mereu pozitiv — se poate da direct ca sămânță.
int stableHash(String input) {
  var hash = 0x811C9DC5; // offset basis FNV-1a
  for (var i = 0; i < input.length; i++) {
    hash ^= input.codeUnitAt(i);
    // hash *= 16777619, descompus în shift-uri: fiecare termen rămâne sub
    // 2^32, deci și suma lor stă comod sub 2^53 (limita întregilor exacți
    // într-un double).
    hash = (hash +
            (hash << 1) +
            (hash << 4) +
            (hash << 7) +
            (hash << 8) +
            (hash << 24)) &
        0xFFFFFFFF;
  }
  return hash;
}

/// xorshift32 — starea trebuie să fie nenulă, altfel rămâne blocată pe 0.
int _nextState(int state) {
  var s = state;
  s = (s ^ (s << 13)) & 0xFFFFFFFF;
  s = s ^ (s >> 17);
  s = (s ^ (s << 5)) & 0xFFFFFFFF;
  return s;
}

/// Generator de numere aleatoare STABIL între platforme, cu API-ul lui
/// `Random` (atât cât folosim: `nextDouble`, `nextInt`, `nextBool`).
///
/// `Random(seed)` din `dart:math` NU garantează același șir pe platforme —
/// documentația spune explicit „the implementation of the random stream can
/// change". De aceea orice desen sau alegere pe care trebuie s-o vadă la fel
/// și cel de pe telefon, și cel din browser, trece pe aici.
///
/// Folosit de: forma bolovanilor din Obby (aceeași pentru toți cei care se
/// uită la același jucător). NU e criptografic și nu pretinde să fie.
class StableRandom implements Random {
  int _state;

  StableRandom(int seed) : _state = (seed & 0xFFFFFFFF) == 0 ? 0xDEAD : (seed & 0xFFFFFFFF);

  int _next() {
    _state = _nextState(_state);
    return _state;
  }

  @override
  int nextInt(int max) {
    if (max <= 0) throw RangeError.range(max, 1, null, 'max');
    return _next() % max;
  }

  /// 0.0 (inclusiv) .. 1.0 (exclusiv), cu 32 de biți de precizie — mai mult
  /// decât are nevoie orice desen.
  @override
  double nextDouble() => _next() / 4294967296.0;

  @override
  bool nextBool() => (_next() & 1) == 1;
}

/// Fisher–Yates cu generatorul de mai sus: aceeași listă și aceeași sămânță
/// dau aceeași ordine pe orice platformă. Amestecă lista pe loc, ca
/// `List.shuffle`.
void stableShuffle<T>(List<T> list, int seed) {
  var state = seed & 0xFFFFFFFF;
  if (state == 0) state = 0xDEAD;
  for (var i = list.length - 1; i > 0; i--) {
    state = _nextState(state);
    final j = state % (i + 1);
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
  }
}
