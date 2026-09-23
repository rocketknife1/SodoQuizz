/// Regulile modului multiplayer **Quizz Tanks** — până la [tanksPlayerCount]
/// tancuri, întrebări de cultură generală și o bară de viață de 100, ca la
/// jocurile de luptă.
///
/// Runda, în patru pași:
///   1. **Răspuns** — toți cei rămași în viață văd aceeași întrebare și au
///      [tanksRoundSeconds] secunde. Cine a apăsat primește o bifă —
///      ceilalți văd bifa, nu și răspunsul.
///   2. **Țintire** — cine a răspuns CORECT primește ecranul de țintire și
///      alege, în [tanksTargetSeconds] secunde, PE CINE atacă dintre
///      adversarii rămași în viață. Cine n-a apucat să aleagă trage automat
///      în cel mai slăbit adversar. Dacă n-a nimerit nimeni răspunsul, pasul
///      ăsta se sare cu totul: n-are cine trage.
///   3. **Foc** — fiecare țintaș trimite UN proiectil spre ținta lui.
///   4. Proiectilul poate lovi sau poate fi evitat. Cine a răspuns și el
///      corect e „în gardă" și evită mult mai des ([tanksDodgeOnCorrect])
///      decât cine a greșit sau n-a apucat să răspundă
///      ([tanksDodgeOnWrong]) — deci un răspuns corect ajută de două ori:
///      și la atac, și la apărare.
///
/// DE CE DAUNELE SUNT ÎNTR-UN INTERVAL, ȘI DE CE ACEL INTERVAL: cerința a
/// fost explicită — „să nu murim nici repede, dar nici să pierdem pe
/// întrebare câte 5hp". O valoare fixă mică face meciul interminabil, una
/// mare îl termină în două runde.
///
/// Cifrele sunt legate direct de faptul că se trage într-o SINGURĂ țintă
/// aleasă, nu în toți: la o masă de patru cu ~2 răspunsuri corecte pe rundă
/// pleacă ~2 proiectile, deci un jucător anume e vizat cam o dată la o rundă
/// și jumătate. Cu [tanksDamageMin]–[tanksDamageMax] pe lovitură asta
/// înseamnă ~12 HP pierduți în medie pe rundă și un meci de 8-12 runde.
/// Cine e luat la ochi de doi deodată pierde ~35 dintr-o rundă și chiar
/// trebuie să-i fie frică — exact ce face alegerea țintei o decizie, nu o
/// formalitate.
///
/// (Prima versiune trăgea automat în toți trei și avea 8-16 daune; când
/// tragerea a devenit țintită, un singur proiectil pe țintaș ar fi lungit
/// meciul la peste 20 de runde, de-aia intervalul a urcat.)
///
/// PLAFONUL DE JUCĂTORI A URCAT DE LA 4 LA 10, IAR DAUNELE AU FOST COBORÂTE
/// EXACT DIN MOTIVUL PREVĂZUT MAI SUS: la o masă plină trag proporțional mai
/// mulți țintași în aceeași rundă, deci un meci de 10 se termina mult prea
/// repede la 18-30 pe lovitură. Userul a cerut explicit „mult mai puțin
/// damage, să se continue tura mai mult timp" — de-aia intervalul e acum
/// [tanksDamageMin]–[tanksDamageMax] (vezi valorile de mai jos), cam
/// jumătate din cât era. Efectul: la 4 jucători meciul devine ceva mai lung
/// decât înainte, iar la 8-10 rămâne în banda de ~10-14 runde în loc să se
/// încheie în 4-5.
///
/// TOATE ARUNCĂRILE DE ZAR SE FAC ÎNTR-UN SINGUR LOC: în tranzacția care
/// rezolvă runda (vezi MultiplayerService.resolveTanksRound). Rezultatul
/// (lista de proiectile, cine a fost lovit, cât) se SCRIE în Firestore, iar
/// ceilalți clienți doar îl animează. Nu există niciun zar aruncat de două
/// ori pe două telefoane — greșeala clasică prin care doi jucători ar vedea
/// bătălii diferite în același meci.
library;

import 'dart:math';

import 'multiplayer_round.dart';
import 'powerups.dart';

/// Câți jucători încap într-o cameră de Quizz Tanks. Urcat de la 4 la 10 prin decizie de design (toate modurile trebuie să accepte 10) —
/// arena nu mai e o grilă fixă 2×2, ci 2 coloane × câte rânduri sunt
/// necesare pentru [tanksPlayerCount] (vezi
/// MultiplayerTanksScreen._buildArenaFrame). Camera se poate porni și cu mai
/// puțini (de la 2), dar nu primește niciodată al unsprezecelea jucător.
const int tanksPlayerCount = 10;

/// Viața de start a fiecărui tanc. 100 fix, ca procentele din bară să se
/// citească direct ca HP.
const int tanksMaxHp = 100;

/// Cât are fiecare la dispoziție ca să răspundă — comun tuturor modurilor cu
/// rundă sincronizată, vezi core/multiplayer_round.dart.
const int tanksRoundSeconds = sharedRoundAnswerSeconds;

/// Cât durează alegerea țintei. Urcat de la 6 la 10 secunde prin decizie de design: cardurile de țintă arată acum șansă de lovire,
/// daune făcute și etichete tactice (ÎN GARDĂ, CEL MAI PERICULOS, LOVITURĂ
/// MORTALĂ) — la 6 secunde abia apucai să le citești, darămite să cântărești
/// între ele. Cine nu apucă să aleagă trage automat — vezi
/// MultiplayerService.resolveTanksRound.
const int tanksTargetSeconds = 10;

/// Cât ține faza de după rundă când NU s-a tras niciun foc — nimeni n-a
/// nimerit răspunsul, sau a mai rămas un singur tanc în viață (vezi
/// MultiplayerService.closeTanksAnswering, care în cazurile astea sare direct
/// la `revealed`, cu `roundShots` gol).
///
/// Rămân doar cât să se citească răspunsul corect. Când s-a tras, durata
/// vine din programul rundei — vezi [buildTankAttackPlan].
const int tanksEmptyRevealSeconds = 3;

/// Plafon absolut de runde, ca meciul să nu poată rămâne agățat la
/// nesfârșit. Se atinge doar în cazul patologic în care nimeni nu mai
/// nimerește nimic (fără răspunsuri corecte nu se trage niciun proiectil,
/// deci nu scade nicio bară). La atingerea lui meciul se încheie normal,
/// iar clasamentul rămâne cel dat de daunele făcute.
/// Urcat de la 20 la 32 odată cu coborârea daunelor: cu lovituri de ~10 HP,
/// un meci echilibrat are nevoie de mai multe runde până cade cineva, iar
/// vechiul plafon l-ar fi tăiat artificial exact în mijloc.
const int tanksMaxRounds = 32;

/// Daunele unei lovituri reușite, în HP (= procente din [tanksMaxHp]).
/// COBORÂTE de la 18-30 prin decizie de design („tancurile dau
/// mult mai puțin damage, să se continue tura mai mult timp") — vezi
/// comentariul din capul fișierului pentru socoteala completă. La ~10 HP
/// media pe lovitură, un tanc rezistă ~10 lovituri reușite în loc de ~4.
const int tanksDamageMin = 7;
const int tanksDamageMax = 13;

/// Efectele evenimentelor de rundă specifice Quizz Tanks (core/powerups.dart
/// `RoundEvent`) — vezi [resolveTanksRound] pentru unde se aplică.
const double tanksBattleFogDodgeBonus = 0.2;
const double tanksHeavyShellsMultiplier = 1.5;
const int tanksFieldRepairsHeal = 15;

/// Șansa ca ținta să EVITE proiectilul, după cum a răspuns ea însăși în
/// runda curentă. Asimetria e toată ideea de echilibru a modului.
const double tanksDodgeOnCorrect = 0.55;
const double tanksDodgeOnWrong = 0.12;

// ─── Geometria arenei ───────────────────────────────────────────────────────

/// Rezultatul calculului grilei de tancuri — folosit de
/// MultiplayerTanksScreen._buildArenaFrame ca să poziționeze cutiile, dar
/// scos aici, PUR (fără niciun import Flutter), ca să poată fi testat direct
/// pentru orice [TankArenaLayout.playerCount] fără să monteze ecranul
/// întreg. Vezi test/tank_arena_layout_test.dart — genul de bug de aici nu e
/// o eroare de compilare, ci o cutie cu lățime negativă sau un NaN care
/// apare abia la un anumit număr de jucători, pe un anumit ecran.
class TankArenaLayout {
  final double cellWidth;
  final double cellHeight;
  final int rows;
  final int cols;

  /// Câte cutii arată efectiv grila (rânduri × coloane) — poate fi mai mare
  /// decât [playerCount], ca să completeze ultimul rând (vezi
  /// [computeTankArenaLayout]); apelantul desenează locurile goale de la
  /// [playerCount] până la [slots].
  final int slots;

  /// Câți jucători sunt CHIAR la masă — cifra din care s-a calculat grila.
  final int playerCount;

  /// Înălțimea totală a conținutului — mai mare decât [viewportHeight] doar
  /// când [scrolls] e adevărat.
  final double contentHeight;

  /// Grila nu mai încape întreagă în spațiul disponibil (o masă plină de
  /// 8-10 jucători, pe un ecran mai mic) — arena trebuie învelită într-un
  /// container derulabil, altfel cutiile de jos ar rămâne tăiate.
  final bool scrolls;

  /// Decalajul de sus, ca grila să fie centrată pe verticală când NU
  /// derulează. Zero când derulează — primul rând trebuie ancorat sus.
  final double top;

  const TankArenaLayout({
    required this.cellWidth,
    required this.cellHeight,
    required this.rows,
    required this.cols,
    required this.slots,
    required this.playerCount,
    required this.contentHeight,
    required this.scrolls,
    required this.top,
  });
}

/// Calculează grila arenei pentru cei [playerCount] jucători CHIAR la masă
/// (NU plafonul modului, [tanksPlayerCount]) — o cameră de 2-3 prieteni tot
/// primește o grilă mică, cu cutii mari, exact ca înainte de urcarea
/// plafonului la 10; doar o masă plină ajunge la grila mare, cu mai multe
/// rânduri.
///
/// Coloanele rămân fixe la 2 — telefoanele sunt înalte, nu late, deci mai
/// multe RÂNDURI încap mai bine decât mai multe coloane. Cutiile păstrează
/// un raport lățime/înălțime fix (0.62) și nu coboară niciodată sub
/// [minCellHeight] — NU se comprimă doar ca să încapă toate în spațiul dat,
/// ca la o masă plină tancurile să nu devină ilizibil de mici. Dacă grila
/// completă nu mai încape pe verticală, [TankArenaLayout.scrolls] devine
/// adevărat, ca apelantul să învelească arena într-un container derulabil —
/// arena deruleze, nu tancurile se micșorează sub prag.
TankArenaLayout computeTankArenaLayout({
  required double viewportWidth,
  required double viewportHeight,
  required int playerCount,
  int cols = 2,
  double gap = 10,
  double sidePad = 12,
  double minCellHeight = 80,
}) {
  final clampedCount = playerCount.clamp(1, tanksPlayerCount);
  final rows = (clampedCount / cols).ceil();
  final cellWidth = (viewportWidth - sidePad * 2 - gap * (cols - 1)) / cols;
  final cellHeight = max(cellWidth.clamp(0.0, 168.0) * 0.62, minCellHeight);
  final gridHeight = cellHeight * rows + gap * (rows - 1);
  final scrolls = gridHeight > viewportHeight;
  return TankArenaLayout(
    cellWidth: cellWidth,
    cellHeight: cellHeight,
    rows: rows,
    cols: cols,
    slots: rows * cols,
    playerCount: clampedCount,
    contentHeight: scrolls ? gridHeight : viewportHeight,
    scrolls: scrolls,
    top: scrolls ? 0.0 : ((viewportHeight - gridHeight) / 2).clamp(0.0, double.infinity),
  );
}

/// Rezultatul unei singure trageri — ce se scrie în Firestore și ce
/// animează toți clienții.
class TankShotRoll {
  final bool hit;
  final int damage;
  const TankShotRoll({required this.hit, required this.damage});
}

/// Aruncă zarurile pentru un proiectil. [targetAnsweredCorrectly] e
/// principalul lucru care schimbă șansele — nu contează cine trage, ca să nu
/// existe jucători „mai tari" decât alții din alte motive decât răspunsurile
/// lor. [dodgeBonus] e singura excepție, folosită DOAR de evenimentul de
/// rundă „Ceață de Luptă" ([tanksBattleFogDodgeBonus]), unde șansa crește
/// pentru TOATĂ masa deodată, nu pentru cineva anume.
TankShotRoll rollTankShot({required bool targetAnsweredCorrectly, required Random rnd, double dodgeBonus = 0}) {
  final dodge = (targetAnsweredCorrectly ? tanksDodgeOnCorrect : tanksDodgeOnWrong) + dodgeBonus;
  if (rnd.nextDouble() < dodge) return const TankShotRoll(hit: false, damage: 0);
  final damage = tanksDamageMin + rnd.nextInt(tanksDamageMax - tanksDamageMin + 1);
  return TankShotRoll(hit: true, damage: damage);
}

/// Șansa ca proiectilul să CHIAR lovească ținta — exact inversul evitării de
/// mai sus, scoasă separat fiindcă se arată jucătorului pe ecranul de țintire.
///
/// DE CE E ARĂTATĂ: cine a răspuns corect în runda curentă e deja public în
/// documentul meciului (`roundWinnerIds` = lista țintașilor, scrisă de
/// [MultiplayerService.closeTanksAnswering]), deci cifra asta nu deconspiră
/// nimic secret. În schimb transformă alegerea victimei într-o decizie
/// adevărată: tragi în cel slăbit, care e „în gardă" și evită mai des, sau în
/// cel sănătos, pe care sigur îl atingi?
double tanksHitChance({required bool targetAnsweredCorrectly}) =>
    1 - (targetAnsweredCorrectly ? tanksDodgeOnCorrect : tanksDodgeOnWrong);

/// Dacă ținta poate fi DOBORÂTĂ dintr-o singură lovitură reușită — adică
/// viața ei rămasă intră în intervalul de daune. Marcat explicit pe ecranul
/// de țintire: e singura informație care schimbă complet ce merită atacat.
bool tanksCanKill(int targetHp) => targetHp <= tanksDamageMax;

// ─── Prada de la final ──────────────────────────────────────────────────────

/// DE CE PRADA E DATĂ DE JOC, NU LUATĂ DIN BALANȚA CELORLALȚI.
///
/// Ideea inițială era ca cel cu cele mai multe daune să ia inimi/hints/gems
/// direct din conturile celor pe care i-a lovit. Nu se poate, și nu doar
/// „tehnic":
///   • Quizz Tanks NU are miză de intrare (spre deosebire de celelalte
///     moduri, vezi core/betting.dart). A lua din balanța cuiva ceva ce el
///     n-a pus niciodată pe masă e exact pariul pe care modul ăsta l-a
///     scos deliberat.
///   • Regulile Firestore interzic unui client să scrie în `users/{uid}`-ul
///     altcuiva (vezi firestore.rules), și pe bună dreptate. Singura
///     variantă ar fi ca fiecare perdant să se debiteze singur la ecranul de
///     final — adică oricine închide aplicația înainte de final nu plătește
///     nimic, iar câștigătorului i s-ar promite o pradă care uneori nu
///     există. O recompensă care apare pe ecran dar nu ajunge în cont e mai
///     rea decât niciuna.
/// Așa că prada se calculează tot din daunele făcute (cine lovește mai mult
/// ia mai mult, exact ca în cerință), dar iese din joc, ca „fier vechi
/// recuperat din epave", nu din portofelul nimănui.
///
/// Toate valorile sunt de ordin de mărime diferit — monede zeci, hints
/// puține, inimi 0-2, gems rar — ca fiecare linie din lista de la final să
/// însemne altceva.
const double tanksScrapCoinsPerDamage = 0.30;

/// Un hint la fiecare atâtea daune, cu plafon — hint-urile sunt mai valoroase
/// decât monedele, deci nu se pot aduna la nesfârșit dintr-un singur meci.
const int tanksDamagePerHint = 60;
const int tanksMaxScrapHints = 2;

/// O inimă pentru cel cu cele mai multe daune și o inimă pentru oricine
/// rămâne în viață la final (de obicei aceeași persoană, deci maximul real
/// e 2 — vezi [tanksSalvageFor]).
const int tanksMvpHearts = 1;
const int tanksSurvivorHearts = 1;

/// Gems: singura recompensă cu adevărat RARĂ din mod. Doar cel cu cele mai
/// multe daune are dreptul să arunce zarul, și doar o dată la cinci meciuri
/// îi iese — altfel gems-urile, care în restul jocului se cumpără greu, ar
/// deveni bani mărunți.
const int tanksMvpGems = 1;
const double tanksMvpGemChance = 0.20;

/// Ce ia un jucător la finalul unui meci de Quizz Tanks.
class TanksSalvage {
  final int coins;
  final int hints;
  final int hearts;
  final int gems;

  const TanksSalvage({this.coins = 0, this.hints = 0, this.hearts = 0, this.gems = 0});

  bool get isEmpty => coins <= 0 && hints <= 0 && hearts <= 0 && gems <= 0;
}

/// [isTopDamage] = a făcut cele mai multe daune de la masă (se poate să fie
/// mai mulți la egalitate — atunci iau toți, e o situație rară și nu merită
/// un departajaj artificial). [survived] = mai era în viață la fluier.
///
/// [rnd] e injectabil doar ca să poată fi testat; în joc fiecare client îl
/// aruncă pentru el însuși, fiindcă prada lui nu-i afectează pe ceilalți.
TanksSalvage tanksSalvageFor({
  required int damageDealt,
  required bool isTopDamage,
  required bool survived,
  Random? rnd,
}) {
  if (damageDealt <= 0 && !survived) return const TanksSalvage();
  final random = rnd ?? Random();
  return TanksSalvage(
    coins: (damageDealt * tanksScrapCoinsPerDamage).round(),
    hints: (damageDealt ~/ tanksDamagePerHint).clamp(0, tanksMaxScrapHints),
    hearts: (isTopDamage ? tanksMvpHearts : 0) + (survived ? tanksSurvivorHearts : 0),
    gems: isTopDamage && random.nextDouble() < tanksMvpGemChance ? tanksMvpGems : 0,
  );
}

// ─── Rezolvarea rundei (logica pură, fără Firestore) ────────────────────────

/// Un proiectil rezolvat: cine a tras, în cine, dacă a lovit și cât.
/// Echivalentul pur al `TankShot` din models — [MultiplayerService] îl
/// mapează la ăla când scrie în Firestore.
class ResolvedTankShot {
  final String byId;
  final String atId;
  final bool hit;
  final int damage;
  const ResolvedTankShot({required this.byId, required this.atId, required this.hit, required this.damage});
}

/// Tot ce iese din rezolvarea unei runde de Quizz Tanks — calculat o singură
/// dată, de clientul care câștigă tranzacția, apoi scris în Firestore.
class TanksRoundOutcome {
  /// Proiectilele, în ordinea tragerii ([alive] sortat), inclusiv cele
  /// întoarse de [PowerUp.reflect].
  final List<ResolvedTankShot> shots;

  /// id → HP pierdut runda asta (se scade din HP-ul de la începutul rundei).
  final Map<String, int> damageTaken;

  /// id → daune CREDITATE runda asta. Include creditul primit de reflector
  /// pentru lovitura întoarsă, și daunele „în plus" peste viața rămasă a
  /// țintei (contorul e daune FĂCUTE, iar atacatorul chiar atât a tras).
  final Map<String, int> damageDealt;

  /// id-urile ajunse la ≤ 0 HP.
  final List<String> destroyed;

  const TanksRoundOutcome({
    required this.shots,
    required this.damageTaken,
    required this.damageDealt,
    required this.destroyed,
  });
}

/// Adversarul implicit al unui țintaș care n-a ales (sau a ales invalid):
/// cel cu cea mai puțină viață. La egalitate decide uid-ul, ca oricare
/// client să ajungă la aceeași alegere.
String? tanksWeakestEnemy(List<String> alive, Map<String, int> hp, String shooter, {Set<String> exclude = const {}}) {
  String? best;
  for (final id in alive) {
    if (id == shooter || exclude.contains(id)) continue;
    final h = hp[id] ?? tanksMaxHp;
    final b = best == null ? null : (hp[best] ?? tanksMaxHp);
    if (best == null || h < b! || (h == b && id.compareTo(best) < 0)) best = id;
  }
  return best;
}

/// Calculează efectul complet al fazei de foc. PUR: nu atinge Firestore, nu
/// citește ceasul — [rng] e injectat (în joc: `Random()`; în teste: sămânță
/// fixă). Vezi MultiplayerService.resolveTanksRound pentru cine îl cheamă și
/// ce scrie cu rezultatul.
///
///  - [alive] — id-urile tancurilor încă în viață, SORTATE (ordinea
///    proiectilelor).
///  - [shooters] — cine trage (a răspuns corect ȘI e în viață).
///  - [rawTargets] — id țintaș → `"tinta"` sau `"tintaA|tintaB"` (lovitură
///    dublă), exact ce e în `roundTargets`.
///  - [rawPowerUps] — id → numele power-up-ului activ ([PowerUp.name]).
///  - [allyShieldedIds] — cine e sub scut de aliat runda asta.
///  - [event] — evenimentul rundei (Ceață de Luptă / Muniție Grea contează
///    aici).
TanksRoundOutcome resolveTanksVolleys({
  required List<String> alive,
  required Set<String> shooters,
  required Map<String, int> hpAtStart,
  required Map<String, String> rawTargets,
  required Map<String, String> rawPowerUps,
  required Set<String> allyShieldedIds,
  required RoundEvent event,
  required Random rng,
}) {
  PowerUp powerUpOf(String id) {
    final raw = rawPowerUps[id];
    if (raw == null) return PowerUp.none;
    return PowerUp.values.firstWhere((p) => p.name == raw, orElse: () => PowerUp.none);
  }

  final dodgeBonus = event == RoundEvent.battleFog ? tanksBattleFogDodgeBonus : 0.0;
  final damageMultiplier = event == RoundEvent.heavyShells ? tanksHeavyShellsMultiplier : 1.0;

  // Un scut (propriu sau de aliat) blochează TOATE loviturile primite în
  // runda asta, nu doar prima — decizie de design (2026-09-02):
  // „mereu protecția te va proteja și de double shot sau orice lovitură
  // asupra ta în runda aia". Include ambele proiectile ale unei lovituri
  // duble țintite pe același tanc.
  final shots = <ResolvedTankShot>[];
  final incoming = {for (final id in alive) id: 0};
  final dealt = {for (final id in alive) id: 0};

  String? validEnemy(String shooter, String? id) =>
      (id != null && id != shooter && alive.contains(id)) ? id : null;

  for (final shooter in alive) {
    if (!shooters.contains(shooter)) continue;
    final shooterPower = powerUpOf(shooter);
    final parts = (rawTargets[shooter] ?? '').split(tanksTargetSeparator);
    final target = validEnemy(shooter, parts.isEmpty ? null : parts.first)
        ?? tanksWeakestEnemy(alive, hpAtStart, shooter);
    if (target == null) continue;

    // Lovitură dublă: ținta fiecărui proiectil aleasă de jucător. Aceeași
    // țintă de două ori ⇒ o lovitură concentrată, cu daune ×
    // [tanksDoubleShotFocusMultiplier].
    final volley = <(String, double)>[(target, 1.0)];
    if (shooterPower == PowerUp.doubleShot) {
      final second = validEnemy(shooter, parts.length > 1 ? parts[1] : null)
          ?? tanksWeakestEnemy(alive, hpAtStart, shooter, exclude: {target});
      if (second == target || second == null) {
        volley
          ..clear()
          ..add((target, tanksDoubleShotFocusMultiplier));
      } else {
        volley.add((second, 1.0));
      }
    }

    for (final (t, focusMult) in volley) {
      var roll = rollTankShot(targetAnsweredCorrectly: shooters.contains(t), rnd: rng, dodgeBonus: dodgeBonus);
      // Mega Racheta nu se poate evita: o eschivă reușită dădea 0 daune × 3.5.
      if (!roll.hit && shooterPower == PowerUp.megaRocket) {
        roll = TankShotRoll(hit: true, damage: tanksDamageMin + rng.nextInt(tanksDamageMax - tanksDamageMin + 1));
      }
      if (roll.hit && damageMultiplier != 1.0) {
        roll = TankShotRoll(hit: true, damage: (roll.damage * damageMultiplier).round());
      }
      if (shooterPower == PowerUp.megaRocket) {
        roll = TankShotRoll(hit: true, damage: (roll.damage * megaRocketDamageMultiplier).round());
      }
      if (roll.hit && focusMult != 1.0) {
        roll = TankShotRoll(hit: true, damage: (roll.damage * focusMult).round());
      }
      // Scut (propriu sau de aliat): blochează orice lovitură care CHIAR ar
      // fi atins ținta, de câte ori vine în runda asta.
      if (roll.hit &&
          (powerUpOf(t) == PowerUp.shield || allyShieldedIds.contains(t))) {
        roll = const TankShotRoll(hit: false, damage: 0);
      }
      // Reflexie: lovitura care ar fi atins un tanc cu [PowerUp.reflect] se
      // întoarce spre atacator — el încasează, reflectorul ia creditul.
      if (roll.hit && t != shooter && powerUpOf(t) == PowerUp.reflect && incoming.containsKey(shooter)) {
        shots.add(ResolvedTankShot(byId: t, atId: shooter, hit: true, damage: roll.damage));
        incoming[shooter] = incoming[shooter]! + roll.damage;
        dealt[t] = (dealt[t] ?? 0) + roll.damage;
        roll = const TankShotRoll(hit: false, damage: 0);
      }
      shots.add(ResolvedTankShot(byId: shooter, atId: t, hit: roll.hit, damage: roll.damage));
      if (roll.hit) {
        incoming[t] = incoming[t]! + roll.damage;
        dealt[shooter] = dealt[shooter]! + roll.damage;
      }
    }
  }

  final destroyed = [
    for (final id in alive)
      if ((hpAtStart[id] ?? tanksMaxHp) - incoming[id]! <= 0) id,
  ];

  return TanksRoundOutcome(
    shots: shots,
    damageTaken: incoming,
    damageDealt: dealt,
    destroyed: destroyed,
  );
}

// ─── Coregrafia fazei de foc (logică pură) ──────────────────────────────────
//
// Tragerile rundei se grupează după ȚINTĂ, în „unități de atac". Toți cei
// implicați într-o unitate (ținta + atacatorii ei) văd aceeași scenă în
// aceeași clipă. Unitățile care au un jucător comun se joacă pe rând, pe
// „sloturi"; cele fără jucători comuni rulează în paralel. Totul se
// calculează din `roundShots` (aceleași date pe toate telefoanele), deci
// fiecare client ajunge la exact același program — fără sincronizare în plus.

/// Banner-ul „FOC!" de la începutul fazei, înainte de primul slot.
const double tanksFireLeadSeconds = 0.6;

/// Cât zboară un obuz. La reflexie (dus-întors) drumul e mai lung.
const double tanksFlightSeconds = 1.3;
const double tanksReflectFlightFactor = 1.8;

/// Cât ține camera după impact în scenele 1 la 1 — aceeași valoare ca
/// `tankPovAftermath` din widgets/tank_pov.dart (verificat în teste).
const double tanksCamAftermathSeconds = 1.7;

/// Bombardament: pauza de țintire de la începutul scenei, decalajul dintre
/// obuze și cât rămâne cadrul după ultimul impact (totalul încasat).
const double tanksSalvoAimSeconds = 0.55;
const double tanksSalvoStaggerSeconds = 0.16;
const double tanksSalvoAftermathSeconds = tanksCamAftermathSeconds;

/// 1 la 1: obuzul pleacă aproape imediat — ținta e una singură.
const double tanksSingleLaunchDelay = 0.25;

/// După ultimul slot: barele se așază și apare „X DISTRUS".
const double tanksRevealTailSeconds = 2.4;

enum TankUnitKind {
  /// ≥2 atacatori pe aceeași țintă — scena comună de bombardament.
  salvo,

  /// Un singur atacator.
  single,

  /// A trage în B și B în A, fiecare singurul atacator al celuilalt.
  duel,

  /// Lovitură dublă pe două ținte, fiecare atacată doar de el — un obuz
  /// care se desparte în două.
  split,
}

class TankAttackUnit {
  final TankUnitKind kind;

  /// Ținta scenei. La duel e primul dintre cei doi (ordinea tragerilor), la
  /// split e prima dintre cele două ținte.
  final String targetId;

  /// Atacatorii, în ordinea tragerilor.
  final List<String> attackerIds;

  /// Indicii din lista de trageri care aparțin unității (inclusiv întoarcerea
  /// unei reflexii).
  final List<int> shotIndexes;

  /// Toți cei care văd scena: ținte + atacatori.
  final Set<String> participants;

  final int slot;
  final double startAt;
  final double endAt;

  const TankAttackUnit({
    required this.kind,
    required this.targetId,
    required this.attackerIds,
    required this.shotIndexes,
    required this.participants,
    required this.slot,
    required this.startAt,
    required this.endAt,
  });
}

class TankShotTiming {
  final int unitIndex;
  final double launchAt;
  final double impactAt;
  const TankShotTiming({required this.unitIndex, required this.launchAt, required this.impactAt});
}

class TankAttackPlan {
  final List<TankAttackUnit> units;

  /// Momentul fiecărei trageri, după indicele ei în `roundShots`.
  final Map<int, TankShotTiming> timings;

  /// Indicii „întoarcerilor" de reflexie — se desenează ca parte din zborul
  /// dus-întors al perechii lor, nu separat.
  final Map<int, int> reflectBackOf;

  /// Cât ține toată faza de foc, în secunde.
  final double revealSeconds;

  const TankAttackPlan({
    required this.units,
    required this.timings,
    required this.reflectBackOf,
    required this.revealSeconds,
  });

  static const empty = TankAttackPlan(
    units: [],
    timings: {},
    reflectBackOf: {},
    revealSeconds: tanksEmptyRevealSeconds + 0.0,
  );

  /// Unitatea în care sunt implicat la momentul [t] (cel mult una, fiindcă
  /// unitățile cu jucători comuni nu împart un slot).
  TankAttackUnit? activeUnitFor(String playerId, double t) {
    for (final u in units) {
      if (t >= u.startAt && t < u.endAt && u.participants.contains(playerId)) return u;
    }
    return null;
  }

  /// Unitățile care rulează la momentul [t].
  List<TankAttackUnit> activeUnits(double t) =>
      [for (final u in units) if (t >= u.startAt && t < u.endAt) u];

  /// Când începe să scadă bara lui [playerId]: la finalul ultimei scene în
  /// care a fost lovit. `null` dacă n-a fost ținta nimănui.
  double? drainStartFor(String playerId, List<ResolvedTankShot> shots) {
    double? at;
    for (final u in units) {
      final hitHere = u.shotIndexes.any((i) => shots[i].atId == playerId && shots[i].hit);
      if (hitHere) at = at == null ? u.endAt : max(at, u.endAt);
    }
    return at;
  }
}

/// Construiește programul fazei de foc din tragerile rundei.
/// [reflectorIds] = cine avea Reflexie, [doubleShotIds] = cine avea Lovitură
/// dublă (din `roundPowerUps`).
TankAttackPlan buildTankAttackPlan({
  required List<ResolvedTankShot> shots,
  Set<String> reflectorIds = const {},
  Set<String> doubleShotIds = const {},
}) {
  if (shots.isEmpty) return TankAttackPlan.empty;

  // Reflexii: `resolveTanksVolleys` scrie întoarcerea (R→S, lovește) și
  // plecarea (S→R, ratată). Întoarcerea se lipește de plecare.
  final reflectBackOf = <int, int>{};
  final reflectBack = <int>{};
  for (var i = 0; i < shots.length; i++) {
    for (var j = 0; j < shots.length; j++) {
      if (i == j || reflectBack.contains(j)) continue;
      final out = shots[i], back = shots[j];
      if (out.byId == back.atId && out.atId == back.byId && !out.hit && back.hit && reflectorIds.contains(out.atId)) {
        reflectBackOf[i] = j;
        reflectBack.add(j);
        break;
      }
    }
  }

  // Grupare după țintă (fără întoarcerile de reflexie).
  final byTarget = <String, List<int>>{};
  for (var i = 0; i < shots.length; i++) {
    if (reflectBack.contains(i)) continue;
    byTarget.putIfAbsent(shots[i].atId, () => []).add(i);
  }
  Set<String> shootersOf(List<int> idx) => {for (final i in idx) shots[i].byId};

  final drafts = <({TankUnitKind kind, String target, List<int> idx})>[];
  final used = <String>{};
  final targets = byTarget.keys.toList()..sort();
  for (final t in targets) {
    if (used.contains(t)) continue;
    final idx = byTarget[t]!;
    final shooters = shootersOf(idx);
    if (shooters.length >= 2) {
      drafts.add((kind: TankUnitKind.salvo, target: t, idx: idx));
      used.add(t);
      continue;
    }
    final a = shooters.first;
    // Duel: a e singurul atacator al lui t, iar t singurul atacator al lui a.
    final back = byTarget[a];
    if (back != null && !used.contains(a) && shootersOf(back).length == 1 && shootersOf(back).first == t) {
      drafts.add((kind: TankUnitKind.duel, target: t, idx: [...idx, ...back]..sort()));
      used..add(t)..add(a);
      continue;
    }
    // Split: a are Lovitură dublă pe două ținte, fiecare atacată doar de el.
    if (doubleShotIds.contains(a)) {
      String? other;
      for (final o in targets) {
        if (o == t || used.contains(o)) continue;
        final oi = byTarget[o]!;
        if (shootersOf(oi).length == 1 && shootersOf(oi).first == a) other = o;
      }
      if (other != null) {
        drafts.add((kind: TankUnitKind.split, target: t, idx: [...idx, ...byTarget[other]!]..sort()));
        used..add(t)..add(other);
        continue;
      }
    }
    drafts.add((kind: TankUnitKind.single, target: t, idx: idx));
    used.add(t);
  }

  // Ordinea de așezare: bombardamentele mari întâi, apoi restul; departajare
  // pe țintă — deterministă pe orice telefon.
  int rank(TankUnitKind k) => switch (k) {
        TankUnitKind.salvo => 0,
        TankUnitKind.split => 1,
        TankUnitKind.duel => 2,
        TankUnitKind.single => 3,
      };
  drafts.sort((x, y) {
    final r = rank(x.kind).compareTo(rank(y.kind));
    if (r != 0) return r;
    if (x.kind == TankUnitKind.salvo) {
      final s = y.idx.length.compareTo(x.idx.length);
      if (s != 0) return s;
    }
    return x.target.compareTo(y.target);
  });

  Set<String> participantsOf(List<int> idx) => {
        for (final i in idx) ...[shots[i].byId, shots[i].atId],
        for (final i in idx)
          if (reflectBackOf[i] != null) ...[shots[reflectBackOf[i]!].byId, shots[reflectBackOf[i]!].atId],
      };

  // Colorare greedy: fiecare unitate în primul slot fără jucători comuni.
  final slotOf = <int>[];
  final slotPeople = <Set<String>>[];
  for (final d in drafts) {
    final people = participantsOf(d.idx);
    var s = 0;
    while (s < slotPeople.length && slotPeople[s].intersection(people).isNotEmpty) {
      s++;
    }
    if (s == slotPeople.length) slotPeople.add({});
    slotPeople[s].addAll(people);
    slotOf.add(s);
  }

  double flightFor(int i) =>
      reflectBackOf.containsKey(i) ? tanksFlightSeconds * tanksReflectFlightFactor : tanksFlightSeconds;

  double durationOf(({TankUnitKind kind, String target, List<int> idx}) d) {
    final longest = d.idx.map(flightFor).reduce(max);
    if (d.kind == TankUnitKind.salvo) {
      return tanksSalvoAimSeconds + tanksSalvoStaggerSeconds * (d.idx.length - 1) + longest + tanksSalvoAftermathSeconds;
    }
    return tanksSingleLaunchDelay + longest + tanksCamAftermathSeconds;
  }

  final slotLen = List<double>.filled(slotPeople.length, 0);
  for (var k = 0; k < drafts.length; k++) {
    slotLen[slotOf[k]] = max(slotLen[slotOf[k]], durationOf(drafts[k]));
  }
  final slotStart = <double>[];
  var cursor = tanksFireLeadSeconds;
  for (final len in slotLen) {
    slotStart.add(cursor);
    cursor += len;
  }

  final units = <TankAttackUnit>[];
  final timings = <int, TankShotTiming>{};
  for (var k = 0; k < drafts.length; k++) {
    final d = drafts[k];
    final start = slotStart[slotOf[k]];
    final attackers = <String>[];
    for (var n = 0; n < d.idx.length; n++) {
      final i = d.idx[n];
      if (!attackers.contains(shots[i].byId)) attackers.add(shots[i].byId);
      final launch = d.kind == TankUnitKind.salvo
          ? start + tanksSalvoAimSeconds + tanksSalvoStaggerSeconds * n
          : start + tanksSingleLaunchDelay;
      final timing = TankShotTiming(unitIndex: k, launchAt: launch, impactAt: launch + flightFor(i));
      timings[i] = timing;
      final back = reflectBackOf[i];
      if (back != null) timings[back] = timing;
    }
    units.add(TankAttackUnit(
      kind: d.kind,
      targetId: d.target,
      attackerIds: attackers,
      shotIndexes: [
        ...d.idx,
        for (final i in d.idx) if (reflectBackOf[i] != null) reflectBackOf[i]!,
      ],
      participants: participantsOf(d.idx),
      slot: slotOf[k],
      startAt: start,
      endAt: start + slotLen[slotOf[k]],
    ));
  }

  return TankAttackPlan(
    units: units,
    timings: timings,
    reflectBackOf: reflectBackOf,
    revealSeconds: cursor + tanksRevealTailSeconds,
  );
}
