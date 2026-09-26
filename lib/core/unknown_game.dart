/// „Unknown" (nume de lucru) — cursa pe numere din copilărie (Piticot,
/// Șerpi și scări, Jocul gâștei), cu întrebări și cu artefacte.
///
/// Drumul are câmpurile 1..[unknownFinish]. Toată masa răspunde DEODATĂ la
/// aceeași întrebare, iar răspunsul dă zarurile: greșit = un zar (tot
/// avansezi, nimeni nu rămâne pe loc), corect = două, cel mai rapid ia și
/// monede. Pe drum: scări (urci), șerpi (aluneci înapoi), „înapoi 3",
/// „stai o tură", trifoiul care îți dă imunitate, cufere cu artefacte care
/// se combină, dueluri, magazin, evenimente. Câștigă primul care ajunge la
/// [unknownFinish]. Fără „fix pe ultimul câmp": cu două zaruri, șansa să
/// nimerești exact era atât de mică încât finalul se târa 7-8 runde (măsurat
/// în test/unknown_game_test.dart) — tensiunea de final o dau șerpii.
///
/// Se joacă „toți deodată" (multiplayer și cu boți, prin același drum):
/// nimic nu oprește runda în mijloc ca să aștepte un singur jucător.
///  • duelul și întrebarea de aur se decid la URMĂTOAREA întrebare de masă;
///  • cufărul și magazinul rămân oferte în așteptare, alese cât se animă
///    runda și aplicate la închiderea rundei următoare ([resolveRound]).
///
/// Pur și determinist: toată aleatoriea vine dintr-un [StableRandom] (aceeași
/// secvență pe telefon și în browser), consumat în ordinea apelurilor, iar
/// starea lui se salvează cu restul jocului ([UnknownGame.toJson]).
library;

import 'dart:math';

import 'lang.dart';
import 'stable_hash.dart';

const int unknownFinish = 60;

/// Plafonul de siguranță: dacă nimeni n-a ajuns până atunci, câștigă cel
/// mai avansat. Un meci obișnuit se termină în jur de 8-10 runde.
const int unknownMaxRounds = 22;
const int unknownStartCoins = 10;
const int unknownQuestionSeconds = 15;
const int unknownMaxRelics = 3;
const int unknownMaxItems = 2;
const int unknownMinPlayers = 2;
const int unknownMaxPlayers = 6;

enum UnknownTile { normal, ladder, snake, back3, trap, clover, chest, event, duel, shop, coins, tax, finish }

/// Scările: de jos → sus.
const Map<int, int> unknownLadders = {3: 11, 8: 19, 20: 29, 27: 38, 36: 44, 43: 52};

/// Șerpii: de la cap → la coadă.
const Map<int, int> unknownSnakes = {17: 6, 25: 13, 34: 22, 41: 30, 49: 37, 57: 45};

const Map<int, UnknownTile> _special = {
  2: UnknownTile.coins,
  5: UnknownTile.chest,
  7: UnknownTile.shop,
  10: UnknownTile.event,
  12: UnknownTile.clover,
  14: UnknownTile.duel,
  15: UnknownTile.back3,
  16: UnknownTile.coins,
  18: UnknownTile.chest,
  21: UnknownTile.coins,
  23: UnknownTile.trap,
  24: UnknownTile.shop,
  26: UnknownTile.event,
  31: UnknownTile.back3,
  32: UnknownTile.chest,
  33: UnknownTile.coins,
  35: UnknownTile.duel,
  39: UnknownTile.clover,
  40: UnknownTile.event,
  42: UnknownTile.shop,
  46: UnknownTile.chest,
  47: UnknownTile.trap,
  48: UnknownTile.coins,
  50: UnknownTile.duel,
  51: UnknownTile.event,
  53: UnknownTile.back3,
  54: UnknownTile.tax,
  55: UnknownTile.chest,
  56: UnknownTile.coins,
  58: UnknownTile.coins,
  59: UnknownTile.tax,
};

UnknownTile unknownTileAt(int n) {
  if (n == unknownFinish) return UnknownTile.finish;
  if (unknownLadders.containsKey(n)) return UnknownTile.ladder;
  if (unknownSnakes.containsKey(n)) return UnknownTile.snake;
  return _special[n] ?? UnknownTile.normal;
}

T? _byName<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// Lista de nume din Firestore → valorile enum-ului; numele necunoscute
/// (de la o versiune mai nouă) se sar în loc să strice tot jocul.
List<T> _enumList<T extends Enum>(List<T> values, Object? raw) => [
      for (final n in (raw as List? ?? const []))
        if (_byName(values, n) case final v?) v,
    ];

// ─── Artefacte (pasive, maxim 3) ────────────────────────────────────────

enum UnknownRelic {
  scholar,
  onFire,
  magnet,
  umbrella,
  goldLadder,
  lightning,
  loadedDie,
  duelist,
  collector,
  echo,
  consolation,
}

String unknownRelicEmoji(UnknownRelic r) => switch (r) {
      UnknownRelic.scholar => '📚',
      UnknownRelic.onFire => '🔥',
      UnknownRelic.magnet => '🧲',
      UnknownRelic.umbrella => '☂️',
      UnknownRelic.goldLadder => '🪜',
      UnknownRelic.lightning => '⚡',
      UnknownRelic.loadedDie => '🎲',
      UnknownRelic.duelist => '⚔️',
      UnknownRelic.collector => '🏺',
      UnknownRelic.echo => '🔔',
      UnknownRelic.consolation => '🍀',
    };

String unknownRelicName(UnknownRelic r) => switch (r) {
      UnknownRelic.scholar => tr('Bibliotecarul', 'The Scholar'),
      UnknownRelic.onFire => tr('Seria de foc', 'On Fire'),
      UnknownRelic.magnet => tr('Magnetul', 'The Magnet'),
      UnknownRelic.umbrella => tr('Umbrela', 'The Umbrella'),
      UnknownRelic.goldLadder => tr('Scara de aur', 'Golden Ladder'),
      UnknownRelic.lightning => tr('Fulgerul', 'Lightning'),
      UnknownRelic.loadedDie => tr('Zarul trucat', 'Loaded Die'),
      UnknownRelic.duelist => tr('Duelistul', 'The Duelist'),
      UnknownRelic.collector => tr('Colecționarul', 'The Collector'),
      UnknownRelic.echo => tr('Ecoul', 'Echo'),
      UnknownRelic.consolation => tr('Trifoiul norocos', 'Lucky Clover'),
    };

String unknownRelicDesc(UnknownRelic r) => switch (r) {
      UnknownRelic.scholar => tr('+2 🪙 la fiecare răspuns corect', '+2 🪙 for every correct answer'),
      UnknownRelic.onFire =>
        tr('Răspunsuri corecte la rând: +1 pas pentru fiecare (max +3)', 'Correct answers in a row: +1 step each (max +3)'),
      UnknownRelic.magnet => tr('Când treci pe lângă cineva, îi iei 2 🪙', 'Passing someone steals 2 🪙 from them'),
      UnknownRelic.umbrella => tr('Șerpii te duc doar pe jumătate înapoi', 'Snakes only take you halfway back'),
      UnknownRelic.goldLadder => tr('Scările te urcă cu 3 câmpuri mai sus', 'Ladders take you 3 spaces higher'),
      UnknownRelic.lightning => tr('Cel mai rapid răspuns corect: +1 zar', 'Fastest correct answer: +1 die'),
      UnknownRelic.loadedDie => tr('Fața 1 a zarului devine 4', 'A rolled 1 becomes a 4'),
      UnknownRelic.duelist => tr('Duelurile câștigate iau dublu', 'Won duels steal double'),
      UnknownRelic.collector => tr('+1 🪙 pe rundă pentru fiecare artefact', '+1 🪙 per round for each relic'),
      UnknownRelic.echo => tr('Câmpurile cu monede dau dublu', 'Coin spaces pay double'),
      UnknownRelic.consolation => tr('Răspuns greșit: +2 🪙 și +1 pas', 'Wrong answer: +2 🪙 and +1 step'),
    };

// ─── Obiecte (consumabile, maxim 2) ─────────────────────────────────────

enum UnknownItem { extraDie, bigStep, shield, swap }

int unknownItemPrice(UnknownItem i) => switch (i) {
      UnknownItem.extraDie => 6,
      UnknownItem.bigStep => 7,
      UnknownItem.shield => 8,
      UnknownItem.swap => 12,
    };

String unknownItemEmoji(UnknownItem i) => switch (i) {
      UnknownItem.extraDie => '🎲',
      UnknownItem.bigStep => '👟',
      UnknownItem.shield => '🛡️',
      UnknownItem.swap => '🔀',
    };

String unknownItemName(UnknownItem i) => switch (i) {
      UnknownItem.extraDie => tr('Zar în plus', 'Extra Die'),
      UnknownItem.bigStep => tr('Cizme de 7 leghe', 'Seven-League Boots'),
      UnknownItem.shield => tr('Scutul', 'The Shield'),
      UnknownItem.swap => tr('Schimbul', 'The Swap'),
    };

String unknownItemDesc(UnknownItem i) => switch (i) {
      UnknownItem.extraDie => tr('Arunci un zar în plus', 'Roll one more die'),
      UnknownItem.bigStep => tr('+3 pași la mutare', '+3 steps on your move'),
      UnknownItem.shield => tr('Imunitate la următorul șarpe sau capcană', 'Immune to the next snake or trap'),
      UnknownItem.swap => tr('Schimbi locul cu cel din fața ta', 'Swap places with the player ahead'),
    };

// ─── Evenimente (câmpul „?") ────────────────────────────────────────────

enum UnknownEvent { coinRain, whirl, luckTax, gust, freeItem, robinHood, quake, goldenQuestion }

String unknownEventTitle(UnknownEvent e) => switch (e) {
      UnknownEvent.coinRain => tr('Ploaie de monede!', 'Coin rain!'),
      UnknownEvent.whirl => tr('Vârtejul!', 'The Whirl!'),
      UnknownEvent.luckTax => tr('Taxa norocului', 'Luck tax'),
      UnknownEvent.gust => tr('Rafală de vânt!', 'Gust of wind!'),
      UnknownEvent.freeItem => tr('Cadou pe drum', 'Gift on the road'),
      UnknownEvent.robinHood => tr('Robin Hood', 'Robin Hood'),
      UnknownEvent.quake => tr('Cutremur!', 'Earthquake!'),
      UnknownEvent.goldenQuestion => tr('Întrebarea de aur', 'The golden question'),
    };

String unknownEventDesc(UnknownEvent e) => switch (e) {
      UnknownEvent.coinRain => tr('Toată lumea +3 🪙, cine a picat aici +6', 'Everyone +3 🪙, whoever landed here +6'),
      UnknownEvent.whirl => tr('Schimbă locul cu cineva la întâmplare', 'Swaps places with a random player'),
      UnknownEvent.luckTax => tr('Dă 5 🪙 celui mai sărac', 'Gives 5 🪙 to the poorest player'),
      UnknownEvent.gust => tr('Vântul îl duce 4 câmpuri înainte', 'The wind carries them 4 spaces ahead'),
      UnknownEvent.freeItem => tr('Un obiect gratis', 'A free item'),
      UnknownEvent.robinHood => tr('Ia 5 🪙 de la cel mai bogat', 'Takes 5 🪙 from the richest'),
      UnknownEvent.quake => tr('Toți ceilalți dau înapoi 2 câmpuri', 'Everyone else falls back 2 spaces'),
      UnknownEvent.goldenQuestion =>
        tr('La următoarea întrebare: corect = +4 câmpuri', 'On the next question: right = +4 spaces'),
    };

// ─── Ce s-a întâmplat pe câmp (textul îl face fiecare ecran în limba lui) ─

enum UnknownNote { ladder, snake, snakeBlocked, back3, back3Blocked, trap, trapBlocked, clover, cloverCoins, skipped }

String unknownNoteText(UnknownNote n, int from, int to) => switch (n) {
      UnknownNote.ladder => tr('🪜 Scara! $from → $to', '🪜 A ladder! $from → $to'),
      UnknownNote.snake => tr('🐍 Șarpele! $from → $to', '🐍 A snake! $from → $to'),
      UnknownNote.snakeBlocked => tr('🛡️ Imunitate! Șarpele nu prinde', '🛡️ Immune! The snake misses'),
      UnknownNote.back3 => tr('⬅️ Înapoi 3!', '⬅️ Back 3!'),
      UnknownNote.back3Blocked => tr('🛡️ Imunitate! Rămâne pe loc', '🛡️ Immune! Stays put'),
      UnknownNote.trap => tr('🕸️ Capcană: stă o tură', '🕸️ Trap: skips a turn'),
      UnknownNote.trapBlocked => tr('🛡️ Imunitate! Capcana nu ține', '🛡️ Immune! The trap can\'t hold'),
      UnknownNote.clover => tr('🍀 Trifoi: imunitate la următorul necaz', '🍀 Clover: immune to the next trouble'),
      UnknownNote.cloverCoins => tr('🍀 Trifoi: avea deja imunitate, +3 🪙', '🍀 Clover: already immune, +3 🪙'),
      UnknownNote.skipped => tr('⏸️ Stă o tură (capcana)', '⏸️ Sits this one out (the trap)'),
    };

// ─── Starea jocului ─────────────────────────────────────────────────────

class UnknownPlayer {
  UnknownPlayer({required this.id, required this.name, required this.isBot, required this.colorIndex});

  final String id;
  final String name;
  final bool isBot;
  final int colorIndex;

  /// 0 = la START (în afara drumului), [unknownFinish] = a ajuns.
  int pos = 0;
  int coins = unknownStartCoins;
  int streak = 0;

  /// Imunitate la următorul șarpe / „înapoi 3" / capcană.
  bool shielded = false;

  /// A picat pe „stai o tură": nu se mută la runda următoare.
  bool skipNext = false;

  /// A plecat din meci: rămâne în clasament unde a rămas, dar nu mai joacă.
  bool left = false;

  /// Runda în care a ajuns la final (null = încă pe drum).
  int? finishedRound;

  /// Al câtelea a ajuns (0 = primul).
  int? finishOrder;

  final List<UnknownRelic> relics = [];
  final List<UnknownItem> items = [];

  /// Obiectul pregătit pentru mutarea următoare (se consumă la ea).
  UnknownItem? armed;

  int correct = 0;
  int duelsWon = 0;

  bool get finished => pos >= unknownFinish;

  /// Încă în cursă: nici ajuns, nici plecat.
  bool get racing => !finished && !left;
  bool has(UnknownRelic r) => relics.contains(r);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bot': isBot,
        'color': colorIndex,
        'pos': pos,
        'coins': coins,
        'streak': streak,
        'shield': shielded,
        'skip': skipNext,
        'left': left,
        'fr': finishedRound,
        'fo': finishOrder,
        'relics': [for (final r in relics) r.name],
        'items': [for (final i in items) i.name],
        'armed': armed?.name,
        'correct': correct,
        'duels': duelsWon,
      };

  factory UnknownPlayer.fromJson(Map<String, dynamic> j) {
    int n(String k, [int d = 0]) => (j[k] as num?)?.toInt() ?? d;
    final p = UnknownPlayer(
      id: j['id'] as String,
      name: j['name'] as String? ?? '?',
      isBot: j['bot'] as bool? ?? false,
      colorIndex: n('color'),
    )
      ..pos = n('pos')
      ..coins = n('coins', unknownStartCoins)
      ..streak = n('streak')
      ..shielded = j['shield'] as bool? ?? false
      ..skipNext = j['skip'] as bool? ?? false
      ..left = j['left'] as bool? ?? false
      ..finishedRound = (j['fr'] as num?)?.toInt()
      ..finishOrder = (j['fo'] as num?)?.toInt()
      ..armed = _byName(UnknownItem.values, j['armed'])
      ..correct = n('correct')
      ..duelsWon = n('duels');
    for (final r in (j['relics'] as List? ?? const [])) {
      final v = _byName(UnknownRelic.values, r);
      if (v != null) p.relics.add(v);
    }
    for (final i in (j['items'] as List? ?? const [])) {
      final v = _byName(UnknownItem.values, i);
      if (v != null) p.items.add(v);
    }
    return p;
  }
}

/// Cheia de clasament: cine a ajuns (în ordinea sosirii) înaintea oricui
/// încă pe drum; pe drum, cine e mai departe; apoi monedele. Aceeași ordine
/// ca [UnknownGame.standings], ca număr — ecranul de rezultate sortează după el.
int unknownRankKey(UnknownPlayer p) {
  final fo = p.finishOrder;
  if (fo != null) return 10000000 - fo * 100000;
  return p.pos * 1000 + min(p.coins, 999);
}

/// Un efect de arătat pe hartă (monede care zboară, un simbol). Etichetele
/// sunt simboluri, nu text — ajung la toți jucătorii, în orice limbă.
class UnknownFx {
  const UnknownFx(this.playerId, this.label, {this.coins = 0});

  final String playerId;
  final String label;
  final int coins;

  Map<String, dynamic> toJson() => {'p': playerId, 'l': label, 'c': coins};

  factory UnknownFx.fromJson(Map<String, dynamic> j) =>
      UnknownFx(j['p'] as String, j['l'] as String? ?? '', coins: (j['c'] as num?)?.toInt() ?? 0);
}

List<Map<String, dynamic>> _fxJson(List<UnknownFx> fx) => [for (final f in fx) f.toJson()];
List<UnknownFx> _fxFrom(Object? raw) => [
      for (final f in (raw as List? ?? const [])) UnknownFx.fromJson(Map<String, dynamic>.from(f as Map)),
    ];

class UnknownAnswer {
  const UnknownAnswer({required this.correct, required this.ms});

  final bool correct;
  final int ms;
}

class UnknownRoll {
  UnknownRoll({
    required this.playerId,
    required this.dice,
    required this.bonus,
    required this.labels,
    required this.fastest,
    this.skipped = false,
  });

  final String playerId;
  final List<int> dice;
  final int bonus;

  /// De unde vine bonusul, ca să-l arătăm („🔥 +2", „👟 +3").
  final List<String> labels;
  final bool fastest;

  /// „Stai o tură": nu se mută runda asta.
  final bool skipped;

  int get total => skipped ? 0 : dice.fold(0, (a, b) => a + b) + bonus;
}

/// Cum ajunge pionul pe [UnknownHop.tile]: pas cu pas, pe scară, pe șarpe
/// sau dintr-un salt (înapoi 3, vânt, schimb de locuri).
enum UnknownHopKind { walk, ladder, snake, jump }

class UnknownHop {
  const UnknownHop(this.tile, this.kind, [this.fx = const []]);

  final int tile;
  final UnknownHopKind kind;
  final List<UnknownFx> fx;

  Map<String, dynamic> toJson() => {'t': tile, 'k': kind.name, if (fx.isNotEmpty) 'fx': _fxJson(fx)};

  factory UnknownHop.fromJson(Map<String, dynamic> j) => UnknownHop(
        (j['t'] as num).toInt(),
        _byName(UnknownHopKind.values, j['k']) ?? UnknownHopKind.walk,
        _fxFrom(j['fx']),
      );
}

enum UnknownLandingKind { none, chest, shop, duel, goldenQuestion }

class UnknownLanding {
  const UnknownLanding({
    required this.kind,
    this.fx = const [],
    this.relicOffers = const [],
    this.itemOffers = const [],
    this.opponentId,
    this.event,
    this.note,
    this.noteFrom = 0,
    this.noteTo = 0,
  });

  final UnknownLandingKind kind;
  final List<UnknownFx> fx;
  final List<UnknownRelic> relicOffers;
  final List<UnknownItem> itemOffers;
  final String? opponentId;
  final UnknownEvent? event;

  /// Ce s-a întâmplat pe câmp; textul îl face [unknownNoteText].
  final UnknownNote? note;
  final int noteFrom;
  final int noteTo;

  String? get noteText => note == null ? null : unknownNoteText(note!, noteFrom, noteTo);
}

class UnknownMove {
  const UnknownMove(this.hops, this.landing);

  final List<UnknownHop> hops;
  final UnknownLanding landing;
}

// ─── Jurnalul rundei (ce animă toate ecranele) ──────────────────────────

/// Poziția și monedele fiecăruia, după un pas al rundei — ecranul arată
/// cifrele pe măsură ce se întâmplă, nu direct pe cele de la final.
Map<String, List<int>> _snapshot(List<UnknownPlayer> players) => {
      for (final p in players) p.id: [p.pos, p.coins],
    };

Map<String, dynamic> _snapJson(Map<String, List<int>> s) => {for (final e in s.entries) e.key: e.value};
Map<String, List<int>> _snapFrom(Object? raw) => {
      for (final e in (raw as Map? ?? const {}).entries)
        e.key as String: [for (final v in (e.value as List)) (v as num).toInt()],
    };

/// Mutarea unui jucător, cu tot ce trebuie ca s-o animezi.
class UnknownMoveLog {
  const UnknownMoveLog({required this.roll, required this.move, required this.after});

  final UnknownRoll roll;
  final UnknownMove move;
  final Map<String, List<int>> after;

  Map<String, dynamic> toJson() {
    final l = move.landing;
    return {
      'id': roll.playerId,
      'd': roll.dice,
      'b': roll.bonus,
      'lb': roll.labels,
      'f': roll.fastest,
      's': roll.skipped,
      'h': [for (final h in move.hops) h.toJson()],
      'lk': l.kind.name,
      if (l.fx.isNotEmpty) 'lfx': _fxJson(l.fx),
      if (l.relicOffers.isNotEmpty) 'ro': [for (final r in l.relicOffers) r.name],
      if (l.itemOffers.isNotEmpty) 'io': [for (final i in l.itemOffers) i.name],
      if (l.opponentId != null) 'op': l.opponentId,
      if (l.event != null) 'ev': l.event!.name,
      if (l.note != null) 'n': l.note!.name,
      'nf': l.noteFrom,
      'nt': l.noteTo,
      'a': _snapJson(after),
    };
  }

  factory UnknownMoveLog.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    return UnknownMoveLog(
      roll: UnknownRoll(
        playerId: id,
        dice: [for (final d in (j['d'] as List? ?? const [])) (d as num).toInt()],
        bonus: (j['b'] as num?)?.toInt() ?? 0,
        labels: List<String>.from(j['lb'] as List? ?? const []),
        fastest: j['f'] as bool? ?? false,
        skipped: j['s'] as bool? ?? false,
      ),
      move: UnknownMove(
        [for (final h in (j['h'] as List? ?? const [])) UnknownHop.fromJson(Map<String, dynamic>.from(h as Map))],
        UnknownLanding(
          kind: _byName(UnknownLandingKind.values, j['lk']) ?? UnknownLandingKind.none,
          fx: _fxFrom(j['lfx']),
          relicOffers: _enumList(UnknownRelic.values, j['ro']),
          itemOffers: _enumList(UnknownItem.values, j['io']),
          opponentId: j['op'] as String?,
          event: _byName(UnknownEvent.values, j['ev']),
          note: _byName(UnknownNote.values, j['n']),
          noteFrom: (j['nf'] as num?)?.toInt() ?? 0,
          noteTo: (j['nt'] as num?)?.toInt() ?? 0,
        ),
      ),
      after: _snapFrom(j['a']),
    );
  }
}

/// Alegerea făcută la cufăr sau la magazin (null = nimic).
class UnknownChoiceLog {
  const UnknownChoiceLog({required this.playerId, required this.chest, this.relic, this.drop, this.item});

  final String playerId;
  final bool chest;
  final UnknownRelic? relic;
  final UnknownRelic? drop;
  final UnknownItem? item;

  Map<String, dynamic> toJson() => {
        'id': playerId,
        'c': chest,
        if (relic != null) 'r': relic!.name,
        if (drop != null) 'x': drop!.name,
        if (item != null) 'i': item!.name,
      };

  factory UnknownChoiceLog.fromJson(Map<String, dynamic> j) => UnknownChoiceLog(
        playerId: j['id'] as String,
        chest: j['c'] as bool? ?? true,
        relic: _byName(UnknownRelic.values, j['r']),
        drop: _byName(UnknownRelic.values, j['x']),
        item: _byName(UnknownItem.values, j['i']),
      );
}

class UnknownDuelLog {
  const UnknownDuelLog({required this.attackerId, required this.defenderId, required this.winnerId, required this.fx});

  final String attackerId;
  final String defenderId;
  final String? winnerId;
  final List<UnknownFx> fx;

  Map<String, dynamic> toJson() => {'a': attackerId, 'd': defenderId, 'w': winnerId, 'fx': _fxJson(fx)};

  factory UnknownDuelLog.fromJson(Map<String, dynamic> j) => UnknownDuelLog(
        attackerId: j['a'] as String,
        defenderId: j['d'] as String,
        winnerId: j['w'] as String?,
        fx: _fxFrom(j['fx']),
      );
}

/// Tot ce s-a întâmplat într-o rundă, în ordinea în care se animă:
/// alegerile din runda trecută, duelurile și întrebările de aur decise de
/// întrebarea asta, monedele de la răspunsuri, apoi mutările pe rând.
class UnknownRoundLog {
  const UnknownRoundLog({
    required this.round,
    required this.choices,
    required this.duels,
    required this.golden,
    required this.answerFx,
    required this.prelude,
    required this.moves,
  });

  final int round;
  final List<UnknownChoiceLog> choices;
  final List<UnknownDuelLog> duels;

  /// Întrebările de aur decise acum: id → a nimerit.
  final Map<String, bool> golden;
  final List<UnknownFx> answerFx;

  /// Pozițiile și monedele după tot ce vine înaintea mutărilor.
  final Map<String, List<int>> prelude;
  final List<UnknownMoveLog> moves;

  Map<String, dynamic> toJson() => {
        'r': round,
        'ch': [for (final c in choices) c.toJson()],
        'du': [for (final d in duels) d.toJson()],
        'go': golden,
        'afx': _fxJson(answerFx),
        'pre': _snapJson(prelude),
        'mv': [for (final m in moves) m.toJson()],
      };

  factory UnknownRoundLog.fromJson(Map<String, dynamic> j) => UnknownRoundLog(
        round: (j['r'] as num?)?.toInt() ?? 0,
        choices: [for (final c in (j['ch'] as List? ?? const [])) UnknownChoiceLog.fromJson(Map<String, dynamic>.from(c as Map))],
        duels: [for (final d in (j['du'] as List? ?? const [])) UnknownDuelLog.fromJson(Map<String, dynamic>.from(d as Map))],
        golden: {for (final e in (j['go'] as Map? ?? const {}).entries) e.key as String: e.value as bool},
        answerFx: _fxFrom(j['afx']),
        prelude: _snapFrom(j['pre']),
        moves: [for (final m in (j['mv'] as List? ?? const [])) UnknownMoveLog.fromJson(Map<String, dynamic>.from(m as Map))],
      );
}

/// O ofertă de cufăr sau magazin care așteaptă alegerea jucătorului.
class UnknownOffer {
  const UnknownOffer({required this.chest, this.relics = const [], this.items = const []});

  final bool chest;
  final List<UnknownRelic> relics;
  final List<UnknownItem> items;

  Map<String, dynamic> toJson() => {
        'c': chest,
        if (relics.isNotEmpty) 'r': [for (final r in relics) r.name],
        if (items.isNotEmpty) 'i': [for (final i in items) i.name],
      };

  factory UnknownOffer.fromJson(Map<String, dynamic> j) => UnknownOffer(
        chest: j['c'] as bool? ?? true,
        relics: _enumList(UnknownRelic.values, j['r']),
        items: _enumList(UnknownItem.values, j['i']),
      );
}

/// Alegerea trimisă de jucător pentru oferta lui. Pe fir: `""` = nimic,
/// `"numeArtefact"`, `"numeArtefact|artefactDeLăsat"` sau `"numeObiect"`.
class UnknownChoice {
  const UnknownChoice({this.take, this.drop});

  final String? take;
  final String? drop;

  static const none = UnknownChoice();

  String encode() => take == null ? '' : (drop == null ? take! : '$take|$drop');

  factory UnknownChoice.decode(String raw) {
    if (raw.isEmpty) return none;
    final parts = raw.split('|');
    return UnknownChoice(take: parts[0], drop: parts.length > 1 ? parts[1] : null);
  }
}

class UnknownGame {
  UnknownGame({required this.players, required int seed, this.maxRounds = unknownMaxRounds}) : _rng = StableRandom(seed);

  UnknownGame._(this.players, this._rng, this.maxRounds);

  final List<UnknownPlayer> players;
  final int maxRounds;
  final StableRandom _rng;

  int round = 0;
  int _finishers = 0;

  /// Dueluri decise de următoarea întrebare: (atacator, apărător).
  final List<(String, String)> pendingDuels = [];

  /// Cine are întrebarea de aur la următoarea întrebare.
  final List<String> pendingGolden = [];

  /// Oferte de cufăr/magazin care așteaptă alegerea (se aplică la
  /// următorul [resolveRound]).
  final Map<String, UnknownOffer> pendingOffers = {};

  /// Meciul se încheie la finalul rundei în care a ajuns primul — ceilalți
  /// își termină mutarea din runda aia (au răspuns la aceeași întrebare).
  /// Sau când a rămas un singur jucător la masă (ceilalți au plecat).
  bool get isOver =>
      round >= maxRounds ||
      players.any((p) => p.finished && p.finishedRound! < round) ||
      players.where((p) => !p.left).length < unknownMinPlayers;

  UnknownPlayer player(String id) => players.firstWhere((p) => p.id == id);

  Map<String, dynamic> toJson() => {
        'rng': _rng.state,
        'round': round,
        'fin': _finishers,
        'max': maxRounds,
        'players': [for (final p in players) p.toJson()],
        // Obiecte, nu perechi `[a, d]`: Firestore refuză liste în liste.
        'duels': [for (final (a, d) in pendingDuels) {'a': a, 'd': d}],
        'golden': pendingGolden,
        'offers': {for (final e in pendingOffers.entries) e.key: e.value.toJson()},
      };

  factory UnknownGame.fromJson(Map<String, dynamic> j) {
    final g = UnknownGame._(
      [for (final p in (j['players'] as List)) UnknownPlayer.fromJson(Map<String, dynamic>.from(p as Map))],
      StableRandom((j['rng'] as num).toInt()),
      (j['max'] as num?)?.toInt() ?? unknownMaxRounds,
    )
      ..round = (j['round'] as num?)?.toInt() ?? 0
      .._finishers = (j['fin'] as num?)?.toInt() ?? 0;
    for (final d in (j['duels'] as List? ?? const [])) {
      final pair = Map<String, dynamic>.from(d as Map);
      g.pendingDuels.add((pair['a'] as String, pair['d'] as String));
    }
    g.pendingGolden.addAll(List<String>.from(j['golden'] as List? ?? const []));
    for (final e in (j['offers'] as Map? ?? const {}).entries) {
      g.pendingOffers[e.key as String] = UnknownOffer.fromJson(Map<String, dynamic>.from(e.value as Map));
    }
    return g;
  }

  /// Clasamentul: cine a ajuns, în ordinea sosirii; apoi cine e mai departe;
  /// apoi monedele; la egalitate rămâne ordinea mesei.
  List<UnknownPlayer> standings() {
    final order = {for (var i = 0; i < players.length; i++) players[i].id: i};
    return List.of(players)
      ..sort((a, b) {
        final k = unknownRankKey(b).compareTo(unknownRankKey(a));
        if (k != 0) return k;
        return order[a.id]!.compareTo(order[b.id]!);
      });
  }

  /// Ultimul primește „vânt din spate" (+2 pași). Nimeni în prima rundă sau
  /// când toți sunt pe același câmp.
  UnknownPlayer? tailwindPlayer() {
    final racing = [for (final p in players) if (p.racing) p];
    if (round == 0 || racing.length < 2) return null;
    final minPos = racing.map((p) => p.pos).reduce(min);
    final maxPos = players.where((p) => !p.left).map((p) => p.pos).reduce(max);
    if (minPos == maxPos) return null;
    return racing.lastWhere((p) => p.pos == minPos);
  }

  UnknownPlayer? richestExcept(UnknownPlayer except) {
    UnknownPlayer? best;
    for (final q in players) {
      if (q.id == except.id || q.left) continue;
      if (best == null || q.coins > best.coins) best = q;
    }
    return best;
  }

  /// Cel mai apropiat jucător din fața lui [p] (pentru Schimb).
  UnknownPlayer? nearestAhead(UnknownPlayer p) {
    UnknownPlayer? best;
    for (final q in players) {
      if (q.id == p.id || !q.racing || q.pos <= p.pos) continue;
      if (best == null || q.pos < best.pos) best = q;
    }
    return best;
  }

  void _gain(UnknownPlayer p, int amount, List<UnknownFx> fx, String label) {
    if (amount == 0) return;
    p.coins = max(0, p.coins + amount);
    fx.add(UnknownFx(p.id, label, coins: amount));
  }

  int _steal(UnknownPlayer to, UnknownPlayer from, int amount, List<UnknownFx> fx, String label) {
    final taken = min(amount, from.coins);
    if (taken <= 0) return 0;
    from.coins -= taken;
    to.coins += taken;
    fx.add(UnknownFx(from.id, label, coins: -taken));
    fx.add(UnknownFx(to.id, label, coins: taken));
    return taken;
  }

  // ─── Runda întreagă ────────────────────────────────────────────────────

  /// Rezolvă o rundă „toți deodată", în ordinea în care se și animă:
  ///  1. alegerile de la cufăr/magazin din runda trecută ([choices]);
  ///  2. obiectele pregătite ([arms]);
  ///  3. duelurile și întrebările de aur în așteptare, decise de [answers];
  ///  4. zarurile și monedele de la răspunsuri;
  ///  5. mutările, pe rând — cuferele/magazinele de acum devin oferte noi,
  ///     duelurile și întrebările de aur de acum așteaptă runda următoare.
  UnknownRoundLog resolveRound(
    Map<String, UnknownAnswer> answers, {
    Map<String, UnknownItem> arms = const {},
    Map<String, UnknownChoice> choices = const {},
  }) {
    final choiceLogs = _applyChoices(choices);

    for (final p in players) {
      final item = arms[p.id];
      if (item != null && p.racing && p.armed != item) arm(p, item);
    }

    final duelLogs = <UnknownDuelLog>[];
    for (final (a, d) in pendingDuels) {
      final attacker = player(a);
      final defender = player(d);
      if (attacker.left || defender.left) continue;
      const miss = UnknownAnswer(correct: false, ms: 1 << 30);
      final res = resolveDuel(attacker, defender, answers[a] ?? miss, answers[d] ?? miss);
      duelLogs.add(UnknownDuelLog(attackerId: a, defenderId: d, winnerId: res.winnerId, fx: res.fx));
    }
    pendingDuels.clear();

    final golden = <String, bool>{};
    for (final id in pendingGolden) {
      final p = player(id);
      if (!p.racing) continue;
      golden[id] = resolveGolden(p, answers[id]?.correct == true);
    }
    pendingGolden.clear();

    final res = resolveAnswers(answers);
    final prelude = _snapshot(players);

    final moves = <UnknownMoveLog>[];
    for (final id in moveOrder(answers)) {
      final p = player(id);
      final roll = res.rolls[id]!;
      final m = move(p, roll);
      switch (m.landing.kind) {
        case UnknownLandingKind.chest:
          pendingOffers[id] = UnknownOffer(chest: true, relics: m.landing.relicOffers);
        case UnknownLandingKind.shop:
          pendingOffers[id] = UnknownOffer(chest: false, items: m.landing.itemOffers);
        case UnknownLandingKind.duel:
          pendingDuels.add((id, m.landing.opponentId!));
        case UnknownLandingKind.goldenQuestion:
          pendingGolden.add(id);
        case UnknownLandingKind.none:
          break;
      }
      moves.add(UnknownMoveLog(roll: roll, move: m, after: _snapshot(players)));
    }

    final log = UnknownRoundLog(
      round: round,
      choices: choiceLogs,
      duels: duelLogs,
      golden: golden,
      answerFx: res.fx,
      prelude: prelude,
      moves: moves,
    );
    endRound();
    return log;
  }

  List<UnknownChoiceLog> _applyChoices(Map<String, UnknownChoice> choices) {
    final out = <UnknownChoiceLog>[];
    for (final p in players) {
      final offer = pendingOffers[p.id];
      if (offer == null) continue;
      final c = choices[p.id] ?? UnknownChoice.none;
      if (offer.chest) {
        final relic = _byName(offer.relics, c.take);
        var drop = _byName(p.relics, c.drop);
        var take = relic;
        if (take != null && p.relics.length >= unknownMaxRelics && drop == null) take = null;
        if (take == null) drop = null;
        takeRelic(p, take, drop: drop);
        out.add(UnknownChoiceLog(playerId: p.id, chest: true, relic: take, drop: drop));
      } else {
        final item = _byName(offer.items, c.take);
        final bought = item != null && buyItem(p, item);
        out.add(UnknownChoiceLog(playerId: p.id, chest: false, item: bought ? item : null));
      }
    }
    pendingOffers.clear();
    return out;
  }

  // ─── Faza de răspuns → zaruri ──────────────────────────────────────────

  /// Ordinea mutărilor: întâi cei care au răspuns corect, după viteză, apoi
  /// ceilalți. Cine a ajuns sau a plecat nu se mai mută.
  List<String> moveOrder(Map<String, UnknownAnswer> answers) {
    int rank(UnknownPlayer p) => answers[p.id]?.correct == true ? 0 : 1;
    int ms(UnknownPlayer p) => answers[p.id]?.ms ?? 1 << 30;
    final idx = {for (var i = 0; i < players.length; i++) players[i].id: i};
    final list = [for (final p in players) if (p.racing) p]
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        final t = ms(a).compareTo(ms(b));
        if (t != 0) return t;
        return idx[a.id]!.compareTo(idx[b.id]!);
      });
    return [for (final p in list) p.id];
  }

  /// Transformă răspunsurile rundei în zaruri, bonusuri și monede. Lipsa
  /// răspunsului (a expirat timpul) contează ca greșit: tot un zar.
  ({Map<String, UnknownRoll> rolls, List<UnknownFx> fx}) resolveAnswers(Map<String, UnknownAnswer> answers) {
    final fx = <UnknownFx>[];
    final tailwind = tailwindPlayer();
    String? fastestId;
    var best = 1 << 30;
    for (final p in players) {
      final a = answers[p.id];
      if (p.racing && a != null && a.correct && a.ms < best) {
        best = a.ms;
        fastestId = p.id;
      }
    }

    final rolls = <String, UnknownRoll>{};
    for (final p in players) {
      if (!p.racing) continue;
      final correct = answers[p.id]?.correct == true;
      final fastest = p.id == fastestId;
      final labels = <String>[];
      var bonus = 0;

      if (correct) {
        p.correct++;
        p.streak++;
        if (p.has(UnknownRelic.scholar)) _gain(p, 2, fx, '📚');
      } else {
        p.streak = 0;
        if (p.has(UnknownRelic.consolation)) {
          _gain(p, 2, fx, '🍀');
          bonus += 1;
          labels.add('🍀 +1');
        }
      }
      if (fastest) _gain(p, 3, fx, '⚡');
      if (p.has(UnknownRelic.collector)) _gain(p, p.relics.length, fx, '🏺');

      if (p.skipNext) {
        p.skipNext = false;
        rolls[p.id] = UnknownRoll(playerId: p.id, dice: const [], bonus: 0, labels: const [], fastest: fastest, skipped: true);
        continue;
      }

      var diceCount = correct ? 2 : 1;
      if (fastest && p.has(UnknownRelic.lightning)) diceCount++;

      final armed = p.armed;
      p.armed = null;
      switch (armed) {
        case UnknownItem.extraDie:
          diceCount++;
        case UnknownItem.bigStep:
          bonus += 3;
          labels.add('👟 +3');
        case UnknownItem.shield:
          p.shielded = true;
          fx.add(UnknownFx(p.id, '🛡️'));
        case UnknownItem.swap:
          final ahead = nearestAhead(p);
          if (ahead != null) {
            final tmp = p.pos;
            p.pos = ahead.pos;
            ahead.pos = tmp;
            fx.add(UnknownFx(p.id, '🔀'));
            fx.add(UnknownFx(ahead.id, '🔀'));
          } else {
            p.items.add(UnknownItem.swap);
          }
        case null:
          break;
      }

      if (correct && p.has(UnknownRelic.onFire) && p.streak >= 2) {
        final fire = min(p.streak - 1, 3);
        bonus += fire;
        labels.add('🔥 +$fire');
      }
      if (tailwind != null && tailwind.id == p.id) {
        bonus += 2;
        labels.add('🌬️ +2');
      }

      final dice = <int>[];
      for (var i = 0; i < diceCount; i++) {
        var d = 1 + _rng.nextInt(6);
        if (d == 1 && p.has(UnknownRelic.loadedDie)) d = 4;
        dice.add(d);
      }
      rolls[p.id] = UnknownRoll(playerId: p.id, dice: dice, bonus: bonus, labels: labels, fastest: fastest);
    }
    return (rolls: rolls, fx: fx);
  }

  // ─── Mutarea ───────────────────────────────────────────────────────────

  List<UnknownFx> _passFx(UnknownPlayer p, int tile) {
    final fx = <UnknownFx>[];
    if (p.has(UnknownRelic.magnet)) {
      for (final q in players) {
        if (q.id != p.id && !q.left && q.pos == tile && tile > 0) _steal(p, q, 2, fx, '🧲');
      }
    }
    return fx;
  }

  /// Pașii de mers; pe [unknownFinish] se oprește, restul zarului se pierde.
  List<UnknownHop> _walk(UnknownPlayer p, int steps) {
    final hops = <UnknownHop>[];
    for (var i = 0; i < steps && p.pos < unknownFinish; i++) {
      p.pos++;
      hops.add(UnknownHop(p.pos, UnknownHopKind.walk, _passFx(p, p.pos)));
    }
    return hops;
  }

  /// Mută [p] cu zarurile din [roll] și aplică efectul câmpului. Scările,
  /// șerpii și „înapoi 3" se aplică o singură dată (nu în lanț).
  UnknownMove move(UnknownPlayer p, UnknownRoll roll) {
    if (roll.skipped) {
      return const UnknownMove([], UnknownLanding(kind: UnknownLandingKind.none, note: UnknownNote.skipped));
    }
    final hops = _walk(p, max(1, roll.total));
    UnknownNote? note;
    var from = p.pos;
    var to = p.pos;
    final fx = <UnknownFx>[];

    switch (unknownTileAt(p.pos)) {
      case UnknownTile.ladder:
        to = unknownLadders[p.pos]!;
        if (p.has(UnknownRelic.goldLadder)) to = min(unknownFinish - 1, to + 3);
        p.pos = to;
        hops.add(UnknownHop(to, UnknownHopKind.ladder));
        note = UnknownNote.ladder;
      case UnknownTile.snake:
        if (_shieldBlocks(p)) {
          note = UnknownNote.snakeBlocked;
        } else {
          to = unknownSnakes[p.pos]!;
          if (p.has(UnknownRelic.umbrella)) to = from - (from - to) ~/ 2;
          p.pos = to;
          hops.add(UnknownHop(to, UnknownHopKind.snake));
          note = UnknownNote.snake;
        }
      case UnknownTile.back3:
        if (_shieldBlocks(p)) {
          note = UnknownNote.back3Blocked;
        } else {
          p.pos = max(1, p.pos - 3);
          to = p.pos;
          hops.add(UnknownHop(p.pos, UnknownHopKind.jump));
          note = UnknownNote.back3;
        }
      case UnknownTile.trap:
        if (_shieldBlocks(p)) {
          note = UnknownNote.trapBlocked;
        } else {
          p.skipNext = true;
          note = UnknownNote.trap;
        }
      case UnknownTile.clover:
        if (p.shielded) {
          _gain(p, 3, fx, '🍀');
          note = UnknownNote.cloverCoins;
        } else {
          p.shielded = true;
          note = UnknownNote.clover;
        }
      default:
        break;
    }

    if (p.pos >= unknownFinish && p.finishedRound == null) {
      p.finishedRound = round;
      p.finishOrder = _finishers++;
    }
    return UnknownMove(hops, _land(p, fx, note, from, to));
  }

  bool _shieldBlocks(UnknownPlayer p) {
    if (!p.shielded) return false;
    p.shielded = false;
    return true;
  }

  UnknownLanding _land(UnknownPlayer p, List<UnknownFx> fx, UnknownNote? note, int from, int to) {
    UnknownLanding plain({
      UnknownLandingKind kind = UnknownLandingKind.none,
      List<UnknownRelic> relics = const [],
      List<UnknownItem> items = const [],
      String? opp,
      UnknownEvent? event,
      List<UnknownFx>? effects,
    }) =>
        UnknownLanding(
          kind: kind,
          fx: effects ?? fx,
          relicOffers: relics,
          itemOffers: items,
          opponentId: opp,
          event: event,
          note: note,
          noteFrom: from,
          noteTo: to,
        );

    final echo = p.has(UnknownRelic.echo) ? 2 : 1;
    switch (unknownTileAt(p.pos)) {
      case UnknownTile.coins:
        _gain(p, 3 * echo, fx, '');
      case UnknownTile.tax:
        _gain(p, -3, fx, '');
      case UnknownTile.chest:
        return plain(kind: UnknownLandingKind.chest, relics: _relicOffers(p));
      case UnknownTile.shop:
        return plain(kind: UnknownLandingKind.shop, items: _itemOffers());
      case UnknownTile.duel:
        final opp = richestExcept(p);
        if (opp != null) return plain(kind: UnknownLandingKind.duel, opp: opp.id);
      case UnknownTile.event:
        final (event, efx) = _event(p);
        if (event == UnknownEvent.goldenQuestion) return plain(kind: UnknownLandingKind.goldenQuestion, event: event);
        return plain(event: event, effects: [...fx, ...efx]);
      default:
        break;
    }
    return plain();
  }

  List<UnknownRelic> _relicOffers(UnknownPlayer p) {
    final pool = [for (final r in UnknownRelic.values) if (!p.has(r)) r];
    final out = <UnknownRelic>[];
    while (out.length < 3 && pool.isNotEmpty) {
      out.add(pool.removeAt(_rng.nextInt(pool.length)));
    }
    return out;
  }

  List<UnknownItem> _itemOffers() {
    final pool = List.of(UnknownItem.values);
    pool.removeAt(_rng.nextInt(pool.length));
    return pool;
  }

  (UnknownEvent, List<UnknownFx>) _event(UnknownPlayer p) {
    final e = UnknownEvent.values[_rng.nextInt(UnknownEvent.values.length)];
    final fx = <UnknownFx>[];
    switch (e) {
      case UnknownEvent.coinRain:
        for (final q in players) {
          if (!q.left) _gain(q, q.id == p.id ? 6 : 3, fx, '☔');
        }
      case UnknownEvent.whirl:
        final others = [for (final q in players) if (q.id != p.id && q.racing) q];
        if (others.isNotEmpty) {
          final q = others[_rng.nextInt(others.length)];
          final tmp = p.pos;
          p.pos = q.pos;
          q.pos = tmp;
          fx.add(UnknownFx(p.id, '🌪️'));
          fx.add(UnknownFx(q.id, '🌪️'));
        }
      case UnknownEvent.luckTax:
        UnknownPlayer? poorest;
        for (final q in players) {
          if (q.id != p.id && !q.left && (poorest == null || q.coins < poorest.coins)) poorest = q;
        }
        if (poorest != null) _steal(poorest, p, 5, fx, '🎗️');
      case UnknownEvent.gust:
        p.pos = min(unknownFinish - 1, p.pos + 4);
        fx.add(UnknownFx(p.id, '💨'));
      case UnknownEvent.freeItem:
        final item = UnknownItem.values[_rng.nextInt(UnknownItem.values.length)];
        if (p.items.length < unknownMaxItems) {
          p.items.add(item);
          fx.add(UnknownFx(p.id, unknownItemEmoji(item)));
        } else {
          _gain(p, 5, fx, '🎁');
        }
      case UnknownEvent.robinHood:
        final victim = richestExcept(p);
        if (victim != null) _steal(p, victim, 5, fx, '🏹');
      case UnknownEvent.quake:
        for (final q in players) {
          if (q.id == p.id || !q.racing || q.pos <= 0) continue;
          if (_shieldBlocks(q)) {
            fx.add(UnknownFx(q.id, '🛡️'));
          } else {
            q.pos = max(1, q.pos - 2);
            fx.add(UnknownFx(q.id, '💥'));
          }
        }
      case UnknownEvent.goldenQuestion:
        break;
    }
    return (e, fx);
  }

  // ─── Deciziile de pe câmpuri ───────────────────────────────────────────

  /// Ia artefactul [relic]; cu trei deja, [drop] iese din joc. `null` la
  /// [relic] = jucătorul a refuzat toate trei.
  void takeRelic(UnknownPlayer p, UnknownRelic? relic, {UnknownRelic? drop}) {
    if (relic == null) return;
    if (p.relics.length >= unknownMaxRelics) {
      p.relics.remove(drop ?? p.relics.first);
    }
    p.relics.add(relic);
  }

  /// `false` dacă nu are bani sau buzunarele sunt pline.
  bool buyItem(UnknownPlayer p, UnknownItem item) {
    final price = unknownItemPrice(item);
    if (p.coins < price || p.items.length >= unknownMaxItems) return false;
    p.coins -= price;
    p.items.add(item);
    return true;
  }

  /// Pregătește [item] pentru mutarea următoare. Unul singur deodată.
  void arm(UnknownPlayer p, UnknownItem item) {
    if (!p.items.remove(item)) return;
    final prev = p.armed;
    if (prev != null) p.items.add(prev);
    p.armed = item;
  }

  void disarm(UnknownPlayer p) {
    final prev = p.armed;
    if (prev == null) return;
    p.armed = null;
    p.items.add(prev);
  }

  /// Duel: ambii răspund la aceeași întrebare. Unul singur corect câștigă;
  /// amândoi corecți → câștigă cel mai rapid; amândoi greșit → nimic.
  ({String? winnerId, List<UnknownFx> fx}) resolveDuel(
    UnknownPlayer attacker,
    UnknownPlayer defender,
    UnknownAnswer a,
    UnknownAnswer d,
  ) {
    final fx = <UnknownFx>[];
    UnknownPlayer? winner;
    if (a.correct && !d.correct) {
      winner = attacker;
    } else if (d.correct && !a.correct) {
      winner = defender;
    } else if (a.correct && d.correct) {
      winner = a.ms <= d.ms ? attacker : defender;
    }
    if (winner == null) return (winnerId: null, fx: fx);
    final loser = winner == attacker ? defender : attacker;
    winner.duelsWon++;
    _steal(winner, loser, winner.has(UnknownRelic.duelist) ? 12 : 6, fx, '⚔️');
    return (winnerId: winner.id, fx: fx);
  }

  /// Întrebarea de aur: corect → +4 câmpuri (fără să treacă de final).
  bool resolveGolden(UnknownPlayer p, bool correct) {
    if (!correct) return false;
    p.pos = min(unknownFinish - 1, p.pos + 4);
    return true;
  }

  void endRound() => round++;
}

// ─── Boții ──────────────────────────────────────────────────────────────

int _relicWeight(UnknownRelic r) => switch (r) {
      UnknownRelic.goldLadder => 8,
      UnknownRelic.umbrella => 8,
      UnknownRelic.onFire => 8,
      UnknownRelic.lightning => 7,
      UnknownRelic.loadedDie => 6,
      UnknownRelic.consolation => 6,
      UnknownRelic.scholar => 5,
      UnknownRelic.echo => 4,
      UnknownRelic.collector => 4,
      UnknownRelic.magnet => 4,
      UnknownRelic.duelist => 3,
    };

/// Botul ia cel mai valoros artefact oferit; cu buzunarul plin, aruncă pe
/// cel mai slab doar dacă cel nou e mai bun.
({UnknownRelic? take, UnknownRelic? drop}) unknownBotPickRelic(UnknownPlayer p, List<UnknownRelic> offers) {
  if (offers.isEmpty) return (take: null, drop: null);
  final best = offers.reduce((a, b) => _relicWeight(b) > _relicWeight(a) ? b : a);
  if (p.relics.length < unknownMaxRelics) return (take: best, drop: null);
  final worst = p.relics.reduce((a, b) => _relicWeight(b) < _relicWeight(a) ? b : a);
  if (_relicWeight(best) <= _relicWeight(worst)) return (take: null, drop: null);
  return (take: best, drop: worst);
}

/// Botul cumpără cel mai scump obiect pe care și-l permite, dacă îi rămân
/// măcar 4 monede (să nu rămână complet pe zero).
UnknownItem? unknownBotPickItem(UnknownPlayer p, List<UnknownItem> offers) {
  if (p.items.length >= unknownMaxItems) return null;
  final affordable = [for (final i in offers) if (p.coins - unknownItemPrice(i) >= 4) i]
    ..sort((a, b) => unknownItemPrice(b).compareTo(unknownItemPrice(a)));
  return affordable.isEmpty ? null : affordable.first;
}

/// Alegerea botului pentru oferta lui, gata de trimis ca jucătorii reali.
UnknownChoice unknownBotChoice(UnknownPlayer p, UnknownOffer offer) {
  if (offer.chest) {
    final pick = unknownBotPickRelic(p, offer.relics);
    return UnknownChoice(take: pick.take?.name, drop: pick.drop?.name);
  }
  final item = unknownBotPickItem(p, offer.items);
  return UnknownChoice(take: item?.name);
}

/// Obiectul pe care botul îl pregătește la începutul rundei (sau null).
/// Schimbul doar dacă cel din față e departe (altfel e degeaba); Scutul doar
/// dacă n-are deja.
UnknownItem? unknownBotArmChoice(UnknownGame g, UnknownPlayer p) {
  if (p.armed != null || p.items.isEmpty || !p.racing) return null;
  for (final item in p.items) {
    if (item == UnknownItem.shield && p.shielded) continue;
    if (item == UnknownItem.swap) {
      final ahead = g.nearestAhead(p);
      if (ahead == null || ahead.pos - p.pos < 6) continue;
    }
    return item;
  }
  return null;
}

/// Varianta pe loc a [unknownBotArmChoice] (teste și simulări).
void unknownBotArm(UnknownGame g, UnknownPlayer p) {
  final item = unknownBotArmChoice(g, p);
  if (item != null) g.arm(p, item);
}
