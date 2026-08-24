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

/// Câți jucători încap într-o cameră de Quizz Tanks. Urcat de la 4 la 10 la
/// cererea explicită a userului (toate modurile trebuie să accepte 10) —
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

/// Cât durează alegerea țintei. Urcat de la 6 la 10 secunde la cererea
/// explicită a userului: cardurile de țintă arată acum șansă de lovire,
/// daune făcute și etichete tactice (ÎN GARDĂ, CEL MAI PERICULOS, LOVITURĂ
/// MORTALĂ) — la 6 secunde abia apucai să le citești, darămite să cântărești
/// între ele. Cine nu apucă să aleagă trage automat — vezi
/// MultiplayerService.resolveTanksRound.
const int tanksTargetSeconds = 10;

/// Cât durează spectacolul de după rundă (proiectile în aer, impacturi,
/// bare care scad, tancuri care explodează) înainte să înceapă runda
/// următoare. Trebuie să acopere toată coregrafia din
/// MultiplayerTanksScreen — dacă se scurtează aici, se scurtează și acolo.
///
/// Urcat de la 4 la 5, apoi la 9 secunde când s-a adăugat camera de pe
/// proiectil (vezi widgets/tank_pov.dart): pentru cel care trage, secundele
/// astea nu mai sunt o pauză de privit, ci propria lovitură văzută de pe
/// obuz. A doua urcare (5→9) a venit după ce userul a văzut prima versiune
/// rulând live pe două ecrane și n-a apucat să citească nici traiectoria,
/// nici textul de deznodământ ("-24"/"EVITAT!") — totul se termina înainte
/// să se fixeze ochiul pe el.
///
/// Bugetul e împărțit așa (secunde de la începutul fazei, vezi și
/// MultiplayerTanksScreen._firstShotAt/_flightDuration/_drainDelayAfterImpacts
/// mai jos, care trebuie ținute în pas cu asta): ~0,6 încărcare, ~1,3 zbor,
/// ~1,7 impact/evitare, apoi barele care scad și epavele care explodează, cu
/// timp de rămas pentru „cine a fost distrus".
const int tanksRevealSeconds = 9;

/// Cât ține faza de după rundă când NU s-a tras niciun foc — nimeni n-a
/// nimerit răspunsul, sau a mai rămas un singur tanc în viață (vezi
/// MultiplayerService.closeTanksAnswering, care în cazurile astea sare direct
/// la `revealed`, cu `roundShots` gol).
///
/// Fără constanta asta, toată lumea aștepta [tanksRevealSeconds] întregi
/// uitându-se la o arenă în care nu zbura nimic: bugetul de 9 secunde e
/// dimensionat pentru coregrafia completă (încărcare, zbor, impact, bare care
/// scad, epave care explodează), iar când nu există niciun proiectil, din el
/// nu se consumă nimic. Rămân doar cât să se citească răspunsul corect.
const int tanksEmptyRevealSeconds = 3;

/// Cât trebuie ținută faza de reveal a rundei curente. Toți clienții o
/// calculează din ACELEAȘI date publice (`roundShots` din documentul
/// meciului), deci ajung la aceeași valoare — important, fiindcă fiecare
/// client își pornește singur cronometrul de avansare a rundei.
int tanksRevealSecondsFor({required bool anyShots}) =>
    anyShots ? tanksRevealSeconds : tanksEmptyRevealSeconds;

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
/// COBORÂTE de la 18-30 la cererea explicită a userului („tancurile dau
/// mult mai puțin damage, să se continue tura mai mult timp") — vezi
/// comentariul din capul fișierului pentru socoteala completă. La ~10 HP
/// media pe lovitură, un tanc rezistă ~10 lovituri reușite în loc de ~4.
const int tanksDamageMin = 7;
const int tanksDamageMax = 13;

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

/// Aruncă zarurile pentru un proiectil. [targetAnsweredCorrectly] e singurul
/// lucru care schimbă șansele — nu contează cine trage, ca să nu existe
/// jucători „mai tari" decât alții din alte motive decât răspunsurile lor.
TankShotRoll rollTankShot({required bool targetAnsweredCorrectly, required Random rnd}) {
  final dodge = targetAnsweredCorrectly ? tanksDodgeOnCorrect : tanksDodgeOnWrong;
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
