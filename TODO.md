# Ce urmează

Document de orientare, actualizat după fiecare sesiune mare — nu e un plan
de implementare. Aici stă doar ce rămâne deschis.

Ultima curățare: 2026-08-29. Tot ce era rezolvabil în cod din lista veche a
fost făcut (vezi „Rezolvat în sesiunea din 2026-08-29" la final). Ce a rămas
mai jos e blocat pe o decizie de-a ta sau pe o acțiune în Firebase Console —
nu se poate închide din cod. Restul e „de probat pe telefon".

## De probat pe telefon (scris, dar neconfirmat cu 2 jucători)

Modificările din 2026-08-29 au trecut `flutter analyze` (0) și
`flutter test`, dar NU au fost jucate pe telefon cu doi jucători reali:

- **Gardă de fază pe power-up-uri** (`core/powerups.dart`
  `powerUpUsableInPhase` + `powerUpUsablePhases`, cablată în `_usePowerUp`
  din Tanks / Scaunul Electric / Obby). Puterile „de luptă" care se scriu pe
  `roundPowerUps` (mega rachetă, lovitură dublă, scut, șoc perforant, scut
  pe aliat, sabotaj, jetpack) nu se mai pot apăsa în faza `revealed` (runda
  s-a rezolvat deja) — apare un SnackBar „Prea târziu…" și puterea **rămâne**
  în inventar, nu se consumă degeaba. De verificat că fereastra aleasă
  pentru fiecare putere e cea corectă în joc real (nu prea strânsă).
- **Anunț la primirea unei puteri** (`_announcePowerUp` în cele 3 ecrane) —
  banner `InAppNotification.showInfo` (nu fură tap-uri, e `IgnorePointer`)
  care spune ce putere ai primit și că se apasă pastila din bară. De văzut
  că nu se suprapune urât cu bannerul de eveniment de rundă.

- **Lovitură Dublă (Double Shot) rescrisă** după clarificarea userului
  (2026-08-25 „edit1"): faza de țintire cere acum DOUĂ apăsări când ai
  double shot (titlu „ȚINTA 1 DIN 2" / „2 DIN 2"). Aceeași țintă de două
  ori ⇒ o singură lovitură cu daune ×`tanksDoubleShotFocusMultiplier`
  (1.8); ținte diferite ⇒ două proiectile normale, unul pe fiecare. Cele
  două ținte se scriu în `roundTargets[shooter]` ca `"a|b"`
  (`tanksTargetSeparator`), despărțite la rezolvare. Câmp nou pe `MatchInfo`:
  `roundPowerUps` (ca ecranul să știe în țintire cine are double shot). DE
  PROBAT cu 3 jucători — atinge echilibrul modului și animația de foc (POV-ul
  țintașului la două ținte diferite arată doar al doilea proiectil).

- **Power-up-urile „doar vizuale" au acum efect real** (toate 5). Fără
  fereastră nouă de alegere — auto-țintire, exact convenția deja folosită
  de `allyShield` la Scaunul Electric:
  - `allyShield` la Quizz Tanks — apără automat tancul cel mai slăbit
    2 runde (`useTanksAllyShield`, `shields.<id>` citit de
    `resolveTanksRound`, blochează prima lovitură ca scutul propriu).
  - `reflect` la Tanks — proiectilul care te-ar lovi se întoarce spre
    atacator (un obuz nou în animație `byId: victimă → atacator`); el
    încasează, tu primești creditul de daune.
  - `reflect` la Scaunul Electric — dacă ai picat testul dar ai reflect,
    scapi, iar fiecare atacator pierde o viață. Nu iei puncte de apărare.
  - `peek` (Tanks / Obby / Scaunul Electric) — efect 100% local: banner
    `InAppNotification` cu ce au răspuns ceilalți până în acel moment. Nu
    scrie nimic, nu schimbă rezolvarea. (Ar putea deveni un panou live într-o
    trecere viitoare, dar snapshot-ul e deja util lângă finalul cronometrului.)
  DE PROBAT pe telefon: `reflect` la ambele moduri și `allyShield` la Tanks
  ating tranzacția de rezolvare — 2-3 jucători reali.

## Magazin cu bani reali (IAP) — user anunță el când

Monedele/gems sunt azi 100% virtuale (`pubspec.yaml` n-are
`in_app_purchase`). Blocul de preț real din `shop_screen.dart` /
`lib/data/shop.dart` e deliberat ascuns în spatele vălului „În curând"
(`premiumShopRevealed = false`). **Nu se dezvăluie din proprie inițiativă**
— userul a zis explicit că anunță el.

## Audit de securitate 2026-08-25 — ce a rămas

Reparate în 2026-08-29: #2 (grant de admin aplicat de două ori — acum
revendicat printr-o tranzacție înainte de aplicare, `cloud_sync_service.dart`
`consumePendingGrant`) și #3 (`completed_matches` avea `allow write` liber
— acum regula verifică exact cele 3 câmpuri, tipurile lor, `playerCount >= 2`
și interzice `delete`).

**Rămâne #1 — blocat pe Cloud Functions:** orice cont autentificat (Guest
inclusiv) poate scrie/șterge direct în Firestore documentele unui meci
multiplayer în curs al altcuiva (`firestore.rules` `matches/{matchId}` &
sub-colecții — compromis conștient, comentat: fără Cloud Functions regulile
nu pot fi owner-only, fiindcă liderul de meci scrie în documentele altor
candidați). Premiile din pariuri se calculează din scorul citit din
Firestore și acordarea monedelor se face 100% local
(`multiplayer_results_screen.dart`, `StorageService.addCoins`), fără
validare pe server. Cineva care scrie direct în Firestore și-ar putea umfla
scorul și primi monede nemeritat, sau sabota meciul altcuiva. Repararea
cere o Cloud Function care validează scorurile server-side → cere planul
Blaze (mai jos).

**Ce s-a verificat și e în regulă** (să nu se re-audieze): nicio cheie/token
privat hardcodat în `lib/` sau `tools/`; scripturile `tools/*.py` au mod
raport implicit și cer `--sterge`; tranzacțiile Firestore din
`multiplayer_service.dart` sunt folosite consecvent la scrieri concurente;
formula de premii din `betting.dart` e matematic corectă; n-au fost găsite
`dispose()` lipsă în ecranele multiplayer verificate.

## Firebase Blaze — de evaluat, nedecis

Motivul concret: **planul gratuit (Spark) nu permite deloc Cloud
Functions** (nu e cotă, e blocat — rulează pe Cloud Run, inexistent pe
Spark). Fără Cloud Functions nu se poate repara auditul #1 de mai sus.

Ce ar aduce upgrade-ul:
- **Validare server-side a scorurilor/premiilor multiplayer** — repară #1.
- **Aplicarea grant-urilor de admin server-side, atomic** — ar face #2 și
  mai robust (acum e o tranzacție pe client, tot mai bine ca înainte).
- **Curățare automată programată** a meciurilor/`completed_matches` vechi,
  în loc de `tools/purge_*.py` rulate manual.
- **Fără plafonul dur al planului Spark.** Spark oprește serviciul (erori
  la jucători) când se depășește cota zilnică gratuită. Blaze păstrează
  EXACT aceeași cotă gratuită, dar facturează doar depășirea — deci jocul
  nu se mai „rupe" brusc dacă baza de jucători crește (AdMob e deja live).
- **Apeluri de rețea externe din Cloud Functions** (blocate pe Spark) —
  relevant pentru validarea chitanțelor IAP dacă se face magazinul real.

Cost: „plătești ce depășești" — cât timp utilizarea rămâne sub cota
gratuită (identică cu Spark), costul e $0. Riscul real e doar un bug care
face bucle de citire/scriere — de-aia contează App Check (mai jos).

Lămurit deja (ca să nu se re-explice): un telefon lăsat pornit ore în șir
**nu** generează trafic — Firestore nu face polling, un listener trimite
date doar când chiar se schimbă ceva. Consumul vine din activitate reală de
joc. Plasă de siguranță: Firebase Console → Billing → Budgets & alerts dă
avertisment pe email cu mult înainte de o sumă mare.

## Acțiuni care sunt strict ale tale, în Firebase Console

1. **Alerte de buget** (Billing → Budgets & alerts) — gratuit, de făcut
   indiferent de decizia Blaze.
2. **App Check pe „Enforce"** — codul trimite deja tokenul din 2026-08-18
   (`lib/core/app_check_service.dart`, vezi memoria `project_guess_it_app_check`),
   dar aplicația nu e înregistrată la App Check și e pe „Unenforced", deci
   Firebase nu respinge nimic. Pași: Console → „sodoquizz" → App Check →
   înregistrează app-ul Android (Play Integrity, deja în cod) → pentru
   fiecare serviciu trece din „Unenforced" în „Enforce" — DAR abia după ce
   te-ai asigurat că build-ul curent de pe telefon trimite deja tokenul cu
   succes (altfel blochezi jucători reali). Capcană: APK-ul sideloaded din
   GitHub Releases primește UNRECOGNIZED_VERSION și rămâne fără
   multiplayer/leaderboard/cloud save — Enforce doar după ce canalul ăla e
   închis sau declarat acceptabil de pierdut.

---

## Rezolvat în sesiunea din 2026-08-29

- Gardă de fază + anunț la primire pe power-up-uri (vezi „De probat" sus).
- Lovitură Dublă rescrisă (vezi „De probat" sus).
- Cele 5 power-up-uri „doar vizuale" au acum efect real (vezi „De probat" sus).
- Audit securitate #2 și #3 (vezi secțiunea de audit sus).
- Șters fișierul gol `scriptul` din rădăcină.

Cu asta, singurele lucruri rămase deschise sunt: IAP (aștepți tu), auditul
#1 (cere Cloud Functions), decizia Blaze, și cele două acțiuni din Firebase
Console. Nimic din ce mai e în fișier nu se poate face din cod fără tine.

Tot ce e în „De probat pe telefon" a trecut `flutter analyze` (0) și
`flutter test`, dar NU a fost jucat pe telefon cu 2-3 jucători — asta
rămâne de făcut de user.
