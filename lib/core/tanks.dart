/// Regulile modului multiplayer **Quizz Tanks** — patru tancuri, întrebări de
/// cultură generală și o bară de viață de 100, ca la jocurile de luptă.
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
/// TOATE ARUNCĂRILE DE ZAR SE FAC ÎNTR-UN SINGUR LOC: în tranzacția care
/// rezolvă runda (vezi MultiplayerService.resolveTanksRound). Rezultatul
/// (lista de proiectile, cine a fost lovit, cât) se SCRIE în Firestore, iar
/// ceilalți clienți doar îl animează. Nu există niciun zar aruncat de două
/// ori pe două telefoane — greșeala clasică prin care doi jucători ar vedea
/// bătălii diferite în același meci.
library;

import 'dart:math';

/// Câți jucători încap într-o cameră de Quizz Tanks. Nu e o cifră
/// decorativă: cu patru jucători, cel care țintește alege dintre exact trei
/// adversari — atâtea cutii încap lizibil pe ecranul de țintire — iar arena
/// e desenată ca o grilă 2×2 (vezi MultiplayerTanksScreen). Camera se poate
/// porni și cu mai puțini (2 sau 3) — altfel n-ai cum să joci până nu
/// strângi exact trei prieteni — dar nu primește niciodată al cincilea
/// jucător.
const int tanksPlayerCount = 4;

/// Viața de start a fiecărui tanc. 100 fix, ca procentele din bară să se
/// citească direct ca HP.
const int tanksMaxHp = 100;

/// Cât are fiecare la dispoziție ca să răspundă. Ridicat de la 5 la 12
/// secunde la cererea explicită a userului — 5 secunde era prea puțin ca
/// să apuci și să citești întrebarea, nu doar să reacționezi.
const int tanksRoundSeconds = 12;

/// Cât durează alegerea țintei. Puțin mai lung decât răspunsul, fiindcă aici
/// chiar ai ce cântări (cine e slăbit? cine mă vânează?), dar tot scurt: o
/// rundă întreagă trebuie să rămână sub ~15 secunde, altfel un meci de zece
/// runde devine obositor. Cine nu apucă să aleagă trage automat — vezi
/// MultiplayerService.resolveTanksRound.
const int tanksTargetSeconds = 6;

/// Cât durează spectacolul de după rundă (proiectile în aer, impacturi,
/// bare care scad, tancuri care explodează) înainte să înceapă runda
/// următoare. Trebuie să acopere toată coregrafia din
/// MultiplayerTanksScreen — dacă se scurtează aici, se scurtează și acolo.
const int tanksRevealSeconds = 4;

/// Plafon absolut de runde, ca meciul să nu poată rămâne agățat la
/// nesfârșit. Se atinge doar în cazul patologic în care nimeni nu mai
/// nimerește nimic (fără răspunsuri corecte nu se trage niciun proiectil,
/// deci nu scade nicio bară). La atingerea lui meciul se încheie normal,
/// iar clasamentul rămâne cel dat de daunele făcute.
const int tanksMaxRounds = 20;

/// Daunele unei lovituri reușite, în HP (= procente din [tanksMaxHp]).
/// Vezi comentariul din capul fișierului pentru de ce sunt atât de mari:
/// se trage într-o singură țintă aleasă, nu în toți odată.
const int tanksDamageMin = 18;
const int tanksDamageMax = 30;

/// Șansa ca ținta să EVITE proiectilul, după cum a răspuns ea însăși în
/// runda curentă. Asimetria e toată ideea de echilibru a modului.
const double tanksDodgeOnCorrect = 0.55;
const double tanksDodgeOnWrong = 0.12;

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
