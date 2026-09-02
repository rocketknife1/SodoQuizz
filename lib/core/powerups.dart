/// **Power-up-uri și evenimente de rundă**, comune tuturor modurilor
/// multiplayer — cerința userului: „zeci de evente și power ups și nebunii
/// de genul să te țină captivat și să se răstoarne meciurile într-o manieră
/// amuzantă/frustrantă".
///
/// ## De ce totul e determinist, fără niciun câmp nou în Firestore
///
/// Fiecare power-up și fiecare eveniment se calculează pe client din
/// `matchId` + `roundIndex` (+ `playerId` unde e personal), exact ca placa
/// falsă de la Obby (vezi core/obby.dart `obbyFakePlatformIndex`). Toți
/// clienții ajung la ACELEAȘI valori fiindcă folosesc același hash stabil
/// (core/stable_hash.dart), deci nu e nevoie nici de o scriere în plus, nici
/// de o rundă de sincronizare. Un client modificat ar putea afla dinainte ce
/// urmează — dar asta nu deschide nicio portiță nouă: răspunsurile corecte
/// sunt oricum în clar pe fiecare telefon, iar proiectul n-are Cloud
/// Functions. Același model de încredere ca restul multiplayer-ului.
///
/// ## Cele două familii, și de ce sunt separate
///
///  - [RoundEvent] — se întâmplă la MASĂ, tuturor deodată, anunțat la
///    începutul rundei („runda asta valorează dublu", „răspunsurile sunt
///    ascunse"). Schimbă regula rundei pentru toți.
///  - [PowerUp] — e AL UNUI JUCĂTOR, câștigat pentru ceva ce a făcut el, și
///    se consumă pe cineva anume (scut, rachetă, sabotaj). Schimbă rezultatul
///    unei acțiuni individuale.
///
/// Ținute separat fiindcă răspund la întrebări diferite: un eveniment nu
/// poate fi „păstrat pentru mai târziu", iar un power-up n-are sens să apară
/// din senin la toată lumea în același timp.
///
/// ## Handicapul (catch-up) — de ce există și de ce nu e „cadou"
///
/// Userul a cerut explicit „un fel de handicap dacă cineva are avantaj mare
/// și altul trebuie să recupereze". [catchUpBoostFor] dă power-up-uri MAI
/// DES celor rămași în urmă, dar nu le dă niciodată puncte/progres direct:
/// un meci în care ultimul primește gratis exact ce i-ar trebui ca să câștige
/// nu mai e un meci. Așa, cel din urmă capătă mai multe ȘANSE să întoarcă
/// meciul, dar tot trebuie să răspundă corect ca să le folosească.
library;

import 'stable_hash.dart';

/// Un eveniment de rundă — schimbă regula pentru TOATĂ masa, o singură rundă.
///
/// Valorile sunt împărțite pe moduri prin [RoundEvent.modes]: un eveniment de
/// tancuri (ceață care strică ținta) n-are ce căuta la Obby, iar unul de
/// Obby (plăci care se mișcă) n-are sens la Scaunul Electric.
enum RoundEvent {
  /// Nimic special — cazul implicit, cel mai frecvent.
  none,

  // ─── Comune tuturor modurilor cu rundă sincronizată ───────────────────
  /// Punctele/efectul rundei se dublează pentru toată lumea.
  doubleOrNothing,

  /// Cine răspunde PRIMUL corect primește un bonus în plus.
  firstBloodBonus,

  /// Variantele sunt amestecate mai agresiv / întrebarea e „grea".
  suddenDeath,

  /// Toată lumea primește un power-up la începutul rundei.
  powerUpRain,

  // ─── Quizz Tanks ──────────────────────────────────────────────────────
  /// Ceață de luptă: șansa de a evita crește pentru toți.
  battleFog,

  /// Muniție grea: daunele rundei sunt mai mari pentru toți.
  heavyShells,

  /// Reparație generală: toți primesc puțin HP înapoi la începutul rundei.
  fieldRepairs,

  // ─── Obby ─────────────────────────────────────────────────────────────
  /// Gravitație mică: cine sare bine trece două obstacole.
  lowGravity,

  /// Furtună de asteroizi: două din trei plăci sunt false, nu una.
  asteroidStorm,

  // ─── Scaunul Electric ─────────────────────────────────────────────────
  /// Tensiune dublă: cine pică pe scaun pierde două vieți, nu una.
  overcharge,

  /// Siguranță: cine scapă de pe scaun primește o viață înapoi.
  groundedFuse,
}

/// În ce moduri poate apărea fiecare eveniment. Cheile sunt id-urile de mod
/// din `MatchGameMode.name` — ținute ca string ca `core/` să nu depindă de
/// `models/` (aceeași graniță ca în restul fișierelor din core).
const Map<RoundEvent, Set<String>> roundEventModes = {
  RoundEvent.doubleOrNothing: {'quizzTanks', 'obby', 'electricChair', 'higherLower', 'classic'},
  RoundEvent.firstBloodBonus: {'quizzTanks', 'obby', 'electricChair', 'higherLower'},
  RoundEvent.suddenDeath: {'quizzTanks', 'obby', 'electricChair', 'higherLower', 'classic'},
  RoundEvent.powerUpRain: {'quizzTanks', 'obby', 'electricChair'},
  RoundEvent.battleFog: {'quizzTanks'},
  RoundEvent.heavyShells: {'quizzTanks'},
  RoundEvent.fieldRepairs: {'quizzTanks'},
  RoundEvent.lowGravity: {'obby'},
  RoundEvent.asteroidStorm: {'obby'},
  RoundEvent.overcharge: {'electricChair'},
  RoundEvent.groundedFuse: {'electricChair'},
};

/// Titlul scurt al evenimentului, afișat ca banner la începutul rundei.
/// Perechea (ro, en) — apelantul alege prin `tr()`, ca restul aplicației.
const Map<RoundEvent, (String, String)> roundEventTitles = {
  RoundEvent.doubleOrNothing: ('🔥 Rundă Dublă', '🔥 Double Round'),
  RoundEvent.firstBloodBonus: ('⚡ Primul Sânge', '⚡ First Blood'),
  RoundEvent.suddenDeath: ('💀 Moarte Subită', '💀 Sudden Death'),
  RoundEvent.powerUpRain: ('🎁 Ploaie de Power-Up', '🎁 Power-Up Rain'),
  RoundEvent.battleFog: ('🌫️ Ceață de Luptă', '🌫️ Battle Fog'),
  RoundEvent.heavyShells: ('💥 Muniție Grea', '💥 Heavy Shells'),
  RoundEvent.fieldRepairs: ('🔧 Reparații pe Teren', '🔧 Field Repairs'),
  RoundEvent.lowGravity: ('🌙 Gravitație Mică', '🌙 Low Gravity'),
  RoundEvent.asteroidStorm: ('☄️ Furtună de Asteroizi', '☄️ Asteroid Storm'),
  RoundEvent.overcharge: ('⚡ Supratensiune', '⚡ Overcharge'),
  RoundEvent.groundedFuse: ('🛡️ Siguranță', '🛡️ Grounded Fuse'),
};

/// Ce face efectiv evenimentul, într-un rând — banner-ul arată și asta, ca
/// jucătorul să nu trebuiască să ghicească regula nouă în 15 secunde.
const Map<RoundEvent, (String, String)> roundEventDescriptions = {
  RoundEvent.doubleOrNothing: ('Runda asta valorează dublu.', 'This round counts double.'),
  RoundEvent.firstBloodBonus: ('Primul care răspunde corect ia un power-up.', 'First correct answer gets a power-up.'),
  RoundEvent.suddenDeath: ('Fără a doua șansă runda asta.', 'No second chances this round.'),
  RoundEvent.powerUpRain: ('Toată lumea primește un power-up!', 'Everyone gets a power-up!'),
  RoundEvent.battleFog: ('Toată lumea evită mai ușor.', 'Everyone dodges more easily.'),
  RoundEvent.heavyShells: ('Loviturile dor mai tare.', 'Hits land harder.'),
  RoundEvent.fieldRepairs: ('Toți primesc viață înapoi.', 'Everyone repairs some HP.'),
  RoundEvent.lowGravity: ('Săritura bună trece DOUĂ obstacole.', 'A good jump clears TWO obstacles.'),
  RoundEvent.asteroidStorm: ('Două plăci din trei sunt false!', 'Two of three platforms are fake!'),
  RoundEvent.overcharge: ('Scaunul ia DOUĂ vieți.', 'The chair takes TWO lives.'),
  RoundEvent.groundedFuse: ('Cine scapă primește o viață.', 'Surviving the chair heals one life.'),
};

/// Un power-up deținut de un jucător anume.
enum PowerUp {
  none,

  // ─── Ofensive ─────────────────────────────────────────────────────────
  /// Quizz Tanks: lovitura următoare face daune mult mai mari și nu poate fi
  /// evitată.
  megaRocket,

  /// Quizz Tanks (meciuri de 3+): tragi DOUĂ proiectile și alegi separat
  /// unde merge fiecare. Aleargă aceeași țintă de două ori ⇒ o singură
  /// lovitură, dar cu daune mai mari ([tanksDoubleShotFocusMultiplier]).
  doubleShot,

  /// Scaunul Electric: victima aleasă de tine nu poate fi apărată de scut.
  piercingShock,

  /// Obby: îi „muți" cuiva o placă bună în placă falsă.
  sabotage,

  // ─── Defensive ────────────────────────────────────────────────────────
  /// Scut propriu: loviturile/șocul primite în runda asta nu au efect (la
  /// Quizz Tanks — toate, inclusiv ambele proiectile ale unei lovituri duble).
  shield,

  /// Scut pus PE ALTCINEVA, valabil două runde — vezi
  /// [powerUpDurationRounds]. Cerut explicit de user („sheild 2 runde pe
  /// altcineva").
  allyShield,

  /// Reflectă înapoi atacatorului: cine te lovește încasează el.
  reflect,

  // ─── Utilitare ────────────────────────────────────────────────────────
  /// Elimină două variante greșite la întrebarea următoare.
  fiftyFifty,

  /// Îți dă câteva secunde în plus la runda următoare.
  extraTime,

  /// Vezi ce a răspuns altcineva înainte să se închidă runda.
  peek,

  /// Obby: sari peste rundă fără risc — treci obstacolul automat.
  jetpack,

  /// Sari peste un rând de vieți: recuperezi o viață (Scaunul Electric) sau
  /// HP (Quizz Tanks).
  repairKit,
}

/// În ce moduri are sens fiecare power-up.
const Map<PowerUp, Set<String>> powerUpModes = {
  PowerUp.megaRocket: {'quizzTanks'},
  PowerUp.doubleShot: {'quizzTanks'},
  PowerUp.piercingShock: {'electricChair'},
  PowerUp.sabotage: {'obby'},
  PowerUp.shield: {'quizzTanks', 'electricChair'},
  PowerUp.allyShield: {'quizzTanks', 'electricChair'},
  PowerUp.reflect: {'quizzTanks', 'electricChair'},
  PowerUp.fiftyFifty: {'quizzTanks', 'obby', 'electricChair', 'higherLower', 'classic'},
  // DOAR Clasic. În modurile sincrone (Tanks, Obby, Scaunul Electric,
  // Higher & Lower) runda se închide când expiră cronometrul ORICĂRUI client
  // (`closeTanksAnswering` & co. sunt apelate de toată lumea), iar secundele
  // în plus sunt o valoare LOCALĂ — deci adversarul îți taie runda la
  // secunda normală și puterea nu face absolut nimic. La Clasic fiecare are
  // propriul termen (`_deadline`), acolo chiar funcționează.
  // Recenzie 2026-09-01. Dacă vrei puterea înapoi în modurile sincrone,
  // trebuie scrisă în documentul meciului ca să prelungească runda pentru
  // toți — altă mecanică, altă decizie.
  PowerUp.extraTime: {'classic'},
  PowerUp.peek: {'quizzTanks', 'obby', 'electricChair'},
  PowerUp.jetpack: {'obby'},
  PowerUp.repairKit: {'quizzTanks', 'electricChair'},
};

/// În ce FAZE de rundă mai are efect real folosirea fiecărui power-up
/// „de luptă". Cheile sunt `RoundPhase.name` (ținute ca string ca `core/` să
/// nu depindă de `models/`, aceeași graniță ca [powerUpModes]).
///
/// Bug raportat live pe telefon (2026-08-25): puterile astea se scriu pe
/// `roundPowerUps` și sunt citite abia la rezolvarea rundei
/// ([MultiplayerService.resolveTanksRound] / `resolveElectricChairRound` /
/// `resolveObbyChoices`). Dacă jucătorul apasă după ce runda s-a rezolvat
/// deja (faza [RoundPhase]`.revealed`), scrierea ajunge prea târziu și
/// puterea se pierde în tăcere. Ecranele verifică lista asta prin
/// [powerUpUsableInPhase] înainte s-o consume și, dacă nu se poate, o
/// păstrează și îi spun jucătorului.
///
/// Power-up-urile care NU apar aici (trusa de reparații) au efect local
/// instant și se pot folosi oricând, n-au fereastră.
///
/// 50/50 a fost ADĂUGAT aici la recenzia din 2026-09-01: nu avea fereastră,
/// deci trecea de gardă în orice fază, iar corpul lui nu făcea nimic afară
/// din `answering` — puterea dispărea din inventar, nu se întâmpla nimic, și
/// se ardea și dreptul la o putere pe runda aia.
const Map<PowerUp, Set<String>> powerUpUsablePhases = {
  PowerUp.fiftyFifty: {'answering'},
  PowerUp.megaRocket: {'answering', 'targeting'},
  PowerUp.doubleShot: {'answering', 'targeting'},
  PowerUp.shield: {'answering', 'targeting', 'chair'},
  PowerUp.piercingShock: {'answering', 'targeting'},
  PowerUp.allyShield: {'answering', 'targeting', 'chair'},
  PowerUp.reflect: {'answering', 'targeting', 'chair'},
  PowerUp.peek: {'answering', 'targeting', 'choosing', 'chair'},
  PowerUp.sabotage: {'answering', 'choosing'},
  PowerUp.jetpack: {'answering', 'choosing'},
};

/// Poate fi folosit [p] acum, în faza [phaseName] (= `RoundPhase.name`)?
/// Vezi [powerUpUsablePhases]. Necunoscut/neangajat în listă ⇒ oricând.
bool powerUpUsableInPhase(PowerUp p, String phaseName) {
  final allowed = powerUpUsablePhases[p];
  if (allowed == null) return true;
  return allowed.contains(phaseName);
}

const Map<PowerUp, (String, String)> powerUpTitles = {
  PowerUp.megaRocket: ('🚀 Mega Rachetă', '🚀 Mega Rocket'),
  PowerUp.doubleShot: ('🎯 Lovitură Dublă', '🎯 Double Shot'),
  PowerUp.piercingShock: ('⚡ Șoc Perforant', '⚡ Piercing Shock'),
  PowerUp.sabotage: ('🕳️ Sabotaj', '🕳️ Sabotage'),
  PowerUp.shield: ('🛡️ Scut', '🛡️ Shield'),
  PowerUp.allyShield: ('🛡️ Scut pe Aliat', '🛡️ Ally Shield'),
  PowerUp.reflect: ('🪞 Reflexie', '🪞 Reflect'),
  PowerUp.fiftyFifty: ('✂️ 50/50', '✂️ 50/50'),
  PowerUp.extraTime: ('⏱️ Timp în Plus', '⏱️ Extra Time'),
  PowerUp.peek: ('👁️ Spionaj', '👁️ Peek'),
  PowerUp.jetpack: ('🛸 Jetpack', '🛸 Jetpack'),
  PowerUp.repairKit: ('🔧 Trusă de Reparații', '🔧 Repair Kit'),
};

const Map<PowerUp, (String, String)> powerUpDescriptions = {
  PowerUp.megaRocket: ('Lovitură uriașă, imposibil de evitat.', 'Huge hit, impossible to dodge.'),
  PowerUp.doubleShot: ('Două proiectile — alege ținta fiecăruia.', 'Two shots — aim each one.'),
  PowerUp.piercingShock: ('Trece prin scutul victimei.', 'Goes through the victim shield.'),
  PowerUp.sabotage: ('Strici placa bună a cuiva.', "Ruin someone's good platform."),
  PowerUp.shield: ('Blochezi loviturile primite runda asta.', 'Block incoming hits this round.'),
  PowerUp.allyShield: ('Aperi pe altcineva 2 runde.', 'Protect someone else for 2 rounds.'),
  PowerUp.reflect: ('Cine te lovește încasează el.', 'Whoever hits you takes it instead.'),
  PowerUp.fiftyFifty: ('Două variante greșite dispar.', 'Two wrong options disappear.'),
  PowerUp.extraTime: ('Secunde în plus la runda următoare.', 'Extra seconds next round.'),
  PowerUp.peek: ('Vezi ce a răspuns altcineva.', "See someone else's answer."),
  PowerUp.jetpack: ('Treci obstacolul automat.', 'Clear the obstacle automatically.'),
  PowerUp.repairKit: ('Recuperezi viață.', 'Recover some life.'),
};

/// Câte runde ține un power-up cu durată. Cele care nu apar aici se consumă
/// instantaneu, în runda în care sunt folosite.
const Map<PowerUp, int> powerUpDurationRounds = {
  PowerUp.allyShield: 2, // cerință explicită a userului
};

/// Multiplicatorul de daune al [PowerUp.megaRocket] — cerut explicit ca
/// „mega rachetă", deci trebuie să se SIMTĂ, nu doar să fie cu puțin peste
/// o lovitură obișnuită. La 3.5× din maximul normal, o mega rachetă ia cam
/// jumătate din viața unui tanc dintr-o singură lovitură.
const double megaRocketDamageMultiplier = 3.5;

/// [PowerUp.doubleShot] cu ambele proiectile pe aceeași țintă: în loc de două
/// lovituri normale (care s-ar putea rata separat), o singură lovitură cu
/// daune înmulțite cu asta. Sub 2× intenționat — concentrarea pe o țintă
/// schimbă un „poate lovesc de două ori" într-un „sigur lovesc o dată tare".
const double tanksDoubleShotFocusMultiplier = 1.8;

/// Separatorul dintre cele două ținte ale unei lovituri duble, în valoarea
/// din `roundTargets[shooter]` (`"tintaA|tintaB"`). Un uid Firebase nu
/// conține niciodată `|`, deci despărțirea e fără ambiguitate. Ținta simplă
/// rămâne un uid gol, fără separator — compatibil cu ce era înainte.
const String tanksTargetSeparator = '|';

/// Câte secunde în plus dă [PowerUp.extraTime].
const int extraTimeSeconds = 6;

/// Câtă viață/HP recuperează [PowerUp.repairKit].
const int repairKitHp = 25;
const int repairKitLives = 1;

/// Șansa de bază ca o rundă să aibă un eveniment. Nu prea des: dacă fiecare
/// rundă are o regulă nouă, „evenimentul" devine regula, iar surpriza
/// dispare — exact greșeala pe care userul o descrie ca „devine previzibil
/// după 3-4 meciuri".
const double roundEventChance = 0.28;

/// Șansa de bază ca un jucător să primească un power-up după o rundă
/// câștigată (răspuns corect). Vezi [catchUpBoostFor] pentru cum crește la
/// cei rămași în urmă.
const double powerUpDropChance = 0.35;

/// Ce eveniment are runda [roundIndex] a meciului [matchId], în modul
/// [gameModeId] (= `MatchGameMode.name`).
///
/// Prima rundă nu are niciodată eveniment: jucătorii n-au apucat încă să
/// prindă ritmul de bază, iar o regulă specială acolo se citește ca „așa e
/// jocul", nu ca o excepție.
RoundEvent roundEventFor({
  required String matchId,
  required int roundIndex,
  required String gameModeId,
}) {
  if (roundIndex <= 0) return RoundEvent.none;
  final roll = stableHash('$matchId#$roundIndex#event') % 1000;
  if (roll >= (roundEventChance * 1000).round()) return RoundEvent.none;
  final pool = [
    for (final e in RoundEvent.values)
      if (e != RoundEvent.none && (roundEventModes[e]?.contains(gameModeId) ?? false)) e,
  ];
  if (pool.isEmpty) return RoundEvent.none;
  final pick = stableHash('$matchId#$roundIndex#eventpick') % pool.length;
  return pool[pick];
}

/// Cât de mult i se umflă șansele la power-up cuiva rămas în urmă —
/// handicapul cerut explicit de user.
///
/// [myRank] e locul curent (0 = primul), [totalPlayers] câți sunt la masă.
/// Întoarce un multiplicator de șansă: 1.0 pentru lider, până la
/// [maxCatchUpMultiplier] pentru ultimul. Cu mai puțin de 2 jucători nu are
/// ce recupera nimeni, deci rămâne neutru.
///
/// NU dă niciodată puncte direct — vezi comentariul din capul fișierului.
const double maxCatchUpMultiplier = 2.6;

double catchUpBoostFor({required int myRank, required int totalPlayers}) {
  if (totalPlayers < 2 || myRank <= 0) return 1;
  final t = (myRank / (totalPlayers - 1)).clamp(0.0, 1.0);
  return 1 + t * (maxCatchUpMultiplier - 1);
}

/// Primește jucătorul [playerId] un power-up după runda [roundIndex]?
///
/// [wonRound] = a făcut ce trebuia runda asta (răspuns corect). Cine n-a
/// făcut nimic nu primește nimic — altfel power-up-urile ar deveni un premiu
/// de participare, iar handicapul ar răsplăti pasivitatea.
///
/// [myRank]/[totalPlayers] hrănesc [catchUpBoostFor].
bool grantsPowerUp({
  required String matchId,
  required int roundIndex,
  required String playerId,
  required bool wonRound,
  required int myRank,
  required int totalPlayers,
}) {
  if (!wonRound) return false;
  final boost = catchUpBoostFor(myRank: myRank, totalPlayers: totalPlayers);
  final threshold = (powerUpDropChance * boost * 1000).round().clamp(0, 1000);
  final roll = stableHash('$matchId#$roundIndex#$playerId#drop') % 1000;
  return roll < threshold;
}

/// CARE power-up primește, dintre cele valabile în modul curent.
PowerUp powerUpFor({
  required String matchId,
  required int roundIndex,
  required String playerId,
  required String gameModeId,
}) {
  final pool = [
    for (final p in PowerUp.values)
      if (p != PowerUp.none && (powerUpModes[p]?.contains(gameModeId) ?? false)) p,
  ];
  if (pool.isEmpty) return PowerUp.none;
  final pick = stableHash('$matchId#$roundIndex#$playerId#which') % pool.length;
  return pool[pick];
}
