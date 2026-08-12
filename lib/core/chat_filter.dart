/// Filtrul de limbaj pentru chat — cel din camera multiplayer ȘI cel privat
/// dintre prieteni.
///
/// De ce există: formularul de Content rating din Google Play întreabă
/// explicit dacă jocul are chat între utilizatori și ce mecanisme de
/// siguranță are. Fără nicio filtrare, singurul răspuns onest la „chat
/// moderation" era NU (vezi secțiunea 3B din notele proiectului). Aici e
/// jumătatea automată — cuvinte cenzurate înainte ca mesajul să plece;
/// raportarea și blocarea, jumătatea umană, sunt în ModerationService.
///
/// CUM E GÂNDIT, fiindcă un filtru naiv se ocolește în trei secunde:
///  1. mesajul se normalizează întâi — diacriticele cad („pizdă" → „pizda"),
///     majusculele coboară, cifrele-leet se întorc în litere (4→a, 3→e, 0→o,
///     $→s);
///  2. separatorii (spații, puncte, cratime, emoji) se scot de tot pentru
///     căutare, ca „p.u.l.a" și „p u l a" să nu treacă;
///  3. fiecare rădăcină se caută cu repetiții permise pe fiecare literă
///     („pula" se caută ca `p+u+l+a+`), ca „puuulaaa" să fie prinsă.
///
/// DOUĂ REGULI FAC FILTRUL FOLOSIBIL, amândouă învățate din cazuri care chiar
/// s-au rupt în timp ce era scris (vezi test/chat_filter_test.dart):
///
///  - potrivirea e ancorată la ÎNCEPUT DE CUVÂNT. Fără ancoră, „populație"
///    conține „pula" și „informații" conține „matii" — un chat de quiz în
///    care nu poți întreba câți locuitori are un oraș e mai rău decât unul
///    needucat. Prețul: injuria lipită în mijlocul unui cuvânt inventat
///    scapă. Cine se chinuie atât ajunge oricum raportat de ceilalți.
///
///  - repetițiile sunt PERMISE, nu colapsate. Dacă textul s-ar colapsa în
///    schimb („faggot" → „fagot"), filtrul ar tăia și fagotul, instrumentul
///    muzical — un cuvânt perfect plauzibil într-un joc de cultură generală.
///    Cu `f+a+g+g+o+t+` e nevoie de cei doi „g" ca să se potrivească.
///
/// Poziția fiecărui caracter din forma normalizată se ține minte (vezi
/// [_Normalized.sourceIndex]), ca să știm exact ce bucată din textul ORIGINAL
/// să acoperim cu asteriscuri — altfel n-am putea cenzura decât rescriind
/// mesajul întreg, cu diacriticele pierdute.
///
/// Ce NU face: nu blochează trimiterea și nu pedepsește pe nimeni. Un mesaj
/// cenzurat pleacă mai departe cu asteriscuri în loc de cuvânt.
library;

/// Lungimea maximă a unui mesaj de chat. Nu ține de decență, ține de faptul
/// că un mesaj foarte lung strică bula de chat și, în camera multiplayer,
/// împinge lista de jucători în afara ecranului.
const int chatMessageMaxLength = 200;

/// Rădăcini căutate de la ÎNCEPUT DE CUVÂNT înainte, peste separatori scoși
/// („p-u-l-a") și indiferent ce terminație urmează („pizdă", „pizdele").
const _wordStartRoots = <String>[
  'pizd',
  'pula',
  'puli',
  'muie',
  'muist',
  'coaie',
  'curv',
  'cacat',
  'gaoaz',
  'sloboz',
  'labagi',
  'futu',
  'fute',
  'futi',
  'mortii',
  'tigan',
  'fuck',
  'fuk',
  'bullshit',
  'shit',
  'bitch',
  'cunt',
  'nigg',
  'faggot',
  'whore',
  'motherfuck',
  'asshole',
  'retard',
];

/// Rădăcini acceptate DOAR ca și cuvânt complet. Sunt aici fiindcă până și
/// ancorate la început de cuvânt ar tăia cuvinte nevinovate: „ass" începe
/// „assume", „dick" începe „Dickens", iar „cur" începe „curat", „curent",
/// „curte", „curcan".
const _exactWords = <String>[
  'ass',
  'asses',
  'dick',
  'dicks',
  'rape',
  'raped',
  'rapist',
  'cur',
  'curu',
  'curul',
  'fut',
];

/// Diacriticele românești + literele accentuate care apar de la tastaturi
/// străine, aduse la litera de bază.
const _foldings = <String, String>{
  'ă': 'a', 'â': 'a', 'á': 'a', 'à': 'a', 'ä': 'a', 'å': 'a', 'ã': 'a',
  'î': 'i', 'í': 'i', 'ì': 'i', 'ï': 'i',
  'ș': 's', 'ş': 's', 'š': 's',
  'ț': 't', 'ţ': 't',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ç': 'c', 'ñ': 'n',
};

/// Substituțiile „leet" fără echivoc.
const _leet = <String, String>{
  '4': 'a', '@': 'a',
  '3': 'e',
  '0': 'o',
  '5': 's', r'$': 's',
  '7': 't',
  '8': 'b',
};

/// `1` și `!` se scriu și în loc de `i`, și în loc de `l` („sh1t" vs „pu1a") —
/// nu se poate alege una fără să se piardă cealaltă. De-aia
/// [censorChatMessage] normalizează mesajul de două ori, o dată cu fiecare
/// citire, și adună ce a găsit fiecare.
const _ambiguousLeet = <String, String>{'1': 'i', '!': 'i'};
const _ambiguousLeetAlt = <String, String>{'1': 'l', '!': 'l'};

/// „pula" → `p+u+l+a+`. Vezi nota despre repetiții din capul fișierului.
String _repeatTolerant(String root) => root.split('').map((c) => '$c+').join();

/// Toate rădăcinile de la început de cuvânt, într-o singură alternanță — o
/// singură trecere peste text în loc de una pentru fiecare cuvânt din listă.
/// Ancorarea la început de cuvânt NU se poate exprima aici (textul căutat are
/// separatorii scoși, deci n-are granițe), se verifică pe fiecare potrivire.
final _wordStartPattern = RegExp('(?:${_wordStartRoots.map(_repeatTolerant).join('|')})');

final _exactWordPatterns = _exactWords.map((w) => RegExp('(?:^| )(${_repeatTolerant(w)})(?= |\$)')).toList();

/// Textul normalizat + harta înapoi către pozițiile din textul original.
class _Normalized {
  /// Litere mici, fără diacritice, fără leet, cu orice grup de separatori
  /// transformat într-un singur spațiu. Literele NU se colapsează.
  final String text;

  /// `sourceIndex[i]` = poziția în textul ORIGINAL a caracterului care a
  /// produs `text[i]`. Pentru spațiu se reține poziția PRIMULUI separator din
  /// grup, nu a literei care urmează — altfel o cenzură care se termină exact
  /// înaintea unui spațiu ar înghiți și spațiul, lipind cuvântul următor de
  /// asteriscuri („hai fuck acum" → „hai *****acum").
  final List<int> sourceIndex;

  const _Normalized(this.text, this.sourceIndex);
}

bool _isAsciiLetter(String c) {
  final code = c.codeUnitAt(0);
  return code >= 0x61 && code <= 0x7A; // a-z, după toLowerCase
}

_Normalized _normalize(String input, Map<String, String> ambiguousLeet) {
  final buffer = StringBuffer();
  final indices = <int>[];
  var pendingSeparator = false;
  var separatorAt = 0;

  for (var i = 0; i < input.length; i++) {
    final raw = input[i].toLowerCase();
    final mapped = _foldings[raw] ?? _leet[raw] ?? ambiguousLeet[raw] ?? raw;

    if (mapped.length != 1 || !_isAsciiLetter(mapped)) {
      // Orice non-literă (spațiu, punct, emoji, cifră necartografiată) devine
      // graniță de cuvânt. Nu se scrie pe loc, ca să nu rămână spații lipite
      // unul de altul sau la sfârșitul textului.
      if (!pendingSeparator) separatorAt = i;
      pendingSeparator = buffer.isNotEmpty;
      continue;
    }

    if (pendingSeparator) {
      buffer.write(' ');
      indices.add(separatorAt);
      pendingSeparator = false;
    }
    buffer.write(mapped);
    indices.add(i);
  }

  return _Normalized(buffer.toString(), indices);
}

/// Marchează pentru cenzură caracterele din original care au produs
/// intervalul `[start, end)` din forma normalizată.
void _maskRange(List<bool> masked, _Normalized normalized, int start, int end) {
  final from = normalized.sourceIndex[start];
  final to = end < normalized.sourceIndex.length ? normalized.sourceIndex[end] : masked.length;
  for (var i = from; i < to && i < masked.length; i++) {
    masked[i] = true;
  }
}

/// Umple `masked` cu pozițiile de cenzurat, pentru o singură citire a
/// caracterelor ambigue. Apelată de două ori de [censorChatMessage], pe
/// același vector — rezultatele se cumulează.
void _maskProfanity(List<bool> masked, String input, Map<String, String> ambiguousLeet) {
  final normalized = _normalize(input, ambiguousLeet);
  if (normalized.text.isEmpty) return;

  // ── Pasul 1: rădăcini ancorate la început de cuvânt, căutate pe textul cu
  // separatorii scoși. Forma „strânsă" primește harta ei de poziții, ca să
  // putem verifica dacă potrivirea chiar începe un cuvânt și ca să știm ce
  // acoperim în original.
  final squashed = StringBuffer();
  final squashedIndex = <int>[]; // poziție în `normalized.text`
  for (var i = 0; i < normalized.text.length; i++) {
    if (normalized.text[i] == ' ') continue;
    squashed.write(normalized.text[i]);
    squashedIndex.add(i);
  }

  for (final match in _wordStartPattern.allMatches(squashed.toString())) {
    final startInNormalized = squashedIndex[match.start];
    final startsWord = startInNormalized == 0 || normalized.text[startInNormalized - 1] == ' ';
    if (!startsWord) continue;
    // Cenzura merge până la capătul CUVÂNTULUI, nu doar până la capătul
    // rădăcinii — altfel „pizdele" ar ieși „****ele", adică tot citibil, iar
    // asteriscurile ar fi doar decor.
    var wordEnd = squashedIndex[match.end - 1] + 1;
    while (wordEnd < normalized.text.length && normalized.text[wordEnd] != ' ') {
      wordEnd++;
    }
    _maskRange(masked, normalized, startInNormalized, wordEnd);
  }

  // ── Pasul 2: rădăcini permise doar ca și cuvânt complet, căutate pe textul
  // normalizat CU spații — acolo granița de cuvânt e exact ce le face sigure.
  for (final pattern in _exactWordPatterns) {
    for (final match in pattern.allMatches(normalized.text)) {
      // group(1) e cuvântul fără spațiul dinaintea lui, prins de `(?:^| )`.
      _maskRange(masked, normalized, match.end - match.group(1)!.length, match.end);
    }
  }
}

/// Textul cu injurii înlocuite prin asteriscuri. Restul mesajului (inclusiv
/// diacriticele și majusculele) rămâne exact cum a fost scris.
String censorChatMessage(String input) {
  if (input.isEmpty) return input;
  final masked = List<bool>.filled(input.length, false);
  // Cele două citiri ale lui `1`/`!` (vezi [_ambiguousLeet]) — se cenzurează
  // ce a găsit oricare dintre ele.
  _maskProfanity(masked, input, _ambiguousLeet);
  _maskProfanity(masked, input, _ambiguousLeetAlt);

  final out = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    out.write(masked[i] ? '*' : input[i]);
  }
  return out.toString();
}

/// True dacă mesajul conținea ceva de cenzurat — folosit ca să i se spună
/// autorului că mesajul lui a fost modificat, în loc să se trezească cu
/// asteriscuri fără explicație.
bool containsProfanity(String input) => censorChatMessage(input) != input;

/// Pregătește un mesaj pentru trimitere: taie spațiile de la capete, aduce
/// rândurile multiple la unul singur (o bulă de chat n-are de ce să fie
/// înaltă cât ecranul), limitează lungimea și cenzurează.
///
/// Se aplică ÎNAINTE de scrierea în Firestore, deliberat: cenzurarea doar la
/// afișare ar lăsa textul întreg în bază — de unde ajunge oricum pe ecranul
/// oricui deschide consola — iar un client mai vechi (sau modificat) l-ar
/// arăta neatins.
String sanitizeChatMessage(String input) {
  var text = input.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length > chatMessageMaxLength) {
    text = text.substring(0, chatMessageMaxLength).trimRight();
  }
  return censorChatMessage(text);
}
