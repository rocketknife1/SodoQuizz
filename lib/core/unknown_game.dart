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
/// Pur și determinist: toată aleatoriea vine dintr-un singur `Random(seed)`,
/// consumat în ordinea apelurilor. Aceeași secvență de apeluri → același
/// joc. E fundația pentru multiplayer (un client rezolvă, ceilalți doar
/// animă), ca la Quizz Tanks.
library;

import 'dart:math';

import 'lang.dart';

const int unknownFinish = 60;

/// Plafonul de siguranță: dacă nimeni n-a ajuns până atunci, câștigă cel
/// mai avansat. Un meci obișnuit se termină în jur de 12-14 runde.
const int unknownMaxRounds = 22;
const int unknownStartCoins = 10;
const int unknownQuestionSeconds = 15;
const int unknownMaxRelics = 3;
const int unknownMaxItems = 2;

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
      UnknownEvent.coinRain => tr('Toată lumea +3 🪙, tu +6', 'Everyone +3 🪙, you +6'),
      UnknownEvent.whirl => tr('Schimbi locul cu cineva la întâmplare', 'You swap places with a random player'),
      UnknownEvent.luckTax => tr('Dai 5 🪙 celui mai sărac', 'You give 5 🪙 to the poorest player'),
      UnknownEvent.gust => tr('Vântul te duce 4 câmpuri înainte', 'The wind carries you 4 spaces ahead'),
      UnknownEvent.freeItem => tr('Primești un obiect gratis', 'You get a free item'),
      UnknownEvent.robinHood => tr('Iei 5 🪙 de la cel mai bogat', 'You take 5 🪙 from the richest'),
      UnknownEvent.quake => tr('Toți ceilalți dau înapoi 2 câmpuri', 'Everyone else falls back 2 spaces'),
      UnknownEvent.goldenQuestion => tr('Răspunde corect: +4 câmpuri', 'Answer correctly: +4 spaces'),
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
  bool has(UnknownRelic r) => relics.contains(r);
}

/// Un efect de arătat pe hartă (monede care zboară, un text).
class UnknownFx {
  const UnknownFx(this.playerId, this.label, {this.coins = 0});

  final String playerId;
  final String label;
  final int coins;
}

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
  });

  final UnknownLandingKind kind;
  final List<UnknownFx> fx;
  final List<UnknownRelic> relicOffers;
  final List<UnknownItem> itemOffers;
  final String? opponentId;
  final UnknownEvent? event;

  /// Ce s-a întâmplat, pe scurt, pentru panoul de jos („🪜 Scara! 8 → 19").
  final String? note;
}

class UnknownMove {
  const UnknownMove(this.hops, this.landing);

  final List<UnknownHop> hops;
  final UnknownLanding landing;
}

class UnknownGame {
  UnknownGame({required this.players, required int seed, this.maxRounds = unknownMaxRounds}) : _rng = Random(seed);

  final List<UnknownPlayer> players;
  final int maxRounds;
  final Random _rng;

  int round = 0;
  int _finishers = 0;

  /// Meciul se încheie la finalul rundei în care a ajuns primul — ceilalți
  /// își termină mutarea din runda aia (au răspuns la aceeași întrebare).
  bool get isOver => round >= maxRounds || players.any((p) => p.finished && p.finishedRound! < round);

  UnknownPlayer player(String id) => players.firstWhere((p) => p.id == id);

  /// Clasamentul: cine a ajuns, în ordinea sosirii; apoi cine e mai departe;
  /// apoi monedele; la egalitate rămâne ordinea mesei.
  List<UnknownPlayer> standings() {
    final order = {for (var i = 0; i < players.length; i++) players[i].id: i};
    return List.of(players)
      ..sort((a, b) {
        final fa = a.finishOrder ?? 1 << 20;
        final fb = b.finishOrder ?? 1 << 20;
        if (fa != fb) return fa.compareTo(fb);
        final p = b.pos.compareTo(a.pos);
        if (p != 0) return p;
        final c = b.coins.compareTo(a.coins);
        if (c != 0) return c;
        return order[a.id]!.compareTo(order[b.id]!);
      });
  }

  /// Ultimul primește „vânt din spate" (+2 pași). Nimeni în prima rundă sau
  /// când toți sunt pe același câmp.
  UnknownPlayer? tailwindPlayer() {
    final racing = [for (final p in players) if (!p.finished) p];
    if (round == 0 || racing.length < 2) return null;
    final minPos = racing.map((p) => p.pos).reduce(min);
    final maxPos = players.map((p) => p.pos).reduce(max);
    if (minPos == maxPos) return null;
    return racing.lastWhere((p) => p.pos == minPos);
  }

  UnknownPlayer? richestExcept(UnknownPlayer except) {
    UnknownPlayer? best;
    for (final q in players) {
      if (q.id == except.id) continue;
      if (best == null || q.coins > best.coins) best = q;
    }
    return best;
  }

  /// Cel mai apropiat jucător din fața lui [p] (pentru Schimb).
  UnknownPlayer? nearestAhead(UnknownPlayer p) {
    UnknownPlayer? best;
    for (final q in players) {
      if (q.id == p.id || q.finished || q.pos <= p.pos) continue;
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

  // ─── Faza de răspuns → zaruri ──────────────────────────────────────────

  /// Ordinea mutărilor: întâi cei care au răspuns corect, după viteză, apoi
  /// ceilalți. Cine a ajuns deja nu se mai mută.
  List<String> moveOrder(Map<String, UnknownAnswer> answers) {
    int rank(UnknownPlayer p) => answers[p.id]?.correct == true ? 0 : 1;
    int ms(UnknownPlayer p) => answers[p.id]?.ms ?? 1 << 30;
    final idx = {for (var i = 0; i < players.length; i++) players[i].id: i};
    final list = [for (final p in players) if (!p.finished) p]
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
      if (!p.finished && a != null && a.correct && a.ms < best) {
        best = a.ms;
        fastestId = p.id;
      }
    }

    final rolls = <String, UnknownRoll>{};
    for (final p in players) {
      if (p.finished) continue;
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
      if (fastest) _gain(p, 3, fx, tr('⚡ Cel mai rapid', '⚡ Fastest'));
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
        case UnknownItem.swap:
          final ahead = nearestAhead(p);
          if (ahead != null) {
            final tmp = p.pos;
            p.pos = ahead.pos;
            ahead.pos = tmp;
            fx.add(UnknownFx(p.id, tr('🔀 Schimb cu ${ahead.name}', '🔀 Swap with ${ahead.name}')));
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
        if (q.id != p.id && q.pos == tile && tile > 0) _steal(p, q, 2, fx, '🧲');
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
      return UnknownMove(const [], UnknownLanding(kind: UnknownLandingKind.none, note: tr('⏸️ Stă o tură', '⏸️ Sits this one out')));
    }
    final hops = _walk(p, max(1, roll.total));
    String? note;
    final fx = <UnknownFx>[];

    switch (unknownTileAt(p.pos)) {
      case UnknownTile.ladder:
        final from = p.pos;
        var to = unknownLadders[p.pos]!;
        if (p.has(UnknownRelic.goldLadder)) to = min(unknownFinish - 1, to + 3);
        p.pos = to;
        hops.add(UnknownHop(to, UnknownHopKind.ladder));
        note = tr('🪜 Scara! $from → $to', '🪜 A ladder! $from → $to');
      case UnknownTile.snake:
        final from = p.pos;
        if (_shieldBlocks(p)) {
          note = tr('🛡️ Imunitate! Șarpele nu te prinde', '🛡️ Immune! The snake misses you');
        } else {
          var to = unknownSnakes[p.pos]!;
          if (p.has(UnknownRelic.umbrella)) to = from - (from - to) ~/ 2;
          p.pos = to;
          hops.add(UnknownHop(to, UnknownHopKind.snake));
          note = tr('🐍 Șarpele! $from → $to', '🐍 A snake! $from → $to');
        }
      case UnknownTile.back3:
        if (_shieldBlocks(p)) {
          note = tr('🛡️ Imunitate! Rămâi pe loc', '🛡️ Immune! You stay put');
        } else {
          p.pos = max(1, p.pos - 3);
          hops.add(UnknownHop(p.pos, UnknownHopKind.jump));
          note = tr('⬅️ Înapoi 3!', '⬅️ Back 3!');
        }
      case UnknownTile.trap:
        if (_shieldBlocks(p)) {
          note = tr('🛡️ Imunitate! Capcana nu te ține', '🛡️ Immune! The trap can\'t hold you');
        } else {
          p.skipNext = true;
          note = tr('🕸️ Capcană: stai o tură', '🕸️ Trap: skip a turn');
        }
      case UnknownTile.clover:
        if (p.shielded) {
          _gain(p, 3, fx, '🍀');
          note = tr('🍀 Trifoi: ai deja imunitate, +3 🪙', '🍀 Clover: already immune, +3 🪙');
        } else {
          p.shielded = true;
          note = tr('🍀 Trifoi: imunitate la următorul necaz', '🍀 Clover: immune to the next trouble');
        }
      default:
        break;
    }

    if (p.pos >= unknownFinish && p.finishedRound == null) {
      p.finishedRound = round;
      p.finishOrder = _finishers++;
    }
    final landing = _land(p, fx, note);
    return UnknownMove(hops, landing);
  }

  bool _shieldBlocks(UnknownPlayer p) {
    if (!p.shielded) return false;
    p.shielded = false;
    return true;
  }

  UnknownLanding _land(UnknownPlayer p, List<UnknownFx> fx, String? note) {
    final echo = p.has(UnknownRelic.echo) ? 2 : 1;
    switch (unknownTileAt(p.pos)) {
      case UnknownTile.coins:
        _gain(p, 3 * echo, fx, '');
      case UnknownTile.tax:
        _gain(p, -3, fx, '');
      case UnknownTile.chest:
        return UnknownLanding(kind: UnknownLandingKind.chest, relicOffers: _relicOffers(p), note: note);
      case UnknownTile.shop:
        return UnknownLanding(kind: UnknownLandingKind.shop, itemOffers: _itemOffers(), note: note);
      case UnknownTile.duel:
        final opp = richestExcept(p);
        if (opp != null) return UnknownLanding(kind: UnknownLandingKind.duel, opponentId: opp.id, note: note);
      case UnknownTile.event:
        return _event(p, note);
      default:
        break;
    }
    return UnknownLanding(kind: UnknownLandingKind.none, fx: fx, note: note);
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

  UnknownLanding _event(UnknownPlayer p, String? note) {
    final e = UnknownEvent.values[_rng.nextInt(UnknownEvent.values.length)];
    final fx = <UnknownFx>[];
    switch (e) {
      case UnknownEvent.coinRain:
        for (final q in players) {
          _gain(q, q.id == p.id ? 6 : 3, fx, '☔');
        }
      case UnknownEvent.whirl:
        final others = [for (final q in players) if (q.id != p.id && !q.finished) q];
        if (others.isNotEmpty) {
          final q = others[_rng.nextInt(others.length)];
          final tmp = p.pos;
          p.pos = q.pos;
          q.pos = tmp;
          fx.add(UnknownFx(p.id, tr('🌪️ Schimb cu ${q.name}', '🌪️ Swap with ${q.name}')));
        }
      case UnknownEvent.luckTax:
        UnknownPlayer? poorest;
        for (final q in players) {
          if (q.id != p.id && (poorest == null || q.coins < poorest.coins)) poorest = q;
        }
        if (poorest != null) _steal(poorest, p, 5, fx, '🎗️');
      case UnknownEvent.gust:
        p.pos = min(unknownFinish - 1, p.pos + 4);
      case UnknownEvent.freeItem:
        final item = UnknownItem.values[_rng.nextInt(UnknownItem.values.length)];
        if (p.items.length < unknownMaxItems) {
          p.items.add(item);
          fx.add(UnknownFx(p.id, '${unknownItemEmoji(item)} ${unknownItemName(item)}'));
        } else {
          _gain(p, 5, fx, '🎁');
        }
      case UnknownEvent.robinHood:
        final victim = richestExcept(p);
        if (victim != null) _steal(p, victim, 5, fx, '🏹');
      case UnknownEvent.quake:
        for (final q in players) {
          if (q.id == p.id || q.finished || q.pos <= 0) continue;
          if (_shieldBlocks(q)) {
            fx.add(UnknownFx(q.id, '🛡️'));
          } else {
            q.pos = max(1, q.pos - 2);
          }
        }
      case UnknownEvent.goldenQuestion:
        return UnknownLanding(kind: UnknownLandingKind.goldenQuestion, event: e, note: note);
    }
    return UnknownLanding(kind: UnknownLandingKind.none, fx: fx, event: e, note: note);
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

/// Botul pregătește un obiect la începutul rundei. Schimbul doar dacă cel
/// din față e departe (altfel e degeaba); Scutul doar dacă n-are deja.
void unknownBotArm(UnknownGame g, UnknownPlayer p) {
  if (p.armed != null || p.items.isEmpty || p.finished) return;
  for (final item in List.of(p.items)) {
    if (item == UnknownItem.shield && p.shielded) continue;
    if (item == UnknownItem.swap) {
      final ahead = g.nearestAhead(p);
      if (ahead == null || ahead.pos - p.pos < 6) continue;
    }
    g.arm(p, item);
    return;
  }
}
